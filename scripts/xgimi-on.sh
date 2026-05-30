#!/usr/bin/env bash
set -u

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$BASE_DIR/xgimi-lib.sh"

XGIMI_BLE_WAKE_SCRIPT="${XGIMI_BLE_WAKE_SCRIPT:-$BASE_DIR/xgimi-ble-wake70.sh}"
XGIMI_BLE_WAKE_SECONDS="${XGIMI_BLE_WAKE_SECONDS:-3}"
XGIMI_BLE_WAKE_COUNTERS="${XGIMI_BLE_WAKE_COUNTERS:-2e 30 31 32 33}"

ENABLE_WOL_WAKE="${ENABLE_WOL_WAKE:-yes}"
XGIMI_WIFI_MAC="${XGIMI_WIFI_MAC:-}"

ENABLE_CEC_WAKE="${ENABLE_CEC_WAKE:-yes}"
ENABLE_FORCE_MUTE_ON="${ENABLE_FORCE_MUTE_ON:-yes}"

WAIT_NETWORK_TIMEOUT="${WAIT_NETWORK_TIMEOUT:-60}"
WAIT_NETWORK_TIMEOUT_BEFORE_WOL="${WAIT_NETWORK_TIMEOUT_BEFORE_WOL:-${WAIT_NETWORK_TIMEOUT_BEFORE_CEC:-20}}"
WAIT_GOOGLETV_TIMEOUT="${WAIT_GOOGLETV_TIMEOUT:-180}"
ENABLE_RETRY_WAKE_WHEN_GOOGLETV_OFF="${ENABLE_RETRY_WAKE_WHEN_GOOGLETV_OFF:-yes}"
GOOGLETV_OFF_RETRY_AFTER="${GOOGLETV_OFF_RETRY_AFTER:-3}"
ENABLE_GOOGLETV_POWER_RETRY="${ENABLE_GOOGLETV_POWER_RETRY:-yes}"
ENABLE_CEC_RETRY_WAKE="${ENABLE_CEC_RETRY_WAKE:-yes}"

# Integrazione LMS/Jivelite: notifica stato accensione su piCorePlayer.
# Non deve mai bloccare la sequenza XGIMI: se LMS non risponde, si limita a loggare il warning.
ENABLE_LMS_DISPLAY="${ENABLE_LMS_DISPLAY:-no}"
LMS_HOST="${LMS_HOST:-}"
LMS_PORT="${LMS_PORT:-9090}"
LMS_PLAYER_ID="${LMS_PLAYER_ID:-}"
LMS_DISPLAY_TITLE="${LMS_DISPLAY_TITLE:-XGIMI ON}"



