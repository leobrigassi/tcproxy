#!/bin/bash
# Time Capsule Proxy for SmallMediaHub - Updates and readme on https://github.com/leobrigassi/time-capsule-proxy
source /home/ubuntu/tcp/.env #line_3_updated_on_first_run
cd $TIME_CAPSULE_PROXY_PATH
# Log file path
LOG_FILE="$TIME_CAPSULE_PROXY_PATH/connection.log"
touch $LOG_FILE
sudo chmod 770 $LOG_FILE

# Function to check SMB share accessibility
check_smb_share() {
    smbclient //127.0.0.1/tc-proxy -U root%$TC_PASSWORD --port=50445 -c 'exit' > /dev/null 2>&1
    return $?
}

# Function to restart the Time_Capsule_Proxy container
restart_TCP_container() {
    if mountpoint -q "/srv/tc-proxy"; then
        if sudo umount /srv/tc-proxy 2>/dev/null; then
            echo "[  ] Mountpoint /srv/tc-proxy detected. Unmounting..."
        else
            echo "[INFO] Cannot gracefully unmount /srv/tc-proxy. Forcing unmount..."
            sudo umount -f /srv/tc-proxy 2>/dev/null
            sleep 2
            if mountpoint -q "/srv/tc-proxy"; then
                echo "[ERROR] Cannot unmount /srv/tc-proxy. Please umount and run setup again."
                exit 1
            fi
        fi
    fi
    if pgrep -f "mac=02:D2:46:5B:4E:84" > /dev/null 2>&1; then
        echo "[  ] VM detected. Sending poweroff command..."
        sudo ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p50022 "poweroff"
        TIMEOUT=60
        INTERVAL=5
        ELAPSED=0
        while pgrep -f "mac=02:D2:46:5B:4E:84" > /dev/null 2>&1; do
            sleep $INTERVAL
            ELAPSED=$((ELAPSED + INTERVAL))
            if [ $ELAPSED -ge $TIMEOUT ]; then
                echo "[ERROR] VM did not power down after $TIMEOUT seconds. Forcing termination..."
                pkill -f "mac=02:D2:46:5B:4E:84"
                if [ $? -eq 0 ]; then
                    echo "[  ] VM process killed."
                else
                    echo "[ERROR] Failed to kill VM process. Installation stopped."
                    break
                fi
            fi
        done
        if [ $ELAPSED -lt $TIMEOUT ]; then
            echo "[  ] VM powered down."
        fi
    fi
}

# Function to get current timestamp
get_timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

# Function to write log messages
log_message() {
    echo "$(get_timestamp): $1" >> "$LOG_FILE"
}

# Function to load VM
loadVM() {
    arch=$(uname -m)
    if [[ $arch == x86_64* ]]; then
    sudo qemu-system-x86_64 \
    -M q35,accel=kvm \
    -cpu host \
    -m 256 \
    -boot order=c \
    -drive file=data.img,format=qcow2,if=virtio \
    -netdev user,id=net0,hostfwd=tcp::50022-:22,hostfwd=tcp::50445-:445 \
    -device virtio-net,netdev=net0,mac=$(cat qemu.mac) \
    -serial file:./vm.log \
    -daemonize \
    -display none
    fi
    if [[ $arch == aarch64* ]]; then
    sudo qemu-system-aarch64 \
    -M virt,accel=kvm \
    -cpu host \
    -m 256 \
    -drive file=data.img,format=qcow2,if=virtio \
    -bios uefi.rom \
    -device virtio-net-device,netdev=net0,mac=$(cat qemu.mac) \
    -netdev user,id=net0,hostfwd=tcp::50022-:22,hostfwd=tcp::50445-:445 \
    -serial file:./vm.log \
    -daemonize \
    -display none
    fi
}

# Retry logic with a timeout
MAX_RETRIES=20
RETRY_INTERVAL=60
retry_count=0
failed_attempts=0

log_message "[  ] Initiating Time_Capsule_Proxy mount process..."
cd $TIME_CAPSULE_PROXY_PATH

if ! pgrep -f "mac=02:D2:46:5B:4E:84" > /dev/null 2>&1; then
    loadVM 
    sleep 30
fi

while [ $retry_count -lt $MAX_RETRIES ]; do
    if check_smb_share; then
        log_message "[  ] VM samba share is accessible."
        break
    else
        retry_count=$((retry_count + 1))
        failed_attempts=$((failed_attempts + 1))
        log_message "[INFO] Failed to access VM samba share. Attempt $retry_count/$MAX_RETRIES."
        if [ $failed_attempts -eq 5 ]; then
            log_message "[INFO] Restarting time-capsule-proxy VM..."
            restart_TCP_container
            sleep 10
        fi
        if [ $failed_attempts -eq 10 ]; then
            log_message "[ERROR] Container taking very long to load. Killing and restarting time-capsule-proxy container..."
            sudo kill $(pgrep -f "mac=02:D2:46:5B:4E:84")
            sleep 5
            loadVM
        fi
        sleep $RETRY_INTERVAL
    fi
done

# Verify mount
if ! mountpoint -q /srv/tc-proxy; then
    log_message "[  ] Remounting /srv/tc-proxy..."
    sudo umount -l /srv/tc-proxy  > /dev/null 2>&1
    sudo mount -t cifs //127.0.0.1/tc-proxy /srv/tc-proxy/ -o password="$TC_PASSWORD""$TC_FSTAB_USER",rw,uid="$PUID",iocharset=utf8,vers=3.0,nofail,file_mode=0775,dir_mode=0775,port=50445 >> "$LOG_FILE"
fi
log_message "[OK] System up and running"
