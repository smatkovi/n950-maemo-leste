# status-area-applet-battery

A patch on Leste's battery applet
([maemo-leste/status-area-applet-battery](https://github.com/maemo-leste/status-area-applet-battery),
1.5.9, based on commit 0e4fcf0), applied with `git am` or `patch -p1` in its
source tree, and the icons it needs.

| File | What |
| --- | --- |
| `0001-Static-charging-icon-with-a-lightning-bolt-instead-o.patch` | while charging, the charge level with a lightning bolt instead of the animation. The animation reloaded two icons every second for as long as the charger was plugged in (about 5 % CPU on the N950). |
| `icons/{48x48,scalable}/hildon/statusarea_battery_charging{13..100}.png` | the charging icons: Leste's `statusarea_battery_fullNN` with a yellow bolt over the battery body |
| `make-charging-icons.py` | draws those icons from Leste's `fullNN` icons (PIL) |

## Build

The applet is built as Leste's own package (`dpkg-buildpackage -b` in a Leste
armhf environment with its build dependencies). Without access to Leste's
repository, `libhildondesktop1-dev` (2.2.3) and `libprofile-dev` (profiled
1.0.8) can be replaced by their headers, the phone's `libhildondesktop-1.so.0`
and `libprofile.so.0`, and `.pc` files for `libhildondesktop-1` and
`profile` on `PKG_CONFIG_PATH`. Then `autoreconf -fi && ./configure
--prefix=/usr --libdir=/usr/lib/arm-linux-gnueabihf && make` builds
`.libs/status-area-applet-battery.so`.

## Install

- `status-area-applet-battery.so` to `/usr/lib/arm-linux-gnueabihf/hildon-desktop/`
- the icons to `/usr/share/icons/hicolor/{48x48,scalable}/hildon/`, then
  `gtk-update-icon-cache -f /usr/share/icons/hicolor`
- restart `hildon-status-menu` (dsme starts it again)
