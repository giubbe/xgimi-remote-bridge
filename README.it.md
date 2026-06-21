# XGIMI Remote Bridge

Bridge remoto per proiettori XGIMI / Google TV basato su Raspberry Pi, FLIRC, modalità USB HID gadget, Google TV Remote v2, wake BLE, rinforzo di accensione HDMI-CEC e recupero ADB opzionale.

L’obiettivo è usare un telecomando universale IR come telecomando affidabile per il proiettore, usando USB HID a bassa latenza per navigazione e audio, e lasciando Google TV / ADB solo dove servono davvero.

## Stato

Versione: `1.0.2`

Funzioni validate:

- accensione tramite BLE wake, rinforzo immediato HDMI-CEC e WOL come fallback;
- spegnimento / standby tramite Google TV Remote;
- comandi tastiera USB HID a bassa latenza;
- comandi consumer-control USB HID a bassa latenza;
- listener FLIRC stabile con limitazione dell’autorepeat e scarto eventi vecchi;
- pairing Google TV Remote v2 e fallback comandi;
- recupero ADB opzionale tramite adb-auto-enable;
- feedback opzionale su display Logitech Media Server / Jivelite durante l’accensione;
- tasti speciali per selezione ingressi, HDMI, autofocus e menu focus.
- mute USB Consumer rapido durante l’accensione;
- force-mute Google TV dopo conferma `is_on=True`;
- timeout sui controlli Google TV status e force-mute;
- recovery ADB spostato dopo il mute di accensione, così non ritarda la gestione Google TV Remote;

## Nota lingua

Il progetto è stato sviluppato e testato in un ambiente home-lab italiano.
Alcuni commenti interni e messaggi di log sono ancora in italiano.
Il README principale è in inglese per rendere il progetto più facilmente riutilizzabile anche fuori dall’Italia.
Questo file è la documentazione italiana opzionale.

## Architettura

```text
Telecomando IR
 ↓
Ricevitore USB FLIRC
 ↓
Listener su Raspberry Pi
 ↓
Dispatcher xgimi-key.sh
 ├── Tastiera USB HID→ frecce, OK, ESC/backspace
 ├── Consumer control USB HID→ volume, mute, home, back, media
 ├── ADB, quando disponibile → HDMI, focus, scorciatoie app, settings
 └── Google TV Remote v2 → power, status, force mute, fallback
```

Accensione:

```text
xgimi-on.sh
 ├── BLE manufacturer-data wake
 ├── rinforzo immediato HDMI-CEC
 ├── mute USB Consumer rapido, best-effort
 ├── Wake-on-LAN come fallback se la rete non diventa stabile
 ├── messaggi opzionali su Logitech Media Server / Jivelite
 ├── attesa Google TV con timeout per singolo controllo
 ├── force-mute Google TV finale dopo conferma is_on=True
 └── recupero ADB in background dopo il mute di accensione
```


