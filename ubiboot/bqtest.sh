#!/bin/sh
# Run in ubiboot's maintenance shell right after a power-on reset of the
# bq24153 (battery out with no cable): is its safety limit register (6)
# still writable, i.e. has nothing written the chip since the reset?
D=$(dirname "$0")
cp "$D/i2crw" /tmp/i2crw && chmod +x /tmp/i2crw
BUS=
for b in 2 1 3; do
  if /tmp/i2crw $b 6b 03 >/dev/null 2>&1; then BUS=$b; break; fi
done
[ -n "$BUS" ] || { echo "bq24153 not found"; exit 1; }
echo "bq24153 on i2c-$BUS, registers before:"
for r in 00 01 02 03 04 05 06; do /tmp/i2crw $BUS 6b $r; done
echo "write reg 6 <- 47 (VMREG 4.34 V):"
/tmp/i2crw $BUS 6b 06 47
