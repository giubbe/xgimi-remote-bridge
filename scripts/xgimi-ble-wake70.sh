#!/usr/bin/env bash
set -u

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF_FILE="${CONF_FILE:-$BASE_DIR/xgimi.conf}"

if [ -f "$CONF_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONF_FILE"
fi

# XGIMI BLE wake test con manufacturer data 70 / 0x0046.
#
# Cattura reale dal telecomando XGIMI RC:
#   MAC telecomando: AA:BB:CC:DD:EE:FF
#   Service UUID: HID 0x1812
#   Manufacturer 13 / 0x000d: ff ff 42 52 56 31 2e 30 30  = ..BRV1.00
#   Manufacturer 70 / 0x0046:
#       2e 66 55 44 33 22 11 ff ff ff 30 43 52 4b 54 4d
#       30 66 55 44 33 22 11 ff ff ff 30 43 52 4b 54 4d
#       31 66 55 44 33 22 11 ff ff ff 30 43 52 4b 54 4d
#       32 66 55 44 33 22 11 ff ff ff 30 43 52 4b 54 4d
#       33 66 55 44 33 22 11 ff ff ff 30 43 52 4b 54 4d
#
# Nota:
#   66 55 44 33 22 11 è 11:22:33:44:55:66 in ordine inverso.
#   Questo è il MAC Bluetooth/Google TV del proiettore XGIMI.
#
# Limite:
#   Questo script NON spoofa il MAC BLE del telecomando.
#   Se il proiettore valida anche il MAC sorgente, può non funzionare. Spegnere e scollegare dalla corrente 
#   il proiettore prima di usare questo script

HCI_DEV="${HCI_DEV:-hci0}"
SECONDS_ON="${1:-25}"

# Sequenza counter/prefisso osservata.
# Puoi passarne una manuale come secondo argomento, es:
#   sudo ./xgimi-ble-wake70.sh 20 33
COUNTER_OVERRIDE="${2:-}"

XGIMI_BT_MAC="${XGIMI_BT_MAC:-}"

mac_to_le_bytes() {
    local mac="$1"
    echo "$mac" | awk -F: '{
        printf "%s %s %s %s %s %s", tolower($6), tolower($5), tolower($4), tolower($3), tolower($2), tolower($1)
    }'
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [xgimi-ble-wake70] $*"
}

fail() {
    echo "ERRORE: $*" >&2
    exit 1
}

if [ "$(id -u)" -ne 0 ]; then

if [ -z "$XGIMI_BT_MAC" ]; then
    fail "XGIMI_BT_MAC non impostato in xgimi.conf"
fi

BT_MAC_LE="$(mac_to_le_bytes "$XGIMI_BT_MAC")"
    fail "Eseguire con sudo."

if [ -z "$XGIMI_BT_MAC" ]; then
    fail "XGIMI_BT_MAC non impostato in xgimi.conf"
fi

BT_MAC_LE="$(mac_to_le_bytes "$XGIMI_BT_MAC")"
fi

if [ -z "$XGIMI_BT_MAC" ]; then
    fail "XGIMI_BT_MAC non impostato in xgimi.conf"
fi

BT_MAC_LE="$(mac_to_le_bytes "$XGIMI_BT_MAC")"

command -v hcitool >/dev/null 2>&1 || fail "hcitool non trovato. Installa bluez: sudo apt install -y bluez"
command -v hciconfig >/dev/null 2>&1 || fail "hciconfig non trovato. Installa bluez: sudo apt install -y bluez"

cleanup() {
    log "Disabilito advertising BLE"
    hcitool -i "$HCI_DEV" cmd 0x08 0x000a 00 >/dev/null 2>&1 || true
}
trap cleanup EXIT

set_adv_params() {
    # LE Set Advertising Parameters
    # intervallo circa 100 ms, ADV_IND, public address, all channels
    hcitool -i "$HCI_DEV" cmd 0x08 0x0006 \
      a0 00 a0 00 00 00 00 00 00 00 00 00 00 07 00 >/dev/null
}

set_adv_data_70() {
    local C="$1"

    # Advertising data, 27 byte:
    # 02 01 05
    # 03 03 12 18
    # 13 ff 46 00 <16 byte manufacturer 70>
    #
    # Manufacturer 70 data:
    #   C 66 55 44 33 22 11 ff ff ff 30 43 52 4b 54 4d
    #
    # 0x46 0x00 = company id 70 little-endian.
    hcitool -i "$HCI_DEV" cmd 0x08 0x0008 \
      1b \
      02 01 05 \
      03 03 12 18 \
      13 ff 46 00 "$C" $BT_MAC_LE ff ff ff 30 43 52 4b 54 4d \
      00 00 00 00 >/dev/null
}

enable_adv() {
    hcitool -i "$HCI_DEV" cmd 0x08 0x000a 01 >/dev/null
}

disable_adv() {
    hcitool -i "$HCI_DEV" cmd 0x08 0x000a 00 >/dev/null 2>&1 || true
}

log "Preparo controller $HCI_DEV"
hciconfig "$HCI_DEV" up || fail "impossibile attivare $HCI_DEV"

disable_adv
set_adv_params || fail "errore impostazione advertising parameters"

if [ -n "$COUNTER_OVERRIDE" ]; then
    COUNTERS="$COUNTER_OVERRIDE"
else
    # Valori osservati nella cattura.
    COUNTERS="2e 30 31 32 33"
fi

log "Avvio test BLE manufacturer 70 per ${SECONDS_ON}s"
log "Counters: $COUNTERS"

START="$(date +%s)"
while true; do
    NOW="$(date +%s)"
    ELAPSED=$((NOW - START))
    [ "$ELAPSED" -ge "$SECONDS_ON" ] && break

    for C in $COUNTERS; do
        NOW="$(date +%s)"
        ELAPSED=$((NOW - START))
        [ "$ELAPSED" -ge "$SECONDS_ON" ] && break

        log "Advertising counter/prefix 0x$C"
        disable_adv
        set_adv_data_70 "$C" || fail "errore impostazione advertising data counter $C"
        enable_adv || fail "errore enable advertising"
        sleep 2
    done
done

log "Fine test"
