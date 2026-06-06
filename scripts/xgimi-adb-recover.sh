#!/usr/bin/env bash
set -u

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$BASE_DIR/xgimi-lib.sh"
LOCK_HELD="${1:-}"

ADB_AUTO_PORT="${ADB_AUTO_PORT:-9093}"
WAIT_ADB_TIMEOUT="${WAIT_ADB_TIMEOUT:-180}"
ADB_CONNECT_RESET="${ADB_CONNECT_RESET:-yes}"
LMS_DISPLAY_TITLE="XGIMI ADB"

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

adb_auto_last_port_from_status() {
    echo "$1" | sed -n 's/.*"lastPort":[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n 1
}

adb_auto_status_in_progress() {
    echo "$1" | grep -Eq '"lastStatus":"(Enabling wireless debugging|Discovering ADB port|Port switch started)'
}

adb_auto_status_failed() {
    echo "$1" | grep -Eq '"lastStatus":"(Failed|Failed after|Failed - could not switch port)'
}

adb_auto_switch_with_cooldown() {
    if ! adb_switch_cooldown_ok; then
        return 1
    fi

    adb_switch_mark_done
    adb_auto_switch
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
    lms_show_phase "Recupero ADB"

    local start now elapsed status last_port bad_port log_port rc

    start="$(date +%s)"
    attempt=0

    while true; do
        attempt=$((attempt + 1))
        lms_show_attempt "Recupero ADB" "$attempt"
        now="$(date +%s)"
        elapsed=$((now - start))

        if adb_device_is_ready; then
            adb_state_available
            xlog adb-recover "ADB disponibile su ${XGIMI_IP}:${ADB_PORT}"
            lms_show_done "ADB OK"
            exit 0
        fi

        if adb_device_is_offline; then
            xlog adb-recover "ADB locale risulta offline; provo reset connessione"
            adb_local_reset_connect

            if adb_device_is_ready; then
                adb_state_available
                xlog adb-recover "ADB recuperato dopo reset locale"
                lms_show_done "ADB recuperato"
                exit 0
            fi
        fi

        last_port="$(adb_discover_dynamic_port_avahi || true)"

        if [ -n "$last_port" ]; then
            echo "$last_port" > "$ADB_DYNAMIC_PORT_FILE"
            xlog adb-recover "Avahi segnala porta ADB dinamica attuale: $last_port"

            bad_port="$(cat "$ADB_BAD_DYNAMIC_PORT_FILE" 2>/dev/null || true)"

            if [ "$last_port" = "$bad_port" ]; then
                xlog adb-recover "porta dinamica Avahi $last_port già fallita: non riprovo connect manuale"
            else
                lms_show_attempt "ADB Avahi $last_port" "$attempt"

                adb_connect_dynamic_and_switch_5555 "$last_port"
                rc=$?

                if [ "$rc" -eq 0 ]; then
                    xlog adb-recover "ADB disponibile dopo switch manuale da porta Avahi"
                    rm -f "$ADB_BAD_DYNAMIC_PORT_FILE" 2>/dev/null || true
                    rm -f "$ADB_AUTH_BLOCK_FILE" 2>/dev/null || true
                    lms_show_done "ADB 5555 recuperata"
                    exit 0
                elif [ "$rc" -eq 2 ]; then
                    xlog adb-recover "ADB richiede pairing/autorizzazione su porta Avahi: sospendo recovery inutile"
                    lms_show_error "ADB da autorizzare"
                    adb_state_unavailable
                    exit 2
                else
                    echo "$last_port" > "$ADB_BAD_DYNAMIC_PORT_FILE"
                    xlog adb-recover "porta dinamica Avahi $last_port marcata come fallita"
                    lms_show_attempt "Porta Avahi fallita" "$attempt"
                fi
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
                lms_show_done "ADB OK via HTTP"
                exit 0
            fi
        else
            last_port="$(adb_auto_last_port_from_status "$status")"

            if [ -n "$last_port" ]; then
                echo "$last_port" > "$ADB_DYNAMIC_PORT_FILE"
                xlog adb-recover "ADB Auto segnala porta dinamica: $last_port"

                bad_port="$(cat "$ADB_BAD_DYNAMIC_PORT_FILE" 2>/dev/null || true)"

                if [ "$last_port" = "$bad_port" ]; then
                    xlog adb-recover "porta dinamica $last_port già fallita: non riprovo connect manuale"
                else
                    adb_connect_dynamic_and_switch_5555 "$last_port"
                    rc=$?

                    if [ "$rc" -eq 0 ]; then
                        xlog adb-recover "ADB disponibile dopo switch manuale da porta dinamica"
                        rm -f "$ADB_BAD_DYNAMIC_PORT_FILE" 2>/dev/null || true
                        rm -f "$ADB_AUTH_BLOCK_FILE" 2>/dev/null || true
                        lms_show_done "ADB 5555 recuperata"
                        exit 0
                    elif [ "$rc" -eq 2 ]; then
                        xlog adb-recover "ADB richiede pairing/autorizzazione: sospendo recovery inutile"
                        lms_show_error "ADB da autorizzare"
                        adb_state_unavailable
                        exit 2
                    else
                        echo "$last_port" > "$ADB_BAD_DYNAMIC_PORT_FILE"
                        xlog adb-recover "porta dinamica $last_port marcata come fallita"
                        lms_show_attempt "Porta ADB fallita" "$attempt"
                    fi
                fi
            fi

            if adb_auto_status_in_progress "$status"; then
                xlog adb-recover "ADB Auto è già in lavorazione; non richiedo nuovo switch"
            elif adb_auto_status_failed "$status"; then
                xlog adb-recover "ADB Auto in stato failed; provo switch HTTP solo con cooldown"
                lms_show_attempt "Switch ADB HTTP" "$attempt"
                adb_auto_switch_with_cooldown || xlog adb-recover "WARN: switch HTTP non eseguito o fallito"
            else
                xlog adb-recover "ADB Auto non segnala 5555 disponibile; provo switch HTTP con cooldown"
                adb_auto_switch_with_cooldown || xlog adb-recover "WARN: switch HTTP non eseguito o fallito"
            fi
        fi
        else
            xlog adb-recover "ADB Auto HTTP non disponibile su $(adb_auto_url)"
            lms_show_attempt "ADB Auto non risponde" "$attempt"
        fi

        if [ "$elapsed" -ge "$WAIT_ADB_TIMEOUT" ]; then
            adb_state_unavailable
            xlog adb-recover "timeout ADB dopo ${WAIT_ADB_TIMEOUT}s"
            lms_show_error "ADB non disponibile"

            xlog adb-recover "ultimi log ADB Auto:"
            adb_auto_logs_tail >> "$LOG_FILE" 2>&1 || true

            exit 1
        fi

        sleep 5
    done
}

main "$@"
