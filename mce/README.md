# mce

Patches on Leste's mce ([maemo-leste/mce](https://github.com/maemo-leste/mce)),
applied with `patch -p1` in its source tree and built as Leste's own package
(`dpkg-buildpackage -b` in a Leste armhf environment).

| Patch | What |
| --- | --- |
| `0001-lock-tklock-the-power-key-wakes-and-unlocks.patch` | optionally a power-key press wakes and unlocks at once instead of showing the lockscreen: `PowerKeyUnlocks=true` in `[PowerKey]` (`rootfs/overlay/etc/mce/mce.ini.d/71-n950-powerkey.ini`, off by default since 0002) |
| `0002-display-never-unblank-to-brightness-1.patch` | the first unblank after boot no longer writes brightness -1 (rejected by the kernel, display stayed dark after the first lock); the brightness is computed again when it is still unset |
| `0003-display-the-brightness-fade-never-steps-by-0.patch` | a brightness fade towards the value the display already has took steps of 0 and rewrote the same brightness every 10 ms for ever (30-50 backlight uevents a second through udev: load 8-23, lagging sounds, a slow lock screen); the step is at least 1 now |
| `0004-mce-dbus-defer-dbus-handlers-list-changes-during-dis.patch` | Leste's own fix (maemo-leste/mce b48b461, in 1.10.19), backported because our build comes from the older 1.10.17 branch: without it mce crashed (SIGSEGV) at every boot and several times an hour, 92 times in a few days. A NameOwnerChanged owner monitor removed its own handler while msg_handler() walked the handler list, and the walk stepped into the freed node (three cores: mce-dbus.c:425/426 right after inactivity-inhibit.c:111). Installed on the phone 2026-11-15 as /usr/bin/mce only (same tree as 1.10.19+5m9, plus this patch) |

Leste on the N950 loads the Maemo module set (`10-maemo.ini`:
`rtconf-gconf`, `lock-tklock`, `power-dsme`, ...), not the generic one in
`mce.ini`, so tklock and power-key changes belong in `lock-tklock.c`.
