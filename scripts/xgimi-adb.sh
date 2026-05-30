#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$BASE_DIR/xgimi-lib.sh"

run_adb_marked() {
    if adb_shell_fast "$@"; then
        adb_state_available
        return 0
    fi

    adb_state_unavailable
    start_adb_recovery_bg >/dev/null 2>&1 || true
    return 1
}

case "${1:-}" in
  status)
    mark_adb_from_probe
    ;;

  recover)
    start_adb_recovery_bg
    ;;

  inputs|source|input|ingressi)
    xlog adb "apertura selettore ingressi via ADB"
    run_adb_marked am start -n com.google.android.tv.inputplayer/.switcher.SelectInputActivity >/dev/null
    ;;

  hdmi1)
    xlog adb "selezione HDMI1 via PassthroughPlayerActivity HW2"
    run_adb_marked am start \
      -n com.google.android.tv.inputplayer/.player.PassthroughPlayerActivity \
      -a android.intent.action.VIEW \
      -d "content://android.media.tv/passthrough/com.mediatek.tis%2F.HdmiInputService%2FHW2" >/dev/null
    ;;

  hdmi2)
    xlog adb "selezione HDMI2 tentativo HW3"
    run_adb_marked am start \
      -n com.google.android.tv.inputplayer/.player.PassthroughPlayerActivity \
      -a android.intent.action.VIEW \
      -d "content://android.media.tv/passthrough/com.mediatek.tis%2F.HdmiInputService%2FHW3" >/dev/null
    ;;

  mute)
    xlog adb "mute toggle via KEYCODE_F5"
    run_adb_marked input keyevent KEYCODE_F5 >/dev/null
    ;;

  autofocus)
    xlog adb "autofocus via KEYCODE_F12"
    run_adb_marked input keyevent KEYCODE_F12 >/dev/null
    ;;

  prime|primetv)
    run_adb_marked input keyevent KEYCODE_F8 >/dev/null
    ;;

  youtube)
    run_adb_marked input keyevent KEYCODE_F4 >/dev/null
    ;;

  netflix)
    run_adb_marked input keyevent KEYCODE_F9 >/dev/null
    ;;

  xgimi-menu)
    # Non abbiamo ancora una activity proprietaria certa per il menu XGIMI.
    # Lasciato fallire per attivare fallback USB in xgimi-key.sh.
    xlog adb "xgimi-menu via ADB non implementato"
    exit 1
    ;;

  settings)
    xlog adb "apertura impostazioni Android TV via ADB"
    run_adb_marked am start -n com.android.tv.settings/.MainSettings >/dev/null
    ;;

  focus-manual)
    xlog adb "apertura focus manuale XGIMI via ADB KEYCODE_F10"
    run_adb_marked input keyevent KEYCODE_F10 >/dev/null
    ;;

  shell)
    shift
    if [ "$#" -eq 0 ]; then
        echo "Uso: $0 shell COMANDO" >&2
        exit 2
    fi
    run_adb_marked "$@"
    ;;

  *)
    cat >&2 <<USAGE
Uso: $0 status|recover|inputs|hdmi1|hdmi2|mute|autofocus|focus-manual|settings|youtube|netflix|prime|xgimi-menu|shell COMANDO
USAGE
    exit 1
    ;;
esac
