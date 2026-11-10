# ofono on the N950

Leste's ofono (2.18.0-1+5m7, Debian's package rebuilt) with four patches for
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
- `0008-n900-announce-the-info-server-again-after-a-modem-reset.patch`: when
  its radio comes on, the modem asks the phone for the software version part
  of the IMEISV (`PN_EPOC_INFO`, resource 0x62, `INFO_SERIAL_NUMBER_READ_REQ`)
  and resets itself if nobody answers. ofono's info server answers it, but
  after a modem reset its name was never announced to the modem's name
  service again (gisi announces a resource only for its first handler, and
  `n900_pre_sim()` stacked a new server on the old one). The old server is
  now dropped first. This was the "modem resets when the radio starts" bug.
- `0009-n900-no-cell-broadcast-on-the-N9-and-N950.patch`: the second cause:
  about 1.5 s after the CBS atom's `SMS_GSM_CB_ROUTING_REQ` the modem resets
  itself; Harmattan does not send it when the radio comes on. No CBS atom on
  the N9/N950 (device tree compatible), so no cell broadcast there.

Build: unpack Leste's source package (`ofono_2.18.0-1+5m7.dsc` from
maedevu.maemo.org), add the patches to `debian/patches/series`, bump the
version (`1:2.18.0-1+5m7n950.N`, now .6) and build in the armhf chroot
(`build-in-chroot.sh`).

State (2026-11-10, evening): the modem resets after `MTC_NORMAL` were the
missing `PN_EPOC_INFO` answer (0008). Found by bisection on the N950: with
ofonod stopped, a lone `MTC_STATE_REQ NORMAL` still made the modem reset; with
Harmattan csd's name registrations and its answer to the 0x62 request sent by
hand, it stayed online. With 0008 alone it still reset when ofono went
online: replaying ofono's post-online requests one at a time (ofonod
stopped) showed the reset right after `SMS_GSM_CB_ROUTING_REQ` (0009).
With 0008 and 0009 (`1:2.18.0-1+5m7n950.6`) the modem stays online and
registers with the network (EDGE, tested on the N950 on 2026-11-10).
