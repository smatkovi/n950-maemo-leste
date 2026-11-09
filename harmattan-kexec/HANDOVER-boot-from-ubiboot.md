# Handover: boot Leste and the openmode MeeGo kernel from ubiboot — for Fable

The N950 runs ubiboot from mtd2 and boots into a menu. The two OSes to chain-load
from it both die after the `kexec`, each for a now-understood reason. This is how
to boot them, what was found, and the one script that drives it:

```
./boot-from-ubiboot.sh check          # is the device reachable, what is deployed
./boot-from-ubiboot.sh leste          # kexec Leste with the watchdog fix, watch USB
./boot-from-ubiboot.sh erase-log      # erase mtd3 before a MeeGo tracer run
./boot-from-ubiboot.sh meego          # deploy + kexec the mmc-fix MeeGo kernel
./boot-from-ubiboot.sh meego-read     # after the reset: read the boot tracer back
```

## Device access (unchanged)

ubiboot maintenance mode = USB plugged in when ubiboot starts. It runs a DHCP
server offering **192.168.2.100** to the PC and listens on **telnet and ssh at
192.168.2.15**. On the PC: `sudo dhclient <usb-iface>`, or set the address by hand
(`sudo ip addr add 192.168.2.16/24 dev <iface>`). telnet needs CRLF line endings —
use `ubiboot-telnet.py "<cmds>" 192.168.2.15`. ubiboot's busybox has
`devmem nc kexec hexdump md5sum setsid` but **no `flash_erase`** (that is why
`tools/mtderase`, a static ARM binary, exists). The kexec is ubiboot's own
`kexec-tools 2.0.3`, the same one MOSLO uses to boot Leste successfully.

## What is deployed now (2026-11-08)

- p2 `/boot/` : `zImage_2.6.32.54-openmode_icachefix` (the real openmode kernel,
  modules match `/lib/modules/2.6.32.54-dfl61-20121301`) and now also
  `zImage_2.6.32.48-n950tr-mmc` once you run `meego`.
- p4 `/boot/` : `zImage -> zImage-6.18.51-ga6675e716fe6` (Leste, patches 0020/0021/0022),
  `cmdline` = `root=/dev/mmcblk1p4 rootwait rw rootfstype=ext4 init=/sbin/init console=tty0`.
- p1 `/boot/` : `ubiboot.conf` (OS2=Harmattan/p2, OS3=Nemo/Leste/p4, G_DEFAULT_OS=OS2),
  `ubiboot-02.menus.cpio`. OS2 slot 3 was added pointing at the tracer kernel.

---

## Leste — the fix is one cmdline token, no rebuild

**Finding (from the earlier session, confirmed against the driver):** ubiboot arms
the **OMAP watchdog** (`/dev/watchdog`) and the **TWL watchdog** and feeds both from
its PID 1. On the kexec to Leste its kicker dies with it. Leste's kernel adopts the
TWL watchdog (patch 0021 → survived 16 s → 54 s), but its `omap_wdt` driver, with
`early_enable=0` (the default), **disables the OMAP watchdog at probe instead of
adopting it** — and the probe runs too late / the disable does not take, so the OMAP
watchdog fires at ~54 s and resets the phone back to ubiboot.

The a6675 kernel's config already has `CONFIG_WATCHDOG_HANDLE_BOOT_ENABLED=y`,
`CONFIG_WATCHDOG_OPEN_TIMEOUT=0` and `omap_wdt` built in. So the fix needs no rebuild:
boot with **`omap_wdt.early_enable=1`**. The driver then re-arms the running watchdog
*and* sets `WDOG_HW_RUNNING`, and the watchdog core feeds it from probe until dsme
opens `/dev/watchdog`.

```
./boot-from-ubiboot.sh leste
```

kexecs Leste with that token appended and watches the USB bus. **Success = a Leste
USB gadget stays up past ~60 s** (it died at 54 s before). If it works, make it
permanent — append the token to `G_OS3_INIT_CMDLINE_APPENDS` in p1 `/boot/ubiboot.conf`
(it already has `vram=6m omapfb.vram=0:6M`), **or** to p4 `/boot/Nemo/boot/cmdline`,
which ubiboot loads verbatim as the OS3 override:

