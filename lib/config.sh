#!/bin/bash
# shellcheck shell=bash
# tcproxy — configuration constants.
# Sourced early by bin/tcproxy (after release-time concat).
# Edit values here to change behavior without touching logic.

# === Version ===
TCPROXY_COMMIT=v3.1.1
TCPROXY_RELEASE=v3.1.1
TCPROXY_VM_VERSION=v2.1.4
# Format: /heads/<branch> for branch builds, /tags/<version> for releases.
TCPROXY_BRANCH=/tags/v3.1.1

# === Distribution URLs ===
TCPROXY_FILE_BRANCH_URL="https://raw.githubusercontent.com/leobrigassi/tcproxy/${TCPROXY_BRANCH#/*/}/tcproxy"
TCPROXY_FILE_RELEASE_URL="https://github.com/leobrigassi/tcproxy/releases/download/${TCPROXY_BRANCH#/*/}/tcproxy"
TCPROXY_VM_VERSION_URL="https://github.com/leobrigassi/tcproxy/releases/download/${TCPROXY_VM_VERSION}/"

if [[ $TCPROXY_BRANCH == *"tags"* ]]; then
    TCPROXY_FILE_DEFINED_URL=$TCPROXY_FILE_RELEASE_URL
else
    TCPROXY_FILE_DEFINED_URL=$TCPROXY_FILE_BRANCH_URL
fi

# === VM ===
TCPROXY_VM_MAC="02:D2:46:5B:4E:84"
TCPROXY_VM_SSH_PORT=50022
TCPROXY_VM_SMB_PORT=50445
TCPROXY_VM_MEM_MB=256

# === Host paths ===
TCPROXY_HOST_MOUNT_ROOT="/srv/tcproxy"
TCPROXY_SERVICE_NAME="tcproxy-boot-load.service"
TCPROXY_TIMER_NAME="tcproxy-boot-load.timer"
TCPROXY_SERVICE_FILE="/etc/systemd/system/${TCPROXY_SERVICE_NAME}"
TCPROXY_TIMER_FILE="/etc/systemd/system/${TCPROXY_TIMER_NAME}"

# === Retry / timeout tunables ===
TCPROXY_VM_LOAD_RETRIES=10
TCPROXY_VM_LOAD_INTERVAL=15
TCPROXY_VM_BOOT_STEPS=60
TCPROXY_VM_BOOT_INTERVAL=6
TCPROXY_VM_STOP_TIMEOUT=60
TCPROXY_VM_STOP_INTERVAL=5
TCPROXY_UMOUNT_RETRIES=3
TCPROXY_MOUNT_RETRIES=3

# === HTTP ===
TCPROXY_CURL_CONNECT_TIMEOUT=5
TCPROXY_CURL_MAX_TIME=10