```markdown
## Comportamento mute di accensione e recovery ADB

Durante l’accensione, il bridge dà priorità al comportamento percepito dall’utente prima della manutenzione ADB.

La sequenza invia prima il wake BLE e il rinforzo HDMI-CEC, poi tenta un mute rapido tramite USB Consumer appena possibile. Quando rete e Google TV Remote risultano disponibili, applica un force-mute finale tramite Google TV.

Il recovery ADB viene avviato intenzionalmente solo dopo il percorso di mute di accensione. Questo evita che recovery ADB, scoperta della porta dinamica o gestione `adb-auto-enable` possano ritardare il rilevamento Google TV Remote o il mute.

## Scoperta e cattura del payload BLE wake

La parte BLE wake nasce da due fonti:

1. La procedura ufficiale XGIMI per il pairing del telecomando: mettere il telecomando vicino al proiettore e premere **Back + Home** finché il LED del telecomando lampeggia. Questo mette il telecomando in modalità pairing Bluetooth.
2. La ricerca della community nel ticket GitHub `manymuch/Xgimi-4-Home-Assistant` issue #5, dove il telecomando Bluetooth XGIMI è stato osservato trasmettere manufacturer-specific data con **company code `0x0046`** e payload terminante in `30 43 52 4b 54 4d`.

Per questo progetto il pacchetto wake è stato validato catturando gli advertising BLE reali del telecomando XGIMI e replicando dal Raspberry Pi i manufacturer data rilevanti.

### Procedura di cattura

Procedura consigliata:

1. Spegni completamente il proiettore e scollegalo dalla corrente.
 Se il proiettore è acceso, in standby connesso o già associato/connesso al telecomando, il telecomando può smettere di fare advertising e il payload BLE rilevante può non essere visibile.
2. Metti il telecomando XGIMI in modalità pairing Bluetooth con **Back + Home**.
3. Cattura gli advertising BLE con uno di questi strumenti:
 - `btmon` su Linux;
 - `bluetoothctl scan on` per una verifica rapida;
 - app Android BLE scanner;
 - sniffer BLE dedicato, se disponibile.
4. Cerca:
 - Service UUID `0x1812` / HID;
 - manufacturer-specific data;
 - company code `0x0046`;
 - payload con il MAC Bluetooth del proiettore in ordine little-endian;
 - byte counter/prefix variabili come `2e 30 31 32 33`.
5. Copia il MAC Bluetooth del proiettore in `XGIMI_BT_MAC` dentro `xgimi.conf`.

Comandi Linux di esempio:

```bash
sudo btmon
```

In un altro terminale:

```bash
bluetoothctl
scan on
```

Con il proiettore ancora spento/scollegato, metti il telecomando in modalità pairing e osserva gli advertising report BLE.

### Nota privacy

Non pubblicare MAC reali o payload grezzi contenenti identificativi dei tuoi dispositivi. 

## Nota affidabilità accensione HDMI-CEC

Nell’uso quotidiano, HDMI-CEC si è dimostrato necessario per un’accensione affidabile in questa configurazione. Il wake BLE viene ancora inviato per primo, ma CEC viene inviato subito dopo come rinforzo di accensione. Wake-on-LAN resta come fallback solo se la rete non diventa stabile dopo BLE/CEC.

Configurazione consigliata:

```bash
ENABLE_CEC_WAKE="yes"
ENABLE_WOL_WAKE="yes"
```

Per un uso affidabile, non disabilitare CEC salvo verifica esplicita che il tuo proiettore si riaccenda sempre senza CEC.

## Struttura repository consigliata

```text
xgimi-remote-bridge/
├── README.md
├── README.it.md
├── LICENSE
├── .gitignore
├── config/
│ └── xgimi.conf.example
├── scripts/
│ ├── xgimi-adb.sh
│ ├── xgimi-adb-recover.sh
│ ├── xgimi-ble-wake70.sh
│ ├── xgimi-flirc-listener.py
│ ├── xgimi-googletv.sh
│ ├── xgimi-key.sh
│ ├── xgimi-lib.sh
│ ├── xgimi-menu-usb.sh
│ ├── xgimi-off.sh
│ ├── xgimi-on.sh
│ ├── xgimi-status.sh
│ ├── xgimi-usb-consumer-key.sh
│ ├── xgimi-usb-key.sh
│ └── xgimi-usb-hid-setup-v2.sh
├── systemd/
│ ├── xgimi-usb-hid.service
│ └── xgimi-flirc-listener.service
└── tools/
└── script opzionali di test/debug
```

## Requisiti hardware

Richiesti:

- Raspberry Pi con porta USB capace di modalità gadget;
- cavo USB dati dalla porta gadget del Raspberry alla porta USB del proiettore;
- una porta USB host utilizzabile per FLIRC se lo stesso Raspberry Pi deve anche ricevere localmente il telecomando IR;
- ricevitore FLIRC USB collegato localmente al Raspberry bridge, oppure inoltrato via rete da un altro Raspberry Pi;
- telecomando IR/universale, per esempio OneForAll;
- rete raggiungibile tra Raspberry e proiettore;
- Bluetooth sul Raspberry per il wake BLE;
- percorso HDMI-CEC funzionante tra Raspberry Pi/bridge e proiettore. Nell’uso quotidiano è fortemente consigliato perché il solo BLE può non riaccendere il proiettore in modo affidabile;
- display opzionale Logitech Media Server, per esempio piCorePlayer / Jivelite, se si abilita il feedback LMS.

## Topologia USB e nota Raspberry Pi Zero

Il bridge usa due ruoli USB diversi:

1. **USB device/gadget verso il proiettore**: il Raspberry Pi si presenta come tastiera USB HID più consumer-control.
2. **USB host verso FLIRC**: il Raspberry Pi deve anche ricevere il ricevitore IR USB FLIRC, salvo uso di FLIRC remoto.

Un Raspberry Pi Zero / Zero 2 W ha una sola porta USB OTG dati realmente pratica per questo scenario. Quindi, da solo, di solito non basta se vuoi contemporaneamente:

- il proiettore collegato al Pi come gadget USB HID;
- FLIRC collegato fisicamente allo stesso Pi come dispositivo USB host.

Sono supportate due topologie:

### Topologia A: bridge vicino al proiettore, FLIRC remoto

Usa un Raspberry Pi Zero / Zero 2 W accanto al proiettore come bridge USB HID. Collega la sua porta USB gadget al proiettore.

Installa FLIRC su un altro Raspberry Pi con una normale porta USB host, poi inoltra il dispositivo USB FLIRC al Raspberry bridge tramite rete.

Questa è la topologia usata durante lo sviluppo. VirtualHere è consigliato per USB-over-network perché fa apparire un dispositivo USB remoto come se fosse collegato localmente al client.

### Topologia B: singolo Raspberry Pi più grande

Usa un modello Raspberry Pi che possa fornire entrambi:

- modalità USB gadget/device verso il proiettore;
- una porta USB host separata utilizzabile per FLIRC.

Verifica con attenzione la topologia del controller/porte USB prima di scegliere questa strada. Non tutti i modelli Raspberry Pi espongono modalità gadget e porte host indipendenti nel modo richiesto dal progetto.

## Requisiti software su Raspberry Pi

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

`netcat-openbsd` fornisce `nc`, usato dall’integrazione opzionale con il display Logitech Media Server.

`avahi-utils` fornisce `avahi-browse`, usato dal recupero ADB per scoprire la porta dinamica `_adb-tls-connect._tcp` pubblicata dal debug wireless Android TV.

In alternativa a `wakeonlan`:

```bash
sudo apt install -y etherwake
```

Ambiente Python per Google TV Remote:

```bash
sudo mkdir -p /opt/xgimi-remote
sudo chown "$USER":"$USER" /opt/xgimi-remote

