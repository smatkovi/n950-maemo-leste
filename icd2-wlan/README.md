# icd2-wlan

A patch on Leste's WLAN module for icd2,
[maemo-leste/libicd-network-wpasupplicant](https://github.com/maemo-leste/libicd-network-wpasupplicant)
0.1.20 (commit bee40ad), and a script that builds it as the package
`libicd-network-wpasupplicant` 0.1.20+5m7n950.1.

| File | What |
| --- | --- |
| `0001-wlan-let-wpa_supplicant-reconnect-before-closing-the.patch` | after an unrequested disconnection (the AP's deauthentication) wpa_supplicant gets 15 s to reconnect before icd2 closes the connection |
| `build-deb.sh` | `SYSROOT=<armhf root> bash icd2-wlan/build-deb.sh OUTDIR`: clones the module and the sources of the headers it needs (icd2, icd2-osso-ic-dev, connui-common, maemo-security-certman) at fixed revisions, applies the patches, builds in the armhf root and packs the .deb with Leste's maintainer scripts. Leste's -dev packages are not needed. |

## Why

The N950's access point (here a home router) drops the phone now and then:
about every one to one and a half hours on 2026-11-13/14, logged as
`deauthenticated from … (Reason: 7=CLASS3_FRAME_FROM_NONASSOC_STA)`, so the AP
had already forgotten the station. wpa_supplicant reassociated within 0.4 s,
but the module had reported the disconnection to icd2 at once. icd2 then
took the IP layer down (dnsmasq: `no servers found`) and removed the network
from wpa_supplicant, which tore the restored link down again ("by local
choice"), and connected anew about 10 s later: 12 s without network for
each drop.

With the patch a disconnection icd2 did not ask for starts a 15 s timer. If
wpa_supplicant reaches `completed` in that time, icd2 is not told and the IP
configuration stays. If it does not, or wpa_supplicant goes `inactive`, the
connection is closed as before. A disconnection icd2 asked for is handled
as before, and a scan in the meantime keeps the network being reconnected to.

Tested on the phone 2026-11-14 with `wpa_cli disconnect` followed by
`reconnect`. With the old module icd2 closed the connection (dnsmasq lost its
server). With the new one the connection, the address and the DNS server
stayed. Both runs had about 4 s without answers, because `reconnect` scans
first; after a real deauthentication wpa_supplicant needs no scan.
What causes the AP's drops is still open.
