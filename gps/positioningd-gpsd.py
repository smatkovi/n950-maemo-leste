#!/usr/bin/python3
"""positioningd-gpsd: the N950's positions from Harmattan's GPS stack to gpsd.

Harmattan computes positions in Nokia's own nped (with Broadcom's engine for
the BCM4751) and hands them to applications through positioningd on the
session bus. This program is such an application, speaking the client side
of positioningd's interface as Harmattan's QtMobility Location does
(qt-mobility 1.2.1+210, src/location/dbuscomm_maemo.cpp, LGPL):

  registerListener(s service, s path) -> (i client, u methods, u interval)
  configSession(i client, i command, i methods, i interval) -> i
  to the client (com.nokia.qlocation.updates at its own name and path):
    positionUpdate(ay), satellitesInViewUpdate(ay), satellitesInUseUpdate(ay)

The byte arrays are Qt 4 QDataStream serialisations of QGeoPositionInfo
and QList<QGeoSatelliteInfo>. Each position goes out as NMEA (GGA, RMC,
GSA, GSV) on a pseudo terminal, which gpsd reads like a GPS receiver.

    positioningd-gpsd.py BUS_ADDRESS NMEA_LINK

BUS_ADDRESS is the session bus positioningd runs on (harmattan-gps starts
one in the chroot), NMEA_LINK the path where the pseudo terminal appears
for gpsd. Untested on the phone.
"""
import math
import os
import struct
import sys
import time
import uuid

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

NAME = 'com.nokia.positioningd.client'
PATH = '/com/nokia/positioningd/client'
UPDATES = 'com.nokia.qlocation.updates'
CMD_START, CMD_STOP, CMD_METHODS, CMD_INTERVAL, CMD_SAT_START, CMD_SAT_STOP = 1, 2, 4, 8, 16, 32
SATELLITE_METHODS = 0x000000ff
INTERVAL_MS = 1000
# QGeoPositionInfo::Attribute, QGeoSatelliteInfo::Attribute
DIRECTION, GROUND_SPEED, VERTICAL_SPEED, MAGNETIC_VARIATION, H_ACCURACY, V_ACCURACY = range(6)
ELEVATION, AZIMUTH = range(2)
JULIAN_DAY_1970 = 2440588
KNOTS_PER_MS = 1.943844


class Reader:
    """Qt 4 QDataStream, big endian."""

    def __init__(self, data):
        self.data, self.pos = bytes(data), 0

    def take(self, fmt):
        v = struct.unpack_from('>' + fmt, self.data, self.pos)
        self.pos += struct.calcsize('>' + fmt)
        return v if len(v) > 1 else v[0]

    def datetime(self):
        """QDateTime: QDate (julian day), QTime (ms since midnight), spec."""
        day, ms, spec = self.take('IIb')
        if day == 0 or ms == 0xffffffff:
            return None
        t = (day - JULIAN_DAY_1970) * 86400 + ms / 1000.0
        # a local time (spec 0): its fields read as local time
        return t if spec == 1 else time.mktime(time.gmtime(t)) + t % 1

    def attributes(self):
        return dict(self.take('id') for _ in range(self.take('I')))


def position(data):
    r = Reader(data)
    t = r.datetime()
    lat, lon, alt = r.take('ddd')
    attrs = r.attributes()
    if t is None or math.isnan(lat) or math.isnan(lon):
        return None
    return dict(t=t, lat=lat, lon=lon, alt=alt, attrs=attrs)


def satellites(data):
    r = Reader(data)
    out = []
    for _ in range(r.take('I')):
        prn, ss = r.take('ii')
        a = r.attributes()
        out.append(dict(prn=prn, ss=ss, el=a.get(ELEVATION), az=a.get(AZIMUTH)))
    return out


def nmea(body):
    c = 0
    for ch in body.encode('ascii'):
        c ^= ch
    return '$%s*%02X\r\n' % (body, c)


def angle(v, pos, neg, width):
    d = abs(v)
    deg = int(d)
    return '%0*d%07.4f,%s' % (width, deg, (d - deg) * 60, pos if v >= 0 else neg)


