#!/bin/bash
# shellcheck shell=bash
# tcproxy — install/uninstall orchestration and the tcproxy_up convenience
# wrapper used by --up, --restart, and the systemd boot service.
# Depends on: lib/config.sh, lib/common.sh, lib/ui.sh, lib/vm.sh,
#             lib/mount.sh, lib/provision.sh, lib/updater.sh.

# Verifies the host has the qemu flavor matching its arch plus smbclient.
# Bails out on unsupported architectures. This is the install-time
# pre-flight; the lib/common.sh check_dependencies covers the narrower
# set of everyday commands.
check_system_requirements() {
    if [[ $ARCH == x86_64* ]]; then
        if ! which qemu-system-x86_64 >/dev/null 2>&1 && ! which smbclient >/dev/null 2>&1; then
            logm "Dependencies not detected.
        sudo apt install curl qemu-system-x86 qemu-kvm smbclient
        please install and try again."
            exit 1
        fi
    elif [[ $ARCH == aarch64* ]]; then
        if ! which qemu-system-aarch64 >/dev/null 2>&1 && ! which qemu-system-x86_64 >/dev/null 2>&1 && ! which smbclient >/dev/null 2>&1; then
            logm "Dependencies not detected.
        sudo apt install curl qemu-system-aarch64 qemu-kvm smbclient
        Please install and try again."
            exit 1
        fi
    else
        logm "System not supported. Please run from x86_64 or aarch64 systems."
        exit 1
    fi
}

# Removes staging files after --install or --enable-service succeeds.
# -f: staging files may not exist if --enable-service was skipped.
post_install_cleanup() {
    logm "Running post install tasks..."
    logsc sudo rm -f "$TCPROXY_PATH/.tcproxy-boot-load.service"
    logsc sudo rm -f "$TCPROXY_PATH/.tcproxy-boot-load.timer"
}

# Bring up the full VM+mount stack.
# - Starts the VM if not already running.
# - Verifies shares mount inside the VM.
# - Retries host-side smb access up to MAX_RETRIES_UP, restarting the VM
#   after REBOOT_COUNT_VM_UP failed attempts.
# - Finally mounts shares onto $TCPROXY_HOST_MOUNT_ROOT.
tcproxy_up() {
    MAX_RETRIES_UP=10
    RETRY_INTERVAL_UP=60
    RETRY_COUNT_UP=0
    REBOOT_COUNT_VM_UP=5
    logm "Checking VM status..."
    if ! pgrep -f "mac=$TCPROXY_VM_MAC" >/dev/null 2>&1; then
        load_VM
        check_VM_status
    fi
    # v3.2.2: probe the VM's samba port before attempting host cifs mount.
    # Shrinks the transient "Server abruptly closed the connection" window.
    wait_smb_ready || true
    # v3.2.2: test_VM_mount now returns (not exits) on failure so the
    # check_smb_share retry loop below can actually retry.
    test_VM_mount || logm "[INFO] Initial VM mount probe failed; entering retry loop."
    while ! check_smb_share; do
        RETRY_COUNT_UP=$((RETRY_COUNT_UP + 1))
        if [ $RETRY_COUNT_UP -ge $MAX_RETRIES_UP ]; then
            logm "[ERROR] Max retries for check_smb_share reached. Exiting..."
            exit 1
        elif [ $RETRY_COUNT_UP -eq $REBOOT_COUNT_VM_UP ]; then
            logm "[INFO] VM samba share still not accessible. Restarting tcproxy VM..."
            umount_srv_tcproxy
            stopping_VM
            sleep 10
            load_VM
        fi
        test_VM_mount
        logm "[INFO] Failed to access VM samba share. Waiting $RETRY_INTERVAL_UP seconds before next attempt. Attempt $RETRY_COUNT_UP/$MAX_RETRIES_UP."
        sleep $RETRY_INTERVAL_UP
    done
    logm "VM samba share routine completed..."
    mount_routine
}

# Runs the full install wizard: branch warning, cwd setup, system check,
# user inputs, asset download, VM provisioning, and env persistence.
# WEB_INSTALL=TRUE forces non-interactive failure if the GUI is cancelled.
do_install() {
    ui_branch_warning
    create_tcproxy_folder
    download_latest_script
    check_system_requirements
    if ! ui_confirm_close_apps; then
        if [[ $WEB_INSTALL != "TRUE" ]]; then
            prompt_user_inputs
        else
            echo "[INFO] GUI Process Aborted. tcproxy has not been installed."
            exit 1
        fi
    fi
    TC_IP=$(ui_input_field "Time Capsule IPv4" "Enter Time Capsule IPv4 (e.g., 192.168.1.10):")
    if [ -z "$TC_IP" ]; then
        echo "[ERROR] IPv4 required. Process aborted."
        exit 1
    fi
    TC_USER=$(ui_input_field "Time Capsule USER" "Enter Time Capsule USER (optional):")
    TC_PASSWORD=$(ui_input_field "Time Capsule PASSWORD" "Enter Time Capsule PASSWORD:")
    if [ -z "$TC_PASSWORD" ]; then
        echo "[ERROR] PASSWORD is required. Process aborted."
        exit 1
    fi
    TC_DISK=$(ui_input_field "Time Capsule DISK name" "Enter Time Capsule DISK name e.g., Data (optional):")
    TC_DISK_USB=$(ui_input_field "Time Capsule USB disk Name" "Enter Time Capsule USB disk name (optional):")
    if [ -z "$TC_USER" ] && [ -z "$TC_DISK" ] && [ -z "$TC_DISK_USB" ]; then
        echo "[ERROR] Nothing to mount. At least one input among User, DISK or USB Disk is required. Process aborted."
        exit 1
    fi
    github_download
    umount_srv_tcproxy
    stopping_VM
    load_VM
    check_VM_status
    testing_ssh_permission_requirements
    creating_mountpoint_folder
    provision_VM
    # v3.2.2: test_VM_mount no longer exits on failure; enforce hard
    # stop here — the install wizard must not declare success on a VM
    # that can't mount the Time Capsule.
    if ! test_VM_mount; then
        logm "[ERROR] VM unable to mount Time Capsule. Please check credentials, IPv4 and connectivity, then run --install again."
        exit 1
    fi
    tcproxy_up
    save_env
    post_install_cleanup
    logsc sudo rm -f .tcproxy-uninstalled
    logm "Installation completed in folder $TCPROXY_PATH"
}

# Runs the uninstall flow: unmount, stop VM, remove service, delete
# on-disk assets, mark the folder as uninstalled.
do_uninstall() {
    umount_srv_tcproxy
    stopping_VM
    remove_system_service
    remove_env
    logsc sudo rm -f "$TCPROXY_PATH/data.img" "$TCPROXY_PATH/id_rsa_vm" "$TCPROXY_PATH/id_rsa_vm.pub" "$TCPROXY_PATH/qemu.mac" "$TCPROXY_PATH/uefi.rom" "$TCPROXY_PATH/.vm-serial-file"
    touch .tcproxy-uninstalled
    logm "tcproxy uninstalled. You may now remove the folder:
$TCPROXY_PATH
"
}
