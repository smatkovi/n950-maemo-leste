#!/bin/bash
# leste-evidence.sh - after a failed Leste boot from ubiboot: what did the
# kexec'd kernel get done?  Run from ubiboot maintenance (device at $1,
# default 192.168.2.15).  Reads, never writes:
#   * ubiboot's own log (p1 /boot/ubiboot.log): did kexec_load succeed?
#   * p4's ext4 superblock: last mount / last write time and mount count tell
#     whether the Leste kernel mounted its root read-write at all
#   * p4 /var/log: anything init or syslog wrote
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
DEV=${1:-192.168.2.15}
T() { python3 "$HERE/ubiboot-telnet.py" "$1" "$DEV" | sed 's/\x1b\[[0-9;]*m//g' | grep -vE '^/ # |__ENDOFCMD__'; }

echo "== device clock (ubiboot has no RTC sync; compare relative) =="; T 'date; cat /proc/uptime'
echo "== ubiboot.log, last 40 lines =="
T 'mkdir -p /mnt/1; mount -o ro /dev/mmcblk0p1 /mnt/1 && tail -n 40 /mnt/1/boot/ubiboot.log; umount /mnt/1'
echo "== p4 ext4 superblock =="
SB=$(T 'dd if=/dev/mmcblk0p4 bs=1024 skip=1 count=1 2>/dev/null | hexdump -v -e "16/1 \"%02x\" \"\n\""' | grep -E '^[0-9a-f]{32}$' | tr -d '\n')
python3 - "$SB" <<'PY'
import sys, struct, datetime
sb = bytes.fromhex(sys.argv[1])
if len(sb) < 1024: print("superblock read failed", len(sb)); sys.exit(0)
magic = struct.unpack_from("<H", sb, 0x38)[0]
mtime, wtime, mnt_count = struct.unpack_from("<IIH", sb, 0x2C)
lastchk = struct.unpack_from("<I", sb, 0x40)[0]
last_mounted = sb[0x88:0x88+64].split(b"\0")[0].decode(errors="replace")
state = struct.unpack_from("<H", sb, 0x3A)[0]
f = lambda t: datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC") if t else "never"
print(f"magic 0x{magic:04x}  state 0x{state:x} (1=clean, 2=errors)  mount count {mnt_count}")
print(f"last mount  {f(mtime)}   (updated only by a read-write mount)")
print(f"last write  {f(wtime)}")
print(f"last fsck   {f(lastchk)}")
print(f"last mounted on '{last_mounted}'  ('/' = Leste mounted it as root)")
PY
echo "== p4 /var/log (newest first) and the tail of what is there =="
T 'mkdir -p /mnt/4; mount -o ro /dev/mmcblk0p4 /mnt/4 && ls -lat /mnt/4/var/log | head -15 && for f in syslog messages kern.log dmesg boot daemon.log; do [ -s /mnt/4/var/log/$f ] && { echo "--- $f (tail)"; tail -n 25 /mnt/4/var/log/$f; }; done; ls -la /mnt/4/var/log/journal 2>/dev/null; umount /mnt/4'
