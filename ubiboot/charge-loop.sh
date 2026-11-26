#!/bin/sh
# ubiboot charge loop for the N950: what the Leste kernel (patches 0037/0038) does.
# Stop: touch /tmp/chg.stop
I=/tmp/i2crw
val() { $I "$@" 2>/dev/null | sed 's/.*= //'; }
while [ ! -e /tmp/chg.stop ]; do
  a=$(val 1 4a aa); [ -n "$a" ] && $I 1 4a aa $(printf %02x $((0x$a | 2))) >/dev/null 2>&1  # TWL5031 BCC watchdog kick
  $I 2 6b 00 c0 >/dev/null 2>&1   # bq24153 TMR_RST + EN_STAT
  $I 2 6b 01 48 >/dev/null 2>&1   # IINLIM 500 mA, TE=1, CE=0
  $I 2 6b 02 8e >/dev/null 2>&1   # VOREG 4.20 V
  $I 2 6b 04 19 >/dev/null 2>&1   # charge/term current as in Leste
  $I 2 6b 05 04 >/dev/null 2>&1   # LOW_CHG off
  v=$((0x$(val 2 55 0d)$(val 2 55 0c))); i=$((0x$(val 2 55 0f)$(val 2 55 0e))); [ $i -gt 32767 ] && i=$((i-65536))
  echo "$(cut -d' ' -f1 /proc/uptime) ${v}mV ${i}mA st=$(val 2 6b 00) r5=$(val 2 6b 05)" >> /tmp/chg.log
  sleep 5
done
