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
