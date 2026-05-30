#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$BASE_DIR/xgimi-lib.sh"

ON="$BASE_DIR/xgimi-on.sh"
OFF="$BASE_DIR/xgimi-off.sh"
MENU="$BASE_DIR/xgimi-menu-usb.sh"

try_adb_if_available() {
    local cmd="$1"
    shift || true

    case "$(state_get)" in
        available)
            if "$ADB_HELPER" "$cmd" "$@" >/dev/null 2>&1; then
                xlog key "ADB $cmd OK"
                return 0
            fi
            xlog key "ADB $cmd fallito; marco unavailable e avvio recovery"
            adb_state_unavailable
            start_adb_recovery_bg >/dev/null 2>&1 || true
            return 1
            ;;
        recovering|unavailable|unknown)
            return 1
            ;;
    esac
}

run_usb_keyboard_only() {
    local desc="$1"
    local usb_key="$2"

    if try_usb_key "$usb_key"; then
        xlog key "$desc via USB keyboard OK"
        return 0
    fi

    xlog key "$desc USB keyboard fallito; nessun fallback lento"
    return 1
}

run_usb_consumer_only() {
    local desc="$1"
    local usb_key="$2"

    if try_usb_consumer "$usb_key"; then
        xlog key "$desc via USB consumer OK"
        return 0
    fi

    xlog key "$desc USB consumer fallito; nessun fallback lento"
    return 1
}

run_usb_or_gtv() {
    # Solo per comandi non ripetitivi dove il fallback di rete è accettabile.
    local desc="$1"
    local usb_kind="$2"
    local usb_key="$3"
    local gtv_cmd="$4"

    if [ "$usb_kind" = "keyboard" ]; then
        if try_usb_key "$usb_key"; then
            xlog key "$desc via USB keyboard OK"
            return 0
        fi
    else
        if try_usb_consumer "$usb_key"; then
            xlog key "$desc via USB consumer OK"
            return 0
        fi
    fi

    xlog key "$desc USB fallito; provo Google TV: $gtv_cmd"
    try_gtv "$gtv_cmd"
}

cmd="${1:-}"

case "$cmd" in
  up|down|left|right|ok)
    run_usb_keyboard_only "$cmd" "$cmd"
    ;;

  enter)
    run_usb_keyboard_only "enter" ok
    ;;

  back)
    run_usb_consumer_only "back" back
    ;;

  esc)
    run_usb_keyboard_only "esc" back
    ;;

  backspace)
    run_usb_keyboard_only "backspace" backspace
    ;;

  home)
    run_usb_consumer_only "home" home
    ;;

  menu)
    run_usb_consumer_only "menu" menu
    ;;

  volume-up)
    run_usb_consumer_only "volume-up" volume-up
    ;;

  volume-down)
    run_usb_consumer_only "volume-down" volume-down
    ;;

  mute)
    # IMPORTANTISSIMO: mute deve essere a bassa latenza.
    # Non provare ADB prima, perché ADB può essere molto più lento del gadget USB.
    run_usb_consumer_only "mute" mute
    ;;

  force-mute)
    force_mute_best_effort
    ;;

  force-unmute)
    force_unmute_best_effort
    ;;

  power-on|on)
    xlog key "power-on richiesto: avvio asincrono"
    nohup "$ON" >> "$LOG_FILE" 2>&1 &
    exit 0
    ;;

  power-off|off)
    xlog key "power-off richiesto: avvio asincrono"
    nohup "$OFF" >> "$LOG_FILE" 2>&1 &
    exit 0
    ;;

  hdmi1)
    if try_adb_if_available hdmi1; then exit 0; fi
    xlog key "hdmi1 via ADB non disponibile; uso fallback AV"
    "$0" av
    ;;

  hdmi2)
    if try_adb_if_available hdmi2; then exit 0; fi
    xlog key "hdmi2 via ADB non disponibile; apro ingressi fallback"
    "$0" av
    ;;

  av|source|input|ingressi)
    if try_adb_if_available inputs; then exit 0; fi
    xlog key "ingressi via ADB non disponibili; uso macro USB"
    "$MENU"
    ;;

  xgimi-menu)
    if try_adb_if_available xgimi-menu; then exit 0; fi
    "$MENU"
    ;;

  autofocus)
    if try_adb_if_available autofocus; then exit 0; fi
    try_gtv autofocus
    ;;

  focus-manual)
    if try_adb_if_available focus-manual; then exit 0; fi
    xlog key "focus-manual richiede ADB; fallback non disponibile"
    exit 1
    ;;

  settings)
    if try_adb_if_available settings; then exit 0; fi
    try_gtv settings
    ;;

  netflix|youtube|status)
    try_gtv "$cmd"
    ;;

  play-pause)
    run_usb_consumer_only "play-pause" play-pause
    ;;

  stop)
    run_usb_consumer_only "stop" stop
    ;;

  rewind)
    run_usb_consumer_only "rewind" rewind
    ;;

  fast-forward)
    run_usb_consumer_only "fast-forward" fast-forward
    ;;

  adb-recover)
    start_adb_recovery_bg
    ;;

  green)
    xlog key "tasto Green non assegnato"
    ;;

  yellow)
    xlog key "tasto Yellow non assegnato"
    ;;

  text)
    # TEXT = focus manuale XGIMI
    if try_adb_if_available focus-manual; then exit 0; fi
    xlog key "text/focus-manual richiede ADB; fallback non disponibile"
    exit 1
    ;;

  info)
    # INFO = impostazioni/menu info
    if try_adb_if_available settings; then exit 0; fi
    xlog key "info/settings via ADB non disponibile; fallback Google TV settings"
    try_gtv settings
    ;;

  blue)
    # BLUE = autofocus XGIMI
    if try_adb_if_available autofocus; then exit 0; fi
    xlog key "blue/autofocus via ADB non disponibile; provo Google TV autofocus"
    try_gtv autofocus
    ;;

  *)
    cat >&2 <<USAGE
Uso:
  $0 up|down|left|right|ok|enter
  $0 back|home|menu|settings
  $0 volume-up|volume-down|mute|force-mute|force-unmute
  $0 power-on|power-off
  $0 hdmi1|hdmi2|av|source|input|ingressi|xgimi-menu
  $0 autofocus|focus-manual
  $0 netflix|youtube|status
  $0 play-pause|stop|rewind|fast-forward
  $0 adb-recover
USAGE
    exit 1
    ;;
esac
