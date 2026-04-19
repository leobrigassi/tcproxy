#!/bin/bash
# shellcheck shell=bash
# tcproxy — host-side mount management: create mountpoints, mount the VM's
# samba shares over loopback onto $TCPROXY_HOST_MOUNT_ROOT/*, and unmount them.
# Depends on: lib/config.sh (TCPROXY_HOST_MOUNT_ROOT, TCPROXY_VM_SMB_PORT,
#             TCPROXY_MOUNT_RETRIES, TCPROXY_UMOUNT_RETRIES),
#             lib/common.sh (logm, logsm, logsc, LOGSC_OUTPUT/LOGSC_COMMAND,
#             PUID, PGID).

# Creates the host-side mountpoint folders for each configured share.
# Missing TC_* vars collapse to no-ops (paths with empty segments are
# idempotent under mkdir -p).
creating_mountpoint_folder() {
    logsc sudo mkdir -p "$TCPROXY_HOST_MOUNT_ROOT/$TC_DISK_USB"
    logsc sudo mkdir -p "$TCPROXY_HOST_MOUNT_ROOT/$TC_USER"
    logsc sudo mkdir -p "$TCPROXY_HOST_MOUNT_ROOT/$TC_DISK"
}

# Unmounts each configured share on the host. Tries a normal umount first,
# then umount -f; retries up to TCPROXY_UMOUNT_RETRIES per mountpoint.
umount_srv_tcproxy() {
    logm "Initiating umount routine..."
    MAX_RETRIES_UM=$TCPROXY_UMOUNT_RETRIES
    RETRY_COUNT_UM=0
    MOUNT_POINTS_UM=()
    if [[ -n $TC_DISK_USB ]]; then MOUNT_POINTS_UM+=("$TCPROXY_HOST_MOUNT_ROOT/$TC_DISK_USB"); fi
    if [[ -n $TC_USER ]]; then MOUNT_POINTS_UM+=("$TCPROXY_HOST_MOUNT_ROOT/$TC_USER"); fi
    if [[ -n $TC_DISK ]]; then MOUNT_POINTS_UM+=("$TCPROXY_HOST_MOUNT_ROOT/$TC_DISK"); fi
    for MOUNT_POINT_UM in "${MOUNT_POINTS_UM[@]}"; do
        RETRY_COUNT_UM=0
        while [ $RETRY_COUNT_UM -lt "$MAX_RETRIES_UM" ]; do
            RESPONSE_UM=$(sudo umount "$MOUNT_POINT_UM" 2>&1)
            if [ $? -eq 0 ] || [ $? -eq 32 ] || echo "$RESPONSE_UM" | grep -q "not mounted"; then
                logm "Host umount of [$MOUNT_POINT_UM] successful..."
                break
            else
                if ! mountpoint -q "$TCPROXY_HOST_MOUNT_ROOT/$MOUNT_POINT_UM"; then logsm "Host folder [$TCPROXY_HOST_MOUNT_ROOT/$MOUNT_POINT_UM] is not a mountpoint"; break; fi
                logm "Host failed to unmount [$MOUNT_POINT_UM]. $RESPONSE_UM. Forcing umount..."
                sleep 5
                RESPONSE_F_UM=$(sudo umount -f "$MOUNT_POINT_UM" 2>&1)
                if [[ $? -eq 0 ]]; then
                    logm "[INFO] Forced unmount of [$MOUNT_POINT_UM] successful..."
                    break
                elif [[ $RESPONSE_F_UM == *"Stale file handle"* ]]; then
                    logm "[ERROR $RESPONSE_F_UM] Please reboot and retry. Process aborted."
                else
                    logm "[ERROR $RESPONSE_F_UM] Cannot unmount [$MOUNT_POINT_UM] . Is the mount in use?"
                fi
            fi
            RETRY_COUNT_UM=$((RETRY_COUNT_UM + 1))
            logm "Host retrying unmount for [$MOUNT_POINT_UM] ... attempt $RETRY_COUNT_UM"
        done
    done
    logm "Host umount routine of all specified mount points completed."
}

# Triggers mount -a inside the VM and checks each share is visible.
# Exits 1 if any configured share fails to mount in the VM.
test_VM_mount() {
    if [[ -n $TC_DISK_USB ]]; then if $SUDOREQUIRED ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p"$TCPROXY_VM_SSH_PORT" 'mount -a && mount | grep -q //'$TC_IP'/'$TC_DISK_USB''; then logm "VM mount [$TC_DISK_USB] OK..."; else logm "[ERROR] VM unable to mount to Time Capsule folder $TC_IP/$TC_DISK_USB. Please check credentials, IPv4 or connectivity and run again."; exit 1; fi; fi
    if [[ -n $TC_USER ]]; then if $SUDOREQUIRED ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p"$TCPROXY_VM_SSH_PORT" 'mount -a && mount | grep -q //'$TC_IP'/'$TC_USER''; then logm "VM mount [$TC_USER] OK..."; else logm "[ERROR] VM unable to mount to Time Capsule folder $TC_IP/$TC_USER. Please check credentials, IPv4 or connectivity and run again."; exit 1; fi; fi
    if [[ -n $TC_DISK ]]; then if $SUDOREQUIRED ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p"$TCPROXY_VM_SSH_PORT" 'mount -a && mount | grep -q //'$TC_IP'/'$TC_DISK''; then logm "VM mount [$TC_DISK] OK..."; else logm "[ERROR] VM unable to mount to Time Capsule folder $TC_IP/$TC_DISK. Please check credentials, IPv4 or connectivity and run again."; exit 1; fi; fi
}

