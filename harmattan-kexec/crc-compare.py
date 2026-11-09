#!/usr/bin/env python3
"""Can the stock Harmattan modules load on a freshly built kernel?

With CONFIG_MODVERSIONS=y a module records, for every symbol it imports, the CRC the
kernel it was built against exported for it; the kernel refuses the module if one CRC
differs ("disagrees about version of symbol").  This compares the CRCs the stock
modules expect (modprobe --dump-modversions) with the CRCs the new build exports
(Module.symvers).  Symbols that no module in the set exports and that are absent from
Module.symvers are imports from other modules (omaplfb <- pvrsrvkm, wl12xx_sdio <-
wl12xx, sd_mod <- scsi_mod ...) and are reported separately, not as misses.

  crc-compare.py <Module.symvers> [<stock modules dir>]
"""
import os, subprocess, sys
from collections import defaultdict

symvers = sys.argv[1]
moddir = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser(
    "~/n950/extract/n950-root/lib/modules/2.6.32.54-dfl61-20121301")

kernel = {}
for line in open(symvers):
    parts = line.split()
    if len(parts) >= 3:
        kernel[parts[1]] = int(parts[0], 16)

expect = defaultdict(dict)        # module -> symbol -> crc
for root, _, files in os.walk(moddir):
    for f in files:
        if not f.endswith(".ko"):
            continue
        out = subprocess.run(["modprobe", "--dump-modversions", os.path.join(root, f)],
                             capture_output=True, text=True).stdout
        for l in out.splitlines():
            crc, sym = l.split()
            expect[f[:-3]][sym] = int(crc, 16)

# symbols exported by one of the stock modules themselves (inter-module imports)
exported_by_modules = set()
for mod, syms in expect.items():
    pass
# Module.symvers of the new build lists module exports too (as [drivers/...]) when
# modules were built; anything absent from it and imported by >1 module or named like a
# module API is treated as inter-module when the kernel lacks it entirely.

layout_ok = None
mismatch = defaultdict(list); missing = defaultdict(list); ok = defaultdict(int)
for mod, syms in sorted(expect.items()):
    for sym, crc in syms.items():
        if sym == "module_layout":
            layout_ok = (kernel.get(sym) == crc)
        if sym not in kernel:
            missing[mod].append(sym)
        elif kernel[sym] != crc:
            mismatch[mod].append((sym, crc, kernel[sym]))
        else:
            ok[mod] += 1

print(f"stock modules: {len(expect)}   kernel exports in {symvers}: {len(kernel)}")
ml = expect.get("g_nokia", {}).get("module_layout") or next(
    (s["module_layout"] for s in expect.values() if "module_layout" in s), None)
print(f"module_layout: stock 0x{ml:08x}  build 0x{kernel.get('module_layout', 0):08x}  "
      f"{'MATCH' if layout_ok else 'DIFFERENT -> no stock module loads at all'}")
bad = [m for m in expect if mismatch[m]]
print(f"\nmodules with CRC mismatches: {len(bad)} of {len(expect)}")
for m in sorted(bad):
    print(f"  {m}: {len(mismatch[m])} mismatching ({ok[m]} ok)  e.g. " +
          ", ".join(f"{s} stock 0x{a:08x} build 0x{b:08x}" for s, a, b in mismatch[m][:3]))
print(f"\nmodules importing symbols the kernel does not export (inter-module or truly missing): {len([m for m in missing if missing[m]])}")
for m in sorted(missing):
    if missing[m]:
        print(f"  {m}: {len(missing[m])}  e.g. {', '.join(missing[m][:4])}")
clean = [m for m in expect if not mismatch[m]]
print(f"\nmodules whose kernel-exported symbols all match: {len(clean)} of {len(expect)}")
if layout_ok and not bad:
    print("=> the stock modules on p2 load on this kernel; only /boot needs the new zImage.")
elif layout_ok:
    print("=> partial: the listed modules would be refused; install the build's own modules for them (or all).")
else:
    print("=> install the build's own modules under /lib/modules/<release> (stage dir), the stock ones cannot load.")
