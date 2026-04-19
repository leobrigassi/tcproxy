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

# Downloads the arch-matched VM image. The monolith (./tcproxy) is
# already in the repo and committed at each version, so we skip the
# source tarball entirely. This keeps installs lightweight and avoids
# redundant tarball churn in git history.
github_download() {
    logm "Downloading tcproxy VM image from server..."
    sudo rm tcproxy_VM*.tar.gz >/dev/null 2>&1
    if [[ $ARCH == x86_64* ]]; then
        wget "$TCPROXY_VM_VERSION_URL/tcproxy_VM_x86.tar.gz" >/dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            logsm "Download successful $TCPROXY_VM_VERSION_URL/tcproxy_VM_x86.tar.gz"
        else
            logm "tcproxy: Update server currently unavailable. $TCPROXY_VM_VERSION_URL/tcproxy_VM_x86.tar.gz"
            exit 1
        fi
    elif [[ $ARCH == aarch64* ]]; then
        wget "$TCPROXY_VM_VERSION_URL/tcproxy_VM_aarch64.tar.gz" >/dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            logsm "Download successful $TCPROXY_VM_VERSION_URL/tcproxy_VM_aarch64.tar.gz"
        else
            logm "tcproxy: Update server currently unavailable. $TCPROXY_VM_VERSION_URL/tcproxy_VM_aarch64.tar.gz"
            exit 1
        fi
    fi
    tar -xf tcproxy_VM*.tar.gz && sudo rm tcproxy_VM*.tar.gz >/dev/null 2>&1
}

# Extracts the arch-matched VM image tarball after github_download.
deflating_vm() {
    logm "Deflating VM disk..."
    if [[ $ARCH == x86_64* ]]; then
        sudo tar -xf tcproxy_VM_x86.tar.gz
    elif [[ $ARCH == aarch64* ]]; then
        sudo tar -xf tcproxy_VM_aarch64.tar.gz
    fi
    sudo rm tcproxy_VM_aarch64.tar.gz 2>/dev/null
    sudo rm tcproxy_VM_x86.tar.gz 2>/dev/null
}
