#!/usr/bin/env python3
"""Wait for the N950's ubiboot maintenance telnet, push i2crw + chg.sh and start
the charge loop within seconds, then log its readings until the device is gone.
usage: ubicharge.py DIR  (expects DIR/i2crw = static ARM i2crw, DIR/chg.sh = charge-loop.sh; logs DIR/ubicharge.log)
Stop: touch DIR/ubicharge.stop
"""
import os, socket, sys, time

HOST = '192.168.2.15'
D = sys.argv[1]
LOG = os.path.join(D, 'ubicharge.log')
STOP = os.path.join(D, 'ubicharge.stop')

def log(m):
    with open(LOG, 'a') as f:
        f.write('%s %s\n' % (time.strftime('%H:%M:%S'), m))

def clean(b):
    out = bytearray(); i = 0
    while i < len(b):
        if b[i] == 255 and i + 2 < len(b):
            i += 3; continue
        out.append(b[i]); i += 1
    return out.decode('latin-1')

def telnet(cmd, wait=2.0, first=0.4):
    s = socket.create_connection((HOST, 23), timeout=3)
    def drain(t):
        end = time.time() + t; buf = b''
        s.settimeout(0.2)
        while time.time() < end:
            try:
                d = s.recv(65536)
                if not d: break
                buf += d
            except socket.timeout:
                pass
        return buf
    drain(first)
    s.sendall(cmd.encode() + b'\r\n')
    out = clean(drain(wait)); s.close()
    return out

def send(port, path, tries=40):
    data = open(path, 'rb').read()
    for _ in range(tries):
        try:
            s = socket.create_connection((HOST, port), timeout=2)
            s.sendall(data); s.shutdown(socket.SHUT_WR); time.sleep(0.3); s.close()
            return True
        except OSError:
            time.sleep(0.1)
    return False

def up():
    try:
        socket.create_connection((HOST, 23), timeout=0.5).close(); return True
    except OSError:
        return False

log('watcher start')
while not os.path.exists(STOP):
    if not up():
        time.sleep(0.3); continue
    t0 = time.time()
    log('ubiboot telnet up')
    try:
        telnet('setsid sh -c "nc -l -p 5555 > /tmp/i2crw; chmod 755 /tmp/i2crw; '
               'nc -l -p 5556 > /tmp/chg.sh; chmod 755 /tmp/chg.sh; rm -f /tmp/chg.stop; '
               'exec /tmp/chg.sh" </dev/null >/dev/null 2>&1 &', wait=0.3, first=0.3)
        ok1 = send(5555, os.path.join(D, 'i2crw'))
        ok2 = send(5556, os.path.join(D, 'chg.sh'))
        log('pushed i2crw=%s chg.sh=%s after %.1f s' % (ok1, ok2, time.time() - t0))
        time.sleep(6)
        out = telnet('cut -d" " -f1 /proc/uptime; tail -2 /tmp/chg.log; pgrep -f chg.sh | head -1', 1.5)
        log('check: ' + ' | '.join(l.strip() for l in out.splitlines()[1:] if l.strip()))
        if 'mV' not in out:
            log('loop not running -> starting directly')
            telnet('chmod 755 /tmp/i2crw /tmp/chg.sh; rm -f /tmp/chg.stop; setsid /tmp/chg.sh </dev/null >/dev/null 2>&1 &', 0.5)
    except OSError as e:
        log('setup error %r' % e)
    # follow readings until the device disappears
    last = ''
    gone_since = None
    while not os.path.exists(STOP):
        time.sleep(20)
        try:
            out = telnet('tail -1 /tmp/chg.log', 1.0)
            line = [l.strip() for l in out.splitlines() if 'mV' in l and 'tail' not in l]
            if line and line[-1] != last:
                last = line[-1]; log('N950 ' + last)
            gone_since = None
        except OSError:
            if gone_since is None:
                gone_since = time.time(); log('device not reachable')
            if time.time() - gone_since > 60:
                log('device gone, waiting for next boot')
                break
log('watcher end')
