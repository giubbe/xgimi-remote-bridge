#!/usr/bin/env bash
set -u

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF_FILE="$BASE_DIR/xgimi.conf"

if [ -f "$CONF_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONF_FILE"
fi

XGIMI_IP="${XGIMI_IP:-}"
DEVICE_NAME="${DEVICE_NAME:-xgimi}"
LOG_FILE="${LOG_FILE:-$BASE_DIR/xgimi-remote.log}"
GOOGLETV_VENV="${GOOGLETV_VENV:-$BASE_DIR/.venv-googletv}"
GOOGLETV_CERT_FILE="${GOOGLETV_CERT_FILE:-$BASE_DIR/googletv-cert.pem}"
GOOGLETV_KEY_FILE="${GOOGLETV_KEY_FILE:-$BASE_DIR/googletv-key.pem}"
GOOGLETV_CLIENT_NAME="${GOOGLETV_CLIENT_NAME:-xgimi-remote-bridge}"
GOOGLETV_CONNECT_TIMEOUT="${GOOGLETV_CONNECT_TIMEOUT:-12}"

CMD="${1:-help}"
shift || true

log() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$DEVICE_NAME][googletv] $*" >> "$LOG_FILE"
}

PYTHON_BIN="$GOOGLETV_VENV/bin/python3"

if [ ! -x "$PYTHON_BIN" ]; then
    echo "Ambiente Google TV non trovato: $PYTHON_BIN" >&2
    echo "Esegui prima l'installazione:" >&2
    echo "  python3 -m venv '$GOOGLETV_VENV'" >&2
    echo "  '$GOOGLETV_VENV/bin/python3' -m pip install --upgrade pip" >&2
    echo "  '$GOOGLETV_VENV/bin/python3' -m pip install androidtvremote2" >&2
    log "ERRORE: venv Google TV mancante: $GOOGLETV_VENV"
    exit 2
fi

case "$CMD" in
    pair|status|power|wake|home|back|indietro|ok|select|seleziona|up|down|left|right|su|giu|sinistra|destra|menu|settings|impostazioni|autofocus|source|input|ingressi|netflix|youtube|volume-up|volume-down|volumeup|volumedown|mute|force-mute|force-unmute|key|launch|text)
        ;;
    help|-h|--help)
        cat <<HELP
Uso:
  $0 pair                 Pairing iniziale con codice mostrato sul proiettore
  $0 status               Stato collegamento/proiettore
  $0 wake                 Test manuale: POWER poi HOME. Non usare per ON automatico.
  $0 power                Invia KEYCODE POWER
  $0 home                 Invia HOME
  $0 back | indietro      Tasto Indietro
  $0 settings             Apre impostazioni Google TV (tasto SETTINGS)
  $0 impostazioni         Alias italiano di settings
  $0 autofocus            Autofocus XGIMI: prova FOCUS, poi fallback launch intent proprietario
  $0 source               Selezione ingressi: prova TV_INPUT, poi fallback launch intent HDMI
  $0 input | ingressi     Alias di source
  $0 netflix              Avvia Netflix (com.netflix.ninja)
  $0 youtube              Avvia YouTube TV (com.google.android.youtube.tv)
  $0 ok                   Tasto OK / DPAD_CENTER
  $0 up/down/left/right   Frecce direzionali
  $0 su/giu/sinistra/destra Alias italiani delle frecce
  $0 key NOME_TASTO       Invia tasto raw androidtvremote2, es. POWER, HOME, DPAD_CENTER
  $0 volume-up            Volume su
  $0 volume-down          Volume giù
  $0 volumeup             Alias di volume-up
  $0 volumedown           Alias di volume-down
  $0 mute                 Toggle mute
  $0 force-mute           Forza mute: VOLUME_UP, VOLUME_DOWN, MUTE
  $0 force-unmute         Forza audio attivo: VOLUME_UP, VOLUME_DOWN
  $0 launch APP_OR_URL    Avvia app/URL, es. com.google.android.youtube.tv
  $0 text TESTO           Invia testo

NOTE SUI COMANDI SPECIALI XGIMI (versione internazionale Google TV):
  autofocus  - Il keycode FOCUS (camera) spesso non ha effetto su Google TV.
               Questo script invia prima FOCUS, poi come fallback lancia
               l'activity proprietaria XGIMI com.hpplay.projector/.FocusActivity
               Se nemmeno quella funziona, il tasto fisico rimane l'unica via
               oppure abilitare ADB e usare: adb shell am start -n com.hpplay.projector/.FocusActivity
  source     - TV_INPUT non ha un keycode nel protocollo androidtvremote2.
               Lo script lancia l'URL content://android.media.tv/channel
               come fallback per aprire il selettore ingressi Google TV.
               Se fallisce, usare: adb shell am start -a android.intent.action.VIEW -d content://android.media.tv/channel

File usati:
  cert: $GOOGLETV_CERT_FILE
  key : $GOOGLETV_KEY_FILE
  venv: $GOOGLETV_VENV
