#!/bin/bash
# Time Capsule Proxy for SmallMediaHub - Updates and readme on https://github.com/leobrigassi/time-capsule-proxy
if pgrep -f "mac=02:D2:46:5B:4E:84"; then
echo "[OK] Unmounting /srv/tc-proxy ..."
sudo umount /srv/tc-proxy
echo "[OK] Sending poweroff command to VM..."
sudo ssh root@localhost -i ./id_rsa_vm -o StrictHostKeyChecking=no -p50022 "poweroff"
while ! pgrep -f "mac=02:D2:46:5B:4E:84" >/dev/null; do
 sleep 5 
done
fi
echo "[OK] TCProxy unmounted and VM powered down."