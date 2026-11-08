#!/bin/bash
# boot-from-ubiboot.sh - boot Leste or the openmode MeeGo kernel on the N950
# from ubiboot's maintenance shell, and read the Harmattan boot tracer back.
#
# This is the practical driver for the two findings in HANDOVER-boot-from-ubiboot.md:
#   * Leste "did not boot" from ubiboot because p4 carried the modules of the old
#     g79375 kernel while /boot/zImage was ga6675: display, USB and zram are
#     modules, so the kernel ran to multi-user blind.  Installing the matching
#     modules fixed it (2026-11-08).  omap_wdt.early_enable=1 in p4's cmdline is the
#     other, independent fix: that same blind boot carried it and ran ~8 min with no
#     reset, where the earlier boots died at ~54 s.
#   * MeeGo (Harmattan 2.6.32) does NOT die early: the tracer showed it runs to the
#     end of do_basic_setup and then hangs in prepare_namespace waiting for root,
#     because the eMMC times out on its first access after the kexec.  The kernel
#     zImage_2.6.32.48-n950tr-mmc carries the retry fix (patch 0003) plus the tracer.
#
# Device access: ubiboot maintenance (USB plugged in when ubiboot starts) runs a
# DHCP server offering 192.168.2.100 to the PC and listens on telnet/ssh at
# 192.168.2.15.  On the PC: `sudo dhclient <usb-iface>` (or set .16/24 by hand).
# ubiboot's busybox has devmem/nc/kexec/hexdump/md5sum/setsid but NO flash_erase.
#
# Usage:
#   ./boot-from-ubiboot.sh check                 # device reachable? what is deployed?
#   ./boot-from-ubiboot.sh leste                 # kexec Leste with the watchdog fix, watch USB
#   ./boot-from-ubiboot.sh meego                 # deploy + kexec the mmc-fix tracer kernel
#   ./boot-from-ubiboot.sh meego-read            # after the reset: read the tracer pages
#   ./boot-from-ubiboot.sh erase-log             # upload mtderase, erase mtd3 (before a tracer run)
#
# Second argument overrides the device IP (default 192.168.2.15).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
DEV=${2:-192.168.2.15}
T() { python3 "$HERE/ubiboot-telnet.py" "$1" "$DEV"; }
CLEAN() { sed 's/\x1b\[[0-9;]*m//g' | grep -vE '^/ # |__ENDOFCMD__'; }

MEEGO_KERNEL=${MEEGO_KERNEL:-$HOME/n950/zImage_2.6.32.48-n950tr-mmc}
LESTE_CMDLINE_EXTRA="omap_wdt.early_enable=1"

usb_watch() {   # $1 = seconds; prints the N950 USB state, "LESTE" if a non-ubiboot gadget appears
	local n=$1 i id
	for i in $(seq 1 "$n"); do
		id=$(lsusb | grep -oE '(0421|1d6b|0525):[0-9a-f]{4}' | grep -v '0525:a4ab' | head -1)
		if [ -n "$id" ] && [ "$id" != "1d6b:0002" ] && [ "$id" != "1d6b:0003" ]; then
			echo "[$i s] N950 gadget: $id  <- kernel is up and ran its USB gadget"; return 0
		fi
		if lsusb | grep -q '0525:a4ab'; then echo "[$i s] ubiboot back (0525:a4ab) = kexec'd kernel reset"; return 2; fi
		echo "[$i s] USB quiet (kernel running with no gadget yet, or display-only)"
		sleep 1
	done
	echo "no decisive USB change in $n s"; return 1
}

case "${1:-}" in

check)
	ping -c1 -W2 "$DEV" >/dev/null 2>&1 && echo "device $DEV reachable" || { echo "device $DEV NOT reachable - is it in ubiboot maintenance with USB plugged in? did you dhclient?"; exit 1; }
	T 'uname -r; echo "--- tools:"; for t in devmem nc kexec hexdump flash_erase mtderase; do printf "%s=%s " $t "$(which $t 2>/dev/null || echo -)"; done; echo
	   echo "--- p2 MeeGo kernel:"; mkdir -p /mnt/2; mount -o ro /dev/mmcblk0p2 /mnt/2 && ls /mnt/2/boot && ls /mnt/2/lib/modules; umount /mnt/2
	   echo "--- p4 Leste kernel:"; mkdir -p /mnt/4; mount -o ro /dev/mmcblk0p4 /mnt/4 && readlink /mnt/4/boot/zImage && cat /mnt/4/boot/cmdline; umount /mnt/4' | CLEAN
	;;

leste)
	echo "== kexec Leste (a6675, patch 0020/0021/0022) with $LESTE_CMDLINE_EXTRA =="
	echo "   (no reflash, no kernel rebuild - the fix is only the extra cmdline token)"
	# p4's /boot/cmdline (the file ubiboot uses verbatim for OS3) already carries the
	# token since 2026-11-08; append it only if it is missing, so it is not passed twice.
	T "mkdir -p /mnt/4; mount -o ro /dev/mmcblk0p4 /mnt/4 && \
	   CL=\"\$(cat /mnt/4/boot/cmdline)\"; case \"\$CL\" in *$LESTE_CMDLINE_EXTRA*) ;; *) CL=\"\$CL $LESTE_CMDLINE_EXTRA\";; esac; \
	   kexec -l --type=zImage --command-line=\"\$CL\" /mnt/4/boot/zImage && \
	   echo LOAD_OK && umount /mnt/4 2>/dev/null; /usr/bin/disable_pm 2>/dev/null; sync; echo 'firing kexec -e'; kexec -e" | CLEAN
	echo "== watching USB for up to 200 s: Leste's RNDIS gadget (1d6b:0104, 'Maemo Leste') shows up ~150 s after the kexec =="
	usb_watch 200
	echo "Leste answers at 192.168.42.2 (the base image's usb0; give the PC 192.168.42.1/24) or at its"
	echo "IPv6 link-local address (ping -6 ff02::1%<iface>); ssh root with the key, known_hosts.n950-leste."
	echo "No gadget at all = the modules on p4 do not match the kernel (see HANDOVER, 2026-11-08 update)."
	;;