HELP
        exit 0
        ;;
    *)
        echo "Comando non valido: $CMD" >&2
        "$0" help
        exit 1
        ;;
esac

log "Comando richiesto: $CMD $*"

export XGIMI_IP
export GOOGLETV_CLIENT_NAME
export GOOGLETV_CERT_FILE
export GOOGLETV_KEY_FILE
export GOOGLETV_CONNECT_TIMEOUT

"$PYTHON_BIN" - "$CMD" "$@" <<'PYCODE'
import asyncio
import logging
import os
import sys
from androidtvremote2 import AndroidTVRemote, CannotConnect, ConnectionClosed, InvalidAuth

cmd = sys.argv[1]
args = sys.argv[2:]

host = os.environ.get("XGIMI_IP", "")
if not host:
    print("ERRORE: XGIMI_IP non impostato.", file=sys.stderr)
    raise SystemExit(2)
client_name = os.environ.get("GOOGLETV_CLIENT_NAME", "xgimi-remote-bridge")
certfile = os.environ.get("GOOGLETV_CERT_FILE", "googletv-cert.pem")
keyfile = os.environ.get("GOOGLETV_KEY_FILE", "googletv-key.pem")
connect_timeout = float(os.environ.get("GOOGLETV_CONNECT_TIMEOUT", "12"))

logging.basicConfig(level=logging.WARNING, format="%(levelname)s: %(message)s")

# Keycodes che funzionano in modo affidabile su Google TV via androidtvremote2.
# FOCUS e TV_INPUT sono stati rimossi da KEY_ALIASES perché non funzionano
# sulla versione internazionale XGIMI: vengono gestiti come casi speciali sotto.
KEY_ALIASES = {
    "power": "POWER",
    "wake": "POWER",
    "home": "HOME",

    # Navigazione
    "back": "BACK",
    "indietro": "BACK",
    "ok": "DPAD_CENTER",
    "select": "DPAD_CENTER",
    "seleziona": "DPAD_CENTER",
    "up": "DPAD_UP",
    "su": "DPAD_UP",
    "down": "DPAD_DOWN",
    "giu": "DPAD_DOWN",
    "left": "DPAD_LEFT",
    "sinistra": "DPAD_LEFT",
    "right": "DPAD_RIGHT",
    "destra": "DPAD_RIGHT",

    # Sistema
    "menu": "MENU",
    "settings": "SETTINGS",
    "impostazioni": "SETTINGS",

    # Audio
    "volume-up": "VOLUME_UP",
    "volume-down": "VOLUME_DOWN",
    "volumeup": "VOLUME_UP",
    "volumedown": "VOLUME_DOWN",
    "mute": "MUTE",
}

async def pair(remote: AndroidTVRemote) -> int:
    generated = await remote.async_generate_cert_if_missing()
    if generated:
        print(f"Generato nuovo certificato client: {certfile}")
        print(f"Generata nuova chiave client: {keyfile}")
    try:
        name, mac = await asyncio.wait_for(remote.async_get_name_and_mac(), timeout=connect_timeout)
        print(f"Dispositivo trovato: host={host} name={name} mac={mac}")
    except Exception as exc:
        print(f"ATTENZIONE: non riesco a leggere nome/MAC prima del pairing: {exc}", file=sys.stderr)
    print("Avvio pairing. Sul proiettore dovrebbe comparire un codice.")
    await asyncio.wait_for(remote.async_start_pairing(), timeout=connect_timeout)

    if args:
        code = args[0].strip()
    else:
        try:
            with open("/dev/tty", "r", encoding="utf-8") as tty_in:
                print("Codice pairing Google TV: ", end="", flush=True)
                code = tty_in.readline().strip()
        except OSError:
            print("Impossibile leggere il codice dal terminale. Usa: xgimi-googletv.sh pair CODICE", file=sys.stderr)
            return 3

    if not code:
        print("Codice pairing vuoto.", file=sys.stderr)
        return 3

    await asyncio.wait_for(remote.async_finish_pairing(code), timeout=connect_timeout)
    print("Pairing completato.")
    return 0

async def connect(remote: AndroidTVRemote) -> bool:
    await remote.async_generate_cert_if_missing()
    try:
        await asyncio.wait_for(remote.async_connect(), timeout=connect_timeout)
        return True
    except InvalidAuth:
        print("Autenticazione Google TV non valida: rifai il pairing con: xgimi-googletv.sh pair", file=sys.stderr)
    except (CannotConnect, ConnectionClosed, asyncio.TimeoutError) as exc:
        print(f"Connessione Google TV fallita verso {host}: {exc}", file=sys.stderr)
    return False

def send(remote: AndroidTVRemote, key: str) -> None:
    remote.send_key_command(key)

