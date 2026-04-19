#!/bin/bash
# shellcheck shell=bash
# tcproxy — server I/O.
# ALL outbound HTTP to the project server goes through this file.
# Only one caller exists: --remote-log (user-initiated).
# Depends on: lib/config.sh (TCPROXY_SERVER_URL, curl tunables),
#             lib/common.sh (logm, UNIQUE_ID, ARCH, LOG_FILE).

# Post the last 100 log lines to the project server.
# Returns 0 on HTTP 200, non-zero otherwise.
remote_log() {
    local last_lines response response_code
    last_lines=$(tail -n 100 "$LOG_FILE")
    response=$(curl \
        --connect-timeout "$TCPROXY_CURL_CONNECT_TIMEOUT" \
        --max-time "$TCPROXY_CURL_MAX_TIME" \
        -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -d "$UNIQUE_ID;$ARCH;$TCPROXY_COMMIT;$last_lines" \
        "$TCPROXY_SERVER_URL")
    response_code=$(echo "$response" | tail -c 4)
    if [[ "$response_code" == "200" ]]; then
        logm "Remote log sent correctly."
        return 0
    else
        logm "[ERROR $response] Log server down. Try again later."
        return 1
    fi
}
