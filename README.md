# XGIMI Remote Bridge

Remote bridge for XGIMI / Google TV projectors using a Raspberry Pi, FLIRC, USB HID gadget mode, Google TV Remote v2, BLE wake, HDMI-CEC wake reinforcement and optional ADB recovery.

The goal is to use a universal IR remote as a reliable projector remote, with low-latency USB HID for navigation and audio keys, and network/ADB fallbacks only where they are actually useful.

## Status

Version: `1.0.2`

Validated functions:

- power-on workflow with BLE wake, immediate HDMI-CEC wake reinforcement and WOL fallback;
- power-off / standby via Google TV Remote;
- low-latency USB HID keyboard commands;
- low-latency USB HID consumer-control commands;
- FLIRC listener with repeat-rate limiting and stale-event discard;
- Google TV Remote v2 pairing and command fallback;
- optional ADB recovery through adb-auto-enable;
- optional Logitech Media Server / Jivelite display feedback during power-on;
- special keys for input selection, HDMI selection, autofocus and focus menu.
- early USB Consumer mute during power-on;
- Google TV force-mute after confirmed `is_on=True`;
- timeout-protected Google TV status and force-mute calls;
- ADB recovery moved after startup mute so it does not delay Google TV Remote handling;

## Language note

This project was developed and tested in an Italian home-lab environment.
Some inline comments and runtime log messages are still in Italian.
The public documentation is written in English to make the project easier to reuse internationally.
An optional Italian README is available as [`README.it.md`](README.it.md).

## Architecture

```text
IR remote
   ↓
FLIRC USB receiver
   ↓
Raspberry Pi listener
   ↓
xgimi-key.sh dispatcher
   ├── USB HID keyboard          → arrows, OK, ESC/backspace
   ├── USB HID consumer control  → volume, mute, home, back, media
   ├── ADB, when available       → HDMI, focus, app shortcuts, settings
   └── Google TV Remote v2       → power, status, force mute, fallback commands
```

Power-on uses a separate route:

```text
xgimi-on.sh
   ├── BLE manufacturer-data wake
   ├── immediate HDMI-CEC wake reinforcement
   ├── early USB Consumer mute, best-effort
   ├── Wake-on-LAN fallback if network does not become stable
   ├── optional Logitech Media Server / Jivelite status messages
   ├── Google TV status wait with per-call timeout
   ├── final Google TV force-mute after confirmed "is_on=True"
   └── background ADB recovery after startup mute
```

## BLE wake payload discovery and capture

The BLE wake part is based on two sources:

1. XGIMI’s official remote pairing procedure: put the remote near the projector and press **Back + Home** until the remote LED flashes. This puts the remote into Bluetooth pairing mode.
2. Community research from the `manymuch/Xgimi-4-Home-Assistant` GitHub issue, where the XGIMI Bluetooth remote was observed advertising manufacturer-specific data with **company code `0x0046`** and payload ending in `30 43 52 4b 54 4d`.

For this project, the wake packet was validated by capturing the real XGIMI remote BLE advertisements and replaying the relevant manufacturer data from the Raspberry Pi.

### Capture workflow

Recommended capture approach:

1. Turn the projector fully off and disconnect it from power.
   If the projector is on, standby-connected, or already paired/connected to the remote, the remote may stop advertising and the relevant BLE payload may not be visible.
2. Put the XGIMI remote in Bluetooth pairing mode using **Back + Home**.
3. Capture BLE advertisements with one of:
   - `btmon` on Linux;
   - `bluetoothctl scan on` for quick visibility;
   - an Android BLE scanner app;
   - a dedicated BLE sniffer if available.
4. Look for:
   - Service UUID `0x1812` / HID;
   - manufacturer-specific data;
   - company code `0x0046`;
   - payload with the projector Bluetooth MAC in little-endian byte order;
   - changing counter/prefix bytes such as `2e 30 31 32 33`.
5. Copy the projector Bluetooth MAC to `XGIMI_BT_MAC` in `xgimi.conf`.

Example Linux capture commands:

```bash
sudo btmon
```

In another shell:

```bash
bluetoothctl
scan on
```

With the projector still powered off/disconnected, put the remote into pairing mode and watch for BLE advertising reports.

### Important privacy note

Do not publish real captured MAC addresses or raw payloads containing your device identifiers. 

## HDMI-CEC wake reliability note

In daily use, HDMI-CEC has proven to be required for reliable power-on on this setup. BLE wake is still sent first, but CEC is sent immediately after BLE as a wake reinforcement. Wake-on-LAN is kept as a fallback only if the network does not become stable after BLE/CEC.

