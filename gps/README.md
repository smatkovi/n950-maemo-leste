# GPS (BCM4751) through Harmattan's positioning stack

The BCM4751's protocol is Broadcom's and has no free implementation, so
Leste uses the N950's own Harmattan software for it, unchanged, from the
Harmattan partition: `nped` (Nokia's positioning engine with Broadcom's,
which computes the fixes) and `positioningd` (which hands them to
applications). Nothing of Nokia's is in this repository or the image.

```
 BCM4751 --i2c-- bcm4751-gps (patch 0013: /dev/bcm4751-gps, 3-a1fa/{enable,hostreq,wakeup})
                   |
          chroot of Harmattan's p2:  nped  <-- socket -->  positioningd
                                                            | session bus (in the chroot)
          Leste:  positioningd-gpsd.py  (a QtLocation-like client)
                   | NMEA on a pseudo terminal
                  gpsd  -->  Leste's location framework, any gpsd client
```

- `harmattan-gps start|stop` (installed to `/usr/sbin`): mounts Harmattan's
  partition read only, gives the chroot `/var`, `/tmp` and `/home` in
  memory and Leste's system bus, binds a copy of `nped` with its three
  sysfs paths changed from `3-01fa` (Harmattan's 2.6.32 name of the GPS's
  I2C device) to `3-a1fa` (Linux 6.18's) over the original, starts a
  session bus for `positioningd` (D-Bus activation) and `nped` in the
  chroot, then the bridge, and adds its NMEA device to gpsd.
- `positioningd-gpsd.py`: registers with `positioningd` the way Harmattan's
  QtMobility Location does (`registerListener`, `configSession`;
  qt-mobility 1.2.1+210, `src/location/dbuscomm_maemo.cpp`, LGPL), reads the
  QDataStream-serialised positions and satellites and writes GGA, RMC, GSA
  and GSV. Checked on a PC against a stand-in for `positioningd` built on
  the same serialisation (`meego/positioning/positioningd.py` in the Pro1X
  repository) and a real gpsd: 3D fix, time, track, speed, satellites.
- `harmattan-gps.initd` (OpenRC, `rc-service harmattan-gps start`): not
  started at boot, since the GPS stays on while it runs.
- `harmattan-gps.conf`: lets `nped` take its name on Leste's system bus.

What `nped` needs, from reading the binary: the three sysfs files opened
read-write (the driver's `hostreq` allows that), `/dev/bcm4751-gps`, a
phonet interface `phonet0` for the modem's assistance (the mainline modem
driver, `nokia,n950-modem`, makes it once the modem is up) and
Harmattan's libraries and loader throughout, which the chroot gives it.

**Untested on the phone.** Open questions: whether `positioningd` and `nped`
run without Aegis (Harmattan's security framework, absent on Leste's
kernel), and whether `positioningd` needs more of Harmattan's session
(GConf, ContextKit), which the chroot's session bus would start on demand.
