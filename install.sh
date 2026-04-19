#!/bin/bash
# shellcheck shell=bash
# tcproxy — web-install bootstrap.
#
# Usage (from any shell):
#   wget -O - https://github.com/leobrigassi/time_capsule_proxy/raw/main/install.sh | bash
#
# What it does:
# 1. Creates a ./tcproxy folder if not already in one.
# 2. Downloads the latest release-concatenated tcproxy script.
# 3. Execs it with --install, which reruns this flow inside the proper
#    folder with a real tty handed through by the dispatcher.
#
# This is the only entry point that is intentionally thin: everything
# non-trivial lives in the main script so a single code path is
# maintained.

set -e

INSTALL_BRANCH="${INSTALL_BRANCH:-main}"
INSTALL_URL="https://raw.githubusercontent.com/leobrigassi/time_capsule_proxy/${INSTALL_BRANCH}/tcproxy"

if [[ "$(basename "$(pwd)")" != "tcproxy" ]]; then
    mkdir -p tcproxy
    cd tcproxy
fi

echo "Downloading tcproxy from branch ${INSTALL_BRANCH}..."
TEMP_FILE="$(mktemp)"
if ! curl --connect-timeout 5 --max-time 30 -fsSL -o "$TEMP_FILE" "$INSTALL_URL"; then
    echo "[ERROR] Failed to download tcproxy from $INSTALL_URL"
    rm -f "$TEMP_FILE"
    exit 1
fi

mv "$TEMP_FILE" ./tcproxy
chmod +x ./tcproxy

exec ./tcproxy --install