erase-log)
	echo "== upload mtderase and erase mtd3 (block 0..7); ubiboot has no flash_erase =="
	T 'rm -f /tmp/mtderase; (setsid nc -l -p 9998 > /tmp/mtderase </dev/null 2>/dev/null &); echo NC_UP' | CLEAN
	sleep 1; cat "$HERE/tools/mtderase" > "/dev/tcp/$DEV/9998"; sleep 1
	T 'chmod +x /tmp/mtderase && /tmp/mtderase /dev/mtd3 0 8 && echo "--- mtd3 now (must be ff):" && dd if=/dev/mtd3 bs=4096 skip=64 count=1 2>/dev/null | hexdump -C | head -1' | CLEAN
	;;

meego)
	[ -f "$MEEGO_KERNEL" ] || { echo "no $MEEGO_KERNEL - build it: cd $HERE && NAME=$(basename "$MEEGO_KERNEL") ./build-tracer.sh"; exit 1; }
	echo "== copy $(basename "$MEEGO_KERNEL") to p2/boot =="
	T 'rm -f /tmp/zI; (setsid nc -l -p 9999 > /tmp/zI </dev/null 2>/dev/null &); echo NC_UP' | CLEAN
	sleep 1; cat "$MEEGO_KERNEL" > "/dev/tcp/$DEV/9999"; sleep 2
	echo "pc md5:     $(md5sum < "$MEEGO_KERNEL" | cut -c1-32)"
	T "echo \"device md5: \$(md5sum < /tmp/zI | cut -c1-32)\"; mount /dev/mmcblk0p2 /mnt/2 && cp /tmp/zI /mnt/2/boot/$(basename "$MEEGO_KERNEL") && sync && umount /mnt/2 && echo COPIED" | CLEAN
	echo "== kexec it with the Harmattan cmdline (root=/dev/mmcblk0p2) =="
	T 'kexec -l --type=zImage --command-line="$(cat /proc/original_cmdline)" /tmp/zI && echo LOAD_OK; /usr/bin/disable_pm 2>/dev/null; sync; echo "firing kexec -e"; kexec -e' | CLEAN
	echo "== screen goes black. Wait ~30 s for the watchdog reset or pull the battery, bring the"
	echo "   device back into ubiboot maintenance, then run:  $0 meego-read"
	;;

meego-read)
	echo "== Harmattan boot tracer: OneNAND block 80 = mtd3 + 0x40000 =="
	PAGES=$(T 'for p in $(seq 0 31); do printf "page %02d: " $p; dd if=/dev/mtd3 bs=4096 skip=$((64+p)) count=1 2>/dev/null | head -c 16 | hexdump -C | head -1; done' | CLEAN | grep '^page')
	echo "$PAGES"
	python3 - "$PAGES" <<'PY'
import re, sys
NAMES={1:"zImage entry",2:"image checksum OK",3:"caches on",4:"before decompress",5:"decompressed",
6:"jump to kernel",7:"stext",8:"page tables built",9:"cpu setup, MMU next",10:"MMU on->start_kernel",
11:"start_kernel",12:"before paging_init",13:"after paging_init",14:"after setup_arch",15:"after mm_init",
16:"after init_IRQ",17:"after time_init",18:"after console_init",19:"rest_init",20:"kernel_init",
21:"before do_basic_setup",22:"omap3_pm_init entry",23:"omap3_pm_init exit",24:"after do_basic_setup",
25:"init_post: exec init = KERNEL BOOTED, ROOT MOUNTED",26:"decompressor error()",27:"die() oops",
28:"__error_p",29:"__error_a",30:"__error",0:"panic()",31:"IMAGE CHECKSUM FAILED (kexec copy corrupt)"}
found={}
for m in re.finditer(r"page (\d+): \S+\s+((?:[0-9a-f]{2}\s+){15}[0-9a-f]{2})", sys.argv[1]):
    p=int(m.group(1)); b=bytes.fromhex(re.sub(r"\s","",m.group(2)))
    w=[int.from_bytes(b[i:i+4],"little") for i in range(0,16,4)]
    if w[0]==0x4E395452: found[p]=(w[1],w[2],w[3])
for p in sorted(found):
    st,a0,a1=found[p]; print(f"  stage {st:<2} aux0=0x{a0:08x} aux1=0x{a1:08x}  {NAMES.get(p,'')}")
norm=[k for k in found if k not in (0,26,27,28,29,30,31)]
if norm:
    hi=max(norm); print(f"\nfurthest normal stage: {hi} ({NAMES.get(hi,'')})")
    if 25 in found: print("=> MeeGo mounted root and started init. The mmc fix works.")
    elif 24 in found: print("=> still hangs after do_basic_setup at the root mount (stage 24, no 25).")
    else: print(f"=> died at stage {hi}; see the table.")
for e in (31,26,27,28,29,30,0):
    if e in found: print(f"ERROR stage {e}: {NAMES[e]}")
PY
	;;

*)
	sed -n '2,36p' "$0"; exit 1 ;;
esac
