#!/bin/bash
# shellcheck shell=bash
# tcproxy — common helpers: identity, paths, logging, env I/O, deps check.
# Depends on: lib/config.sh (sourced first).

# === Discovered system identity (set on load) ===
USER=$(whoami)
GROUP=$(id -gn)
PUID=$(id -u)
PGID=$(id -g)
ARCH=$(uname -m)
MACHINE_ID=$(cat /etc/machine-id 2>/dev/null || echo "")
CPU_INFO=$(grep -i 'model' /proc/cpuinfo 2>/dev/null | head -1)
MAC_ADDRESS=$(cat /sys/class/net/eth0/address 2>/dev/null || cat /sys/class/net/wlan0/address 2>/dev/null || echo "")
UNIQUE_ID=$(echo -n "${MACHINE_ID}_${CPU_INFO}_${MAC_ADDRESS}" | md5sum | awk '{print $1}')

# === Dependency check ===
check_dependencies() {
    local missing=0 cmd
    for cmd in bash sudo whoami id uname cat md5sum awk grep head readlink pwd chmod mkdir touch rm ssh whiptail smbclient; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "[ERROR] Required command '$cmd' is not installed."
            missing=1
        fi
    done
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        echo "[ERROR] Both 'curl' and 'wget' are required."
        missing=1
    fi
    if [[ $missing -eq 1 ]]; then
        echo "Please install the missing dependencies."
        exit 1
    fi
}

# === Path initialization ===
# Sets TCPROXY_PATH, TCP_ENV, LOG_FILE.
# If cwd basename is not "tcproxy", creates/descends into ./tcproxy.
create_tcproxy_folder() {
    local current_path
    current_path=$(pwd | awk -F'/' '{print $NF}')
    if [[ $current_path == "tcproxy" ]]; then
        TCPROXY_PATH=$(readlink -f .)
    else
        mkdir -p tcproxy
        TCPROXY_PATH=$(readlink -f .)/tcproxy
        cd tcproxy || exit 1
    fi
    TCP_ENV=$TCPROXY_PATH/.tcproxy.env
    [[ ! -e $TCP_ENV ]] && touch "$TCP_ENV"
    sudo chmod 770 "$TCP_ENV"
    LOG_FILE="$TCPROXY_PATH/log-tcproxy.txt"
    [[ ! -e $LOG_FILE ]] && touch "$LOG_FILE"
    sudo chmod 770 "$LOG_FILE"
    if [[ -z "$LOG_FILE" || ! -f "$LOG_FILE" ]]; then
        echo "[ERROR] LOG_FILE is not initialized or does not exist."
        exit 1
    fi
}

# === Logging ===
# logc:  run cmd, stdout+stderr to screen AND log file
# logsc: run cmd silently, output to log file only
# logm:  print message to screen AND log file
# logsm: write message to log file only
logc() {
    LOG_MESSAGE="$(date +"%Y%m%d_%H:%M:%S"): $0 $*"
    LOG_MESSAGE_TIMESTAMP="$(date +"%Y%m%d_%H:%M:%S"): $LOG_MESSAGE"
    echo "$LOG_MESSAGE_TIMESTAMP" >> "$LOG_FILE"
    LOGC_COMMAND=$("$@" 2>&1)
    LOGC_OUTPUT=$?
    echo "$LOGC_COMMAND" | tee -a "$LOG_FILE"
    return $LOGC_OUTPUT
}

logsc() {
    LOG_MESSAGE="$(date +"%Y%m%d_%H:%M:%S"): $0 $*"
    LOGSC_COMMAND=$("$@" 2>&1)
    LOGSC_OUTPUT=$?
    LOG_MESSAGE_TIMESTAMP="$(date +"%Y%m%d_%H:%M:%S"): $LOG_MESSAGE"
    echo "$LOG_MESSAGE_TIMESTAMP" >> "$LOG_FILE"
    echo "$LOGSC_COMMAND" >> "$LOG_FILE"
    return $LOGSC_OUTPUT
}