urlencode_lms() {
    python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

lms_show_status() {
    local line2="${1:-}"
    local duration="${2:-8}"
    local e_line1
    local e_line2

    if [ "$ENABLE_LMS_DISPLAY" != "yes" ]; then
        return 0
    fi

    if [ -z "$LMS_HOST" ] || [ -z "$LMS_PLAYER_ID" ]; then
        xlog lms "LMS display non configurato: LMS_HOST o LMS_PLAYER_ID vuoto"
        return 0
    fi

    if ! command -v nc >/dev/null 2>&1; then
        xlog lms "LMS display non disponibile: comando nc mancante"
        return 0
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        xlog lms "LMS display non disponibile: python3 mancante"
        return 0
    fi

    e_line1="$(urlencode_lms "$LMS_DISPLAY_TITLE")"
    e_line2="$(urlencode_lms "$line2")"

    echo "$LMS_PLAYER_ID show line1:$e_line1 line2:$e_line2 duration:$duration" \
        | nc -w 2 "$LMS_HOST" "$LMS_PORT" >/dev/null 2>&1 || \
            xlog lms "WARN: invio messaggio LMS fallito: $line2"
}

lms_show_phase() {
    lms_show_status "$1" 300
}

lms_show_done() {
    lms_show_status "Sequenza OK" 30
}

lms_show_error() {
    lms_show_status "ERRORE accensione" 60
}

send_ble_wake_all_counters() {
    local counter
    local rc=0

    if [ ! -x "$XGIMI_BLE_WAKE_SCRIPT" ]; then
        xlog on "ERRORE: script BLE wake non eseguibile: $XGIMI_BLE_WAKE_SCRIPT"
        return 2
    fi

    xlog on "invio BLE wake con counter multipli: $XGIMI_BLE_WAKE_COUNTERS"
    xlog on "durata per counter: ${XGIMI_BLE_WAKE_SECONDS}s"

    for counter in $XGIMI_BLE_WAKE_COUNTERS; do
        xlog on "BLE wake counter=$counter"

        sudo "$XGIMI_BLE_WAKE_SCRIPT" \
            "$XGIMI_BLE_WAKE_SECONDS" \
            "$counter" >> "$LOG_FILE" 2>&1

        if [ "$?" -ne 0 ]; then
            xlog on "WARN: BLE wake fallito con counter=$counter"
            rc=1
        fi
    done

    return "$rc"
}

send_wol_wake() {
    if [ "$ENABLE_WOL_WAKE" != "yes" ]; then
        xlog on "WOL disabilitato"
        return 1
    fi

    if [ -z "$XGIMI_WIFI_MAC" ]; then
        xlog on "WOL non possibile: XGIMI_WIFI_MAC non impostato"
        return 1
    fi

    if command -v wakeonlan >/dev/null 2>&1; then
        xlog on "invio WOL con wakeonlan a $XGIMI_WIFI_MAC"
        wakeonlan "$XGIMI_WIFI_MAC" >> "$LOG_FILE" 2>&1
        return $?
    fi

    if command -v etherwake >/dev/null 2>&1; then
        xlog on "invio WOL con etherwake a $XGIMI_WIFI_MAC"
        sudo etherwake "$XGIMI_WIFI_MAC" >> "$LOG_FILE" 2>&1
        return $?
    fi

    xlog on "WOL non disponibile: installare wakeonlan o etherwake"
    return 1
}

send_cec_wake_no_input_change() {
    if [ "$ENABLE_CEC_WAKE" != "yes" ]; then
        xlog on "CEC wake disabilitato"
        return 1
    fi

    if ! command -v cec-client >/dev/null 2>&1; then
        xlog on "cec-client non disponibile"
        return 1
    fi

    xlog on "invio CEC wake: 'on 0', senza active source"
    printf "on 0\n" | cec-client -s -d 1 >> "$LOG_FILE" 2>&1 || true
    sleep 2
    return 0
}

wait_network_stable() {
    local timeout="${1:-60}"
    local required="${2:-5}"
    local count=0
    local start now elapsed

    xlog network "Attendo rete stabile: ${required} ping consecutivi, timeout=${timeout}s"

    start="$(date +%s)"

    while true; do
        if ping -c 1 -W 1 "$XGIMI_IP" >/dev/null 2>&1; then
            count=$((count + 1))
            xlog network "Ping OK consecutivi: $count/$required"

            if [ "$count" -ge "$required" ]; then
                xlog network "Rete stabile confermata"
                ip neigh show "$XGIMI_IP" >> "$LOG_FILE" 2>&1 || true
                return 0
            fi
        else
            if [ "$count" -ne 0 ]; then
                xlog network "Ping fallito: azzero contatore rete stabile"
            fi
            count=0
        fi

        now="$(date +%s)"
        elapsed=$((now - start))

        if [ "$elapsed" -ge "$timeout" ]; then
            xlog network "Timeout rete stabile dopo ${timeout}s"
            ip neigh show "$XGIMI_IP" >> "$LOG_FILE" 2>&1 || true
            return 1
        fi

        sleep 1
    done
}

retry_wake_when_googletv_responds_but_off() {
    xlog on "Retry wake: rete stabile, Google TV risponde, ma XGIMI non risulta acceso"

    xlog on "Retry wake: reinvio BLE wake"
    send_ble_wake_all_counters || xlog on "WARN: retry BLE wake non completato correttamente"

    if [ "$ENABLE_CEC_RETRY_WAKE" = "yes" ]; then
        xlog on "Retry wake: provo CEC wake di rinforzo"
        send_cec_wake_no_input_change || xlog on "WARN: retry CEC wake non riuscito"
    else
        xlog on "Retry wake: CEC retry disabilitato"
    fi

    xlog on "Retry wake: reinvio WOL come fallback"
    send_wol_wake || xlog on "WARN: retry WOL non riuscito o non disponibile"

    if [ "$ENABLE_GOOGLETV_POWER_RETRY" = "yes" ]; then
        xlog on "Retry wake: invio Google TV KEY POWER perché is_on=False"
        "$GOOGLETV_HELPER" key POWER >> "$LOG_FILE" 2>&1 || \
            xlog on "WARN: retry Google TV KEY POWER fallito"
    else
        xlog on "Retry wake: Google TV KEY POWER disabilitato"
    fi
}

wait_googletv_status_stable() {
    local required="${1:-2}"
    local timeout="${2:-180}"
    local count=0
    local off_count=0
    local retry_done=0
    local start now elapsed
    local tmp_status

    tmp_status="/tmp/xgimi-googletv-status.$$"

    xlog googletv "Attendo Google TV stabile/acceso: ${required} status is_on=True consecutivi, timeout=${timeout}s"

    start="$(date +%s)"

    while true; do
        if "$GOOGLETV_HELPER" status > "$tmp_status" 2>&1; then
            cat "$tmp_status" >> "$LOG_FILE"

            if grep -q "is_on=True" "$tmp_status"; then
                count=$((count + 1))
                xlog googletv "Google TV acceso OK consecutivi: $count/$required"

                if [ "$count" -ge "$required" ]; then
                    xlog googletv "Google TV Remote stabile e XGIMI acceso"
                    rm -f "$tmp_status"
                    return 0
                fi
                else
                    count=0
                    off_count=$((off_count + 1))
                    xlog googletv "Google TV risponde ma XGIMI non risulta acceso ($off_count/$GOOGLETV_OFF_RETRY_AFTER)"

                    if [ "$ENABLE_RETRY_WAKE_WHEN_GOOGLETV_OFF" = "yes" ] && \
                    [ "$retry_done" -eq 0 ] && \
                    [ "$off_count" -ge "$GOOGLETV_OFF_RETRY_AFTER" ]; then

                        retry_done=1
                        retry_wake_when_googletv_responds_but_off
                        off_count=0
                    fi
                fi
        else
            count=0
            off_count=0
            xlog googletv "Google TV status fallito"
        fi

        now="$(date +%s)"
        elapsed=$((now - start))

        if [ "$elapsed" -ge "$timeout" ]; then
            xlog googletv "Timeout attesa Google TV acceso/stabile dopo ${timeout}s"
            rm -f "$tmp_status"
            return 1
        fi

        sleep 3
    done
}

main() {
    xlog on "============================================================"
    xlog on "richiesta accensione XGIMI"
    xlog on "Protocollo ON: BLE sempre, CEC subito, WOL solo se rete non stabile"

    if ! transition_lock_acquire "power-on"; then
        xlog on "transizione power già in corso: power-on ignorato"
        exit 0
    fi

    trap transition_lock_release EXIT

    adb_state_unavailable
    lms_show_phase "Accensione XGIMI"

    # 1. Sempre BLE, con tutti i counter censiti
    lms_show_phase "Invio BLE wake"
    send_ble_wake_all_counters || xlog on "WARN: BLE wake non completato correttamente"

    # 2. CEC subito dopo BLE: empiricamente più efficace del WOL
    lms_show_phase "Invio CEC wake"
    send_cec_wake_no_input_change || xlog on "WARN: CEC wake non riuscito"

    # 3. Dopo BLE/CEC, controllo rete stabile; se non arriva, provo WOL come fallback
    lms_show_phase "Attesa rete"
    xlog on "Attendo 10s prima della verifica rete dopo BLE/CEC"
    sleep 10

    if wait_network_stable "$WAIT_NETWORK_TIMEOUT_BEFORE_WOL" 3; then
        xlog on "Rete stabile dopo BLE/CEC: proseguo"
        lms_show_phase "Rete OK"
    else
        xlog on "Rete non stabile dopo BLE/CEC: provo WOL come fallback"
        lms_show_phase "Provo WOL"
        send_wol_wake || xlog on "WARN: WOL non riuscito o non disponibile"

        xlog on "Verifica rete dopo WOL fallback"
        lms_show_phase "Attesa rete WOL"
        wait_network_stable 30 3 || \
            xlog on "WARN: rete ancora non stabile dopo WOL; proseguo comunque con Google TV"
    fi

    # 4. Recovery ADB in background: non blocca l'accensione
    lms_show_phase "Recupero ADB"
    start_adb_recovery_bg >/dev/null 2>&1 || true

    # 5. Attesa Google TV stabile e force mute
    lms_show_phase "Attesa Google TV"
    if wait_googletv_status_stable 2 "$WAIT_GOOGLETV_TIMEOUT"; then
        if [ "$ENABLE_FORCE_MUTE_ON" = "yes" ]; then
            lms_show_phase "Forzo mute"
            force_mute_googletv_only || xlog on "WARN: force-mute Google TV non riuscito"
        else
            xlog on "Force mute su ON disabilitato"
        fi

        lms_show_done
        xlog on "sequenza accensione completata; recovery ADB in background"
    else
        xlog on "WARN: Google TV non stabile/acceso; force-mute ON saltato"
        lms_show_error
        xlog on "sequenza accensione completata con warning; recovery ADB in background"
    fi
}

main "$@"
