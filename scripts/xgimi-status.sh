#!/usr/bin/env bash
set -u

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$BASE_DIR/xgimi-lib.sh"

ok() { echo "OK    - $*"; }
warn() { echo "WARN  - $*"; }
fail() { echo "FAIL  - $*"; }
section() { echo; echo "=== $* ==="; }
check_tcp_port() { nc -vz -w2 "$XGIMI_IP" "$1" >/dev/null 2>&1; }
print_file_state() {
    local path="$1" label="$2"
    if [ -x "$path" ]; then ok "$label eseguibile: $path"
    elif [ -f "$path" ]; then warn "$label presente ma non eseguibile: $path"
    else fail "$label non trovato: $path"
    fi
}

xlog status "richiesta stato"

echo "XGIMI status - $(date '+%Y-%m-%d %H:%M:%S')"
echo "Base dir: $BASE_DIR"

section "Configurazione"
echo "DEVICE_NAME=$DEVICE_NAME"
echo "XGIMI_IP=$XGIMI_IP"
echo "ADB_PORT=$ADB_PORT"
echo "ADB_STATE=$(state_get)"
echo "STATE_DIR=$STATE_DIR"
echo "LOG_FILE=$LOG_FILE"
echo "POWER_TRANSITION_LOCK=$POWER_TRANSITION_LOCK"

section "File operativi"
print_file_state "$USB_KEY" "USB keyboard helper"
print_file_state "$USB_CONSUMER" "USB consumer helper"
print_file_state "$GOOGLETV_HELPER" "Google TV helper"
print_file_state "$ADB_HELPER" "ADB helper"
print_file_state "$ADB_RECOVERY_SCRIPT" "ADB recovery"

section "Rete"
if is_ping_ok; then
    ok "Ping verso $XGIMI_IP riuscito"
    XGIMI_REACHABLE="yes"
else
    fail "Ping verso $XGIMI_IP fallito"
    XGIMI_REACHABLE="no"
fi

echo
echo "Neighbor cache:"
ip neigh show "$XGIMI_IP" 2>/dev/null || true

section "Porte"
if [ "$XGIMI_REACHABLE" = "yes" ]; then
    check_tcp_port 6466 && ok "TCP 6466 Google TV aperta" || warn "TCP 6466 non raggiungibile"
    check_tcp_port 6467 && ok "TCP 6467 Google TV aperta" || warn "TCP 6467 non raggiungibile"
    check_tcp_port "$ADB_PORT" && ok "TCP $ADB_PORT ADB aperta" || warn "TCP $ADB_PORT ADB non raggiungibile"
else
    warn "Salto test porte: XGIMI non raggiungibile"
fi

section "ADB"
if mark_adb_from_probe >/dev/null 2>&1; then
    ok "ADB operativo su $(adb_serial)"
    adb_shell_fast getprop service.adb.tcp.port 2>/dev/null | sed 's/^/service.adb.tcp.port=/' || true
    adb_shell_fast settings get global adb_enabled 2>/dev/null | sed 's/^/adb_enabled=/' || true
    adb_shell_fast settings get global adb_wifi_enabled 2>/dev/null | sed 's/^/adb_wifi_enabled=/' || true
else
    warn "ADB non operativo; stato marcato unavailable"
fi

section "Google TV Remote"
if [ "$XGIMI_REACHABLE" = "yes" ] && [ -x "$GOOGLETV_HELPER" ]; then
    if "$GOOGLETV_HELPER" status; then
        ok "Google TV Remote operativo"
    else
        warn "Google TV Remote non operativo"
    fi
else
    warn "Google TV Remote non testato"
fi

section "Transizione power"
if transition_lock_exists; then
    warn "Transizione power in corso"
    transition_lock_info
else
    ok "Nessuna transizione power in corso"
fi

section "Sintesi"
echo "ADB state file: $(state_get)"
if [ "$XGIMI_REACHABLE" = "yes" ]; then
    echo "Stato probabile: acceso o standby leggero, rete attiva."
else
    echo "Stato probabile: spento/deep standby/non raggiungibile."
fi
