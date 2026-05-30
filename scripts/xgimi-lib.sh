#!/usr/bin/env bash
# Libreria comune XGIMI - Protocollo Flotta v1
# Canali: ADB, USB HID/Consumer, Google TV Remote, BLE wake.

# Questo file deve essere usato con: source "$BASE_DIR/xgimi-lib.sh"

XGIMI_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${BASE_DIR:-$XGIMI_LIB_DIR}"
CONF_FILE="${CONF_FILE:-$BASE_DIR/xgimi.conf}"

if [ -f "$CONF_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONF_FILE"
fi

XGIMI_IP="${XGIMI_IP:-}"
if [ -z "$XGIMI_IP" ]; then
    echo "ERRORE: XGIMI_IP non impostato. Copia config/xgimi.conf.example in xgimi.conf." >&2
    return 1 2>/dev/null || exit 1
fi
DEVICE_NAME="${DEVICE_NAME:-xgimi}"
LOG_FILE="${LOG_FILE:-$BASE_DIR/xgimi-remote.log}"
STATE_DIR="${STATE_DIR:-$BASE_DIR/state}"
ADB_STATE_FILE="${ADB_STATE_FILE:-$STATE_DIR/adb.state}"
ADB_RECOVERY_LOCK="${ADB_RECOVERY_LOCK:-$STATE_DIR/adb-recover.lock}"
ADB_PORT="${ADB_PORT:-5555}"
ADB_RECOVERY_TIMEOUT="${ADB_RECOVERY_TIMEOUT:-45}"
WAIT_NETWORK_TIMEOUT="${WAIT_NETWORK_TIMEOUT:-90}"

USB_KEY="${USB_KEY:-$BASE_DIR/xgimi-usb-key.sh}"
USB_CONSUMER="${USB_CONSUMER:-$BASE_DIR/xgimi-usb-consumer-key.sh}"
GOOGLETV_HELPER="${GOOGLETV_HELPER:-$BASE_DIR/xgimi-googletv.sh}"
ADB_HELPER="${ADB_HELPER:-$BASE_DIR/xgimi-adb.sh}"
ADB_RECOVERY_SCRIPT="${ADB_RECOVERY_SCRIPT:-$BASE_DIR/xgimi-adb-recover.sh}"

mkdir -p "$STATE_DIR" "$(dirname "$LOG_FILE")" 2>/dev/null || true

xlog() {
    local channel="${1:-main}"
    shift || true
    printf '%s [%s][%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$DEVICE_NAME" "$channel" "$*" >> "$LOG_FILE"
}

state_set() {
    local value="$1"
    printf '%s\n' "$value" > "$ADB_STATE_FILE"
    xlog state "ADB state=$value"
}

state_get() {
    if [ -f "$ADB_STATE_FILE" ]; then
        cat "$ADB_STATE_FILE"
    else
        printf 'unknown\n'
    fi
}

adb_state_available() { state_set "available"; }
adb_state_unavailable() { state_set "unavailable"; }
adb_state_recovering() { state_set "recovering"; }

is_ping_ok() {
    ping -c 1 -W 1 "$XGIMI_IP" >/dev/null 2>&1
}

wait_network() {
    local timeout="${1:-$WAIT_NETWORK_TIMEOUT}"
    local start now elapsed

    start="$(date +%s)"
    while true; do
        if is_ping_ok; then
            xlog network "rete raggiungibile: $XGIMI_IP"
            return 0
        fi

        now="$(date +%s)"
        elapsed=$((now - start))
        if [ "$elapsed" -ge "$timeout" ]; then
            xlog network "timeout rete dopo ${timeout}s: $XGIMI_IP"
            return 1
        fi

        sleep 2
    done
}

adb_serial() {
    printf '%s:%s' "$XGIMI_IP" "$ADB_PORT"
}

adb_connect_fast() {
    local serial
    serial="$(adb_serial)"

    adb connect "$serial" >/dev/null 2>&1 || return 1
    adb devices | grep -q "${serial}[[:space:]]*device" || return 1
    return 0
}

adb_shell_fast() {
    local serial
    serial="$(adb_serial)"

    adb_connect_fast || return 1
    adb -s "$serial" shell "$@"
}

mark_adb_from_probe() {
    if adb_connect_fast; then
        adb_state_available
        return 0
    fi

    adb_state_unavailable
    return 1
}

start_adb_recovery_bg() {
    if [ ! -x "$ADB_RECOVERY_SCRIPT" ]; then
        xlog adb "recovery non avviata: script non eseguibile: $ADB_RECOVERY_SCRIPT"
        return 1
    fi

    if mkdir "$ADB_RECOVERY_LOCK" 2>/dev/null; then
        adb_state_recovering
        xlog adb "avvio recovery ADB in background"
        (
            trap 'rmdir "$ADB_RECOVERY_LOCK" 2>/dev/null || true' EXIT
            "$ADB_RECOVERY_SCRIPT" --lock-held >> "$LOG_FILE" 2>&1
        ) &
        return 0
    fi

    xlog adb "recovery ADB già in corso"
    return 0
}

force_mute_usb() {
    [ -x "$USB_CONSUMER" ] || return 1

    run_root_helper "$USB_CONSUMER" volume-up >/dev/null 2>&1 || return 1
    sleep 0.2
    run_root_helper "$USB_CONSUMER" volume-down >/dev/null 2>&1 || return 1
    sleep 0.2
    run_root_helper "$USB_CONSUMER" mute >/dev/null 2>&1 || return 1
}

force_unmute_usb() {
    [ -x "$USB_CONSUMER" ] || return 1

    run_root_helper "$USB_CONSUMER" volume-up >/dev/null 2>&1 || return 1
    sleep 0.2
    run_root_helper "$USB_CONSUMER" volume-down >/dev/null 2>&1 || return 1
}

force_mute_best_effort() {
    xlog audio "force-mute: provo USB consumer"
    if force_mute_usb; then
        xlog audio "force-mute via USB OK"
        return 0
    fi

    xlog audio "force-mute USB fallito; provo Google TV"
    if [ -x "$GOOGLETV_HELPER" ] && "$GOOGLETV_HELPER" force-mute >/dev/null 2>&1; then
        xlog audio "force-mute via Google TV OK"
        return 0
    fi

    xlog audio "WARN: force-mute non riuscito"
    return 1
}

force_unmute_best_effort() {
    xlog audio "force-unmute: provo USB consumer"
    if force_unmute_usb; then
        xlog audio "force-unmute via USB OK"
        return 0
    fi

    xlog audio "force-unmute USB fallito; provo Google TV"
    if [ -x "$GOOGLETV_HELPER" ] && "$GOOGLETV_HELPER" force-unmute >/dev/null 2>&1; then
        xlog audio "force-unmute via Google TV OK"
        return 0
    fi

    xlog audio "WARN: force-unmute non riuscito"
    return 1
}


force_mute_googletv_only() {
    # Usata durante l'accensione: se Google TV non risponde, NON prova USB.
    # Motivo: durante il boot il ping/rete non garantisce che Android accetti HID.
    xlog audio "force-mute ON: provo solo Google TV"

    if [ -x "$GOOGLETV_HELPER" ] && "$GOOGLETV_HELPER" force-mute >/dev/null 2>&1; then
        xlog audio "force-mute ON via Google TV OK"
        return 0
    fi

    xlog audio "WARN: force-mute ON non eseguito: Google TV non disponibile"
    return 1
}

wait_googletv_status() {
    local timeout="${1:-45}"
    local start now elapsed

    [ -x "$GOOGLETV_HELPER" ] || {
        xlog googletv "helper non eseguibile: $GOOGLETV_HELPER"
        return 1
    }

    start="$(date +%s)"
    while true; do
        if "$GOOGLETV_HELPER" status >/dev/null 2>&1; then
            xlog googletv "Google TV Remote operativo"
            return 0
        fi

        now="$(date +%s)"
        elapsed=$((now - start))
        if [ "$elapsed" -ge "$timeout" ]; then
            xlog googletv "timeout Google TV Remote dopo ${timeout}s"
            return 1
        fi

        sleep 2
    done
}

run_root_helper() {
    # Non deve mai chiedere password durante la pressione di un tasto:
    # se sudo richiede password, fallisce subito invece di introdurre latenza.
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo -n "$@"
    fi
}

try_usb_key() {
    local key="$1"
    [ -x "$USB_KEY" ] || {
        xlog usb "keyboard helper non eseguibile: $USB_KEY"
        return 1
    }

    if run_root_helper "$USB_KEY" "$key"; then
        return 0
    fi

    xlog usb "keyboard key=$key fallito"
    return 1
}

try_usb_consumer() {
    local key="$1"
    [ -x "$USB_CONSUMER" ] || {
        xlog usb "consumer helper non eseguibile: $USB_CONSUMER"
        return 1
    }

    if run_root_helper "$USB_CONSUMER" "$key"; then
        return 0
    fi

    xlog usb "consumer key=$key fallito"
    return 1
}

try_gtv() {
    [ -x "$GOOGLETV_HELPER" ] || return 1
    "$GOOGLETV_HELPER" "$@"
}

# ─────────────────────────────────────────────────────────────────────────────
# Lock transizione ON/OFF - Protocollo Flotta v1.2
# Serve a evitare doppi comandi power durante wake/standby e rimbalzi FLIRC.
# ─────────────────────────────────────────────────────────────────────────────
POWER_TRANSITION_LOCK="${POWER_TRANSITION_LOCK:-$STATE_DIR/power-transition.lock}"
POWER_TRANSITION_TTL="${POWER_TRANSITION_TTL:-180}"

_transition_lock_age() {
    local ts now
    ts="$(cat "$POWER_TRANSITION_LOCK/started_at" 2>/dev/null || echo 0)"
    now="$(date +%s)"
    echo $((now - ts))
}

transition_lock_stale() {
    [ -d "$POWER_TRANSITION_LOCK" ] || return 1
    local age
    age="$(_transition_lock_age)"
    [ "$age" -ge "$POWER_TRANSITION_TTL" ]
}

transition_lock_exists() {
    if [ -d "$POWER_TRANSITION_LOCK" ]; then
        if transition_lock_stale; then
            xlog lock "lock transizione stale: rimuovo $POWER_TRANSITION_LOCK"
            rm -rf "$POWER_TRANSITION_LOCK" 2>/dev/null || true
            return 1
        fi
        return 0
    fi
    return 1
}

transition_lock_info() {
    if [ -d "$POWER_TRANSITION_LOCK" ]; then
        echo "cmd=$(cat "$POWER_TRANSITION_LOCK/cmd" 2>/dev/null || echo unknown)"
        echo "pid=$(cat "$POWER_TRANSITION_LOCK/pid" 2>/dev/null || echo unknown)"
        echo "started_at=$(cat "$POWER_TRANSITION_LOCK/started_at" 2>/dev/null || echo unknown)"
        echo "age=$(_transition_lock_age)"
    else
        echo "none"
    fi
}

transition_lock_acquire() {
    local cmd="${1:-unknown}"

    if transition_lock_exists; then
        xlog lock "transizione già in corso; ignoro richiesta=$cmd; $(transition_lock_info | tr '\n' ' ')"
        return 1
    fi

    if mkdir "$POWER_TRANSITION_LOCK" 2>/dev/null; then
        date +%s > "$POWER_TRANSITION_LOCK/started_at"
        echo "$$" > "$POWER_TRANSITION_LOCK/pid"
        echo "$cmd" > "$POWER_TRANSITION_LOCK/cmd"
        xlog lock "lock transizione acquisito: $cmd pid=$$"
        return 0
    fi

    # Possibile race: qualcuno ha creato il lock tra il controllo e mkdir.
    xlog lock "transizione già in corso dopo race; ignoro richiesta=$cmd"
    return 1
}

transition_lock_release() {
    if [ -d "$POWER_TRANSITION_LOCK" ]; then
        local owner
        owner="$(cat "$POWER_TRANSITION_LOCK/pid" 2>/dev/null || echo '')"
        if [ -z "$owner" ] || [ "$owner" = "$$" ]; then
            rm -rf "$POWER_TRANSITION_LOCK" 2>/dev/null || true
            xlog lock "lock transizione rilasciato pid=$$"
        else
            xlog lock "lock transizione non rilasciato: owner=$owner current=$$"
        fi
    fi
}
