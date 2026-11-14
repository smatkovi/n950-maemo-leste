# Maemo Leste on the Nokia N950

Maemo Leste (Devuan-based continuation of Maemo 5) dual-booted next to
MeeGo Harmattan on the Nokia N950 (RM-680, OMAP3630): what mainline Linux and
Leste lack for this phone, as patches on Leste's own kernel, and how to build
and boot it.

**Status: everything here builds, nothing is tested on the phone yet.**

## What is here

| Path | What |
| --- | --- |
| `kernel/patches/` | patches on Leste's kernel (`leste-upstream-forks/droid4-linux`, branch `leste/maemo-6.18.y`, Linux 6.18) |
| `kernel/config/n950.config` | config fragment on top of Leste's `linux-image-omap` configuration |
| `kernel/build.sh` | fetches the tree, applies the patches, builds zImage, the N950 device tree and modules |
| `rootfs/build.sh` | Leste's root file system for partition 4: Leste's N900 image (same SoC family) with the N900 packages swapped for `hildon-meta-n950`, this kernel, `rootfs/overlay` (USB network, Wi-Fi/Bluetooth files from Harmattan, X for the command-mode panel) |
| `install/n950-install.sh` | from a PC, on the eMMC as ubiboot exports it: shrinks MyDocs, adds partition 4 with Leste, makes Harmattan's /home if missing, adds Leste to `ubiboot.conf` |
| `docs/install.md` | the layout, what ubiboot needs, the steps |
| `docs/boot-moslo.md` | **what boots today:** MOSLO from RAM, then Leste by kexec (2026-11-02), and what is still open |
| `gps/` | GPS through Harmattan's `nped` and `positioningd` in a chroot, bridged to gpsd (`harmattan-gps`, `positioningd-gpsd.py`) |
| `sgx/build-deb.sh` | the GPU's user space as `sgx-ddk-um-n950`: TI's DDK 1.17.4948957 for the AM335x (the same SGX530 revision 1.2.5) in place of the GPU libraries of Leste's `sgx-ddk-um-ti343x`, Leste's own `libdbm` kept (release `sgx-ddk-um-n950-1.17.4948957-n950.1`) |
| `harmattan-kexec/` | why Harmattan 2.6.32 dies after a kexec: a boot tracer for the Harmattan kernel (OneNAND + RAM markers, image self-checksum), build and test scripts |
| `apps/n950-fm/` | FM radio for Hildon (the Pro1X's `pro1x-fm` for the N950's receiver), `n950-fm-audio` for its sound, `n950-fm-test` for a shell; `apps/build-deb.sh` builds it as an armhf .deb in a chroot of a Leste image |
| `mce/patches/` | patches on Leste's mce (`maemo-leste/mce`): the power key wakes and unlocks in one press, see [mce/README.md](mce/README.md) |

## Status

