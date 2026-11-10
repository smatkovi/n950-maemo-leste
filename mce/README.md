# mce

Patches on Leste's mce ([maemo-leste/mce](https://github.com/maemo-leste/mce)),
applied with `patch -p1` in its source tree and built as Leste's own package
(`dpkg-buildpackage -b` in a Leste armhf environment).

| Patch | What |
| --- | --- |
| `0001-lock-tklock-the-power-key-wakes-and-unlocks.patch` | a power-key press wakes and unlocks at once instead of only showing the lockscreen; `PowerKeyUnlocks` in `[PowerKey]` (`rootfs/overlay/etc/mce/mce.ini.d/71-n950-powerkey.ini`) |
| `0002-display-never-unblank-to-brightness-1.patch` | the first unblank after boot no longer writes brightness -1 (rejected by the kernel, display stayed dark after the first lock); the brightness is computed again when it is still unset |

Leste on the N950 loads the Maemo module set (`10-maemo.ini`:
`rtconf-gconf`, `lock-tklock`, `power-dsme`, ...), not the generic one in
`mce.ini`, so tklock and power-key changes belong in `lock-tklock.c`.
