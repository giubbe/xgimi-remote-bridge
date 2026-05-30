#!/usr/bin/env bash
set -euo pipefail

HID_DEV="/dev/hidg1"
UDC="3f980000.usb"
STATE_FILE="/sys/class/udc/$UDC/state"

if [[ ! -e "$HID_DEV" ]]; then
  echo "ERRORE: $HID_DEV non esiste. Eseguire prima xgimi-usb-hid-setup-v2.sh" >&2
  exit 1
fi

if [[ -f "$STATE_FILE" ]]; then
  STATE="$(cat "$STATE_FILE")"
  if [[ "$STATE" != "configured" ]]; then
    echo "ERRORE: USB gadget non configurato. Stato: $STATE" >&2
    exit 1
  fi
fi

send_usage_hex_le() {
  local low="$1"
  local high="$2"

  printf "\\x${low}\\x${high}" > "$HID_DEV"
  sleep 0.05
  printf '\x00\x00' > "$HID_DEV"
}

case "${1:-}" in
  home)
    # Consumer AC Home = 0x0223
    send_usage_hex_le 23 02
    ;;
  back)
    # Consumer AC Back = 0x0224
    send_usage_hex_le 24 02
    ;;
  forward)
    # Consumer AC Forward = 0x0225
    send_usage_hex_le 25 02
    ;;
  menu)
    # Consumer Menu = 0x0040
    send_usage_hex_le 40 00
    ;;
  mute)
    # Consumer Mute = 0x00e2
    send_usage_hex_le e2 00
    ;;
  volume-up)
    # Consumer Volume Increment = 0x00e9
    send_usage_hex_le e9 00
    ;;
  volume-down)
    # Consumer Volume Decrement = 0x00ea
    send_usage_hex_le ea 00
    ;;
  play-pause)
    # Consumer Play/Pause = 0x00cd
    send_usage_hex_le cd 00
    ;;
  stop)
    # Consumer Stop = 0x00b7
    send_usage_hex_le b7 00
    ;;

  rewind)
    # Consumer Rewind = 0x00b4
    send_usage_hex_le b4 00
    ;;

  fast-forward)
    # Consumer Fast Forward = 0x00b3
    send_usage_hex_le b3 00
    ;;
  *)
echo "Uso: $0 home|back|forward|menu|mute|volume-up|volume-down|play-pause|stop|rewind|fast-forward" >&2
    exit 1
    ;;
esac