| Part | State |
| --- | --- |
| eMMC | open: after a reboot from Leste, ubiboot often finds no eMMC until a second reset (the core puts the Hynix eMMC to sleep and switches VEMMC off at shutdown). Keeping VEMMC always on is no fix: Leste itself then no longer found the eMMC after ubiboot's kexec (no power cycle at probe) |
| Display | OMAP DSI FIFO thresholds for the manually updated panel (`0001`), the 854 visible lines of the Himalaya panel (`0003`), the first frame of a command-mode panel on OMAP3 (`0023`), landscape turned by the panel itself as on Harmattan (`0024`, `0025`) |
| Touchscreen, LEDs, sensors, fuel gauge | device tree for the maXTouch, LP5523 (channels 0-5 the keyboard light, 8 the white LED, as Harmattan's mce drives them), LIS302DL accelerometer, AK8974 compass, bq27521; OneNAND: boot loader, config, log and moslo read-only so they are never writable from Leste (`0004`); kernel and var writable |
| Proximity and light | BH1770GLC/SFH7770 device tree support and node (`0005`, `0006`) |
| Audio | TLV320DAC33 device tree support, a machine driver for TWL5031 + TLV320DAC33 + TPA6140A2 on one card, device tree nodes (`0007` to `0011`). Headphone plug detection on TWL5031 GPIO 0 as in Nokia's board file (`0015`), since `0041` a jack of the card (`Headphone Jack` control + `SW_HEADPHONE_INSERT`). An ALSA UCM profile (`rootfs/overlay/usr/share/alsa/ucm2`, after Harmattan's PulseAudio paths) gives PipeWire the loudspeaker (TWL5031 DAC2 -> right predriver -> amplifier) and the headphones (DAC33 -> TPA6140A2) with the jack; both outputs tested by ear 2026-11-10; the default output follows the jack (WirePlumber rule ranking the headphones first), the volume is PipeWire's software volume, and the side keys work: their X keysyms (XF86AudioLower/RaiseVolume, missing from Nokia's layout) are added in `26n950-keyboard`, and the volume applet's N900 landscape swap is off (`sinks.ini`). Headsets and their button (`0046`): the TWL5031's ACI block, which has no mainline driver, tells a headset from headphones on a plug and reports the button as `KEY_PLAYPAUSE` (SND_JACK_BTN_0), after Nokia's twl5031-aci.c; not yet tested on the phone. |
| GPS (BCM4751) | driver with Nokia's interface, binding lines for wakeup and HOST_REQ, device tree node (`0012` to `0014`); see below |
| Keyboard | Nokia's own layouts (`nokia_vndr/rm-680` from Harmattan's xkeyboard-config, whose key codes match the device tree's keymap), compiled at session start in Leste's layout (`rootfs/overlay`); the slide switch active high (`0027`); the keyboard light through Leste's mce (`70-n950.ini`) |
| FM radio (WL1273) | `radio-wl1273` back from v6.17 with device tree support, the N950's node: I2C3 0x22, interrupt GPIO 43, reset GPIO 179 (`0016` to `0019`); `/dev/radio0`; `0042` makes it work with the current V4L2 core (probe, open, seek, volume). Tuning, signal, stereo and RDS work. The sound comes over the chip's I2S port: `0043`-`0045` bring back the WL1273 ASoC codec and add the card "N950 FM" on McBSP4 (gpmc_ncs4-7 pads). The chip drives that port only after a Bluetooth vendor command (HCI 0xfc00, `f3 88 01 02`, as FM apps under Harmattan send it); `n950-fm-bt` sends it, `n950-fm-audio` then plays the card through a PulseAudio loopback. The analog route of Nokia's audio configuration 4 (TWL5031 AUXL/AUXR) carries silence. The receiver's firmware patch comes from Harmattan at first boot |
| GPU (SGX530 1.2.5) | `pvrsrvkm_omap3630_sgx530_125` with TI's ti335x user space (`sgx/`): GLES2 for hildon-desktop through Mesa's pvr driver, PVR2D for X (tested 2026-11-03); clocked at CORE/2 (195.2 MHz, the rate an N9 under Harmattan reads back), not the reset default CORE/3 (130 MHz) (`0053`); powered down after 100 ms of idleness instead of 2 ms (`0055`, no measurable difference in frames while scrolling) |
| Wi-Fi (WL1271) | over SPI; wl12xx binds the device wlcore_spi creates (`0026`), the calibrated NVS from Harmattan where wlcore reads it (`n950-firmware`); that NVS has no MAC address, so `n950-wlan-mac` sets a stable, locally administered one derived from the eMMC's CID, and the interface is always wlan0, the only one icd2 manages (`10-n950-wlan.rules`, the persistent-net generator masked) |
| Charger (bq24153a) | the TWL5031's charge control switch to the bq24153a (`0029` to `0031`), the charge voltage per battery and by BSI (`0034` to `0036`, `n950-battery`), the BCC charger watchdog kicked every 5 s and the bq24153's LOW_CHG cleared (`0037`, `0038`, found by tracing bme's i2c traffic on an N9); without the kick the BCC disabled the charger through its CD pin within seconds, which is what stopped charging before. Charging works on its own since (+255 mA at 500 mA input). A pulled cable the USB PHY does not report (its USB_EVENT_NONE went missing once, the charger stayed "online" for hours) is noticed by the kick itself: no VBUS in two kicks in a row is a disconnect (`0056`). A 3.8 V battery (BV-4D) still stops at 4.20 V: the bq24153 clamps to its safety limit register, which locks after the first write to any other register, and on the N950 it is already locked in ubiboot's maintenance shell right after a power-on reset, so NOLO writes the chip first (the SoC is HS, NOLO cannot be changed). Harmattan's bme stops at 4.20 V too. `0039` writes the limit first anyway, for boards where that works |
| Battery level (bq27521) | the gauge gives voltage, current and temperature but no state of charge (Harmattan's bme computed it), so upower showed 0 % and Leste "battery low"; `0040` estimates it from the open circuit voltage (voltage minus current times `bq27xxx_battery.ocv_resistance_mohm`, 200 by default) through a 4.20 V Li-ion table in the device tree, smoothed and seeded from the first plausible reading; 100 % = what the phone charges to. Capacity level low/critical (which Leste's mce on the N950 treats as empty and powers off) only while discharging, at 5/2 %. Works (upower shows the level); the tuned version is deployed, test pending |
| CPU | 1 GHz and 1.1 GHz as turbo OPPs (`0032`, `0033`; 1.1 GHz is DPLL1's ceiling, a 1.2 GHz request runs at 1.1 GHz), kept on by `n950-boost` (one run at a time, back to `/etc/n950-governor`, default ondemand), throttled by the bandgap thermal zone. As under Harmattan: swappiness 80 (`sysctl.d/60-n950.conf`) and 512 KiB read-ahead on the eMMC (`60-n950-readahead.rules`) |
| Modem (CMT) | nokia-modem, ssi_protocol, cmt_speech and phonet load at boot; ofono's n900 plugin boots the modem through `/dev/cmt/<line>/value`, which `98-n950-cmt.rules` points at the GPIOs nokia-modem exports; `50-n950-net` restarts ofono and icd2 once the late devices exist. The modem answers (Nokia NoRM6, firmware V 92_11w51_3), but ofono still drops it shortly afterwards and sees no SIM, while the same SIM works under Harmattan |
| Power key | Leste's mce only shows the lockscreen; with `mce/patches/0001` a press wakes and unlocks at once (`71-n950-powerkey.ini`); tested with injected key events, the physical button still to be confirmed |
| Swap | zram from Leste's zram-tools (512 MB, priority 100; `40-n950-swap` sets up 256 MB only where zram-tools is missing), as Harmattan's `enable-swap.conf` does on phones with 1 GB, and behind it flash swap on OneNAND's var (`45-n950-flashswap`, priority 10): mtdswap with dm-crypt and a random key per boot, as Harmattan does it below 1 GB. OneNAND under Leste: NOLO leaves the chip in synchronous write mode while the GPMC is reset, so the driver clears that mode under NOLO's CS0 configuration (`0048` to `0050`). This 4 KiB-page OneNAND cannot program a page's OOB and its data separately (the chip's ECC covers both), so mtdswap runs markerless like Nokia's (`0051`); mainline mtdswap's OOB markers had every var block marked bad, and `0052` (onenand `scrub_first`/`scrub_last`) let them be erased again. Tested 2026-11-11: 980 MB filled with zram off, about 400 MB of it through the flash at about 1.6 MB/s, every byte verified. `90-drop-caches` drops the page cache once, 5 minutes after boot |

GPS: the BCM4751's protocol is proprietary and has no free implementation.
The `bcm4751-gps` driver offers Nokia's own interface (`/dev/bcm4751-gps`
for raw I2C transfers, `enable`, `wakeup` and `hostreq` in the I2C device's
sysfs directory `3-a1fa`), so that Harmattan's GPS stack from the MeeGo
partition might be run under Leste. Without it the chip can be powered,
but nothing turns its data into positions. Whether Harmattan's stack runs
this way is open until it is tried on the phone.

