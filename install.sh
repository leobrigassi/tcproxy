#!/bin/bash
# Time Capsule Proxy for SmallMediaHub - Updates and readme on https://github.com/leobrigassi/time-capsule-proxy
if [ "$(basename $(pwd))" == "time-capsule-proxy" ]; then
    echo "Extracting in time-capsule-proxy directory."
else
    echo "[ ] Creating Time_Capsule_Proxy directory."
    mkdir -p time-capsule-proxy &&
    cd time-capsule-proxy >/dev/null 2>&1
fi

downloadTC() {
wget https://github.com/leobrigassi/Time_Capsule_Proxy/archive/refs/heads/main.tar.gz &&
tar -xzf main.tar.gz --strip-components=1 && rm main.tar.gz &&
chmod +x setup-time-capsule-proxy.sh
chmod +x mount-time-capsule-proxy.sh
chmod +x enable-service-at-startup.sh
chmod +x install.sh
chmod +x vm-ssh.sh
chmod +x vm-restart.sh
chmod +x vm-down.sh
} 

downloadTC >/dev/null 2>&1