# Verifies each configured share is reachable via smbclient on the loopback
# samba port exposed by the VM. Returns the last smbclient exit code.
check_smb_share() {
    VM_SMB_CHECK=0
    if [[ -n $TC_DISK_USB ]]; then smbclient //127.0.0.1/"$TC_DISK_USB" -U root%"$TC_PASSWORD" --port="$TCPROXY_VM_SMB_PORT" -c 'exit'; VM_SMB_CHECK=$?; if [[ $VM_SMB_CHECK -ne 0 ]]; then echo "[ERROR] Failed to access $TC_DISK_USB"; else echo "VM samba share [$TC_DISK_USB] OK..."; fi ; fi
    if [[ -n $TC_USER ]]; then smbclient //127.0.0.1/"$TC_USER" -U root%"$TC_PASSWORD" --port="$TCPROXY_VM_SMB_PORT" -c 'exit'; VM_SMB_CHECK=$?; if [[ $VM_SMB_CHECK -ne 0 ]]; then echo "[ERROR] Failed to access $TC_USER"; else echo "VM samba share [$TC_USER] OK..."; fi ; fi
    if [[ -n $TC_DISK ]]; then smbclient //127.0.0.1/"$TC_DISK" -U root%"$TC_PASSWORD" --port="$TCPROXY_VM_SMB_PORT" -c 'exit'; VM_SMB_CHECK=$?; if [[ $VM_SMB_CHECK -ne 0 ]]; then echo "[ERROR] Failed to access $TC_DISK"; else echo "VM samba share [$TC_DISK] OK..."; fi ; fi
    return $VM_SMB_CHECK
}

# Mounts each configured share from the VM's loopback samba onto the host.
# Retries each share up to TCPROXY_MOUNT_RETRIES and calls the optional
# after_tcproxy_up hook on first successful mount.
mount_routine() {
    logsm "Initiating mount routine..."
    AFTER_TCPROXY_UP_TRIGGER=0
    MAX_RETRIES_M=$TCPROXY_MOUNT_RETRIES
    RETRY_COUNT_M=0
    MOUNT_POINTS_M=()
    if [[ -n $TC_DISK_USB ]]; then MOUNT_POINTS_M+=("$TC_DISK_USB"); fi
    if [[ -n $TC_USER ]]; then MOUNT_POINTS_M+=("$TC_USER"); fi
    if [[ -n $TC_DISK ]]; then MOUNT_POINTS_M+=("$TC_DISK"); fi
    for MOUNT_POINT_M in "${MOUNT_POINTS_M[@]}"; do
        RETRY_COUNT_M=0
        while [ $RETRY_COUNT_M -lt "$MAX_RETRIES_M" ]; do
            if mountpoint "$TCPROXY_HOST_MOUNT_ROOT/$MOUNT_POINT_M" >/dev/null 2>&1; then
                logm "Host mount [$TCPROXY_HOST_MOUNT_ROOT/$MOUNT_POINT_M] OK..."
                break
            else
                logsc sudo mount -t cifs //127.0.0.1/"$MOUNT_POINT_M" "$TCPROXY_HOST_MOUNT_ROOT/$MOUNT_POINT_M" -o username=root,password="$TC_PASSWORD",rw,iocharset=utf8,vers=3.0,nofail,port="$TCPROXY_VM_SMB_PORT",uid="$PUID",gid="$PGID" 2>&1
                if [ "$LOGSC_OUTPUT" -eq 0 ]; then
                    logm "Host mount [$TCPROXY_HOST_MOUNT_ROOT/$MOUNT_POINT_M] OK..."
                    AFTER_TCPROXY_UP_TRIGGER=1
                    break
                else
                    logm "[ERROR: $LOGSC_OUTPUT] failed to mount [$MOUNT_POINT_M]: $LOGSC_COMMAND. Check system and retry."
                    umount_srv_tcproxy
                    sleep 7
                fi
            fi
            RETRY_COUNT_M=$((RETRY_COUNT_M + 1))
            logm "Retrying mount for $MOUNT_POINT_M... attempt $RETRY_COUNT_M"
        done
    done
    logm "Host mount routine of all specified mount points completed..."
    if [[ $AFTER_TCPROXY_UP_TRIGGER -eq 1 && -e "$TCPROXY_PATH/after_tcproxy_up" ]]; then logsc "$TCPROXY_PATH/after_tcproxy_up"; fi
}