Recommended configuration:

```bash
ENABLE_CEC_WAKE="yes"
ENABLE_WOL_WAKE="yes"
```

For reliable operation, do not disable CEC unless you have verified that your projector wakes consistently without it.

## Startup mute and ADB recovery behavior

During power-on, the bridge prioritizes the visible user experience before ADB maintenance.

The sequence first sends BLE wake and HDMI-CEC wake reinforcement, then tries a fast USB Consumer mute as soon as possible. After network and Google TV Remote become available, it applies a final Google TV force-mute.

ADB recovery is intentionally started only after the startup mute path has completed. This prevents ADB recovery, dynamic-port discovery or `adb-auto-enable` handling from delaying Google TV Remote startup detection or mute handling.

## Repository layout

Recommended layout:

```text
xgimi-remote-bridge/
├── README.md
├── README.it.md
├── LICENSE
├── .gitignore
├── config/
│   └── xgimi.conf.example
├── scripts/
│   ├── xgimi-adb.sh
│   ├── xgimi-adb-recover.sh
│   ├── xgimi-ble-wake70.sh
│   ├── xgimi-flirc-listener.py
│   ├── xgimi-googletv.sh
│   ├── xgimi-key.sh
│   ├── xgimi-lib.sh
│   ├── xgimi-menu-usb.sh
│   ├── xgimi-off.sh
│   ├── xgimi-on.sh
│   ├── xgimi-status.sh
│   ├── xgimi-usb-consumer-key.sh
│   ├── xgimi-usb-key.sh
│   └── xgimi-usb-hid-setup-v2.sh
├── systemd/
│   ├── xgimi-usb-hid.service
│   └── xgimi-flirc-listener.service
└── tools/
    └── optional test/debug scripts
```

## Hardware requirements

Tested conceptually for a Raspberry Pi Zero / Zero 2 style device capable of USB gadget mode.

Required:

- Raspberry Pi with Linux and USB gadget-capable port;
- data-capable USB cable from Raspberry Pi gadget port to the projector;
- one usable USB host port for FLIRC if the same Raspberry Pi must also receive IR locally;
- FLIRC USB IR receiver connected locally to the bridge Raspberry Pi, or forwarded over the network from another Raspberry Pi;
- IR/universal remote, for example OneForAll;
- network reachability from Raspberry Pi to the projector;
- Bluetooth controller on the Raspberry Pi for BLE wake;
- HDMI-CEC-capable path between the Raspberry Pi/bridge and the projector. In daily use this is strongly recommended because BLE alone may not wake the projector reliably;
- optional Logitech Media Server player display, for example piCorePlayer / Jivelite, if LMS feedback is enabled.

## USB topology and Raspberry Pi Zero note

The bridge has two different USB roles:

1. **USB device/gadget toward the projector**: the Raspberry Pi exposes itself as a USB HID keyboard plus consumer-control device.
2. **USB host toward FLIRC**: the Raspberry Pi must also receive the FLIRC USB IR receiver, unless FLIRC is remote.

A Raspberry Pi Zero / Zero 2 W has only one practical USB OTG data port for this use case. Therefore, by itself, it is usually not enough if you want both:

- the projector connected to the Pi as a USB HID gadget;
- FLIRC physically connected to the same Pi as a USB host device.

There are two supported topologies:

### Topology A: bridge near the projector, FLIRC remote

Use a Raspberry Pi Zero / Zero 2 W next to the projector as the USB HID bridge. Connect its gadget-capable USB port to the projector.

Install FLIRC on another Raspberry Pi with a normal USB host port, then forward the FLIRC USB device to the bridge Raspberry Pi over the network.

This is the topology used during development. VirtualHere is recommended for USB-over-network because it makes a remote USB device appear as if it were locally connected to the client machine.

### Topology B: single larger Raspberry Pi

Use a Raspberry Pi model that can provide both:

- USB gadget/device mode toward the projector;
- a separate usable USB host port for FLIRC.

Validate the USB controller/port topology carefully before choosing this route. Not every Raspberry Pi model exposes USB gadget mode and independent host ports in the way this project needs.

## Software requirements on Raspberry Pi

Install packages:

```bash
sudo apt update
sudo apt install -y \
  adb \
  bluez \
  cec-utils \
  python3 \
  python3-venv \
  curl \
  netcat-openbsd \
  avahi-utils \
  wakeonlan
```

`netcat-openbsd` provides `nc`, used by the optional Logitech Media Server display integration.

