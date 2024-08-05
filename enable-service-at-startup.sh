#!/bin/bash
# Time Capsule Proxy for SmallMediaHub - Updates and readme on https://github.com/leobrigassi/time-capsule-proxy
source .env

if ! [ -d /run/systemd/system ]; then
    echo "[ERROR] systemctl not detected, script requires systemd."
    exit 1
fi

# Configure startup service
touch "$TCP_SERVICE_TEMP_FILE"
echo "[Unit]
Description=Mount time-capsule-proxy and Restart Services
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart='$TCP_SERVICE_MOUNT_FILE'
RemainAfterExit=true

[Install]
WantedBy=multi-user.target" > "$TCP_SERVICE_TEMP_FILE"

echo "[  ] Scanning for previously installed daemons..."
sudo systemctl stop time-capsule-proxy.service >/dev/null 2>&1
sudo systemctl disable time-capsule-proxy.service >/dev/null 2>&1
sudo rm $TCP_SERVICE_PATH/time-capsule-proxy.service >/dev/null 2>&1
sudo cp $TCP_SERVICE_TEMP_FILE $TCP_SERVICE_PATH/time-capsule-proxy.service >/dev/null 2>&1
sudo systemctl daemon-reload
sudo systemctl enable time-capsule-proxy.service >/dev/null 2>&1
sudo systemctl start time-capsule-proxy.service >/dev/null 2>&1

echo "[OK] Service enabled at boot."