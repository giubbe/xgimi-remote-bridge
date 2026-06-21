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

ADB_AUTO_HTTP_PORT="${ADB_AUTO_HTTP_PORT:-9093}"
ADB_SWITCH_COOLDOWN="${ADB_SWITCH_COOLDOWN:-60}"
ADB_SWITCH_LAST_FILE="${ADB_SWITCH_LAST_FILE:-$STATE_DIR/adb-switch.last}"
ADB_DYNAMIC_PORT_FILE="${ADB_DYNAMIC_PORT_FILE:-$STATE_DIR/adb-dynamic.port}"
ADB_BAD_DYNAMIC_PORT_FILE="${ADB_BAD_DYNAMIC_PORT_FILE:-$STATE_DIR/adb-bad-dynamic.port}"
ADB_AUTH_BLOCK_FILE="${ADB_AUTH_BLOCK_FILE:-$STATE_DIR/adb-auth-required}"
ADB_AUTH_BLOCK_TTL="${ADB_AUTH_BLOCK_TTL:-3600}"

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

# ─────────────────────────────────────────────────────────────────────────────
# Integrazione LMS/Jivelite: notifica stato su piCorePlayer.
# Non deve mai bloccare gli script XGIMI.
# ─────────────────────────────────────────────────────────────────────────────

ENABLE_LMS_DISPLAY="${ENABLE_LMS_DISPLAY:-no}"
LMS_HOST="${LMS_HOST:-}"
LMS_PORT="${LMS_PORT:-9090}"
LMS_PLAYER_ID="${LMS_PLAYER_ID:-}"
LMS_DISPLAY_TITLE="${LMS_DISPLAY_TITLE:-XGIMI}"