`avahi-utils` provides `avahi-browse`, used by ADB recovery to discover the current wireless debugging `_adb-tls-connect._tcp` port when Android TV publishes a dynamic ADB port.

`etherwake` can be used instead of `wakeonlan` if preferred:

```bash
sudo apt install -y etherwake
```

Create the Python virtual environment for Google TV Remote:

```bash
sudo mkdir -p /opt/xgimi-remote
sudo chown "$USER":"$USER" /opt/xgimi-remote

cd /opt/xgimi-remote
python3 -m venv .venv-googletv
./.venv-googletv/bin/python3 -m pip install --upgrade pip
./.venv-googletv/bin/python3 -m pip install androidtvremote2
```

## Install files

Clone or copy the project:

```bash
sudo mkdir -p /opt/xgimi-remote/scripts
sudo cp scripts/* /opt/xgimi-remote/scripts/
sudo chmod +x /opt/xgimi-remote/scripts/*
```

Create runtime directories:

```bash
sudo mkdir -p /etc/xgimi-remote
sudo mkdir -p /var/lib/xgimi-remote/state
sudo mkdir -p /var/log/xgimi-remote

sudo chown -R root:root /etc/xgimi-remote
sudo chown -R root:root /var/lib/xgimi-remote
sudo chown -R root:root /var/log/xgimi-remote
```

Copy the configuration template:

```bash
sudo cp config/xgimi.conf.example /etc/xgimi-remote/xgimi.conf
sudo nano /etc/xgimi-remote/xgimi.conf
```

For a local development install where scripts and config stay in the same directory, you can also use:

```bash
cp config/xgimi.conf.example scripts/xgimi.conf
nano scripts/xgimi.conf
```

The systemd installation below assumes production paths under `/opt`, `/etc`, `/var`.

## Configuration

Main configuration file:

```text
/etc/xgimi-remote/xgimi.conf
```

Minimum required values:

```bash
XGIMI_IP="192.168.1.100"
XGIMI_WIFI_MAC="00:11:22:33:44:55"
XGIMI_BT_MAC="11:22:33:44:55:66"

GOOGLETV_VENV="/opt/xgimi-remote/.venv-googletv"
GOOGLETV_CERT_FILE="/etc/xgimi-remote/googletv-cert.pem"
GOOGLETV_KEY_FILE="/etc/xgimi-remote/googletv-key.pem"
GOOGLETV_CLIENT_NAME="xgimi-remote-bridge"

STATE_DIR="/var/lib/xgimi-remote/state"
LOG_FILE="/var/log/xgimi-remote/xgimi-remote.log"
```



CEC is strongly recommended for reliable ON behavior:

```bash
# yes/no
ENABLE_CEC_WAKE="yes"

# yes/no - WOL remains a fallback if BLE/CEC do not produce stable network.
ENABLE_WOL_WAKE="yes"
```

Optional Logitech Media Server / Jivelite display integration:

```bash
# yes/no
ENABLE_LMS_DISPLAY="no"

# Logitech Media Server host and CLI port.
# LMS CLI usually listens on TCP 9090.
LMS_HOST="192.168.1.10"
LMS_PORT="9090"

# LMS player identifier, usually the player MAC address.
LMS_PLAYER_ID="00:11:22:33:44:55"

# First line shown on the LMS/Jivelite display during the ON sequence.
LMS_DISPLAY_TITLE="XGIMI ON"
```

When enabled, `xgimi-on.sh` sends short progress messages to the LMS player display during the power-on sequence. This feature is optional and is designed not to block projector startup if LMS is unreachable.

For repository use, do not commit your real configuration.

## Important: make scripts find the production config

The scripts load `xgimi.conf` from their own directory by default. For production installation, create a symlink:

```bash
sudo ln -sf /etc/xgimi-remote/xgimi.conf /opt/xgimi-remote/scripts/xgimi.conf
```

Alternatively, export `CONF_FILE=/etc/xgimi-remote/xgimi.conf` in the systemd service files.

## Enable USB gadget mode on Raspberry Pi

On Raspberry Pi OS, USB gadget mode usually requires `dwc2`.

Edit `/boot/firmware/config.txt` or `/boot/config.txt`, depending on the distribution:

```bash
sudo nano /boot/firmware/config.txt
```

Add:

```text
dtoverlay=dwc2
```

Edit `/boot/firmware/cmdline.txt` or `/boot/cmdline.txt` and ensure `modules-load=dwc2` is present on the single kernel command line.

Example fragment:

```text
modules-load=dwc2
```