class Bridge(dbus.service.Object):
    def __init__(self, bus, link):
        self.service = 'com.nokia.qlocation.I' + str(uuid.uuid4()).replace('-', 'I')
        self.path = '/com/nokia/qlocation/' + self.service.rsplit('.', 1)[1]
        self.name = dbus.service.BusName(self.service, bus)
        super().__init__(bus, self.path)
        self.bus = bus
        self.in_view, self.in_use = [], []
        master, slave = os.openpty()
        self.out = os.fdopen(master, 'w', buffering=1)
        self.slave = slave		# kept open: the link stays usable
        try:
            os.unlink(link)
        except FileNotFoundError:
            pass
        os.symlink(os.ttyname(slave), link)

    def start(self):
        proxy = self.bus.get_object(NAME, PATH)
        pd = dbus.Interface(proxy, NAME)
        client, methods, interval = pd.registerListener(self.service, self.path)
        self.client = int(client)
        print('positioningd-gpsd: client %d, methods 0x%x, minimum interval %d ms'
              % (self.client, methods, interval), flush=True)
        pd.configSession(self.client, CMD_START | CMD_METHODS | CMD_INTERVAL,
                         SATELLITE_METHODS, max(INTERVAL_MS, int(interval)))
        pd.configSession(self.client, CMD_SAT_START, SATELLITE_METHODS, 0)

    @dbus.service.method(UPDATES, in_signature='ay', out_signature='')
    def positionUpdate(self, data):
        fix = position(data)
        if fix is not None:
            self.send(fix)

    @dbus.service.method(UPDATES, in_signature='ay', out_signature='')
    def satellitesInViewUpdate(self, data):
        self.in_view = satellites(data)

    @dbus.service.method(UPDATES, in_signature='ay', out_signature='')
    def satellitesInUseUpdate(self, data):
        self.in_use = satellites(data)

    def send(self, fix):
        tm = time.gmtime(fix['t'])
        hms = '%02d%02d%06.3f' % (tm.tm_hour, tm.tm_min, tm.tm_sec + fix['t'] % 1)
        lat = angle(fix['lat'], 'N', 'S', 2)
        lon = angle(fix['lon'], 'E', 'W', 3)
        a = fix['attrs']
        alt = '' if math.isnan(fix['alt']) else '%.1f' % fix['alt']
        hdop = '%.1f' % (a[H_ACCURACY] / 5.0) if H_ACCURACY in a else ''
        used = len(self.in_use)
        lines = [nmea('GPGGA,%s,%s,%s,1,%02d,%s,%s,M,,M,,' % (hms, lat, lon, used, hdop, alt))]
        speed = '%.2f' % (a[GROUND_SPEED] * KNOTS_PER_MS) if GROUND_SPEED in a else ''
        track = '%.1f' % a[DIRECTION] if DIRECTION in a else ''
        date = '%02d%02d%02d' % (tm.tm_mday, tm.tm_mon, tm.tm_year % 100)
        lines.append(nmea('GPRMC,%s,A,%s,%s,%s,%s,%s,,,A' % (hms, lat, lon, speed, track, date)))
        prns = [s['prn'] for s in self.in_use][:12]
        lines.append(nmea('GPGSA,A,%d,%s,,%s,' % (
            3 if alt else 2, ','.join(['%02d' % p for p in prns] + [''] * (12 - len(prns))), hdop)))
        view = self.in_view
        n = (len(view) + 3) // 4
        for i in range(n):
            group = ''.join(',%02d,%s,%s,%s' % (
                s['prn'], '' if s['el'] is None else '%02d' % s['el'],
                '' if s['az'] is None else '%03d' % s['az'],
                '' if s['ss'] < 0 else '%02d' % s['ss']) for s in view[4 * i:4 * i + 4])
            lines.append(nmea('GPGSV,%d,%d,%02d%s' % (n, i + 1, len(view), group)))
        self.out.write(''.join(lines))


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    DBusGMainLoop(set_as_default=True)
    bus = dbus.bus.BusConnection(sys.argv[1])
    bridge = Bridge(bus, sys.argv[2])
    # positioningd is started on demand (D-Bus activation in the chroot)
    for attempt in range(30):
        try:
            bridge.start()
            break
        except dbus.DBusException as e:
            if attempt == 29:
                sys.exit('positioningd-gpsd: %s' % e)
            time.sleep(2)
    GLib.MainLoop().run()


if __name__ == '__main__':
    main()