urlencode_lms() {
    python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

lms_show_status() {
    local line1="${1:-$LMS_DISPLAY_TITLE}"
    local line2="${2:-}"
    local duration="${3:-8}"
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

    e_line1="$(urlencode_lms "$line1")"
    e_line2="$(urlencode_lms "$line2")"

    echo "$LMS_PLAYER_ID show line1:$e_line1 line2:$e_line2 duration:$duration" \
        | nc -w 2 "$LMS_HOST" "$LMS_PORT" >/dev/null 2>&1 || \
            xlog lms "WARN: invio messaggio LMS fallito: $line1 / $line2"
}

lms_show_phase() {
    lms_show_status "$LMS_DISPLAY_TITLE" "$1" 300
}

lms_show_attempt() {
    local phase="${1:-Fase}"
    local attempt="${2:-?}"
    lms_show_status "$LMS_DISPLAY_TITLE" "$phase - tentativo $attempt" 300
}


lms_show_done() {
    lms_show_status "$LMS_DISPLAY_TITLE" "${1:-Sequenza OK}" 15
}

lms_show_error() {
    lms_show_status "$LMS_DISPLAY_TITLE" "${1:-ERRORE}" 60
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

adb_auth_block_active() {
    local now ts age

    [ -f "$ADB_AUTH_BLOCK_FILE" ] || return 1

    ts="$(cat "$ADB_AUTH_BLOCK_FILE" 2>/dev/null || echo 0)"
    now="$(date +%s)"
    age=$((now - ts))

    if [ "$age" -lt "$ADB_AUTH_BLOCK_TTL" ]; then
        xlog adb-recover "ADB auth block attivo: age=${age}s ttl=${ADB_AUTH_BLOCK_TTL}s"
        return 0
    fi

    rm -f "$ADB_AUTH_BLOCK_FILE" 2>/dev/null || true
    return 1
}

adb_auth_block_set() {
    date +%s > "$ADB_AUTH_BLOCK_FILE"
    xlog adb-recover "ADB auth richiesta: blocco recovery per ${ADB_AUTH_BLOCK_TTL}s"
}

tcp_port_open() {
    local host="$1"
    local port="$2"

    timeout 3 bash -c "</dev/tcp/$host/$port" >/dev/null 2>&1
}

adb_discover_dynamic_port_avahi() {
    local port

    if ! command -v avahi-browse >/dev/null 2>&1; then
        xlog adb-recover "avahi-browse non disponibile: impossibile scoprire porta ADB dinamica"
        return 1
    fi

    port="$(
        avahi-browse -rt _adb-tls-connect._tcp 2>/dev/null |
        awk -v ip="$XGIMI_IP" '
            $1 == "address" && $3 == "[" ip "]" { found_ip=1 }
            found_ip && $1 == "port" {
                gsub(/\[/, "", $3)
                gsub(/\]/, "", $3)
                print $3
                exit
            }
        '
    )"

    if [ -z "$port" ]; then
        xlog adb-recover "avahi-browse non ha trovato porta ADB dinamica per $XGIMI_IP"
        return 1
    fi

    printf '%s\n' "$port"
    return 0
}

adb_switch_cooldown_ok() {
    local now last age

    now="$(date +%s)"
    last="$(cat "$ADB_SWITCH_LAST_FILE" 2>/dev/null || echo 0)"
    age=$((now - last))

    if [ "$age" -lt "$ADB_SWITCH_COOLDOWN" ]; then
        xlog adb-recover "switch ADB in cooldown: age=${age}s cooldown=${ADB_SWITCH_COOLDOWN}s"
        return 1
    fi

    return 0
}

adb_switch_mark_done() {
    date +%s > "$ADB_SWITCH_LAST_FILE"
}

adb_connect_dynamic_and_switch_5555() {
    local dyn_port="$1"
    local dyn_serial="${XGIMI_IP}:${dyn_port}"
    local final_serial

    final_serial="$(adb_serial)"

    if [ -z "$dyn_port" ]; then
        xlog adb-recover "porta dinamica ADB vuota: switch manuale impossibile"
        return 1
    fi

    if [ "$dyn_port" = "$ADB_PORT" ]; then
        xlog adb-recover "porta dinamica già uguale ad ADB_PORT=$ADB_PORT"
        adb_connect_fast && return 0
    fi

    if adb_auth_block_active; then
        return 2
    fi

    if tcp_port_open "$XGIMI_IP" "$dyn_port"; then
        xlog adb-recover "porta dinamica $dyn_serial aperta TCP"
    else
        xlog adb-recover "porta dinamica $dyn_serial chiusa TCP"
        return 1
    fi

    xlog adb-recover "switch manuale ADB: provo connect a porta dinamica $dyn_serial"

    local adb_out

    adb_out="$(adb connect "$dyn_serial" 2>&1 || true)"
    printf '%s\n' "$adb_out" >> "$LOG_FILE"

    if echo "$adb_out" | grep -qiE "failed to authenticate|unauthorized|authentication|not allowed|permission"; then
        xlog adb-recover "ADB connect fallito per autorizzazione/pairing su $dyn_serial"
        adb_auth_block_set
        return 2
    fi

    if ! echo "$adb_out" | grep -qiE "connected to|already connected"; then
        xlog adb-recover "switch manuale ADB: connect a $dyn_serial fallito"
        return 1
    fi

    if ! adb devices | grep -q "${dyn_serial}[[:space:]]*device"; then
        xlog adb-recover "switch manuale ADB: $dyn_serial non risulta device"

        adb devices >> "$LOG_FILE" 2>&1 || true

        if tcp_port_open "$XGIMI_IP" "$dyn_port"; then
            xlog adb-recover "porta TCP aperta ma ADB non autorizzato/non connesso: probabile pairing mancante"
            adb_auth_block_set
            return 2
        fi

        return 1
    fi

    xlog adb-recover "switch manuale ADB: invio tcpip $ADB_PORT tramite $dyn_serial"

    adb -s "$dyn_serial" tcpip "$ADB_PORT" >> "$LOG_FILE" 2>&1 || {
        xlog adb-recover "switch manuale ADB: tcpip $ADB_PORT fallito su $dyn_serial"
        return 1
    }

    sleep 2

    xlog adb-recover "switch manuale ADB: provo connect finale a $final_serial"

    adb connect "$final_serial" >> "$LOG_FILE" 2>&1 || {
        xlog adb-recover "switch manuale ADB: connect finale a $final_serial fallito"
        return 1
    }

    if adb devices | grep -q "${final_serial}[[:space:]]*device"; then
        xlog adb-recover "switch manuale ADB: $final_serial disponibile"
        adb_state_available
        return 0
    fi

    xlog adb-recover "switch manuale ADB: $final_serial non disponibile dopo switch"
    adb devices >> "$LOG_FILE" 2>&1 || true
    return 1
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

force_mute_usb_quick_on() {
    # Tentativo rapido durante l'accensione.
    # Non deve bloccare la sequenza ON.
    local key_timeout="${USB_MUTE_ON_KEY_TIMEOUT:-2}"

    xlog audio "force-mute ON rapido: provo USB consumer"

    [ -x "$USB_CONSUMER" ] || {
        xlog audio "force-mute ON rapido USB saltato: helper non eseguibile: $USB_CONSUMER"
        return 1
    }

    run_root_helper_timeout "$key_timeout" "$USB_CONSUMER" volume-up >/dev/null 2>&1 || return 1
    sleep 0.2

    run_root_helper_timeout "$key_timeout" "$USB_CONSUMER" volume-down >/dev/null 2>&1 || return 1
    sleep 0.2

    run_root_helper_timeout "$key_timeout" "$USB_CONSUMER" mute >/dev/null 2>&1 || return 1

    xlog audio "force-mute ON rapido via USB OK"
    return 0
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
    if [ -x "$GOOGLETV_HELPER" ] && timeout "${GOOGLETV_FORCE_MUTE_TIMEOUT:-5}" "$GOOGLETV_HELPER" force-mute >/dev/null 2>&1; then
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

    if [ -x "$GOOGLETV_HELPER" ] && timeout "${GOOGLETV_FORCE_MUTE_TIMEOUT:-5}" "$GOOGLETV_HELPER" force-mute >/dev/null 2>&1; then
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

run_root_helper_timeout() {
    local seconds="${1:-2}"
    shift || return 1

    if [ "$(id -u)" -eq 0 ]; then
        timeout "$seconds" "$@"
    else
        timeout "$seconds" sudo -n "$@"
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