```
ubiboot-telnet.py 'mount /dev/mmcblk0p1 /mnt/1 && sed -i "s/\(G_OS3_INIT_CMDLINE_APPENDS=\"[^\"]*\)/\1 omap_wdt.early_enable=1/" /mnt/1/boot/ubiboot.conf && grep G_OS3_INIT_CMDLINE_APPENDS /mnt/1/boot/ubiboot.conf && umount /mnt/1' 192.168.2.15
```

If it still resets at ~54 s, the fallback is a kernel patch (same shape as 0021):
make `omap_wdt_probe` always adopt a running watchdog (`set_bit(WDOG_HW_RUNNING)`
without needing the param) — add it to `kernel/patches/` and rebuild with
`kernel/build.sh`. But try the cmdline first.

If instead Leste comes up but **hangs with no reset**, it is the eMMC root mount
(the MeeGo problem below) — but Leste already carries that fix (patch 0020), so this
is unlikely.

---

## MeeGo (Harmattan 2.6.32) — it is NOT a kexec death; it is the eMMC root mount

**This overturns the old "dies in <0.8 s before the decompressor" conclusion.** A boot
tracer was built into the Harmattan kernel (see `README.md`): it records every boot
stage in a OneNAND page (mtd3 block 80, survives a reset) and checksums its own image.
It was flashed to p2, kexec'd from ubiboot, and read back. The result:

```
stage 1..24 ALL written, stage 25 and 0 (panic) empty
  stage  2 aux=0x5bb9b242=0x5bb9b242  -> the kexec copy is INTACT (checksum matches)
  stage  6 entry=0x80008000 atags=0x80100000
  stage 23 ret=0                        -> omap3_pm_init succeeded (secure-RAM save OK, HS device)
  stage 24                              -> ran to the end of do_basic_setup
```

So the kernel decompresses, turns the MMU on, runs **every initcall**, brings the
console up, and reaches the end of `do_basic_setup` — then hangs **before `init_post`
execs init, with no panic**. The only thing between stage 24 and stage 25 is
`prepare_namespace()` mounting root (`/dev/mmcblk0p2`). With `rootwait` it waits for
the device for ever = the black screen. The cause is the **same eMMC-after-kexec
timeout Leste fixes with patch 0020**: the outgoing kernel left the eMMC initialised,
its first access (the EXT_CSD read) times out, and the 2.6.32 MMC core scans a
non-removable card only once.

**The fix (patch `patches/0003-mmc-retry-emmc-after-kexec.patch`, already applied and
built):** `mmc_rescan` retries the eMMC attach up to 10 times, 200 ms apart. The kernel
`~/n950/zImage_2.6.32.48-n950tr-mmc` (md5 `70b6cd1b…`) has that fix **and** the tracer.

```
./boot-from-ubiboot.sh erase-log     # clear mtd3 so the tracer writes into erased pages
./boot-from-ubiboot.sh meego         # copies the kernel to p2/boot, kexecs it
# screen black -> wait ~30 s for the watchdog reset or pull the battery ->
# bring the phone back into ubiboot maintenance ->
./boot-from-ubiboot.sh meego-read    # decodes the tracer
```

**If `meego-read` shows stage 25** ("init_post: exec init"), the eMMC fix worked and
MeeGo mounted root and started `/sbin/preinit` — the black-screen problem is solved.
The display should then come up (omapdss/omapfb are built in). **If it still stops at
stage 24**, raise the retry count / add a controller `SOFTRESET` before the first scan
in `drivers/mmc/host/omap_hsmmc.c`, or power-cycle VEMMC (regulator) at the start of
`mmc_rescan`.

### Making MeeGo actually usable (the module-version step)

`zImage_2.6.32.48-n950tr-mmc` is `2.6.32.48-dfl61-n950tr`; p2's modules are
`2.6.32.54-dfl61-20121301`. preinit only `modprobe ubi` (non-fatal — MeeGo root is
ext4 on p2, already mounted by the kernel; the display/touch/keypad drivers are
built in), so the kernel boots the UI, but Wi-Fi/BT/camera modules will not load.
Two ways to a daily-usable MeeGo:

1. **The real openmode .54 kernel + the mmc fix.** The matching kernel is the one
   already on p2 (`zImage_2.6.32.54-openmode_icachefix`), but it is a binary and no
   2.6.32.54 source is on disk — so the fix cannot be rebuilt into it directly.
   Binary-patching its `mmc_rescan` is possible but fiddly.
