# ubiboot additions for the N950

ubiboot (0.3.9) sources `MyDocs/boot/ubiboot.conf` as a shell script from
its preinit, after mounting the eMMC partitions and before any menu, so
the end of that file is a hook that runs a few seconds after power-on.
`ubiboot.conf.n950-append` is appended to it:

- `usb_is_plugged()` overrides preinit's function so that a wall charger
  (`/sys/class/power_supply/usb/type` = `USB_DCP`) does not count as a cable:
  inserting the battery with a charger plugged in then boots the default OS
  instead of maintenance mode (which exported the partitions to nobody).
  A PC (USB, USB_CDP) still gets maintenance mode.
- The bq24153 charger's safety limit register (6) can only be written until
  some other register has been written since its power-on reset, and its
  VMREG field caps the charge voltage (4.20 V after reset). The hook writes
  4.34 V (0x47) for a 3.8 V battery (BV-4D) as early as ubiboot can, and logs
  what it found to `MyDocs/boot/ubiboot.log` ("n950 bq24153 ..."). The kernel
  still sets the charge voltage itself by the battery's BSI (4.20 V for a
  3.7 V BL-4D), below that ceiling. In the maintenance shell 50 s after a
  power-on reset the register was already locked, which points at NOLO; the
  hook tells whether it is writable earlier.

`i2crw` is a static ARM build of `i2crw.c` (CodeSourcery 2009q3 with the
Harmattan sysroot, `-static`), placed next to `ubiboot.conf` in
`MyDocs/boot/`. `bqtest.sh` reads the charger's registers and tries the
safety limit write by hand from the maintenance shell.

Make a copy of `ubiboot.conf` first and check the result with `sh -n`: a
syntax error in it stops ubiboot (recovery with the flasher).

## Charging an empty battery from ubiboot

The maintained version of this is its own repository,
[n950-battery-rescue](https://github.com/smatkovi/n950-battery-rescue): it
adds temperature, overvoltage and gauge-failure cut-offs, `--stop`,
`--replace` and a prebuilt `i2crw`. The scripts here are the first version.

ubiboot's kernel has no bq24153 or BCC driver and nothing kicks the TWL5031
BCC watchdog, so in maintenance mode on a PC port the charger sits idle (CD
pin raised, LOW_CHG cap) and the phone runs on the battery: measured 3.06 V
at -335 mA, and the phone browned out after 2:40 min. A battery that is that
empty never gets to an OS that charges.

`charge-loop.sh` does in the maintenance shell what the Leste kernel does
(patches 0037/0038): every 5 s it kicks the BCC watchdog (0xAA bit 1 on
i2c-1 0x4a), resets the bq24153 timer and sets 500 mA input, 4.20 V,
Leste's charge current and LOW_CHG off, then logs voltage and current from
the bq27521 gauge (i2c-2 0x55) to `/tmp/chg.log`. Stop it with
`touch /tmp/chg.stop`. Nothing is written persistently; the chip resets on
the next power-on.

`ubicharge.py DIR` runs on the PC and waits for ubiboot's telnet at
192.168.2.15. As soon as it answers, it pushes `DIR/i2crw` and `DIR/chg.sh`
over netcat and starts the loop, all within about 1.5 s, before the
battery collapses. It then logs a reading every 20 s to `DIR/ubicharge.log`.
For use: build `i2crw` statically (for example
`zig cc -target arm-linux-musleabi -mcpu=cortex_a8 -static -Os`), copy
`charge-loop.sh` to `DIR/chg.sh`, start the script, then insert the battery
with the PC cable plugged in. First run (2026-11-26): charging started 13 s
after boot at +291 mA, and the voltage rose from 3.09 V.

The flasher route does not help here. flasher 3.12.1 always waits for
charging when it flashes through the ape-algo: it polls the level once a
second, waits at 10 % or below and flashes from 11 %. The `-Owait-charging`
option it mentions does not exist. `../tools/flasher-charge-guard.py`
wraps that flash (with the ubiboot kernel already in mtd2 as the only image)
and sends SIGINT one percent before the threshold. On this battery the
ape-algo reported 0 % for 3.5 min and then lost the connection to the
device; why is not known.
