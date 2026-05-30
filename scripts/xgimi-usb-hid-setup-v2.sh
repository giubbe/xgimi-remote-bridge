#!/usr/bin/env bash
set -euo pipefail

G="/sys/kernel/config/usb_gadget/xgimi_hid"

modprobe libcomposite
mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config

# Sgancio e pulizia vecchio gadget
if [[ -d "$G" ]]; then
  echo "" > "$G/UDC" 2>/dev/null || true
  find "$G/configs" -type l -delete 2>/dev/null || true
  find "$G/functions" -maxdepth 1 -type d -name 'hid.*' -exec rmdir {} \; 2>/dev/null || true
  find "$G/configs" -depth -type d -exec rmdir {} \; 2>/dev/null || true
  find "$G/strings" -depth -type d -exec rmdir {} \; 2>/dev/null || true
  rmdir "$G" 2>/dev/null || true
fi

mkdir -p "$G"
cd "$G"

echo 0x1d6b > idVendor
echo 0x0104 > idProduct
echo 0x0100 > bcdDevice
echo 0x0200 > bcdUSB

mkdir -p strings/0x409
echo "xgimi-hid-001" > strings/0x409/serialnumber
echo "${USB_GADGET_MANUFACTURER:-XGIMI Remote Bridge}" > strings/0x409/manufacturer
echo "${USB_GADGET_PRODUCT:-XGIMI USB HID Bridge}" > strings/0x409/product

mkdir -p configs/c.1/strings/0x409
echo "HID Keyboard + Consumer Control" > configs/c.1/strings/0x409/configuration
echo 250 > configs/c.1/MaxPower

# === HID 0: tastiera standard ===
mkdir -p functions/hid.usb0
echo 1 > functions/hid.usb0/protocol
echo 1 > functions/hid.usb0/subclass
echo 8 > functions/hid.usb0/report_length

printf '\x05\x01\x09\x06\xa1\x01\x05\x07\x19\xe0\x29\xe7\x15\x00\x25\x01\x75\x01\x95\x08\x81\x02\x95\x01\x75\x08\x81\x01\x95\x05\x75\x01\x05\x08\x19\x01\x29\x05\x91\x02\x95\x01\x75\x03\x91\x01\x95\x06\x75\x08\x15\x00\x25\x65\x05\x07\x19\x00\x29\x65\x81\x00\xc0' > functions/hid.usb0/report_desc

# === HID 1: consumer control ===
mkdir -p functions/hid.usb1
echo 0 > functions/hid.usb1/protocol
echo 0 > functions/hid.usb1/subclass
echo 2 > functions/hid.usb1/report_length

# Consumer Control, 16-bit usage code
printf '\x05\x0c\x09\x01\xa1\x01\x15\x00\x26\xff\x03\x19\x00\x2a\xff\x03\x75\x10\x95\x01\x81\x00\xc0' > functions/hid.usb1/report_desc

ln -s functions/hid.usb0 configs/c.1/
ln -s functions/hid.usb1 configs/c.1/

UDC="$(ls /sys/class/udc | head -n 1)"
echo "$UDC" > UDC

echo "USB HID v2 attivo:"
echo "  /dev/hidg0 = keyboard"
echo "  /dev/hidg1 = consumer control"
echo "  UDC=$UDC"
