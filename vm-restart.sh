#!/bin/bash
# Time Capsule Proxy for SmallMediaHub - Updates and readme on https://github.com/leobrigassi/time-capsule-proxy

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
echo "[  ] Reloading..."
sleep 3
echo "[  ] Initiating mounting sequence..."
touch connection.log >/dev/null 2>&1
echo "[  ] Showing logs from mount-time-capsule-proxy.sh..." > connection.log 
./mount-time-capsule-proxy.sh >/dev/null 2>&1
sleep 1
exec 2>/dev/null
tail -fq -n3 ./connection.log &
TAIL_PID=$!
STOP_STRING="System up and running"
while ! grep -q "$STOP_STRING" < ./connection.log; do
    sleep 1
done
sudo kill "$TAIL_PID" >/dev/null 2>&1
exec 2>&3