# ofono on the N950

Leste's ofono (2.18.0-1+5m7, Debian's package rebuilt) with two patches for
the N950's modem (the CMT, driven through ofono's `n900` plugin):

- `0003-isimodem-cbs-do-not-remove-the-atom-twice.patch`: whenever the modem
  reset while online, ofonod crashed (SIGSEGV): `isi_cbs_remove()` clears the
  driver data and destroys the ISI client, which fails the pending routing
  request, and its callback removed the CBS atom a second time.
- `0004-nokia-gpio-keep-cmt_rst_rq-active-on-the-N9-and-N950.patch`: ofono
  lowers `cmt_rst_rq` once the phonet link is up, as the N900's modem wants;
  on the N950 the modem then reset itself within seconds. Harmattan sets the
  line active at boot (`gpio=cmt_rst_rq:88:sysfs:init_active`). The boards
  are recognised by their device tree compatible.

Build: unpack Leste's source package (`ofono_2.18.0-1+5m7.dsc` from
maedevu.maemo.org), add the patches to `debian/patches/series`, bump the
version (`1:2.18.0-1+5m7n950.N`) and build in the armhf chroot
(`build-in-chroot.sh`).

State (2026-11-10): the modem powers up, the SIM is found (no PIN), the
modem goes online - and resets itself about three seconds after
`MTC_STATE_REQ`/`MTC_NORMAL`, i.e. when its radio starts. Not caused by the
network registration's `NET_NW_ACCESS_CONF_REQ` (skipped as a test: same
reset). After that reset ofono stays offline and the modem keeps running
(no reset for minutes). Next: capture Harmattan's ISI traffic on an N9 while
it brings its modem online, and compare.
