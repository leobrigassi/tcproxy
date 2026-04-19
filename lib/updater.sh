#!/bin/bash
# shellcheck shell=bash
# tcproxy — self-update + VM asset download.
# Handles both the --update-check / --update flow and the one-shot
# install-time download of the suite (script + arch-specific VM image).
# Depends on: lib/config.sh (TCPROXY_FILE_*_URL, TCPROXY_TAR_URL,
#             TCPROXY_VM_VERSION_URL, TCPROXY_BRANCH, TCPROXY_RELEASE,
#             TCPROXY_COMMIT, TCPROXY_CURL_*),
#             lib/common.sh (logm, logsm, footer, ARCH).

# Checks for a newer tcproxy script upstream. In --update mode
# (MAN_UPDATE=1) it downloads and replaces the script in place; in
# --update-check mode it only reports.
#
# Logic:
# 1. Read the main branch's TCPROXY_RELEASE; if ours is older, prefer
#    that (releases take priority over branch builds).
# 2. Otherwise check the active branch's TCPROXY_COMMIT for a newer
#    commit marker.
check_or_update_script() {
    TCPROXY_RELEASE_LAST=$(curl --connect-timeout "$TCPROXY_CURL_CONNECT_TIMEOUT" --max-time "$TCPROXY_CURL_MAX_TIME" -sL "$TCPROXY_FILE_MAIN_URL" | sed -n '5p' | cut -d '=' -f 2)
    if [[ $? -ne 0 ]]; then
        if [[ $MAN_UPDATE == 1 ]]; then
            echo "tcproxy: Update server currently unavailable."
            echo "Visit the project page for more information:"
            echo "https://github.com/leobrigassi/time-capsule-proxy"
        else
            echo "tcproxy: Update server currently unavailable."
            return 1
        fi
    fi
    if [[ $TCPROXY_RELEASE_LAST != "$TCPROXY_RELEASE" ]]; then
        if [[ $MAN_UPDATE == 1 ]]; then
            logm "Downloading tcproxy $TCPROXY_RELEASE_LAST ..."
            BACKUP_FILE="backup_tcproxy_$TCPROXY_COMMIT"
            cp -f "$0" "$BACKUP_FILE"
            TEMP_FILE=$(mktemp)
            curl --connect-timeout "$TCPROXY_CURL_CONNECT_TIMEOUT" --max-time "$TCPROXY_CURL_MAX_TIME" -sL -o "$TEMP_FILE" "$TCPROXY_FILE_MAIN_URL"
            TCPROXY_FILE_DEFINED_URL=$TCPROXY_FILE_MAIN_URL
            mv "$TEMP_FILE" "$0"
            chmod +x "$0"
            logm "tcproxy: Script updated from $TCPROXY_COMMIT to $TCPROXY_RELEASE_LAST"
        else
            echo "tcproxy: New update available $TCPROXY_RELEASE_LAST. (Current $TCPROXY_RELEASE)"
            echo "To update run:  [ ./tcproxy --update ]"
            echo ""
            return 0
        fi
    else
        TCPROXY_COMMIT_LAST=$(curl --connect-timeout "$TCPROXY_CURL_CONNECT_TIMEOUT" --max-time "$TCPROXY_CURL_MAX_TIME" -sL "$TCPROXY_FILE_DEFINED_URL" | sed -n '3p' | cut -d '=' -f 2)
        if [[ $? -ne 0 ]]; then
            if [[ $MAN_UPDATE == 1 ]]; then
                echo "tcproxy: Update server currently unavailable."
                echo "Visit the project page for more information:"
                echo "https://github.com/leobrigassi/time-capsule-proxy"
            else
                echo "tcproxy: Update server currently unavailable."
                return 1
            fi
        fi
        if [[ $TCPROXY_COMMIT_LAST != "$TCPROXY_COMMIT" ]]; then
            if [[ $MAN_UPDATE == 1 ]]; then
                logm "Downloading tcproxy $TCPROXY_COMMIT_LAST ..."
                BACKUP_FILE="backup_tcproxy_$TCPROXY_COMMIT"
                cp -f "$0" "$BACKUP_FILE"
                TEMP_FILE=$(mktemp)
                curl --connect-timeout "$TCPROXY_CURL_CONNECT_TIMEOUT" --max-time "$TCPROXY_CURL_MAX_TIME" -sL -o "$TEMP_FILE" "$TCPROXY_FILE_DEFINED_URL"
                mv "$TEMP_FILE" "$0"
                chmod +x "$0"
                logm "tcproxy: Script updated from $TCPROXY_COMMIT to $TCPROXY_COMMIT_LAST"
            else
                echo "tcproxy: New update available $TCPROXY_COMMIT_LAST. (Current $TCPROXY_COMMIT)"
                echo "To update run:  [ ./tcproxy --update ]"
                return 0
            fi
        else
            logm "tcproxy: Script $TCPROXY_COMMIT is already on latest version."
            return 0
        fi
    fi
}

# Fetches the latest script for the active branch into $TCPROXY_PATH/tcproxy
# and makes it executable. Used by the web-install bootstrap.
download_latest_script() {
    echo "Downloading latest installation script..."
    TEMP_FILE=$(mktemp)
    if curl --connect-timeout "$TCPROXY_CURL_CONNECT_TIMEOUT" --max-time "$TCPROXY_CURL_MAX_TIME" -sL -o "$TEMP_FILE" "$TCPROXY_FILE_DEFINED_URL"; then
        mv "$TEMP_FILE" "$TCPROXY_PATH/tcproxy"
        chmod +x "$TCPROXY_PATH/tcproxy"
    else
        echo "[ERROR] Download failed. Please try again later"
        echo "$TCPROXY_FILE_DEFINED_URL"
        rm -f "$TEMP_FILE"
        footer
        exit 1
    fi
}

# Ensures the arch-matched VM image tarball is present, then extracts it.
# If the tarball is already in TCPROXY_PATH (local clone), it is used as-is.
# If not (wget | bash install), it is downloaded from the repo's raw URL.
github_download() {
    logm "Preparing VM image..."
    local vm_file branch_name
    if [[ $ARCH == x86_64* ]]; then
        vm_file="tcproxy_VM_x86.tar.gz"
    elif [[ $ARCH == aarch64* ]]; then
        vm_file="tcproxy_VM_aarch64.tar.gz"
    else
        logm "[ERROR] Unsupported architecture: $ARCH"
        exit 1
    fi
    if [[ ! -f $vm_file ]]; then
        branch_name="${TCPROXY_BRANCH#/*/}"
        local vm_url="https://github.com/leobrigassi/time_capsule_proxy/raw/${branch_name}/${vm_file}"
        logm "Downloading VM image from repo..."
        if ! wget -q "$vm_url" -O "$vm_file"; then
            logm "[ERROR] Failed to download $vm_file from $vm_url"
            exit 1
        fi
        logsm "Downloaded $vm_file"
    else
        logsm "Using local $vm_file"
    fi
    logm "Extracting VM image..."
    tar -xf "$vm_file" && rm -f "$vm_file"
    logsm "VM image ready."
}

# Alias for compatibility; github_download now handles extraction.
deflating_vm() {
    :
}
