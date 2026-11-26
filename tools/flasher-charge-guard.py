#!/usr/bin/env python3
"""Run Nokia flasher with -O wait-charging under a pty and stop it before it flashes.

flasher 3.12.1 (disassembly 0x410937): polls /device/battery_level every ~1 s,
prints "Charging battery, %2d %% battery level (11 %% required). Ctrl-c to exit"
while level <= 10, and on level > 10 prints "Battery level %d %%, continuing."
and proceeds to SU_BEGIN_UPDATE (= flashing).

Guard: SIGINT as soon as level >= required - 1. Fail closed: "continuing", or any
other non-empty output after the first charging line, also means SIGINT at once.

usage: charge_guard.py LOGFILE -- cmd args...
"""
import os, pty, re, signal, sys, time, select

CHG = re.compile(r'Charging battery,\s*(\d+)\s*%\s*battery level\s*\((\d+)\s*%\s*required\)')
CONT = re.compile(r'Battery level\s*(\d+)\s*%,\s*continuing')
MARGIN = int(os.environ.get('GUARD_MARGIN', '1'))   # stop at required - MARGIN

log_path = sys.argv[1]
assert sys.argv[2] == '--'
cmd = sys.argv[3:]
logf = open(log_path, 'a', buffering=1)

def log(msg):
    logf.write('%s %s\n' % (time.strftime('%H:%M:%S'), msg))

pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)

log('GUARD start pid=%d margin=%d cmd=%r' % (pid, MARGIN, cmd))
seen_charging = False
stopped = None          # reason
stop_t = None
hard_kill_ok = False    # only SIGKILL while sitting in the charging loop
pending = ''
last_level = None

def stop(reason, kill_ok):
    global stopped, stop_t, hard_kill_ok
    if stopped:
        return
    stopped, stop_t, hard_kill_ok = reason, time.time(), kill_ok
    try:
        os.kill(pid, signal.SIGINT)
    except ProcessLookupError:
        pass
    log('GUARD STOP (%s) -> SIGINT sent' % reason)

def check_charging(text):
    global seen_charging, last_level
    for m in CHG.finditer(text):
        lvl, req = int(m.group(1)), int(m.group(2))
        seen_charging = True
        if lvl != last_level:
            log('GUARD level %d %% (required %d %%)' % (lvl, req))
            last_level = lvl
        if not stopped and lvl >= req - MARGIN:
            stop('level %d %% >= %d - %d' % (lvl, req, MARGIN), True)

def handle_line(line):
    s = line.strip()
    if not s:
        return
    log('OUT ' + s)
    if CHG.search(s):
        check_charging(s)
        return
    if stopped:
        return
    if CONT.search(s):
        stop('flasher continues to flash: ' + s, False)
    elif seen_charging:
        stop('unexpected output after charging: ' + s, False)

status = None
while True:
    if stopped and hard_kill_ok and time.time() - stop_t > 20:
        log('GUARD still alive 20 s after SIGINT in charging loop -> SIGKILL')
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        hard_kill_ok = False
    try:
        r, _, _ = select.select([fd], [], [], 0.5)
    except InterruptedError:
        continue
    if r:
        try:
            data = os.read(fd, 4096)
        except OSError:
            data = b''
        if not data:
            break
        pending += data.decode('latin-1')
        parts = re.split(r'[\r\n]', pending)
        pending = parts.pop()
        for p in parts:
            handle_line(p)
        # a charging line may sit unterminated until the next poll -> check the tail too
        check_charging(pending)
    else:
        w, st = os.waitpid(pid, os.WNOHANG)
        if w:
            status = st
            break

if pending.strip():
    handle_line(pending)
if status is None:
    _, status = os.waitpid(pid, 0)
log('GUARD flasher exited status=%r (reason=%s)' % (status, stopped))