Reboot:

```bash
sudo reboot
```

After reboot, verify the UDC exists:

```bash
ls /sys/class/udc
```

Expected example:

```text
3f980000.usb
```

## Install systemd services

Copy service files:

```bash
sudo cp systemd/xgimi-usb-hid.service /etc/systemd/system/
sudo cp systemd/xgimi-flirc-listener.service /etc/systemd/system/
```

If your service files still point to a development directory, edit them so they point to `/opt/xgimi-remote/scripts`.

Recommended service shape:

```ini
[Unit]
Description=XGIMI USB HID Gadget keyboard + consumer control
DefaultDependencies=no
After=local-fs.target
Before=multi-user.target
ConditionPathExists=/sys/kernel/config

[Service]
Type=oneshot
ExecStart=/opt/xgimi-remote/scripts/xgimi-usb-hid-setup-v2.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

```ini
[Unit]
Description=XGIMI FLIRC listener
After=xgimi-usb-hid.service
Requires=xgimi-usb-hid.service

[Service]
Type=simple
Environment=CONF_FILE=/etc/xgimi-remote/xgimi.conf
Environment=XGIMI_BASE_DIR=/opt/xgimi-remote/scripts
WorkingDirectory=/opt/xgimi-remote/scripts
ExecStart=/usr/bin/python3 /opt/xgimi-remote/scripts/xgimi-flirc-listener.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now xgimi-usb-hid.service
sudo systemctl enable --now xgimi-flirc-listener.service
```

Check:

```bash
systemctl status xgimi-usb-hid.service -l --no-pager
systemctl status xgimi-flirc-listener.service -l --no-pager
```

Expected:

```text
xgimi-usb-hid.service        active (exited)
xgimi-flirc-listener.service active (running)
```

## Verify USB HID gadget

After the projector has enumerated the Raspberry Pi as a USB device:

```bash
cat /sys/class/udc/3f980000.usb/state
ls -l /dev/hidg0 /dev/hidg1
```

Expected:

```text
configured
/dev/hidg0
/dev/hidg1
```

Direct command tests:

```bash
cd /opt/xgimi-remote/scripts

sudo ./xgimi-usb-key.sh right
sudo ./xgimi-usb-key.sh ok
sudo ./xgimi-usb-consumer-key.sh volume-up
sudo ./xgimi-usb-consumer-key.sh mute
```

If this works, the low-latency USB route is ready.

## Google TV Remote pairing

The project uses the Android TV Remote v2 protocol through `androidtvremote2`.

Start pairing:

```bash
cd /opt/xgimi-remote/scripts
./xgimi-googletv.sh pair
```

A pairing code should appear on the projector. Enter the code when requested.

The pairing generates or uses:

```text
GOOGLETV_CERT_FILE
GOOGLETV_KEY_FILE
```

These files are private local credentials. Do not commit them.

Test:

```bash
./xgimi-googletv.sh status
./xgimi-googletv.sh home
./xgimi-googletv.sh force-mute
```

## Projector-side ADB helper: adb-auto-enable

ADB is optional but useful for:

- direct HDMI input selection;
- focus manual / autofocus keycodes;
- settings activity;
- app shortcut keycodes;
- recovery of ADB port `5555`.

Android TV / Google TV can disable or randomize wireless ADB after sleep or reboot. This project can use `adb-auto-enable` on the projector as a workaround.

High-level projector-side setup:

1. Enable Developer Options on the projector.
2. Enable Wireless debugging.
3. Install `adb-auto-enable` on the projector.
4. Pair it once with the projector’s local wireless debugging service.
5. Let it switch or restore ADB on port `5555`.
6. Keep its foreground/web service enabled if the app requires it.
7. Set `ADB_AUTO_PORT` in `xgimi.conf`, default:

```bash
ADB_AUTO_PORT="9093"
```

The recovery script expects the app to expose HTTP endpoints such as:

```text
http://PROJECTOR_IP:9093/api/status
http://PROJECTOR_IP:9093/api/switch
http://PROJECTOR_IP:9093/api/logs
```

Test from Raspberry Pi:

```bash
curl -sS "http://$XGIMI_IP:9093/api/status"
```

Then:

```bash
cd /opt/xgimi-remote/scripts
./xgimi-adb.sh status
./xgimi-adb.sh recover
```

Check ADB:

```bash
adb connect "$XGIMI_IP:5555"
adb devices
```

Expected:

```text
PROJECTOR_IP:5555    device
```

### Pair the Raspberry Pi with wireless debugging

The Raspberry Pi running the bridge must be authorized for Android wireless debugging if it needs to connect to the projector's dynamic ADB port and switch it back to `5555`.

On the projector:

```text
Developer options
→ Wireless debugging
→ Pair device with pairing code
```

On the Raspberry Pi, discover the pairing port:

```bash
avahi-browse -rt _adb-tls-pairing._tcp
```

Look for the projector IP and the pairing port, then run:

```bash
adb pair PROJECTOR_IP:PAIRING_PORT
```

Enter the code shown on the projector.

Then discover the current dynamic connect port:

```bash
avahi-browse -rt _adb-tls-connect._tcp
```

Connect to it:

```bash
adb connect PROJECTOR_IP:DYNAMIC_PORT
adb devices
```

Expected:

```text
PROJECTOR_IP:DYNAMIC_PORT    device
```

Once the dynamic port is authorized, the bridge can switch ADB back to `5555`:

```bash
adb -s PROJECTOR_IP:DYNAMIC_PORT tcpip 5555
sleep 2
adb connect PROJECTOR_IP:5555
adb devices
```

After successful pairing, clear any temporary recovery block files:

```bash
rm -f /var/lib/xgimi-remote/state/adb-auth-required
rm -f /var/lib/xgimi-remote/state/adb-bad-dynamic.port
rm -f /var/lib/xgimi-remote/state/adb-dynamic.port
rm -f /var/lib/xgimi-remote/state/adb-switch.last
```

For local development installs, use the `state/` directory under your script directory instead of `/var/lib/xgimi-remote/state`.

### How ADB recovery behaves

`xgimi-adb-recover.sh` treats ADB as optional and opportunistic. It first checks whether `PROJECTOR_IP:5555` is already available. If not, it can use `adb-auto-enable` and Avahi/mDNS discovery to find the current dynamic wireless debugging port, then try to switch it to `5555` from the Raspberry Pi.

If the dynamic port is open at TCP level but `adb connect` still fails, the likely cause is missing wireless-debugging authorization for the Raspberry Pi. In that case the script should stop retrying uselessly, mark ADB as unavailable, and show/log that ADB needs authorization.

## Optional VirtualHere setup for remote FLIRC

Use this only when the bridge Raspberry Pi is next to the projector and does not have a free USB host port for FLIRC.

Recommended layout:

```text
IR remote
   ↓
