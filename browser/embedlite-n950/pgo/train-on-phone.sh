#!/bin/sh
# On the phone as root, detached: train-on-phone.sh MD5 BUILDID. Installs the PGO-instrumented engine from
# /root/pgogen.tar.xz (MD5 of the file; BUILDID compiled into its libxul, for the shader cache stamp)
# and runs the shell over a set of pages, scrolling, then quitting normally so the profiles are written.
# Profiles: /home/user/.cache/pgo/*.profraw. Log: /root/pgo-train.log. Hard limit 45 min.
exec > /root/pgo-train.log 2>&1
set -u
X="DISPLAY=:0 XAUTHORITY=/home/user/.Xauthority"
M="dbus-send --system --type=method_call --dest=com.nokia.mce /com/nokia/mce/request com.nokia.mce.request"
L=/usr/lib/arm-linux-gnueabihf; G=$L/xulrunner-qt5-153.6.0
( sleep 2700; pkill -TERM -f "^/usr/bin/embedlite-shell"; pkill -f train-on-phone.sh ) &
pgrep -f "^/usr/bin/embedlite-shell" && { echo "shell running, abort"; exit 1; }
[ "$(md5sum < /root/pgogen.tar.xz | cut -c1-32)" = "$1" ] || { echo "md5 mismatch"; exit 1; }
tar -xJf /root/pgogen.tar.xz -C $L && rm -f /root/pgogen.tar.xz || { echo "unpack failed"; exit 1; }
printf "$2\n4\n\n\n" > $G/shader-cache/stamp
echo "installed: $(md5sum < $G/libxul.so | cut -c1-12) $(df -h / | tail -1)"
P=/home/user/.cache/pgo; rm -rf $P; mkdir -p $P; chown user $P
for u in https://de.wikipedia.org/wiki/Nokia_N9 https://orf.at/ https://www.derstandard.at/ https://www.oebb.at/de/ \
         https://github.com/smatkovi/n950-maemo-leste https://html.duckduckgo.com/html/?q=nokia+n950 \
         file:///home/user/.cache/jit.html file:///home/user/.cache/counter.html https://shop.oebbtickets.at/; do
  $M.req_display_state_on; $M.req_tklock_mode_change string:unlocked
  t0=$(date +%s)
  su user -c "cd /home/user && $X XDG_RUNTIME_DIR=/run/user/1000 LLVM_PROFILE_FILE=$P/%2m.profraw EMBEDLITE_SHELL_SCROLLTEST=30:10 EMBEDLITE_SHELL_QUIT=75 EMBEDLITE_SHELL_EXIT_GRACE=150 setsid sh -c \"/usr/bin/embedlite-shell '$u' > /dev/null 2>&1\" < /dev/null > /dev/null 2>&1 &"
  sleep 3
  for i in $(seq 1 120); do pgrep -f "^/usr/bin/embedlite-shell" >/dev/null || break; $M.req_display_blanking_pause; sleep 2; done
  if pgrep -f "^/usr/bin/embedlite-shell" >/dev/null; then pkill -TERM -f "^/usr/bin/embedlite-shell"; echo "$u: killed (no profile)"; sleep 5; else echo "$u: exited after $(( $(date +%s) - t0 )) s"; fi
  ls -la $P | awk 'NR>1 && /profraw/ {printf "  %s %d\n", $9, $5}'
done
echo "free: $(df -h / | tail -1)"
echo done
