#!/usr/bin/env bash
set -euo pipefail

HID_DEV="/dev/hidg0"
UDC="3f980000.usb"
STATE_FILE="/sys/class/udc/$UDC/state"

if [[ ! -e "$HID_DEV" ]]; then
  echo "ERRORE: $HID_DEV non esiste. Eseguire prima xgimi-usb-hid-setup.sh" >&2
  exit 1
fi

if [[ -f "$STATE_FILE" ]]; then
  STATE="$(cat "$STATE_FILE")"
  if [[ "$STATE" != "configured" ]]; then
    echo "ERRORE: USB gadget non configurato dal proiettore. Stato attuale: $STATE" >&2
    echo "Controlla cavo dati, porta USB OTG e che XGIMI sia acceso." >&2
    exit 1
  fi
fi

send_key() {
  local code_dec="$1"
  local code_hex

  printf -v code_hex '%02x' "$code_dec"

  # pressione tasto
  printf "\\x00\\x00\\x${code_hex}\\x00\\x00\\x00\\x00\\x00" > "$HID_DEV"

  sleep 0.05

  # rilascio tasto
  printf '\x00\x00\x00\x00\x00\x00\x00\x00' > "$HID_DEV"
}

case "${1:-}" in
  up)
    send_key 82
    ;;
  down)
    send_key 81
    ;;
  right)
    send_key 79
    ;;
  left)
    send_key 80
    ;;
  ok|enter)
    send_key 40
    ;;
  back|esc)
    send_key 41
    ;;
  backspace)
    send_key 42
    ;;
  home-keyboard)
    send_key 74
    ;;
  *)
    echo "Uso: $0 up|down|left|right|ok|back|backspace|home-keyboard" >&2
    exit 1
    ;;
esac