FLIRC
   ↓
Raspberry Pi with USB host port
   ↓  VirtualHere USB Server
Network
   ↓  VirtualHere USB Client
Raspberry Pi bridge near projector
   ↓
Projector USB HID gadget connection
```

Install VirtualHere USB Server on the Raspberry Pi that physically hosts FLIRC. Install VirtualHere USB Client on the bridge Raspberry Pi. Then attach the FLIRC device from the client so that it appears under `/dev/input/by-id/` on the bridge.

After attaching FLIRC through VirtualHere, verify from the bridge:

```bash
ls -l /dev/input/by-id/
```

The listener expects a device name containing:

```text
flirc
event-kbd
```

VirtualHere is not mandatory. Any reliable USB-over-network solution that exposes FLIRC as a local Linux input device on the bridge can be used, but VirtualHere is the tested option.

## FLIRC configuration

FLIRC receives IR from the universal remote and exposes a Linux keyboard-like input device.

The listener searches automatically under:

```text
/dev/input/by-id/
```

for a device containing:

```text
flirc
event-kbd
```

Check:

```bash
ls -l /dev/input/by-id/
```

Expected example:

```text
usb-flirc.tv_flirc_...-event-kbd -> ../eventX
```

### Recommended FLIRC key mapping

Program the OneForAll / universal remote through the FLIRC GUI or `flirc_util`.

The listener expects these Linux key events:

| Remote key | FLIRC/Linux key | Command |
|---|---:|---|
| Up | `KEY_UP` | `up` |
| Down | `KEY_DOWN` | `down` |
| Left | `KEY_LEFT` | `left` |
| Right | `KEY_RIGHT` | `right` |
| OK / Enter | `KEY_ENTER` or `KEY_KPENTER` | `ok` |
| Back / Undo | `KEY_ESC` | `back` |
| Backspace | `KEY_BACKSPACE` | `backspace` |
| Home | `KEY_HOME` | `home` |
| Mute | `KEY_MUTE` | `mute` |
| Volume + | `KEY_VOLUMEUP` | `volume-up` |
| Volume - | `KEY_VOLUMEDOWN` | `volume-down` |
| Red | `KEY_F1` | `power-off` |
| Green | `KEY_F2` | `hdmi1` |
| Yellow | `KEY_F3` | `hdmi2` |
| Blue | `KEY_F4` | `autofocus` |
| AV | `KEY_F5` | `input/source` |
| Text | `KEY_F6` | `focus-manual` |
| Info | `KEY_F7` | `settings/info` |
| Power On | `KEY_F8` | `power-on` |
| Netflix | `KEY_F15` | `netflix` |
| YouTube | `KEY_F16` | `youtube` |
| Settings / App | `KEY_F17` | `settings` |
| Play/Pause | `KEY_PLAYPAUSE` | `play-pause` |
| Stop | `KEY_STOPCD` | `stop` |
| Rewind | `KEY_REWIND` | `rewind` |
| Fast Forward | `KEY_FASTFORWARD` | `fast-forward` |

### Test FLIRC raw events

Install `evtest` if needed:

```bash
sudo apt install -y evtest
```

Run:

```bash
sudo evtest
```

Select the FLIRC `event-kbd` device and press remote buttons. Verify the expected Linux key codes.

### Test listener

```bash
sudo systemctl restart xgimi-flirc-listener.service
journalctl -u xgimi-flirc-listener.service -f
```

Press remote buttons and check:

```bash
tail -f /var/log/xgimi-remote/xgimi-remote.log
```

## Optional LMS / Jivelite display feedback

`xgimi-on.sh` can send temporary status messages to a Logitech Media Server player display, for example a piCorePlayer / Jivelite screen.

This is useful when the projector is still starting and there is no image yet: the user can see which phase is running, such as BLE wake, CEC wake, network wait, ADB recovery, Google TV wait and final mute.

Enable it in `xgimi.conf`:

```bash
ENABLE_LMS_DISPLAY="yes"
LMS_HOST="192.168.1.10"
LMS_PORT="9090"
LMS_PLAYER_ID="00:11:22:33:44:55"
LMS_DISPLAY_TITLE="XGIMI ON"
```

The project uses the LMS CLI `show` command through TCP port `9090`:

```text
PLAYER_ID show line1:TITLE line2:STATUS duration:SECONDS
```

The LMS display path is best-effort only. If LMS is unreachable, `nc` is missing, Python is missing, or the player ID is not configured, `xgimi-on.sh` logs a warning and continues the projector power-on sequence.

Manual test:

```bash
printf 'PLAYER_ID show line1:XGIMI line2:Test duration:10\n' | nc -w 2 LMS_HOST 9090
```

Replace `PLAYER_ID` and `LMS_HOST` with your real values.

## Command dispatcher

The main entry point is:

```bash
xgimi-key.sh COMMAND
```

Examples:

```bash
./xgimi-key.sh right
./xgimi-key.sh ok
./xgimi-key.sh volume-up
./xgimi-key.sh mute
./xgimi-key.sh power-on
./xgimi-key.sh power-off
./xgimi-key.sh hdmi1
./xgimi-key.sh hdmi2
./xgimi-key.sh autofocus
./xgimi-key.sh focus-manual
./xgimi-key.sh settings
```

Low-latency commands are USB-only:

```text
up, down, left, right, ok, back, home, volume-up, volume-down, mute
```

Special commands can use ADB or Google TV fallback:

```text
hdmi1, hdmi2, source/input, autofocus, settings, app shortcuts
```

## Power-on and power-off

Power on:

```bash
./xgimi-on.sh
```

Power off / standby:

```bash
./xgimi-off.sh
```

The dispatcher starts these asynchronously:

```bash
./xgimi-key.sh power-on
./xgimi-key.sh power-off
```

Power transition lock files prevent accidental double toggles.

## Status and diagnostics

Run:

```bash
./xgimi-status.sh
```

It checks:

- configuration;
- helper files;
- ping;
- Google TV ports;
- ADB port;
- ADB state;
- Google TV Remote state;
- power transition lock.

Useful system checks:

```bash
systemctl list-units 'xgimi*'
systemctl list-timers 'xgimi*'
journalctl -u xgimi-usb-hid.service -b --no-pager
journalctl -u xgimi-flirc-listener.service -b --no-pager
```

USB gadget checks:

```bash
cat /sys/class/udc/3f980000.usb/state
ls -l /dev/hidg0 /dev/hidg1
sudo cat /sys/kernel/config/usb_gadget/xgimi_hid/UDC
```

ADB checks:

```bash
adb devices
adb connect "$XGIMI_IP:5555"
./xgimi-adb.sh status
./xgimi-adb.sh recover
```

Google TV checks:

```bash
./xgimi-googletv.sh status
./xgimi-googletv.sh home
```

LMS display check, if enabled:

```bash
printf 'PLAYER_ID show line1:XGIMI line2:Test duration:10\n' | nc -w 2 LMS_HOST 9090
```

BLE wake manual test:

```bash
sudo ./xgimi-ble-wake70.sh 3 2e
```

## Troubleshooting

### Projector does not wake reliably

Keep HDMI-CEC enabled:

```bash
grep -E 'ENABLE_CEC_WAKE|ENABLE_WOL_WAKE' /etc/xgimi-remote/xgimi.conf
```

Expected for the validated daily-use setup:

```bash
ENABLE_CEC_WAKE="yes"
ENABLE_WOL_WAKE="yes"
```

Check that `cec-client` is installed and that the CEC path is working:

```bash
command -v cec-client
printf "on 0\n" | cec-client -s -d 1
```

If CEC is disabled, the projector may fail to wake even when BLE advertising is sent correctly.

### `/dev/hidg0` and `/dev/hidg1` do not exist

Run:

```bash
sudo /opt/xgimi-remote/scripts/xgimi-usb-hid-setup-v2.sh
```

Then:

```bash
ls -l /dev/hidg0 /dev/hidg1
```

If still missing, check:

```bash
ls /sys/class/udc
mount | grep configfs
```

### UDC state is `not attached`

The gadget exists but the projector has not enumerated it.

Check:

- data-capable USB cable;
- correct Raspberry Pi OTG/gadget port;
- projector USB port;
- projector powered on or not in deep sleep;
- no old service is detaching the gadget with `echo "" > .../UDC`.

### Commands are slow

The normal navigation/audio route should be USB HID. Slow commands usually mean USB failed and a network fallback is being used.

Check:

```bash
grep -E "USB fallito|Google TV|ADB .*OK|via USB" /var/log/xgimi-remote/xgimi-remote.log | tail -80
```

### Cursor keeps moving after key release

The FLIRC listener uses:

```python
REPEAT_MIN_INTERVAL = 0.12
STALE_EVENT_MAX_AGE = 0.20
```

If repeat is too slow, lower `REPEAT_MIN_INTERVAL`.

If movement continues after release, lower `STALE_EVENT_MAX_AGE`.

### LMS / Jivelite display does not show status messages

Check that LMS display integration is enabled and configured:

```bash
grep -E 'ENABLE_LMS_DISPLAY|LMS_HOST|LMS_PORT|LMS_PLAYER_ID|LMS_DISPLAY_TITLE' /etc/xgimi-remote/xgimi.conf
```

Verify that the LMS CLI port is reachable:

```bash
nc -vz LMS_HOST 9090
```

Send a manual `show` command:

```bash
printf 'PLAYER_ID show line1:XGIMI line2:Test duration:10\n' | nc -w 2 LMS_HOST 9090
```

If the manual command works but the ON sequence does not show messages, check:

```bash
grep '\[lms\]' /var/log/xgimi-remote/xgimi-remote.log | tail -50
```

The LMS path is intentionally non-blocking: a failure here should not stop the projector from turning on.

### Google TV pairing fails

Remove local cert/key files and pair again:

```bash
sudo rm -f /etc/xgimi-remote/googletv-cert.pem
sudo rm -f /etc/xgimi-remote/googletv-key.pem

