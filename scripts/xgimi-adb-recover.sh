#!/usr/bin/env bash
set -u

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$BASE_DIR/xgimi-lib.sh"
LOCK_HELD="${1:-}"

ADB_AUTO_PORT="${ADB_AUTO_PORT:-9093}"
WAIT_ADB_TIMEOUT="${WAIT_ADB_TIMEOUT:-180}"
ADB_CONNECT_RESET="${ADB_CONNECT_RESET:-yes}"

LOCK_DIR="$STATE_DIR/adb-recover.lock"

adb_auto_url() {
    echo "http://$XGIMI_IP:$ADB_AUTO_PORT"
}

adb_device_is_ready() {
    adb devices 2>/dev/null | grep -q "${XGIMI_IP}:${ADB_PORT}[[:space:]]*device"
}

adb_device_is_offline() {
    adb devices 2>/dev/null | grep -q "${XGIMI_IP}:${ADB_PORT}[[:space:]]*offline"
}

adb_auto_status() {
    curl -sS --max-time 5 "$(adb_auto_url)/api/status" 2>/dev/null
}

adb_auto_logs_tail() {
    curl -sS --max-time 5 "$(adb_auto_url)/api/logs" 2>/dev/null \
        | tail -n 12
}

adb_auto_5555_available() {
    adb_auto_status | grep -q '"adb5555Available":true'
}

adb_auto_switch() {
    xlog adb-recover "richiedo switch ADB a 5555 via HTTP"
    curl -sS --max-time 10 "$(adb_auto_url)/api/switch" >> "$LOG_FILE" 2>&1 || return 1
    return 0
}

adb_local_reset_connect() {
    xlog adb-recover "reset connessione ADB locale verso ${XGIMI_IP}:${ADB_PORT}"

    adb disconnect "${XGIMI_IP}:${ADB_PORT}" >> "$LOG_FILE" 2>&1 || true

    if [ "$ADB_CONNECT_RESET" = "yes" ]; then
        adb kill-server >> "$LOG_FILE" 2>&1 || true
        adb start-server >> "$LOG_FILE" 2>&1 || true
    fi

    adb connect "${XGIMI_IP}:${ADB_PORT}" >> "$LOG_FILE" 2>&1 || true
}

acquire_lock() {
    mkdir -p "$STATE_DIR"

    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo "$$" > "$LOCK_DIR/pid"
        return 0
    fi

    xlog adb-recover "recovery già in corso; esco"
    return 1
}

release_lock() {
    rm -rf "$LOCK_DIR" 2>/dev/null || true
}

main() {
    if [ "$LOCK_HELD" != "--lock-held" ]; then
        if ! acquire_lock; then
            exit 0
        fi
        trap release_lock EXIT
    else
        xlog adb-recover "lock già acquisito dal chiamante"
    fi

    xlog adb-recover "inizio recovery: ip=$XGIMI_IP porta=$ADB_PORT timeout=${WAIT_ADB_TIMEOUT}s"
    adb_state_recovering

    local start now elapsed status

    start="$(date +%s)"

    while true; do
        now="$(date +%s)"
        elapsed=$((now - start))

        if adb_device_is_ready; then
            adb_state_available
            xlog adb-recover "ADB disponibile su ${XGIMI_IP}:${ADB_PORT}"
            exit 0
        fi

        if adb_device_is_offline; then
            xlog adb-recover "ADB locale risulta offline; provo reset connessione"
            adb_local_reset_connect

            if adb_device_is_ready; then
                adb_state_available
                xlog adb-recover "ADB recuperato dopo reset locale"
                exit 0
            fi
        fi

        status="$(adb_auto_status || true)"

        if [ -n "$status" ]; then
            xlog adb-recover "ADB Auto status: $status"

            if echo "$status" | grep -q '"adb5555Available":true'; then
                xlog adb-recover "ADB Auto segnala 5555 disponibile; provo connect"
                adb_local_reset_connect

                if adb_device_is_ready; then
                    adb_state_available
                    xlog adb-recover "ADB disponibile dopo status HTTP"
                    exit 0
                fi
            else
                xlog adb-recover "ADB Auto non segnala 5555 disponibile; provo switch"
                adb_auto_switch || xlog adb-recover "WARN: switch HTTP fallito"
            fi
        else
            xlog adb-recover "ADB Auto HTTP non disponibile su $(adb_auto_url)"
        fi

        if [ "$elapsed" -ge "$WAIT_ADB_TIMEOUT" ]; then
            adb_state_unavailable
            xlog adb-recover "timeout ADB dopo ${WAIT_ADB_TIMEOUT}s"

            xlog adb-recover "ultimi log ADB Auto:"
            adb_auto_logs_tail >> "$LOG_FILE" 2>&1 || true

            exit 1
        fi

        sleep 5
    done
}

main "$@"
