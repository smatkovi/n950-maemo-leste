#!/bin/bash
# One boot-tracer test from ubiboot's maintenance shell (device on USB).
#
#   n950tr-test.sh [zImage] [device ip]
#
# Erases mtd3, uploads the zImage into the device's RAM (/tmp), loads it with
# ubiboot's own command line and kexecs it.  Afterwards wait for the watchdog
# reset (~30 s) or pull the battery, boot to maintenance mode again and run
# n950tr-read.sh.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
K=${1:-$HOME/n950/zImage_2.6.32.48-n950tr1}
DEV=${2:-192.168.2.15}
PORT=9999

T() { python3 "$HERE/ubiboot-telnet.py" "$1" "$DEV"; }

echo "== device =="
T 'uname -r; grep log /proc/mtd; echo "cmdline: $(cat /proc/original_cmdline)"'

echo "== erase mtd3 (log) =="
T 'flash_erase /dev/mtd3 0 8 && echo ERASE_OK'
echo "== trace block before the test (must be all ff) =="
T 'dd if=/dev/mtd3 bs=4096 skip=64 count=32 2>/dev/null | hexdump -C | head -3'

echo "== upload $(basename "$K") to /tmp =="
T "rm -f /tmp/zImage; (setsid nc -l -p $PORT > /tmp/zImage </dev/null 2>/dev/null &) ; echo NC_STARTED"
sleep 1
cat "$K" > "/dev/tcp/$DEV/$PORT"
sleep 2
echo "pc:     $(md5sum < "$K" | cut -c1-32)  $(stat -c%s "$K") bytes"
T 'echo "device: $(md5sum < /tmp/zImage | cut -c1-32)  $(stat -c%s /tmp/zImage) bytes"'

echo "== kexec -l =="
T 'kexec -l --type=zImage --command-line="$(cat /proc/original_cmdline)" /tmp/zImage && echo LOAD_OK'

echo "== kexec -e: the screen goes black now; wait ~30 s for the watchdog reset =="
T '/usr/bin/disable_pm; kexec -e' || true