cd /opt/xgimi-remote/scripts
./xgimi-googletv.sh pair
```

### ADB does not recover

ADB is optional. If recovery fails, first check `adb-auto-enable` on the projector:

```bash
curl -sS "http://$XGIMI_IP:9093/api/status"
```

Then run recovery manually:

```bash
./xgimi-adb-recover.sh
adb devices
cat "$STATE_DIR/adb.state"
```

If `adb-auto-enable` reports an old `lastPort`, or the log shows repeated failures on a dynamic port, discover the current port directly with Avahi:

```bash
avahi-browse -rt _adb-tls-connect._tcp
```

Check whether the advertised port is reachable:

```bash
nc -vz "$XGIMI_IP" DYNAMIC_PORT
```

Interpretation:

- `Connection refused` or timeout: the advertised port is stale or not reachable; wait, restart wireless debugging, or restart `adb-auto-enable` / the projector.
- TCP connection succeeds but `adb connect "$XGIMI_IP:DYNAMIC_PORT"` fails: the Raspberry Pi is probably not paired/authorized for wireless debugging. Pair it using **Wireless debugging → Pair device with pairing code** on the projector and `adb pair` on the Raspberry Pi.
- `adb connect "$XGIMI_IP:DYNAMIC_PORT"` works and appears as `device`: switch to `5555`:

```bash
adb -s "$XGIMI_IP:DYNAMIC_PORT" tcpip 5555
sleep 2
adb connect "$XGIMI_IP:5555"
adb devices
```

If the script previously detected a missing authorization, clear the temporary block after pairing:

```bash
rm -f "$STATE_DIR/adb-auth-required"
rm -f "$STATE_DIR/adb-bad-dynamic.port"
rm -f "$STATE_DIR/adb-dynamic.port"
rm -f "$STATE_DIR/adb-switch.last"
```

Expected final state:

```text
PROJECTOR_IP:5555    device
```

## External references

This project relies on or interoperates with the following external projects and interfaces:

- [`androidtvremote2`](https://pypi.org/project/androidtvremote2/) — Python library for the Android TV Remote protocol v2. It does not require ADB or Developer Options and uses the Android TV Remote Service normally available on Android TV / Google TV devices.
- [`adb-auto-enable`](https://github.com/mouldybread/adb-auto-enable) — Android / Google TV helper app that can automatically enable wireless ADB and switch it to TCP port `5555` on boot, without root.
- [XGIMI Bluetooth remote pairing guide](https://helpcenter.xgimi.com/hc/en-gb/articles/47803066696729-How-to-pair-XGIMI-Bluetooth-remote-control) — official pairing procedure using **Back + Home**.
- [`manymuch/Xgimi-4-Home-Assistant` issue #5](https://github.com/manymuch/Xgimi-4-Home-Assistant/issues/5) — community observation of XGIMI BLE manufacturer-specific data with company code `0x0046`.
- [FLIRC](https://flirc.tv/) — USB IR receiver used to translate IR remote buttons into Linux keyboard events.
- [FLIRC command line utility](https://support.flirc.tv/hc/en-us/articles/203633579-Flirc-Command-Line-Application) — official `flirc_util` documentation for CLI-based configuration and diagnostics.
- [VirtualHere](https://www.virtualhere.com/) — USB-over-network solution used when FLIRC is connected to a different Raspberry Pi than the projector bridge.
- [VirtualHere Linux USB Server](https://www.virtualhere.com/usb_server_software) — server side used on the Raspberry Pi that physically hosts FLIRC.
- [VirtualHere USB Client](https://www.virtualhere.com/usb_client_software) — client side used on the bridge Raspberry Pi to attach the remote FLIRC device.
- [Linux USB gadget ConfigFS documentation](https://docs.kernel.org/usb/gadget_configfs.html) — kernel documentation for creating USB gadgets through ConfigFS.
- [Linux HID gadget testing documentation](https://docs.kernel.org/usb/gadget_hid.html) — kernel documentation for HID gadget behavior and test patterns.
- [Android Debug Bridge documentation](https://developer.android.com/tools/adb) — official Android documentation for ADB.
- [Logitech Media Server / Lyrion Music Server](https://lyrion.org/) — server used by the optional LMS/Jivelite display feedback integration.
- [GNU General Public License v3](https://www.gnu.org/licenses/gpl-3.0.en.html) — license used by this project.


## Known limitations

- BLE wake payloads may be model-specific; on this setup BLE alone is not considered sufficient for reliable daily power-on.
- ADB is optional and treated as opportunistic; do not rely on it for core navigation.
- Google TV Remote requires successful pairing and valid local cert/key files.
- HDMI direct selection depends on Android TV input activity names and may differ across firmware versions.
- USB HID requires proper gadget support and physical USB enumeration by the projector.
- FLIRC key mappings depend on how the IR remote was programmed.
- LMS/Jivelite display feedback is optional and depends on the LMS CLI port and player display support.
- A Raspberry Pi Zero used as the projector-side bridge normally needs remote FLIRC forwarding because its single OTG data port is already used for the projector USB HID gadget connection.

## License

This project is released under the **GNU General Public License v3.0 or later**.

SPDX identifier:

```text
GPL-3.0-or-later
```

See [`LICENSE`](LICENSE) for the full license text.

## Credits

Built for a Raspberry Pi based projector-control bridge using:

- Linux USB HID gadget mode;
- FLIRC IR receiver;
- Android TV Remote v2 through `androidtvremote2`;
- optional `adb-auto-enable` for ADB persistence;
- HDMI-CEC wake reinforcement;
- optional Wake-on-LAN.

Live long and prosper to the universal remote.
