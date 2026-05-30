#!/usr/bin/env bash
set -u

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$BASE_DIR/xgimi-lib.sh"

log() {
    xlog off "$*"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$DEVICE_NAME][off] $*"
}

main() {
    log "============================================================"
    log "Richiesta standby XGIMI"
    log "Modalità: Google TV Remote POWER, senza ADB"

    if transition_lock_exists; then
        log "Transizione power già in corso: standby ignorato"
        transition_lock_info >> "$LOG_FILE" 2>&1 || true
        exit 0
    fi

    if ! transition_lock_acquire "power-off"; then
        log "Transizione power già in corso dopo race: standby ignorato"
        exit 0
    fi
    trap transition_lock_release EXIT

    if ! is_ping_ok; then
        log "XGIMI non raggiungibile in rete: considero già spento/non controllabile"
        ip neigh show "$XGIMI_IP" 2>/dev/null | tee -a "$LOG_FILE" || true
        exit 0
    fi

    if [ ! -x "$GOOGLETV_HELPER" ]; then
        log "ERRORE: Google TV helper non disponibile/eseguibile: $GOOGLETV_HELPER"
        exit 2
    fi

    log "Verifica Google TV Remote: status"
    "$GOOGLETV_HELPER" status >> "$LOG_FILE" 2>&1 || {
        log "ERRORE: Google TV Remote non disponibile; standby non inviato"
        exit 3
    }

    # POWER su Google TV Remote è un toggle.
    # In OFF lo usiamo solo dopo ping+status, quindi il dispositivo è acceso/raggiungibile.
    log "Invio standby tramite Google TV Remote: POWER"
    "$GOOGLETV_HELPER" key POWER >> "$LOG_FILE" 2>&1 || {
        log "ERRORE: comando POWER non inviato"
        exit 4
    }

    log "Comando standby inviato"
}

main "$@"
