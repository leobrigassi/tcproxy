#!/bin/bash
# shellcheck shell=bash
# tcproxy — systemd service + timer install/remove.
# Depends on: lib/config.sh (TCPROXY_SERVICE_NAME, TCPROXY_SERVICE_FILE,
#             TCPROXY_TIMER_NAME, TCPROXY_TIMER_FILE, TCPROXY_HOST_MOUNT_ROOT),
#             lib/common.sh (logm, logsc, TCPROXY_PATH, TCP_ENV, USER, GROUP).

# Writes the tcproxy boot-load .service and .timer unit files to the
# tcproxy folder as staging files. The actual install (cp to
# /etc/systemd/system + enable) happens in install_system_service.
# Gated on STARTUP_MOUNT being yes.
tcproxy_systemd_setup() {
    if [[ "$STARTUP_MOUNT" =~ ^[Yy]$ ]]; then
        if ! [ -d /run/systemd/system ]; then
            logm "[ERROR] systemctl not detected, script requires systemd. System service has not been installed."
            return 1
        fi
        TCPROXY_SERVICE_TEMP_FILE=$TCPROXY_PATH/.tcproxy-boot-load.service
        touch "$TCPROXY_SERVICE_TEMP_FILE"
        echo "[Unit]
Description=tcproxy load VM and mount on $TCPROXY_HOST_MOUNT_ROOT
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=$TCP_ENV
ExecStart=$TCPROXY_PATH/tcproxy --startup-boot
WorkingDirectory=$TCPROXY_PATH
ExecStartPost=/bin/sleep 1
RemainAfterExit=yes
KillMode=none
User=$USER
Group=$GROUP

[Install]
WantedBy=multi-user.target" > "$TCPROXY_SERVICE_TEMP_FILE"

        touch "$TCPROXY_PATH/.tcproxy-boot-load.timer"
        echo "[Unit]
Description=tcproxy health check on VM and mount on $TCPROXY_HOST_MOUNT_ROOT

[Timer]
OnCalendar=*:0/30
Persistent=true

[Install]
WantedBy=timers.target" > "$TCPROXY_PATH/.tcproxy-boot-load.timer"

    fi
}

# Removes any previously installed tcproxy boot unit (v1 and v2 names)
# plus the health-check timer. Idempotent: missing files are ignored.
remove_system_service() {
    logm "Scanning for previously installed daemons..."
    if [[ -f /etc/systemd/system/time-capsule-proxy.service ]]; then
        logsc sudo systemctl stop time-capsule-proxy.service
        logsc sudo systemctl disable time-capsule-proxy.service
        logsc sudo rm /etc/systemd/system/time-capsule-proxy.service
        logm "Found and removed boot service v1"
    fi
    if [[ -f $TCPROXY_SERVICE_FILE ]]; then
        logsc sudo systemctl stop "$TCPROXY_SERVICE_NAME"; sleep 5
        logsc sudo systemctl disable "$TCPROXY_SERVICE_NAME"; sleep 5
        logsc sudo rm "$TCPROXY_SERVICE_FILE"
        logsc sudo systemctl daemon-reload
        logm "Found and removed boot service v2"
    fi
    if [[ -f $TCPROXY_TIMER_FILE ]]; then
        logsc sudo systemctl stop "$TCPROXY_TIMER_NAME"; sleep 5
        logsc sudo systemctl disable "$TCPROXY_TIMER_NAME"; sleep 5
        logsc sudo rm "$TCPROXY_TIMER_FILE"
        logsc sudo systemctl daemon-reload
        logm "Found and removed health-check service v2"
    fi
    logm "Startup daemon disabled and removed..."
}

# Copies the staged unit files into /etc/systemd/system, enables and
# starts both the boot service and the health-check timer.
install_system_service() {
    logm "Installing startup daemon..."
    logsc sudo cp "$TCPROXY_SERVICE_TEMP_FILE" "$TCPROXY_SERVICE_FILE"
    logsc sudo systemctl daemon-reload; sleep 3
    logsc sudo systemctl enable --now "$TCPROXY_SERVICE_NAME"; sleep 5
    logsc sudo systemctl is-active --quiet "$TCPROXY_SERVICE_NAME"; sleep 3
    if [ $? -eq 0 ]; then
        logm "Service enabled at boot."
    else
        logm "[ERROR] Failed to start $TCPROXY_SERVICE_FILE - Error code $?"
    fi
    logm "Installing health-check daemon..."
    logsc sudo cp "$TCPROXY_PATH/.tcproxy-boot-load.timer" "$TCPROXY_TIMER_FILE"
    logsc sudo systemctl daemon-reload; sleep 3
    logsc sudo systemctl enable --now "$TCPROXY_TIMER_NAME"; sleep 5
    logsc sudo systemctl is-active --quiet "$TCPROXY_TIMER_NAME"; sleep 3
    if [ $? -eq 0 ]; then
        logm "Health check enabled in systemd"
    else
        logm "[ERROR] Failed to start $TCPROXY_TIMER_NAME - Error code $?"
    fi
}
