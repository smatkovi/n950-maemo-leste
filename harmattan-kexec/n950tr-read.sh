#!/bin/bash
# Read the boot tracer's markers back from ubiboot's maintenance shell.
#
#   n950tr-read.sh [device ip]
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
DEV=${1:-192.168.2.15}

T() { python3 "$HERE/ubiboot-telnet.py" "$1" "$DEV"; }

# RAM first: ubiboot's kernel treats that page as free memory
echo "== RAM record at 0x9F000000 =="
RAM=$(T 'for a in 0 4 8 12 16 20 24 28; do devmem $((0x9F000000+a)); done' | grep -E '^0x[0-9A-Fa-f]+$' || true)
echo "$RAM"

echo "== OneNAND block 80 (mtd3 + 0x40000), first 16 bytes of pages 0..31 =="
PAGES=$(T 'for p in $(seq 0 31); do printf "page %02d: " $p; dd if=/dev/mtd3 bs=4096 skip=$((64+p)) count=1 2>/dev/null | head -c 16 | hexdump -C | head -1; done')
echo "$PAGES" | grep '^page' || true

python3 - "$PAGES" "$RAM" <<'EOF'
import re, sys
NAMES = {
 0: "panic()", 1: "zImage entry", 2: "image checksum OK", 3: "caches on",
 4: "before decompress", 5: "decompressed", 6: "jump to kernel",
 7: "stext", 8: "page tables built", 9: "cpu setup done, MMU next",
 10: "MMU on -> start_kernel", 11: "start_kernel", 12: "before paging_init",
 13: "after paging_init", 14: "after setup_arch", 15: "after mm_init",
 16: "after init_IRQ", 17: "after time_init", 18: "after console_init",
 19: "rest_init", 20: "kernel_init", 21: "before do_basic_setup",
 22: "omap3_pm_init entry", 23: "omap3_pm_init exit", 24: "after do_basic_setup",
 25: "init_post: exec init (kernel booted)", 26: "decompressor error()",
 27: "die() oops", 28: "__error_p", 29: "__error_a", 30: "__error",
 31: "IMAGE CHECKSUM FAILED (kexec copy corrupt)"}
pages, ram = sys.argv[1], sys.argv[2]
found = {}
for m in re.finditer(r"page (\d+): \S+\s+((?:[0-9a-f]{2}\s+){15}[0-9a-f]{2})", pages):
    p = int(m.group(1)); b = bytes.fromhex(re.sub(r"\s", "", m.group(2)))
    w = [int.from_bytes(b[i:i+4], "little") for i in range(0, 16, 4)]
    if w[0] == 0x4E395452:
        found[p] = (w[1], w[2], w[3])
    elif any(x != 0xFFFFFFFF for x in w):
        found[p] = ("?", w[0], w[1])
print()
if not found:
    print("no trace pages written: the tracer kernel never ran its first instruction")
    print("(or mtd3 was not erased / the OneNAND write failed - check the RAM record)")
else:
    for p in sorted(found):
        st, a0, a1 = found[p]
        print("page %2d  stage %-3s aux0=0x%08x aux1=0x%08x  %s" % (p, st, a0, a1, NAMES.get(p, "")))
    hi = max(k for k in found if k not in (0, 26, 27, 28, 29, 30, 31))
    print("\nfurthest normal stage: %d (%s)" % (hi, NAMES.get(hi, "")))
    for e in (31, 26, 28, 29, 30, 27, 0):
        if e in found:
            print("ERROR stage %d: %s" % (e, NAMES[e]))
words = [int(x, 16) for x in ram.split()]
print()
if len(words) == 8 and words[0] == 0x4E395452:
    print("RAM record: stages %s last=%d aux0=0x%08x aux1=0x%08x calls=%d"
          % ([i for i in range(32) if words[1] >> i & 1], words[2], words[3], words[4], words[5]))
    ctrl, wp = words[6], words[7]
    print("OneNAND after last PROG: CTRL_STATUS=0x%04x%s  WP_STATUS after UNLOCK=0x%04x (%s)"
          % (ctrl, " ERROR" if ctrl & 0x400 else (" LOCKED" if ctrl & 0x4000 else " ok"), wp,
             "unlocked" if wp & 4 else "locked" if wp & 2 else "lock-tight" if wp & 1 else "?"))
else:
    print("RAM record not intact (DDR did not survive the reset, or no stage ran):", ram.split())
EOF
