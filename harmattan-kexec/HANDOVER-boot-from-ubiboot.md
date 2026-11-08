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

**On the watchdog story:** `omap_wdt.early_enable=1` stays in p4 `/boot/cmdline`
(the file ubiboot uses verbatim for OS3), but whether it is needed is **untested**:
reading the 6.18 tree, hwmod resets and stops `wd_timer2` at `postcore_initcall`
(`omap2_wd_timer_reset` → `omap2_wd_timer_disable`) long before `omap_wdt` probes,
and the earlier "~54 s reset" tests all ran without matching modules too. Try a boot
without the token when convenient; if it still boots, drop it.

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