2. **Build .48 with the drivers MeeGo needs built in** (rm581_defconfig already builds
   most =y) and rename the version to match the modules dir, or accept module-less
   operation for the UI. The vermagic/CRC of the stock .54 modules will not match a
   .48 build, so stock modules cannot be loaded regardless; the clean route is =y.

The milestone that proves the whole black-screen theory is **stage 25 + the MeeGo boot
logo**; the module work is a follow-up.

---

## Files

| File | What |
| --- | --- |
| `boot-from-ubiboot.sh` | the driver described above |
| `ubiboot-telnet.py` | runs commands in ubiboot's telnet shell (CRLF) |
| `tools/mtderase.c` / `tools/mtderase` | static ARM MTD eraser (ubiboot has no flash_erase) |
| `~/n950/zImage_2.6.32.48-n950tr-mmc` | Harmattan kernel: tracer + eMMC-retry fix (md5 70b6cd1b) |
| `patches/0001` | decompressor I-cache/BTB invalidate (the "icachefix", source form) |
| `patches/0002` | the boot tracer |
| `patches/0003` | mmc: retry the non-removable eMMC after a kexec |
| `README.md` | the tracer: stages, OneNAND layout, build |
| kernel tree | `~/ps/harmattan-src/kernel_2.6.32-20115101+0m7/kernel-2.6.32` (git: baseline, tracer, mmc fix) |

Build the MeeGo kernel: `cd harmattan-kexec && NAME=zImage_2.6.32.48-n950tr-mmc ./build-tracer.sh`
(CodeSourcery 2009q3 from the Harmattan SDK; ~3 min on 4 cores).

---

## Update 2026-11-08 ~23:20 — Leste boots from ubiboot; the real cause was the modules

The first test of the `leste` recipe ended in a black screen with no USB gadget and
the phone would not wake. With the phone back in ubiboot maintenance the evidence
was on p4 itself (`leste-evidence.sh` reads it): `/var/log/dmesg` and `syslog` of
that very boot (the command line carries `omap_wdt.early_enable=1`) showed

- the eMMC retry did fire: `mmc1: error -110 whilst initialising MMC card` →
  `retrying the non-removable card (1)` → card found at 5.7 s;
- `Run /sbin/init` at 6.6 s, rsyslog, udev, dbus, cron, oFono … up to ~2 min — far
  past the 54 s at which it used to die;
- **not one line from omapdrm, panel-dsi-cm, musb or the USB PHY**, and
  `Error: inserting the zram kernel module`.

The reason: p4's `/lib/modules` only held `6.18.51-g79375bbc75bf` (the Oct 29
release kernel), while `/boot/zImage` had been switched to `ga6675e716fe6`. All
display and USB drivers are modules (`=m`), so the kernel ran to multi-user blind.

**Fix:** ubiboot maintenance exports the whole eMMC as a USB disk (`/dev/sda`,
`sda4` = p4; check `md5sum` of the first MiB of `/dev/mmcblk0p4` on the phone
against `/dev/sda4` on the PC before touching it). Mount `sda4` on the PC and copy
`~/ps/n950-kernel/stage-6.18.51-ga6675e716fe6/lib/modules/6.18.51-ga6675e716fe6`
into `/lib/modules/`, `chown -R root:root`, `sync`, unmount. Done on 2026-11-08.

**Result:** kexec from the maintenance shell → the gadget `1d6b:0104 "Maemo Leste /
Hildon RNDIS"` appears ~150 s after the kexec (the base image's usb0 wins over
n950-usbnet: `UDC core: n950: couldn't find an available UDC`). Leste answers at
**192.168.42.2** (give the PC 192.168.42.1/24) and on its IPv6 link-local address;
`ssh root@…` with the key (`~/.ssh/known_hosts.n950-leste`). omapdrm, panel-dsi-cm,
musb_hdrc, omap2430, phy-twl4030-usb loaded; `card1-DSI-1` connected and enabled;
Xorg, hildon-desktop, mce, dsme running; 7 min uptime and counting. A black screen
*now* is mce's display blanking (`bl_power=4`), the power button or
`dbus-send … com.nokia.mce.request.req_display_state_on` turns it on.