logm() {
    LOG_MESSAGE="$*"
    LOG_MESSAGE_TIMESTAMP="$(date +"%Y%m%d_%H:%M:%S"): $LOG_MESSAGE"
    echo "$LOG_MESSAGE"
    echo "$LOG_MESSAGE_TIMESTAMP" >> "$LOG_FILE"
}

logsm() {
    LOG_MESSAGE="$*"
    LOG_MESSAGE_TIMESTAMP="$(date +"%Y%m%d_%H:%M:%S"): $LOG_MESSAGE"
    echo "$LOG_MESSAGE_TIMESTAMP" >> "$LOG_FILE"
}

# === Env persistence ===
# Writes current state to TCP_ENV. Sourced by future tcproxy invocations
# and by the systemd EnvironmentFile.
save_env() {
    if [[ ! -f $TCP_ENV ]]; then
        touch "$TCP_ENV"
    else
        echo "# Environment variables for tcproxy. Run ./tcproxy --install to modify." > "$TCP_ENV"
    fi
    {
        echo "TCPROXY_PATH=$TCPROXY_PATH"
        echo "TCP_ENV=$TCP_ENV"
        echo "USER=$USER"
        echo "GROUP=$GROUP"
        echo "PUID=$PUID"
        echo "PGID=$PGID"
        echo "TC_IP=$TC_IP"
        echo "TC_DISK=$TC_DISK"
        echo "TC_DISK_USB=$TC_DISK_USB"
        echo "TC_USER=$TC_USER"
        echo "TC_PASSWORD=$TC_PASSWORD"
        echo "STARTUP_MOUNT=$STARTUP_MOUNT"
        echo "TCPROXY_SERVICE_FILE=$TCPROXY_SERVICE_FILE"
        echo "TCPROXY_SERVICE_TEMP_FILE=$TCPROXY_SERVICE_TEMP_FILE"
        echo "SUDOREQUIRED=$SUDOREQUIRED"
        echo "LOG_FILE=$LOG_FILE"
        echo "ARCH=$ARCH"
        echo "UNIQUE_ID=$UNIQUE_ID"
    } >> "$TCP_ENV"
    logsm "tcproxy: environment variables updated"
}

# Sources .tcproxy.env from the script's directory if present.
# Returns 0 on load, 1 if not found.
load_env_if_exists() {
    local env_path
    env_path="$(cd "$(dirname "${BASH_SOURCE[-1]}")" && pwd)/.tcproxy.env"
    if [[ -e $env_path && -s $env_path ]]; then
        # shellcheck disable=SC1090
        source "$env_path"
        return 0
    fi
    return 1
}

remove_env() {
    [[ -f $TCP_ENV ]] && sudo rm "$TCP_ENV"
    logsm ".tcproxy.env removed"
}

# === Log rotation ===
keep_log_small() {
    if [[ $(wc -l < "$LOG_FILE") -gt 1000 ]]; then
        cat "$LOG_FILE" >> "${LOG_FILE}archive.txt" && echo "" > "$LOG_FILE"
    fi
    if [[ -f "${LOG_FILE}archive.txt" ]]; then
        if [[ $(wc -l < "${LOG_FILE}archive.txt") -gt 3000 ]]; then
            tail -n 2000 "${LOG_FILE}archive.txt" > "${LOG_FILE}archive.txt.tmp" \
                && mv "${LOG_FILE}archive.txt.tmp" "${LOG_FILE}archive.txt"
        fi
    fi
}

# === Screen UI helpers ===
header() {
    echo "GNU tcproxy: mount Time Capsule / AirPort Extreme on debian kernels 5.15+.
tcproxy $TCPROXY_COMMIT: [ $SCRIPT_COMMAND ] $DESCR_COM
"
    sleep 1
}

footer() {
    echo "
tcproxy $TCPROXY_COMMIT: command completed. Try [ ./tcproxy --help ] for more options."
}

countdown() {
    local s=$1
    while [ "$s" -gt 0 ]; do
        echo -ne "Continuing in ... ${s} seconds\033[0K\r"
        sleep 1
        ((s--))
    done
    echo ""
}
