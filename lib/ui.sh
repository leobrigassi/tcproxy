#!/bin/bash
# shellcheck shell=bash
# tcproxy — user-facing UI: whiptail wrappers, text-prompt fallback, help menu.
# Depends on: lib/config.sh (version/paths), lib/common.sh (logm).

BETA_WARNING_TEXT="You have selected the BETA branch of tcproxy.
What we are testing:
- selective download of VM relevant to host arch reducing install download by 50%
- if script named [ after_tcproxy_up ] exists in tcproxy folder it will be executed after tcproxy mount is successful. Useful to restart services such as Plex so that new mounts can be crawled."

DEV_WARNING_TEXT="You have selected the DEV branch of tcproxy.
This is intended for DEV testing ONLY."

# Shows a whiptail msgbox with the branch warning if on beta or dev.
ui_branch_warning() {
    case "$TCPROXY_BRANCH" in
        /heads/beta)
            whiptail --title "tcproxy $TCPROXY_COMMIT installation GUI" \
                --msgbox "$BETA_WARNING_TEXT" 15 60
            ;;
        /heads/dev)
            whiptail --title "tcproxy $TCPROXY_COMMIT installation GUI" \
                --msgbox "$DEV_WARNING_TEXT" 15 60
            ;;
    esac
}

# yesno confirm before install. Returns the whiptail exit code (0 = yes).
ui_confirm_close_apps() {
    whiptail --title "tcproxy $TCPROXY_COMMIT installation GUI" --yesno \
        "Close any app or terminal window using $TCPROXY_HOST_MOUNT_ROOT before continuing.\n\nDo you want to continue?" 15 60
}

# Echoes the user's input for a single whiptail inputbox.
ui_input_field() {
    local title="$1" prompt="$2" default="${3:-}"
    whiptail --title "$title" --inputbox "$prompt" 8 60 "$default" 3>&1 1>&2 2>&3
}

# Text-based fallback for the install wizard. Used when the whiptail
# flow is cancelled in an interactive (non-web) session.
prompt_user_inputs() {
    echo "GUI closed unexpectedly. Running text based setup.
Close any app or terminal window using $TCPROXY_HOST_MOUNT_ROOT before continuing."
    read -rp "[INPUT] Continue? (y/N): " CONFIRM_INSTALL
    if [[ ! "$CONFIRM_INSTALL" =~ ^[Yy]$ ]]; then
        logm "[INFO] Setup aborted. tcproxy has not been installed."
        exit 1
    fi
    read -rp "[INPUT] Time Capsule IPv4 (e.g. 192.168.1.10): " TC_IP
    if [ -z "$TC_IP" ]; then
        logm "[ERROR] IPv4 required. Process aborted"
        exit 1
    fi
    read -rp "[INPUT] Time Capsule USER (optional): " TC_USER
    read -rp "[INPUT] Time Capsule PASSWORD: " TC_PASSWORD
    if [ -z "$TC_PASSWORD" ]; then
        logm "[ERROR] PASSWORD is required. Process aborted"
        exit 1
    fi
    read -rp "[INPUT] Time Capsule DISK name (e.g. Data): " TC_DISK
    if [ -z "$TC_DISK" ]; then
        logm "[ERROR] DISK name is required. Process aborted"
        exit 1
    fi
    read -rp "[INPUT] Time Capsule USB drive (optional): " TC_DISK_USB
    read -rp "[INPUT] Do you want to enable mount at startup? (y/N): " STARTUP_MOUNT
}

help_menu() {
    echo "Usage: ./tcproxy [OPTION]...

  -d,  --down               unmounts $TCPROXY_HOST_MOUNT_ROOT and poweroff to VM
  -h,  --help               prints this help
  -i,  --install            initiates setup wizard
  -l,  --log                prints last 100 log lines to screen
  -r,  --restart            restarts VM and remounts $TCPROXY_HOST_MOUNT_ROOT
  -s,  --ssh                connects to the VM via ssh
  -u,  --up                 loads VM and initiates mount $TCPROXY_HOST_MOUNT_ROOT on host
  -v,  --version            Shows current version of tcproxy installed
  --enable-service          (beta) installs systemd startup service
  --disable-service         stops and removes systemd startup service
  --uninstall               unmounts $TCPROXY_HOST_MOUNT_ROOT and poweroff to VM and stops and removes system service

For bug reports, questions, discussions and/or open issues visit:
https://github.com/leobrigassi/tcproxy"
}
