#!/bin/bash
# Time Capsule Proxy for SmallMediaHub - Updates and readme on https://github.com/leobrigassi/time-capsule-proxy

# Prompt User Inputs
read -p "[INFO] This script will unistall time-capsule-proxy and disable startup script.
Close any app or terminal window using /srv/tc-proxy before continuing. 
[INPUT] Continue? (y/N): " UNINSTALL
if [[ "$UNINSTALL" =~ ^[Yy]$ ]]; then
    echo "[  ] Removing systemd services..."
    sudo systemctl stop time-capsule-proxy.service >/dev/null 2>&1 &&
    sudo systemctl disable time-capsule-proxy.service >/dev/null 2>&1 &&
    sudo rm /etc/systemd/system/time-capsule-proxy.service
    current_dir=$(pwd | awk -F'/' '{print $NF}')
    if [ $current_dir == "time-capsule-proxy" ]; then
        # stopping previously installed VMs and mounts
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
        echo "[OK] Uninstall completed. It is now safe to delete the time-capsule-proxy directory and all its content."
    else
        echo "[ERROR] Directory time-capsule-proxy not detected. Please run from time-capsule-proxy. Process aborted."
        exit 1
    fi
else
    echo "[INFO] Uninstall script aborted. No change has been performed."
    exit 1
fi