cd /opt/xgimi-remote
python3 -m venv .venv-googletv
./.venv-googletv/bin/python3 -m pip install --upgrade pip
./.venv-googletv/bin/python3 -m pip install androidtvremote2
```

## Installazione file

```bash
sudo mkdir -p /opt/xgimi-remote/scripts
sudo cp scripts/* /opt/xgimi-remote/scripts/
sudo chmod +x /opt/xgimi-remote/scripts/*
```

Directory runtime:

```bash
sudo mkdir -p /etc/xgimi-remote
sudo mkdir -p /var/lib/xgimi-remote/state
sudo mkdir -p /var/log/xgimi-remote

sudo chown -R root:root /etc/xgimi-remote
sudo chown -R root:root /var/lib/xgimi-remote
sudo chown -R root:root /var/log/xgimi-remote
```

Configurazione:

```bash
sudo cp config/xgimi.conf.example /etc/xgimi-remote/xgimi.conf
sudo nano /etc/xgimi-remote/xgimi.conf
```

Collegamento comodo per far trovare la configurazione agli script:

```bash
sudo ln -sf /etc/xgimi-remote/xgimi.conf /opt/xgimi-remote/scripts/xgimi.conf
```

## Configurazione minima

File:

```text
/etc/xgimi-remote/xgimi.conf
```

Valori minimi:

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



CEC è fortemente consigliato per il comportamento ON affidabile:

```bash
# yes/no
ENABLE_CEC_WAKE="yes"

# yes/no - WOL resta un fallback se BLE/CEC non producono rete stabile.
ENABLE_WOL_WAKE="yes"
```

Integrazione opzionale Logitech Media Server / Jivelite:

```bash
# yes/no
ENABLE_LMS_DISPLAY="no"

# Host Logitech Media Server e porta CLI.
# La CLI LMS normalmente ascolta su TCP 9090.
LMS_HOST="192.168.1.10"
LMS_PORT="9090"

# Identificativo player LMS, di solito il MAC address del player.
LMS_PLAYER_ID="00:11:22:33:44:55"

# Prima riga mostrata sul display LMS/Jivelite durante la sequenza ON.
LMS_DISPLAY_TITLE="XGIMI ON"
```

Quando abilitato, `xgimi-on.sh` invia brevi messaggi di avanzamento al display del player LMS durante l’accensione. La funzione è opzionale e non deve bloccare l’accensione del proiettore se LMS non è raggiungibile.

Non committare mai il tuo `xgimi.conf` reale.

## Abilitare USB gadget mode

Su Raspberry Pi OS serve normalmente `dwc2`.

Modifica `/boot/firmware/config.txt` oppure `/boot/config.txt`:

```bash
sudo nano /boot/firmware/config.txt
```

Aggiungi:

```text
dtoverlay=dwc2
```

Poi modifica `/boot/firmware/cmdline.txt` oppure `/boot/cmdline.txt` e verifica che sulla singola riga del kernel sia presente:

```text
modules-load=dwc2
```

Riavvia:

```bash
sudo reboot
```

Verifica:

```bash
ls /sys/class/udc
```

Esempio atteso:

```text
3f980000.usb
```

## Servizi systemd

Copia i servizi:

```bash
sudo cp systemd/xgimi-usb-hid.service /etc/systemd/system/
sudo cp systemd/xgimi-flirc-listener.service /etc/systemd/system/
```

Forma consigliata per `xgimi-usb-hid.service`:

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

Forma consigliata per `xgimi-flirc-listener.service`:

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

Abilita:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now xgimi-usb-hid.service
sudo systemctl enable --now xgimi-flirc-listener.service
```

Controlla:

```bash
systemctl status xgimi-usb-hid.service -l --no-pager
systemctl status xgimi-flirc-listener.service -l --no-pager
```

Atteso:

```text
xgimi-usb-hid.serviceactive (exited)
xgimi-flirc-listener.service active (running)
```

## Verifica USB HID

```bash
cat /sys/class/udc/3f980000.usb/state
ls -l /dev/hidg0 /dev/hidg1
```

Atteso:

```text
configured
/dev/hidg0
/dev/hidg1
```

Test diretto:

```bash
cd /opt/xgimi-remote/scripts

sudo ./xgimi-usb-key.sh right
sudo ./xgimi-usb-key.sh ok
sudo ./xgimi-usb-consumer-key.sh volume-up
sudo ./xgimi-usb-consumer-key.sh mute
```

## Pairing Google TV Remote

Il progetto usa il protocollo Android TV Remote v2 tramite `androidtvremote2`.

```bash
cd /opt/xgimi-remote/scripts
./xgimi-googletv.sh pair
```

Sul proiettore dovrebbe comparire un codice. Inseriscilo quando richiesto.

I file:

```text
GOOGLETV_CERT_FILE
GOOGLETV_KEY_FILE
```

sono credenziali locali private. Non committarli.

Test:

```bash
./xgimi-googletv.sh status
./xgimi-googletv.sh home
./xgimi-googletv.sh force-mute
```

## Configurazione lato proiettore: adb-auto-enable

ADB è opzionale, ma utile per:

- selezione diretta HDMI;
- focus manuale / autofocus via keycode;
- settings activity;
- scorciatoie app;
- recupero porta TCP `5555`.

Su Android TV / Google TV, ADB wireless può disattivarsi o cambiare porta dopo sleep o reboot. Questo progetto può usare `adb-auto-enable` come workaround.

Procedura generale lato proiettore:

1. Abilita Opzioni sviluppatore.
2. Abilita Debug wireless.
3. Installa `adb-auto-enable`.
4. Esegui il pairing iniziale dell’app con il servizio debug wireless locale.
5. Lascia che l’app ripristini ADB su porta `5555`.
6. Mantieni attivo il servizio dell’app se necessario.
7. In `xgimi.conf` lascia o imposta:

```bash
ADB_AUTO_PORT="9093"
```

Il recovery script si aspetta endpoint HTTP come:

```text
http://PROJECTOR_IP:9093/api/status
http://PROJECTOR_IP:9093/api/switch
http://PROJECTOR_IP:9093/api/logs
```

Test dal Raspberry:

```bash
curl -sS "http://$XGIMI_IP:9093/api/status"
```

Poi:

```bash
cd /opt/xgimi-remote/scripts
./xgimi-adb.sh status
./xgimi-adb.sh recover
```

ADB:

```bash
adb connect "$XGIMI_IP:5555"
adb devices
```

Atteso:

```text
PROJECTOR_IP:5555    device
```

### Accoppiare il Raspberry Pi al debug wireless

Il Raspberry Pi che esegue il bridge deve essere autorizzato per il debug wireless Android se deve collegarsi alla porta ADB dinamica del proiettore e riportarla su `5555`.

Sul proiettore:

```text
Opzioni sviluppatore
→ Debug wireless
→ Associa dispositivo con codice di accoppiamento
```

Sul Raspberry Pi, scopri la porta di pairing:

```bash
avahi-browse -rt _adb-tls-pairing._tcp
```

Cerca l’IP del proiettore e la porta di pairing, poi esegui:

```bash
adb pair PROJECTOR_IP:PORTA_PAIRING
```

Inserisci il codice mostrato dal proiettore.

Poi scopri la porta dinamica di connessione:

```bash
avahi-browse -rt _adb-tls-connect._tcp
```

Connettiti alla porta mostrata:

```bash
adb connect PROJECTOR_IP:PORTA_DINAMICA
adb devices
```

Atteso:

```text
PROJECTOR_IP:PORTA_DINAMICA    device
```

Quando la porta dinamica è autorizzata, il bridge può riportare ADB su `5555`:

```bash
adb -s PROJECTOR_IP:PORTA_DINAMICA tcpip 5555
sleep 2
adb connect PROJECTOR_IP:5555
adb devices
```

Dopo un pairing riuscito, pulisci eventuali blocchi temporanei del recovery:

```bash
rm -f /var/lib/xgimi-remote/state/adb-auth-required
rm -f /var/lib/xgimi-remote/state/adb-bad-dynamic.port
rm -f /var/lib/xgimi-remote/state/adb-dynamic.port
rm -f /var/lib/xgimi-remote/state/adb-switch.last
```

Per installazioni locali di sviluppo, usa invece la directory `state/` dentro la cartella degli script.

### Comportamento del recovery ADB

`xgimi-adb-recover.sh` tratta ADB come opzionale e opportunistico. Prima controlla se `PROJECTOR_IP:5555` è già disponibile. Se non lo è, può usare `adb-auto-enable` e la scoperta Avahi/mDNS per trovare la porta dinamica corrente del debug wireless, poi provare a riportarla su `5555` dal Raspberry Pi.

Se la porta dinamica è aperta a livello TCP ma `adb connect` fallisce, la causa più probabile è che il Raspberry Pi non sia ancora autorizzato al debug wireless. In quel caso lo script deve evitare tentativi inutili, segnare ADB come non disponibile e indicare nei log/display che ADB deve essere autorizzato.

## Configurazione opzionale VirtualHere per FLIRC remoto

Usa questa modalità quando il Raspberry Pi bridge è vicino al proiettore e non ha una porta USB host libera per FLIRC.

Schema consigliato:

```text
Telecomando IR
 ↓
FLIRC
 ↓
Raspberry Pi con porta USB host
 ↓VirtualHere USB Server
Rete
 ↓VirtualHere USB Client
Raspberry Pi bridge vicino al proiettore
 ↓
Collegamento USB HID gadget al proiettore
```

Installa VirtualHere USB Server sul Raspberry Pi che ospita fisicamente FLIRC. Installa VirtualHere USB Client sul Raspberry Pi bridge. Poi aggancia il dispositivo FLIRC dal client, in modo che appaia sotto `/dev/input/by-id/` sul bridge.

Dopo aver agganciato FLIRC tramite VirtualHere, verifica dal bridge:

```bash
ls -l /dev/input/by-id/
```

Il listener cerca un device che contenga:

```text
flirc
event-kbd
```

VirtualHere non è obbligatorio. Qualsiasi soluzione USB-over-network affidabile che esponga FLIRC come dispositivo input Linux locale sul bridge può funzionare, ma VirtualHere è l’opzione testata.

## Configurazione FLIRC

FLIRC riceve IR dal telecomando universale e si presenta a Linux come tastiera.

Il listener cerca automaticamente in:

```text
/dev/input/by-id/
```

un dispositivo che contenga:

```text
flirc
event-kbd
```

Controllo:

```bash
ls -l /dev/input/by-id/
```

Esempio:

```text
usb-flirc.tv_flirc_...-event-kbd -> ../eventX
```

### Mappa tasti consigliata

Programma il telecomando tramite GUI FLIRC o `flirc_util`.

| Tasto telecomando | Tasto Linux / FLIRC | Comando |
|---|---:|---|
| Su | `KEY_UP` | `up` |
| Giù | `KEY_DOWN` | `down` |
| Sinistra | `KEY_LEFT` | `left` |
| Destra | `KEY_RIGHT` | `right` |
| OK / Enter | `KEY_ENTER` o `KEY_KPENTER` | `ok` |
| Back / Undo | `KEY_ESC` | `back` |
| Backspace | `KEY_BACKSPACE` | `backspace` |
| Home | `KEY_HOME` | `home` |
| Mute | `KEY_MUTE` | `mute` |
| Volume + | `KEY_VOLUMEUP` | `volume-up` |
| Volume - | `KEY_VOLUMEDOWN` | `volume-down` |
| Rosso | `KEY_F1` | `power-off` |
| Verde | `KEY_F2` | `hdmi1` |
| Giallo | `KEY_F3` | `hdmi2` |
| Blu | `KEY_F4` | `autofocus` |
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

Test eventi:

```bash
sudo apt install -y evtest
sudo evtest
```

Scegli il device FLIRC e premi i tasti.

## Feedback opzionale LMS / Jivelite

`xgimi-on.sh` può inviare messaggi temporanei di stato al display di un player Logitech Media Server, per esempio uno schermo piCorePlayer / Jivelite.

È utile durante l’accensione, quando il proiettore non mostra ancora immagine: il display può indicare la fase in corso, ad esempio BLE wake, CEC wake, attesa rete, recupero ADB, attesa Google TV e mute finale.

Abilitazione in `xgimi.conf`:

```bash
ENABLE_LMS_DISPLAY="yes"
LMS_HOST="192.168.1.10"
LMS_PORT="9090"
LMS_PLAYER_ID="00:11:22:33:44:55"
LMS_DISPLAY_TITLE="XGIMI ON"
```

Il progetto usa il comando CLI LMS `show` tramite porta TCP `9090`:

```text
PLAYER_ID show line1:TITOLO line2:STATO duration:SECONDI
```

Il percorso LMS è solo best-effort. Se LMS non è raggiungibile, manca `nc`, manca Python o il player ID non è configurato, `xgimi-on.sh` scrive un warning nel log e continua la sequenza di accensione.

Test manuale:

```bash
printf 'PLAYER_ID show line1:XGIMI line2:Test duration:10\n' | nc -w 2 LMS_HOST 9090
```

Sostituisci `PLAYER_ID` e `LMS_HOST` con i valori reali.

## Dispatcher comandi

Entry point principale:

```bash
xgimi-key.sh COMANDO
```

Esempi:

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

Comandi a bassa latenza, USB-only:

```text
up, down, left, right, ok, back, home, volume-up, volume-down, mute
```

Comandi speciali con ADB o fallback Google TV:

```text
hdmi1, hdmi2, source/input, autofocus, settings, scorciatoie app
```

## Accensione e spegnimento

Accensione:

```bash
./xgimi-on.sh
```

Standby:

```bash
./xgimi-off.sh
```

Via dispatcher:

```bash
./xgimi-key.sh power-on
./xgimi-key.sh power-off
```

Il lock di transizione evita doppi toggle accidentali.

## Diagnostica

```bash
./xgimi-status.sh
```

Controlli utili:

```bash
systemctl list-units 'xgimi*'
systemctl list-timers 'xgimi*'
journalctl -u xgimi-usb-hid.service -b --no-pager
journalctl -u xgimi-flirc-listener.service -b --no-pager
```

USB gadget:

```bash
cat /sys/class/udc/3f980000.usb/state
ls -l /dev/hidg0 /dev/hidg1
sudo cat /sys/kernel/config/usb_gadget/xgimi_hid/UDC
```

ADB:

```bash
adb devices
adb connect "$XGIMI_IP:5555"
./xgimi-adb.sh status
./xgimi-adb.sh recover
```

Google TV:

```bash
./xgimi-googletv.sh status
./xgimi-googletv.sh home
```

Controllo display LMS, se abilitato:

```bash
printf 'PLAYER_ID show line1:XGIMI line2:Test duration:10\n' | nc -w 2 LMS_HOST 9090
```

BLE wake manuale:

```bash
sudo ./xgimi-ble-wake70.sh 3 2e
```

## Troubleshooting

### Il proiettore non si accende in modo affidabile

Mantieni HDMI-CEC abilitato:

```bash
grep -E 'ENABLE_CEC_WAKE|ENABLE_WOL_WAKE' /etc/xgimi-remote/xgimi.conf
```

Atteso per la configurazione validata nell’uso quotidiano:

```bash
ENABLE_CEC_WAKE="yes"
ENABLE_WOL_WAKE="yes"
```

Controlla che `cec-client` sia installato e che il percorso CEC funzioni:

```bash
command -v cec-client
printf "on 0\n" | cec-client -s -d 1
```

Se CEC è disabilitato, il proiettore può non accendersi anche se il BLE advertising viene inviato correttamente.

### Mancano `/dev/hidg0` e `/dev/hidg1`

```bash
sudo /opt/xgimi-remote/scripts/xgimi-usb-hid-setup-v2.sh
ls -l /dev/hidg0 /dev/hidg1
```

Se mancano ancora:

```bash
ls /sys/class/udc
mount | grep configfs
```

### Stato UDC `not attached`

Il gadget esiste ma il proiettore non lo ha enumerato.

Controlla:

- cavo USB dati;
- porta OTG corretta sul Raspberry;
- porta USB del proiettore;
- proiettore acceso o non in deep standby;
- assenza di vecchi servizi che eseguono `echo "" > .../UDC`.

### Comandi lenti

La navigazione normale deve passare da USB HID. Se è lenta, probabilmente sta usando fallback di rete.

```bash
grep -E "USB fallito|Google TV|ADB .*OK|via USB" /var/log/xgimi-remote/xgimi-remote.log | tail -80
```

### Il cursore continua dopo il rilascio

Il listener usa:

```python
REPEAT_MIN_INTERVAL = 0.12
STALE_EVENT_MAX_AGE = 0.20
```

Se il repeat è lento, abbassa `REPEAT_MIN_INTERVAL`.

Se continua dopo il rilascio, abbassa `STALE_EVENT_MAX_AGE`.

### Il display LMS / Jivelite non mostra i messaggi

Controlla che l’integrazione LMS sia abilitata e configurata:

```bash
grep -E 'ENABLE_LMS_DISPLAY|LMS_HOST|LMS_PORT|LMS_PLAYER_ID|LMS_DISPLAY_TITLE' /etc/xgimi-remote/xgimi.conf
```

Verifica che la porta CLI LMS sia raggiungibile:

```bash
nc -vz LMS_HOST 9090
```

Invia manualmente un comando `show`:

```bash
printf 'PLAYER_ID show line1:XGIMI line2:Test duration:10\n' | nc -w 2 LMS_HOST 9090
```

Se il comando manuale funziona ma la sequenza ON non mostra messaggi, controlla:

```bash
grep '\[lms\]' /var/log/xgimi-remote/xgimi-remote.log | tail -50
```

Il percorso LMS è volutamente non bloccante: un errore qui non deve impedire al proiettore di accendersi.

### Pairing Google TV fallito

```bash
sudo rm -f /etc/xgimi-remote/googletv-cert.pem
sudo rm -f /etc/xgimi-remote/googletv-key.pem

cd /opt/xgimi-remote/scripts
./xgimi-googletv.sh pair
```

### ADB non recupera

ADB è opzionale. Se il recupero fallisce, controlla prima `adb-auto-enable` sul proiettore:

```bash
curl -sS "http://$XGIMI_IP:9093/api/status"
```

Poi lancia il recovery manualmente:

```bash
./xgimi-adb-recover.sh
adb devices
cat "$STATE_DIR/adb.state"
```

Se `adb-auto-enable` riporta un vecchio `lastPort`, o il log mostra fallimenti ripetuti su una porta dinamica, scopri la porta corrente direttamente con Avahi:

```bash
avahi-browse -rt _adb-tls-connect._tcp
```

Controlla se la porta pubblicata è raggiungibile:

```bash
nc -vz "$XGIMI_IP" PORTA_DINAMICA
```

Interpretazione:

- `Connection refused` o timeout: la porta pubblicata è vecchia o non raggiungibile; attendi, riavvia il debug wireless, oppure riavvia `adb-auto-enable` / il proiettore.
- La connessione TCP riesce ma `adb connect "$XGIMI_IP:PORTA_DINAMICA"` fallisce: probabilmente il Raspberry Pi non è associato/autorizzato per il debug wireless. Esegui il pairing da **Debug wireless → Associa dispositivo con codice di accoppiamento** sul proiettore e `adb pair` sul Raspberry Pi.
- `adb connect "$XGIMI_IP:PORTA_DINAMICA"` funziona e appare come `device`: riporta ADB su `5555`:

```bash
adb -s "$XGIMI_IP:PORTA_DINAMICA" tcpip 5555
sleep 2
adb connect "$XGIMI_IP:5555"
adb devices
```

Se lo script aveva rilevato una mancata autorizzazione, dopo il pairing cancella i blocchi temporanei:

```bash
rm -f "$STATE_DIR/adb-auth-required"
rm -f "$STATE_DIR/adb-bad-dynamic.port"
rm -f "$STATE_DIR/adb-dynamic.port"
rm -f "$STATE_DIR/adb-switch.last"
```

Stato finale atteso:

```text
PROJECTOR_IP:5555    device
```

## Riferimenti esterni

- [`androidtvremote2`](https://pypi.org/project/androidtvremote2/) — libreria Python per Android TV Remote protocol v2. Non richiede ADB né Opzioni sviluppatore e usa Android TV Remote Service.
- [`adb-auto-enable`](https://github.com/mouldybread/adb-auto-enable) — app Android / Google TV per riabilitare automaticamente ADB wireless e porta `5555` al boot, senza root.
- [Guida pairing telecomando Bluetooth XGIMI](https://helpcenter.xgimi.com/hc/en-gb/articles/47803066696729-How-to-pair-XGIMI-Bluetooth-remote-control) — procedura ufficiale con **Back + Home**.
- [`manymuch/Xgimi-4-Home-Assistant` issue #5](https://github.com/manymuch/Xgimi-4-Home-Assistant/issues/5) — osservazione community dei manufacturer-specific data BLE XGIMI con company code `0x0046`.
- [FLIRC](https://flirc.tv/) — ricevitore IR USB usato per trasformare tasti IR in eventi tastiera.
- [FLIRC command line utility](https://support.flirc.tv/hc/en-us/articles/203633579-Flirc-Command-Line-Application) — documentazione ufficiale di `flirc_util`.
- [VirtualHere](https://www.virtualhere.com/) — soluzione USB-over-network usata quando FLIRC è collegato a un Raspberry Pi diverso dal bridge del proiettore.
- [VirtualHere Linux USB Server](https://www.virtualhere.com/usb_server_software) — lato server usato sul Raspberry Pi che ospita fisicamente FLIRC.
- [VirtualHere USB Client](https://www.virtualhere.com/usb_client_software) — lato client usato sul Raspberry bridge per agganciare il FLIRC remoto.
- [Linux USB gadget ConfigFS documentation](https://docs.kernel.org/usb/gadget_configfs.html) — documentazione kernel per gadget USB via ConfigFS.
- [Linux HID gadget testing documentation](https://docs.kernel.org/usb/gadget_hid.html) — documentazione kernel per HID gadget.
- [Android Debug Bridge documentation](https://developer.android.com/tools/adb) — documentazione ufficiale ADB.
- [Logitech Media Server / Lyrion Music Server](https://lyrion.org/) — server usato dall’integrazione opzionale con display LMS/Jivelite.
- [GNU General Public License v3](https://www.gnu.org/licenses/gpl-3.0.en.html) — licenza usata dal progetto.


## Limitazioni note

- Il payload BLE wake può essere specifico per modello/firmware; in questa configurazione il solo BLE non è considerato sufficiente per l’accensione quotidiana affidabile.
- ADB è opzionale e opportunistico: non va usato come base della navigazione normale.
- Google TV Remote richiede pairing valido e certificato/chiave locali.
- La selezione HDMI diretta può cambiare tra firmware diversi.
- USB HID richiede supporto gadget e corretta enumerazione fisica da parte del proiettore.
- La mappatura FLIRC dipende da come è stato programmato il telecomando IR.
- Il feedback LMS/Jivelite è opzionale e dipende dalla porta CLI LMS e dal supporto display del player.
- Un Raspberry Pi Zero usato come bridge lato proiettore normalmente richiede l’inoltro remoto di FLIRC, perché la sua singola porta dati OTG è già usata per il collegamento USB HID gadget al proiettore.

## Licenza

Questo progetto è rilasciato sotto **GNU General Public License v3.0 or later**.

Identificatore SPDX:

```text
GPL-3.0-or-later
```

Vedi [`LICENSE`](LICENSE) per il testo completo della licenza.

## Crediti

Costruito come bridge di controllo proiettore basato su Raspberry Pi usando:

- Linux USB HID gadget mode;
- ricevitore IR FLIRC;
- Android TV Remote v2 tramite `androidtvremote2`;
- `adb-auto-enable` opzionale per persistenza ADB;
- rinforzo di accensione HDMI-CEC;
- Wake-on-LAN opzionale.

Lunga vita e prosperità al telecomando universale.