**On the watchdog story:** two independent problems, two fixes. The blind boot above
already had `omap_wdt.early_enable=1` on its command line (from p4 `/boot/cmdline`,
the file ubiboot uses verbatim for OS3) and ran for about 8 minutes with no reset
(dmesg to 65 s, syslog to ~2 min, the phone was switched off by hand later) — so the
token does cure the ~54 s reset, and the modules cure the blindness. The earlier test
that "made no difference" most likely went through `G_OS3_INIT_CMDLINE_APPENDS`,
which ubiboot ignores whenever the cmdline *file* exists. Keep the token. (One boot
without it would settle the point for good; the reading that 6.18's hwmod code
stops `wd_timer2` early on its own is a hypothesis from the source, not an
observation.) The boot in the logs was started from the ubiboot *menu*, so the
PC-free menu path is validated too, not only the manual kexec.

Also seen in Leste's dmesg after a kexec from ubiboot: `PVR_K:(Error):
BridgedDispatchKM: Initialisation failed. Driver unusable.` (SGX) — a GPU topic,
not a boot blocker.

**MeeGo (OS2 slot 3, `zImage_2.6.32.48-n950tr-mmc`) is still untested.** Given that
Leste's log shows exactly the predicted eMMC timeout-and-retry after the kexec, the
same fix in the 2.6.32 kernel is the right bet. The PR1.3 source for a
module-compatible `2.6.32.54-dfl61-20121301` build is now at
`~/ps/harmattan-src/kernel-pr13/src` (github nemomobile/kernel-adaptation-n950-n9,
branch `mer-n9-2.6.32-20121301`, `rm581_defconfig`).

| File | What |
| --- | --- |
| `leste-evidence.sh` | read-only: ubiboot.log, p4 superblock (note: ubiboot itself mounts p4 rw, so its mount time is useless), p4 `/var/log` |

## Update 2026-11-09 ~07:50 — MeeGo: the mmc fix works, stage 25 reached

Run: device cold-started with USB plugged in → ubiboot maintenance → `erase-log` →
`meego` (kexec of `zImage_2.6.32.48-n950tr-mmc`, md5 70b6cd1b, cmdline from
`/proc/original_cmdline`). The `meego` run itself was interrupted on the PC side, so its
md5/LOAD_OK lines were not seen; what is on record is ubiboot's USB gadget dropping at
07:37:32 and, on the screen (reported by the owner): Nokia logo, then Harmattan's **R&D
screen** with the new kernel's version, a build date of today — which identifies the
kernel as the tracer build — and `bootreason: usb`. That screen is drawn by `/sbin/preinit`
(`show_rd_versions`, `text2screen`) running **from the eMMC root** — so the root mount
that hung every kexec'd 2.6.32 boot so far now succeeds. It stayed on that screen; the
owner restarted with the power key after ~1.5 min (NOLO at 07:39:09, ubiboot back).

Tracer pages read back afterwards (`meego-read`): stages 1–25 all written, 2 = checksum
OK, **25 = init_post / exec init** (new), no error page. Before this run block 80 still
held the 2026-11-08 result (1–24, no 25), so the difference is the mmc retry.

Why it stops at the R&D screen: this kernel is `2.6.32.48-dfl61-n950tr`, p2's modules are
`2.6.32.54-dfl61-20121301` with `CONFIG_MODVERSIONS=y`; PVR (`pvrsrvkm`, `omaplfb`),
`g_nokia`, `wl12xx`, `twl4030_keypad`, `twl4030-pwrbutton` … are modules, so upstart
starts blind: no compositor, no USB gadget, no WLAN. p2's `/var/log` is untouched
(Harmattan has no syslog by default), so there is no userland log of that minute.

Two more facts for the next step:
* `bootreason: usb` — the boot reason is a **cmdline token from NOLO**: ubiboot's
  `/proc/original_cmdline` is NOLO's full line (`... bootreason=pwr_key bootmode=normal
  nolo=2.3.6 product_name=RM-680 imei=... g_nokia.iSerialNumber=... omapdss.def_disp_enabled=1
  ...`), and that is what `meego` passes to the kexec'd kernel. Harmattan's
  `/sbin/getbootstate` (strings) parses `bootreason=` from `/proc/cmdline`: `pwr_key` →
  USER ("User pressed power button"), `charger` → ACT_DEAD ("User attached charger"),
  `sw_rst`/`32wd_to`/`swdg_to` → reset handling; `usb` is not in its table ("Unknown
  bootreason ... passed by nolo"). The morning run had been started by plugging USB in
  (NOLO said `usb`); the later session was started with the power key and carries
  `pwr_key`. So: **start the device with the power key** (USB may be plugged in), and a
  kexec from the maintenance shell is a normal USER boot whose outcome is observable from
  the PC (MeeGo's g_nokia gadget 0421:xxxx on `lsusb`, UI on the screen). Deploy the
  module-compatible kernel as a **new file plus a new ubiboot OS2 entry** (slot 4; leave
  slot 3 and the stock entry alone) so it is also selectable from the menu.
* Next milestone = a module-compatible kernel: `2.6.32.54-dfl61-20121301` built from the
  PR1.3 source (`~/ps/harmattan-src/kernel-pr13/src`) with `rm581_defconfig` as is (the
  CRCs of the exported symbols depend on the config), `CONFIG_LOCALVERSION="-dfl61-20121301"`,
  AUTO off, plus patch 0003 (mmc retry; applies cleanly) and the decompressor I-cache/BTB
  invalidate from the .48 tree. Check offline before flashing anything: `modprobe
  --dump-modversions` of the 91 stock modules (1784 symbol/CRC pairs, incl. `module_layout`)
  against the build's `Module.symvers`. If they match, the stock modules load and nothing
  on p2 needs to change but `/boot`; if not, install the build's own modules next to the
  stock ones.

## Update 2026-11-09 ~08:30 — module-compatible kernel: modules load, Aegis is the next wall

**Built** `zImage_2.6.32.54-dfl61-20121301-mmcfix` (md5 262a04fd, `build-pr13.sh`) from the
nemomobile tree (`~/ps/harmattan-src/kernel-pr13/src`, branch `n950-mmcfix`: host fixes
0005/0007/0008, mmc retry 0003, decompressor cache fix 0004, IOMMU tristate again 0006).
`crc-compare.py`: `module_layout` and all 1784 symbol CRCs of the 91 stock modules match,
0 mismatches — the stock modules load on it. Deployed to p2 `/boot` as ubiboot OS2 slot 4
(`deploy-pr13`; p1 `ubiboot.conf` backup `ubiboot.conf.bak-*`).

**Test** (`meego-pr13`, kexec from the maintenance shell, NOLO cmdline with
`bootreason=pwr_key`): USB timeline on the PC — ubiboot gadget gone 08:05:39; **+12 s:
`0421:03d1 "Nokia N950"`** = Harmattan's `g_nokia` gadget, so userland was up and had
**loaded a stock module**; +16 s: disconnect, NOLO (`0421:0105`), ubiboot back at +57 s.
The new ubiboot session's `/proc/original_cmdline` says **`bootreason=sw_rst`**: a software
reboot, not a watchdog (`32wd_to`) — and no oops/panic text in mtd3.

**Cause, found in the source:** the nemomobile tree has Nokia's **Aegis security framework
removed** (`security/aegis/`, `include/linux/aegis/`, `CONFIG_SECURITY_AEGIS{,_VALIDATOR,
_RESTOK,_CREDS,_CREDP}` and `SECURITY_DMESG_RESTRICT` gone from `rm581_defconfig`,
`commoncap.c` without `credp_apply`). Harmattan userland is built on it (`aegis-session`,
`aegisfs` — upstart job with `respawn limit 3 300` + `reboot` stanza — libcreds, the
validator). Without the LSM those jobs fail and upstart reboots the device: exactly the
observed sw_rst after ~16 s. The CRC comparison could not see this: Aegis exports no symbol
the 91 modules import.

**Fix path:** build from **Nokia's pristine PR1.3 source**, now at
`~/ps/harmattan-src/dl-nokia-pr13/` (`kernel_2.6.32-20121301+0m8.tar.gz`, md5 32dd66fd, from
the Harmattan SDK sources ISO `maemo.cloud-7.de/HARM/N9/1.3/cdrom.iso`; `.dsc` checksums
match). Full diff to the Nemo tree: 49 files, the big ones are vibra_spi.c, mach-omap2/Makefile,
wait.h, cgroup.c, pa.c, proc-v7.S, tty_io.c, the gadget Kconfig/f_obex, plus the Aegis removal;
Nemo-only additions are FunctionFS and the rm696_nemo defconfigs. Nokia's tree needs only
the perl fix (0005), 0003 and 0004 — no `-mno-unaligned-access`, no `.arch_extension`, IOMMU
is tristate. Same `build-pr13.sh` with `KSRC=.../dl-nokia-pr13/kernel-2.6.32`. The build was
not started: the session's permission classifier blocked running the build in a directory a
helper had downloaded; the owner has to allow it or run it.

**Side effect to know:** after Harmattan's software reset the eMMC stays in a state ubiboot's
stock 2.6.32 mmc core cannot initialise (`mmc0: error -110 whilst initialising MMC card`), so
ubiboot comes up **without its config** (defaults: IP 192.168.0.15, DHCP offers
192.168.0.100, no partition export, nothing bootable; on the screen it says "boot menu
script not found"). A cold start (power off, power key) clears it. Ubiboot's own kernel would want patch 0003 too.

## Update 2026-11-09 ~08:25 — MeeGo boots from ubiboot with the kernel built from Nokia's PR1.3 source

**Confirmation of the Aegis diagnosis:** after the cold start, p2 `/var/lib/upstart/
jobs_unrecoverable` (written during the slot-4 test boot) reads `dbus: 1`. Harmattan's
`dbus.conf` has `respawn limit 0 0` + `reboot` and runs under `aegis-session`; without the
Aegis LSM the job cannot start, Upstart marks it unrecoverable and reboots → the sw_rst.

**Built from Nokia's tree** (`prep-nokia-tree.sh`: git baseline of
`kernel_2.6.32-20121301+0m8`, branch `n950-mmcfix` = perl host fix + 0003 + 0004, then
`build-pr13.sh`): `zImage_2.6.32.54-dfl61-20121301-mmcfix-nokia`, 2781156 bytes, md5
cebaaeea; 100 modules; `crc-compare.py` again 91/91, `module_layout` match. Deployed with
`PR13_SLOT=5 PR13_LABEL="MeeGo PR1.3 Nokia src + mmc fix" ./boot-from-ubiboot.sh deploy-pr13
~/n950/zImage_2.6.32.54-dfl61-20121301-mmcfix-nokia` → p2 `/boot`, ubiboot OS2 slot 5.

**Test** (`meego-pr13 <that file>`, from the maintenance shell of a power-key session,
`bootreason=pwr_key`): ubiboot gadget gone 08:21:44, **`0421:03d1 "Nokia N950"` at
08:22:02 (+18 s) and still there at +3 min** — no sw_rst this time, the stock `g_nokia`
loaded by Harmattan's own userland. WLAN did not answer at 192.168.1.6 in the first
minutes, so the kernel identity on the running system (`uname -r`, `lsmod`, the dmesg
retry line) is still to be read once the owner confirms the UI and the WLAN is up.

So the chain is complete: ubiboot → kexec → 2.6.32.54 with the eMMC retry → root
mounted → stock modules → Harmattan userland. What is left is cosmetic/operational:
* ubiboot `G_DEFAULT_KERNEL` still points at the stock openmode kernel (which hangs at the
  root mount); switching the default to slot 5 is the owner's call (`ubiboot.conf` on p1).
* The slot-4 kernel (Nemo tree, no Aegis) can be deleted from p2 `/boot`; keep slot 3
  (tracer) only if more tracing is wanted.
* ubiboot's own 2.6.32 kernel has the same eMMC weakness after Harmattan's software reset
  (`mmc0: error -110`, config not found, "boot menu script not found"): a cold start
  fixes it; patching ubiboot's kernel with 0003 would fix it for good.

| File | What |
| --- | --- |
| `build-pr13.sh` | builds 2.6.32.54-dfl61-20121301 (zImage + staged modules) from a given tree |
| `prep-nokia-tree.sh` | git baseline + patches for Nokia's pristine PR1.3 source, then build-pr13.sh |
| `crc-compare.py` | stock modules' expected CRCs vs the build's Module.symvers |
| `patches/0004..0008` | decompressor cache fix; IOMMU tristate, unaligned-access flag, sec_hal `.arch_extension` (Nemo tree only); perl host fix |
| `boot-from-ubiboot.sh deploy-pr13 / meego-pr13` | copy a kernel to p2/boot + ubiboot slot (env PR13_SLOT/PR13_LABEL), kexec it and watch USB |

**08:28 — owner confirms: MeeGo booted to the UI** with the slot-5 kernel ("hat gebootet").
Still open on the ubiboot side: `G_DEFAULT_KERNEL` points at the stock openmode kernel,
and `G_OS2_NUM` on p1 was never read back (the local copy says 1, which would hide slots
2–5 in the menu); the menu path for slot 5 is therefore untested. Both are one conf edit
in maintenance mode, pending the owner's OK. The owner then booted Leste from the menu.
