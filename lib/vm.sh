#!/bin/bash
# shellcheck shell=bash
# tcproxy — QEMU VM lifecycle: start, stop, boot-wait, ssh, privilege probe.
# Depends on: lib/config.sh (TCPROXY_VM_*, TCPROXY_PATH), lib/common.sh (logm/logsm).

# Probes whether ssh into the VM needs sudo. Sets SUDOREQUIRED to
# "" or "sudo " for later callers. Exits on unreachable VM.
testing_ssh_permission_requirements() {
    ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p"$TCPROXY_VM_SSH_PORT" "ls"
    SUDOREQUIREDEXIT=$?
    if [ $SUDOREQUIREDEXIT -eq 0 ]; then
        SUDOREQUIRED=""
    else
        sudo ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p"$TCPROXY_VM_SSH_PORT" "ls"
        SUDOREQUIREDEXIT=$?
        if [ $SUDOREQUIREDEXIT -eq 0 ]; then
            SUDOREQUIRED="sudo "
            logm "[INFO] SSH privileges have been elevated."
        else
            logm "[ERROR] Cannot SSH in the VM. Process aborted. Error code $SUDOREQUIREDEXIT"
            exit 1
        fi
    fi
}

# Sends poweroff over ssh. Falls back to pkill after
# TCPROXY_VM_STOP_TIMEOUT seconds.
stopping_VM() {
    if pgrep -f "mac=$TCPROXY_VM_MAC" >/dev/null 2>&1; then
        logm "VM detected. Sending poweroff command..."
        $SUDOREQUIRED ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p"$TCPROXY_VM_SSH_PORT" "poweroff"
        TIMEOUT_ST=$TCPROXY_VM_STOP_TIMEOUT
        INTERVAL_ST=$TCPROXY_VM_STOP_INTERVAL
        ELAPSED_ST=0
        while pgrep -f "mac=$TCPROXY_VM_MAC" >/dev/null 2>&1; do
            sleep "$INTERVAL_ST"
            ELAPSED_ST=$((ELAPSED_ST + INTERVAL_ST))
            if [ $ELAPSED_ST -ge "$TIMEOUT_ST" ]; then
                logm "[ERROR] VM did not power down after $TIMEOUT_ST seconds. Forcing termination..."
                sudo pkill -f "mac=$TCPROXY_VM_MAC"
                if [ $? -eq 0 ]; then
                    logm "VM process killed."
                else
                    logm "[ERROR] Failed to kill VM process. Process aborted."
                    exit 1
                fi
            fi
        done
        if [ "$ELAPSED_ST" -lt "$TIMEOUT_ST" ]; then
            logm "VM powered down..."
        fi
    else
        logsm "VM powered down..."
    fi
}

# Starts qemu daemonized. Arch-aware: q35 for x86_64, virt+uefi for aarch64.
# Retries up to TCPROXY_VM_LOAD_RETRIES with TCPROXY_VM_LOAD_INTERVAL sleeps.
load_VM() {
    MAX_RETRIES_VM_UP=$TCPROXY_VM_LOAD_RETRIES
    RETRY_INTERVAL_VM_UP=$TCPROXY_VM_LOAD_INTERVAL
    RETRY_COUNT_VM_UP=0
    while ! pgrep -f "mac=$TCPROXY_VM_MAC" >/dev/null 2>&1; do
        RETRY_COUNT_VM_UP=$((RETRY_COUNT_VM_UP + 1))
        if [ $RETRY_COUNT_VM_UP -ge "$MAX_RETRIES_VM_UP" ]; then
            logm "[ERROR] Max retries for load_VM reached. Exiting..."
            exit 1
        fi
        logm "VM down... attempting to load..."
        if [[ $ARCH == x86_64* ]]; then
            sudo qemu-system-x86_64 \
                -M q35,accel=kvm \
                -cpu host \
                -m "$TCPROXY_VM_MEM_MB" \
                -boot order=c \
                -drive file="$TCPROXY_PATH/data.img",format=qcow2,if=virtio \
                -netdev user,id=net0,hostfwd=tcp::"$TCPROXY_VM_SSH_PORT"-:22,hostfwd=tcp::"$TCPROXY_VM_SMB_PORT"-:445 \
                -device virtio-net,netdev=net0,mac=$(cat "$TCPROXY_PATH/qemu.mac") \
                -serial file:"$TCPROXY_PATH/.vm-serial-file" \
                -daemonize \
                -display none
        elif [[ $ARCH == aarch64* ]]; then
            sudo qemu-system-aarch64 \
                -M virt,accel=kvm \
                -cpu host \
                -m "$TCPROXY_VM_MEM_MB" \
                -drive file="$TCPROXY_PATH/data.img",format=qcow2,if=virtio \
                -bios "$TCPROXY_PATH/uefi.rom" \
                -device virtio-net-device,netdev=net0,mac=$(cat "$TCPROXY_PATH/qemu.mac") \
                -netdev user,id=net0,hostfwd=tcp::"$TCPROXY_VM_SSH_PORT"-:22,hostfwd=tcp::"$TCPROXY_VM_SMB_PORT"-:445 \
                -serial file:"$TCPROXY_PATH/.vm-serial-file" \
                -daemonize \
                -display none
        fi
        sleep "$RETRY_INTERVAL_VM_UP"
    done
    logm "VM launched..."
}

# Polls the VM serial log for the Alpine banner as a readiness signal.
check_VM_status() {
    logm "Waiting for VM to boot..."
    MAX_RETRIES_VM_ST=$TCPROXY_VM_BOOT_STEPS
    RETRY_INTERVAL_VM_ST=$TCPROXY_VM_BOOT_INTERVAL
    RETRY_COUNT_VM_ST=0
    while ! sudo grep -q "Welcome to Alpine Linux" "$TCPROXY_PATH/.vm-serial-file"; do
        RETRY_COUNT_VM_ST=$((RETRY_COUNT_VM_ST + 1))
        if [ $RETRY_COUNT_VM_ST -ge "$MAX_RETRIES_VM_ST" ]; then
            logm "[ERROR] Max retries for check_VM_status reached. Exiting..."
            exit 1
        fi
        sleep "$RETRY_INTERVAL_VM_ST"
    done
    logm "VM up..."
}

# Interactive ssh shell into the VM (used by --ssh).
ssh_vm() {
    testing_ssh_permission_requirements
    logsm "ssh-in"
    $SUDOREQUIRED ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p"$TCPROXY_VM_SSH_PORT"
    logsm "ssh-out"
}
