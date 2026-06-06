#!/usr/bin/env python3
import os
import sys
import time
import struct
import subprocess
from datetime import datetime

BASE_DIR = os.environ.get("XGIMI_BASE_DIR", "/opt/xgimi-remote/scripts")
XGIMI_KEY = os.path.join(BASE_DIR, "xgimi-key.sh")
LOG_FILE = os.path.join(BASE_DIR, "xgimi-remote.log")

# Linux input event constants
EV_KEY = 0x01

# Key codes Linux input-event-codes.h
KEY_ESC = 1
KEY_1 = 2
KEY_2 = 3
KEY_3 = 4
KEY_4 = 5
KEY_5 = 6
KEY_6 = 7
KEY_7 = 8
KEY_8 = 9
KEY_9 = 10
KEY_0 = 11
KEY_BACKSPACE = 14
KEY_ENTER = 28
KEY_LEFTCTRL = 29
KEY_M = 50
KEY_LEFTALT = 56
KEY_F1 = 59
KEY_HOME = 102
KEY_UP = 103
KEY_LEFT = 105
KEY_RIGHT = 106
KEY_DOWN = 108
KEY_MUTE = 113
KEY_VOLUMEDOWN = 114
KEY_VOLUMEUP = 115
KEY_F2 = 60
KEY_F3 = 61
KEY_F4 = 62
KEY_F5 = 63
KEY_F6 = 64
KEY_F7 = 65
KEY_F8 = 66
KEY_KPENTER = 96

KEY_PLAYPAUSE = 164
KEY_STOPCD = 166
KEY_REWIND = 168
KEY_FASTFORWARD = 208

# F13-F24
KEY_F13 = 183
KEY_F14 = 184
KEY_F15 = 185
KEY_F16 = 186
KEY_F17 = 187
KEY_F18 = 188
KEY_F19 = 189
KEY_F20 = 190
KEY_F21 = 191
KEY_F22 = 192
KEY_F23 = 193
KEY_F24 = 194

KEY_MAP = {
    KEY_UP: "up",
    KEY_DOWN: "down",
    KEY_LEFT: "left",
    KEY_RIGHT: "right",

    KEY_ENTER: "ok",
    KEY_KPENTER: "ok",

    # Back fisico = cancellazione testo
    # Undo / freccia indietro = back UI
    KEY_BACKSPACE: "backspace",
    KEY_ESC: "back",

    # Tasto MENU del telecomando = HOME Google TV
    KEY_HOME: "home",

    KEY_MUTE: "mute",
    KEY_VOLUMEUP: "volume-up",
    KEY_VOLUMEDOWN: "volume-down",

    # Tasti colorati / speciali OneForAll
    KEY_F1: "power-off",   # Red
    KEY_F2: "hdmi1",       # Green
    KEY_F3: "hdmi2",       # Yellow
    KEY_F4: "blue",        # Blue, per ora libero/non assegnato
    KEY_F5: "av",          # AV = selettore ingressi
    KEY_F6: "text",        # Text
    KEY_F7: "info",        # Info = opzioni/menu XGIMI
    KEY_F8: "power-on",

    KEY_PLAYPAUSE: "play-pause",
    KEY_STOPCD: "stop",
    KEY_REWIND: "rewind",
    KEY_FASTFORWARD: "fast-forward",

    KEY_F15: "netflix",
    KEY_F16: "youtube",
    KEY_F17: "settings",
    KEY_F18: "adb-force",
}

# Tasti su cui accettiamo autorepeat, ma con rate-limit e scarto eventi vecchi.
REPEAT_ALLOWED = {
    KEY_UP,
    KEY_DOWN,
    KEY_LEFT,
    KEY_RIGHT,
    KEY_VOLUMEUP,
    KEY_VOLUMEDOWN,
    KEY_BACKSPACE,
}

# Intervallo minimo tra due ripetizioni accettate dello stesso tasto.
# Se troppo lento: prova 0.08. Se ancora scorre dopo il rilascio: prova 0.16/0.20.
REPEAT_MIN_INTERVAL = 0.12

# Se un evento letto dal device è più vecchio di questa soglia, viene scartato.
# Questo taglia la "coda" accumulata quando subprocess.run impiega più del ritmo FLIRC.
STALE_EVENT_MAX_AGE = 0.20

def log(msg: str) -> None:
    line = f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} flirc-listener: {msg}"
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(line + "\n")

def find_flirc_device() -> str:
    by_id = "/dev/input/by-id"
    if os.path.isdir(by_id):
        for name in sorted(os.listdir(by_id)):
            lname = name.lower()
            if "flirc" in lname and "event-kbd" in lname:
                return os.path.realpath(os.path.join(by_id, name))

    raise RuntimeError("FLIRC event-kbd non trovato in /dev/input/by-id")

def run_xgimi(command: str) -> None:
    log(f"comando={command}")
    try:
        subprocess.run(
            [XGIMI_KEY, command],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            timeout=3
        )
    except subprocess.CalledProcessError as e:
        log(f"ERRORE comando={command} rc={e.returncode} stderr={e.stderr.strip()}")
    except subprocess.TimeoutExpired:
        log(f"ERRORE timeout comando={command}")

def event_age_seconds(sec: int, usec: int) -> float:
    return time.time() - (sec + (usec / 1_000_000.0))

def main() -> int:
    if not os.path.exists(XGIMI_KEY):
        print(f"ERRORE: manca {XGIMI_KEY}", file=sys.stderr)
        return 1

    if len(sys.argv) > 1:
        dev = sys.argv[1]
    else:
        dev = find_flirc_device()

    log(f"avvio su device={dev}")

    event_struct = "llHHI"
    event_size = struct.calcsize(event_struct)

    last_repeat_at = {}

    with open(dev, "rb", buffering=0) as f:
        while True:
            data = f.read(event_size)
            if len(data) != event_size:
                time.sleep(0.05)
                continue

            sec, usec, ev_type, code, value = struct.unpack(event_struct, data)

            if ev_type != EV_KEY:
                continue

            if value == 0:
                # Release: azzera il rate-limit del tasto.
                last_repeat_at.pop(code, None)
                continue

            age = event_age_seconds(sec, usec)
            if age > STALE_EVENT_MAX_AGE:
                # Evento già vecchio: non svuotiamo code dopo il rilascio.
                log(f"scarto evento vecchio code={code} value={value} age={age:.3f}s")
                continue

            # value:
            # 0 = release
            # 1 = press
            # 2 = autorepeat
            if value == 2:
                if code not in REPEAT_ALLOWED:
                    continue

                now = time.monotonic()
                previous = last_repeat_at.get(code, 0.0)
                if now - previous < REPEAT_MIN_INTERVAL:
                    continue
                last_repeat_at[code] = now

            elif value != 1:
                continue

            command = KEY_MAP.get(code)

            if command is None:
                log(f"tasto non mappato code={code} value={value}")
                continue

            run_xgimi(command)

    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as e:
        log(f"FATALE: {e}")
        print(f"ERRORE: {e}", file=sys.stderr)
        raise SystemExit(1)
