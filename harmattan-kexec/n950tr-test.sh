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

echo "== pre-flight: program page 63 of block 80 by hand (devmem), same sequence as the tracer =="
T 'devmem 0x0401E200 16 80; devmem 0x0401E202 16 0; devmem 0x0401E498 16 80; devmem 0x0401E482 16 0; devmem 0x0401E440 16 0x23
   i=0; while [ $i -lt 1000 ]; do v=$(devmem 0x0401E482 16); case $v in 0x8*|0x9*|0xA*|0xB*|0xC*|0xD*|0xE*|0xF*) break;; esac; i=$((i+1)); done
   echo "after UNLOCK: INT=$(devmem 0x0401E482 16) WP_STATUS=$(devmem 0x0401E49C 16) (0x0004 = unlocked)"
   devmem 0x04000400 32 0x4E395452; devmem 0x04000404 32 0x63
   devmem 0x0401E200 16 80; devmem 0x0401E202 16 0; devmem 0x0401E20E 16 252; devmem 0x0401E400 16 0x800; devmem 0x0401E482 16 0; devmem 0x0401E440 16 0x80
   i=0; while [ $i -lt 1000 ]; do v=$(devmem 0x0401E482 16); case $v in 0x8*|0x9*|0xA*|0xB*|0xC*|0xD*|0xE*|0xF*) break;; esac; i=$((i+1)); done
   echo "after PROG: INT=$(devmem 0x0401E482 16) CTRL_STATUS=$(devmem 0x0401E480 16) (bit 10 = error, bit 14 = locked)"
   echo "page 63 now reads:"; dd if=/dev/mtd3 bs=4096 skip=127 count=1 2>/dev/null | head -c 16 | hexdump -C | head -1'
echo "   expected: WP_STATUS 0x0004, CTRL_STATUS without 0x0400, page 63 starting 52 54 39 4e 63 00 00 00"
echo "   anything else means the tracer's OneNAND path does not work from this state - stop and look."

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
