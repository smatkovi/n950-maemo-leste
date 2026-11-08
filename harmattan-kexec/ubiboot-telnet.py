#!/usr/bin/env python3
# telnet runner for ubiboot maintenance shell (CRLF line endings!)
import socket, sys, time
HOST = sys.argv[2] if len(sys.argv) > 2 else "192.168.0.15"
cmds = sys.argv[1]
s = socket.create_connection((HOST, 23), timeout=8)
s.settimeout(2)
def rd(t):
    out = b''; end = time.time() + t
    while time.time() < end:
        try:
            d = s.recv(4096)
            if not d: break
            out += d
        except socket.timeout:
            pass
    return out
init = rd(2.5)
resp = bytearray(); i = 0
while i < len(init):
    if init[i] == 255 and i + 2 < len(init):
        c, o = init[i+1], init[i+2]
        if c in (251, 252): resp += bytes([255, 254, o])
        elif c in (253, 254): resp += bytes([255, 252, o])
        i += 3; continue
    i += 1
if resp: s.sendall(bytes(resp))
rd(0.3)
payload = cmds.strip() + "\r\necho __ENDOFCMD__\r\n"
s.sendall(payload.encode())
data = bytearray(); deadline = time.time() + 40
while time.time() < deadline:
    try:
        chunk = s.recv(4096)
    except socket.timeout:
        continue
    if not chunk: break
    data += chunk
    if b"__ENDOFCMD__\r\n" in data and data.count(b"__ENDOFCMD__") >= 2:
        break
s.close()
print(data.decode("utf-8", "replace").replace("\r", ""))
