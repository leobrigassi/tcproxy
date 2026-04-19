#!/bin/bash
# shellcheck shell=bash
# tcproxy — VM asset download and install-time script fetch.
# Depends on: lib/config.sh (TCPROXY_FILE_DEFINED_URL, TCPROXY_BRANCH,
#             TCPROXY_CURL_*), lib/common.sh (logm, logsm, footer, ARCH).

# Fetches the latest tcproxy script into $TCPROXY_PATH/tcproxy.
# Used by the web-install bootstrap (wget | bash) to persist the script
# locally so future runs don't need to re-download.
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
        local vm_url="https://github.com/leobrigassi/tcproxy/raw/${branch_name}/${vm_file}?t=$(date +%s)"
        logm "Downloading VM image from repo..."
        if ! wget -q --timeout=30 --no-compress "$vm_url" -O "$vm_file"; then
            logm "[ERROR] Failed to download $vm_file from $vm_url"
            rm -f "$vm_file"
            exit 1
        fi
        if [[ ! -s "$vm_file" ]]; then
            logm "[ERROR] Downloaded file is empty or corrupt"
            rm -f "$vm_file"
            exit 1
        fi
        logsm "Downloaded $vm_file ($(du -h "$vm_file" | cut -f1))"
    else
        logsm "Using local $vm_file"
    fi
    logm "Extracting VM image..."
    if ! tar -xJ -f "$vm_file"; then
        logm "[ERROR] Failed to extract $vm_file"
        rm -f "$vm_file"
        exit 1
    fi
    rm -f "$vm_file"
    logsm "VM image ready."
}