What Harmattan's `nped` (the positioning engine, it computes the fixes
itself) needs from Leste, from reading its binary:

- the sysfs files of Nokia's driver at `3-01fa`, its old name for the
  device; under 6.18 it is `3-a1fa`, so `nped` needs that path changed in
  a local copy. It opens all three files read-write, `hostreq` included,
  which the driver allows for that reason.
- a phonet interface `phonet0` (it binds a phonet socket for the modem's
  assistance and stops without one).
- Harmattan's own libraries throughout (its loader and eglibc 2.10), so
  it runs in a chroot of Harmattan's partition.

It hands out positions over its socket `/var/run/nped/nped.socket` to
Harmattan's `positioningd`; its D-Bus name only serves network-initiated
SUPL. So the bridge to gpsd talks to `positioningd` instead, whose client
interface is open (Harmattan's QtMobility Location): `gps/`, see
[gps/README.md](gps/README.md).

Booting: ubiboot with Leste on its own partition (p4, 4 GiB, taken from
MyDocs) next to Harmattan, see [docs/install.md](docs/install.md). The file
systems ubiboot reads get exactly the ext4 features of Harmattan's own root
partition, since ubiboot's 2.6.32 kernel mounts nothing newer. For a first test,
a tethered boot into RAM (`flasher -k`, nothing flashed) needs no
partition at all.

Firmware and calibration data from Harmattan (WLAN NVS, Bluetooth
`ti1273.bin`, touchscreen configuration) are never part of this repository.

## Diagnostic kernel

    DIAG=1 WORK=$HOME/n950-kernel bash kernel/build.sh

builds a variant of the same kernel (version `-diag`) whose boot can be
watched before any root file system is mounted: `kernel/config/diag.config`
on top of `n950.config`, output in `$WORK/out-diag`, the release build left
alone. Built in: omapdrm with DSI, the panel (`panel-dsi-cm`) and fbcon
(landscape, `fbcon=rotate:3`); musb with the TWL4030 PHY and the serial
gadget with its console (`console=ttyGS0`, the PC's `/dev/ttyACM*`); a
1 MiB log; `ignore_loglevel panic=0` and the consoles appended to whatever
the boot loader passes (`CONFIG_CMDLINE_EXTEND`). Two patches go only into
this variant (`kernel/patches/diag/`):

- the N950's TWL5031 watchdog cannot be stopped (Harmattan logs "HACK:
  TWL5031 WDT can't be disabled" on every boot of the phone at hand), and
  mainline only writes 0 to it, so the phone resets at most 30 s after the
  boot loader's last kick; the patch has the watchdog core keep it fed;
- the panel's own backlight starts at brightness 0, which leaves the screen
  dark until user space sets one; the patch starts it at full brightness.

Boot it from RAM (nothing is written to the phone), the phone off and the
USB cable in:

    sudo flasher -k $HOME/n950-kernel/out-diag/arch/arm/boot/zImage-dtb -l \
        -b"root=PARTUUID=00048046-04 rootwait rw rootfstype=ext4 init=/sbin/init console=ttyGS0,115200 console=tty0"

and read the log on the PC as soon as the gadget appears, since its console
keeps only 8 KiB until the PC reads (ModemManager must not grab the port):

    until [ -e /dev/serial/by-id/*diag*Gadget_Serial* ]; do sleep 0.2; done
    stty -F /dev/serial/by-id/*diag*Gadget_Serial* raw -echo
    cat /dev/serial/by-id/*diag*Gadget_Serial* | tee n950-diag.log

Its modules are not built, those on p4 do not match it, and the serial
gadget holds the USB controller, so the image's USB network does not come
up. After a panic or a hard hang nothing feeds the watchdog, so the screen
stays for 15 to 30 s before the phone resets: film it.

## License

The kernel patches are GPL-2.0 like the kernel; the scripts are MIT.