async def main() -> int:
    remote = AndroidTVRemote(client_name, certfile, keyfile, host, enable_voice=False)

    if cmd == "pair":
        return await pair(remote)

    if not await connect(remote):
        return 20

    try:
        if cmd == "status":
            is_on = getattr(remote, "is_on", None)
            current_app = getattr(remote, "current_app", None)
            device_info = getattr(remote, "device_info", None)
            volume_info = getattr(remote, "volume_info", None)
            voice_enabled = getattr(remote, "is_voice_enabled", None)
            print("available=True")
            print(f"is_on={is_on}")
            print(f"current_app={current_app}")
            print(f"device_info={device_info}")
            print(f"volume_info={volume_info}")
            print(f"voice_enabled={voice_enabled}")
            return 0

        if cmd == "wake":
            send(remote, "POWER")
            await asyncio.sleep(1.5)
            send(remote, "HOME")
            print("Inviati: POWER, HOME")
            return 0

        if cmd == "force-mute":
            send(remote, "VOLUME_UP")
            await asyncio.sleep(0.2)
            send(remote, "VOLUME_DOWN")
            await asyncio.sleep(0.2)
            send(remote, "MUTE")
            print("Inviati: VOLUME_UP, VOLUME_DOWN, MUTE")
            return 0

        if cmd == "force-unmute":
            send(remote, "VOLUME_UP")
            await asyncio.sleep(0.2)
            send(remote, "VOLUME_DOWN")
            print("Inviati: VOLUME_UP, VOLUME_DOWN")
            return 0

        # ── AUTOFOCUS ──────────────────────────────────────────────────────────
        # FOCUS (keycode 80) è il tasto fotocamera Android: su Google TV/XGIMI
        # internazionale non ha effetto. Si tenta prima il keycode, poi si lancia
        # l'activity proprietaria XGIMI tramite send_launch_app_command.
        # Alternativa ADB (se disponibile):
        #   adb shell am start -n com.hpplay.projector/.FocusActivity
        if cmd == "autofocus":
            send(remote, "FOCUS")
            await asyncio.sleep(0.3)
            # Fallback: activity proprietaria XGIMI per l'autofocus.
            # Provare anche "com.hpplay.projector/.AutoFocusActivity" se questa non funziona.
            remote.send_launch_app_command("com.hpplay.projector/.FocusActivity")
            print("Inviati: FOCUS + launch com.hpplay.projector/.FocusActivity")
            print("NOTA: se non funziona, provare 'launch com.hpplay.projector/.AutoFocusActivity'")
            return 0

        # ── SOURCE / INGRESSI ──────────────────────────────────────────────────
        # TV_INPUT non esiste come keycode nel protocollo androidtvremote2.
        # Il fallback usa l'URL del content provider degli input Android TV,
        # che su Google TV apre il selettore sorgenti.
        # Alternativa ADB:
        #   adb shell am start -a android.intent.action.VIEW -d content://android.media.tv/channel
        if cmd in ("source", "input", "ingressi"):
            # Primo tentativo: URL del selettore ingressi Google TV
            remote.send_launch_app_command("content://android.media.tv/channel")
            await asyncio.sleep(0.5)
            print("Inviato launch: content://android.media.tv/channel")
            print("NOTA: se non funziona, provare 'launch com.google.android.leanback/.app.SearchActivity'")
            return 0

        # ── NETFLIX ────────────────────────────────────────────────────────────
        if cmd == "netflix":
            remote.send_launch_app_command("com.netflix.ninja")
            print("Inviato launch Netflix: com.netflix.ninja")
            return 0

        # ── YOUTUBE ────────────────────────────────────────────────────────────
        if cmd == "youtube":
            remote.send_launch_app_command("com.google.android.youtube.tv")
            print("Inviato launch YouTube TV: com.google.android.youtube.tv")
            return 0

        if cmd in KEY_ALIASES:
            key = KEY_ALIASES[cmd]
            send(remote, key)
            print(f"Inviato tasto: {key}")
            return 0

        if cmd == "key":
            if not args:
                print("Manca nome tasto. Esempio: key POWER", file=sys.stderr)
                return 2
            key = args[0].upper().replace("KEYCODE_", "")
            send(remote, key)
            print(f"Inviato tasto: {key}")
            return 0

        if cmd == "launch":
            if not args:
                print("Manca app/URL. Esempio: launch com.google.android.youtube.tv", file=sys.stderr)
                return 2
            target = args[0]
            remote.send_launch_app_command(target)
            print(f"Inviato launch: {target}")
            return 0

        if cmd == "text":
            if not args:
                print("Manca testo.", file=sys.stderr)
                return 2
            text = " ".join(args)
            remote.send_text(text)
            print("Testo inviato.")
            return 0

        print(f"Comando non gestito: {cmd}", file=sys.stderr)
        return 2
    finally:
        try:
            remote.disconnect()
        except Exception:
            pass

try:
    raise SystemExit(asyncio.run(main()))
except KeyboardInterrupt:
    raise SystemExit(130)
except InvalidAuth:
    print("Pairing non valido: esegui xgimi-googletv.sh pair", file=sys.stderr)
    raise SystemExit(21)
except Exception as exc:
    print(f"Errore Google TV: {exc}", file=sys.stderr)
    raise SystemExit(99)
PYCODE
RET=$?
log "Comando $CMD terminato con codice $RET"
exit "$RET"
