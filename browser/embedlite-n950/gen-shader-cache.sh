#!/bin/sh
# On the phone, as root: fill a fresh EmbedLite profile's WebRender shader cache on
# the SGX530 (shader warmup: the shipped cache is moved aside, so seeding fails and
# every program is compiled), then install it next to libxul as shader-cache.
G=/usr/lib/arm-linux-gnueabihf/xulrunner-qt5-153.6.0
H=/home/user/.cache/el-gen
C=$H/.mozilla/embedlite-shell/shader-cache
rm -rf $H; mkdir -p $H; chown user:user $H
[ -d $G/shader-cache ] && mv $G/shader-cache $G/shader-cache.old
start=$(date +%s)
su user -c "cd $H && HOME=$H DISPLAY=:0 XAUTHORITY=/home/user/.Xauthority XDG_RUNTIME_DIR=/run/user/1000 setsid sh -c \"/usr/bin/embedlite-shell about:blank > $H/log 2>&1\" < /dev/null > /dev/null 2>&1 &"
last=-1; same=0
for i in $(seq 1 180); do
	sleep 5
	dbus-send --system --type=method_call --dest=com.nokia.mce /com/nokia/mce/request com.nokia.mce.request.req_display_blanking_pause
	n=$(ls $C 2>/dev/null | wc -l)
	[ "$n" != "$last" ] && echo "t=$(( $(date +%s) - start ))s files=$n"
	if [ "$n" -gt 1 ] && [ "$n" = "$last" ]; then same=$((same+1)); else same=0; fi
	last=$n
	[ $same -ge 12 ] && break
	pgrep -f "^/usr/bin/embedlite-shell about:blank" >/dev/null || { echo "shell exited"; break; }
done
pkill -TERM -f "^/usr/bin/embedlite-shell about:blank"; sleep 5
pkill -KILL -f "^/usr/bin/embedlite-shell about:blank" 2>/dev/null
echo "== stamp"; cat $C/stamp
if [ "$(ls $C 2>/dev/null | wc -l)" -gt 10 ]; then
	rm -rf $G/shader-cache.old
	cp -r $C $G/shader-cache && chmod -R a+rX $G/shader-cache && echo "installed $(ls $G/shader-cache | wc -l) files, $(du -sh $G/shader-cache | cut -f1)"
else
	echo "too few programs, keeping the old cache"; [ -d $G/shader-cache.old ] && mv $G/shader-cache.old $G/shader-cache
fi
rm -rf $H
