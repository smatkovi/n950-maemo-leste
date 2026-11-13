#!/bin/sh
# On the phone, as root: fill a fresh profile's WebRender shader cache on the
# SGX530 (hardware WebRender, shader warmup), then install it next to Firefox
# as /opt/firefox-n950/shader-cache. Log: /home/user/.cache/ff-gen/log
P=/home/user/.cache/ff-gen
rm -rf $P; mkdir -p $P/profile
cat > $P/profile/user.js <<'JS'
user_pref("gfx.webrender.all", true);
user_pref("gfx.webrender.software", false);
user_pref("gfx.webrender.program-binary-disk", true);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
JS
chown -R user:user $P
start=$(date +%s)
su user -c "DISPLAY=:0 XAUTHORITY=/home/user/.Xauthority MOZ_USE_XINPUT2=1 setsid /opt/firefox-n950/firefox-n950 --profile $P/profile --no-remote about:blank > $P/log 2>&1 < /dev/null &"
last=-1; same=0
for i in $(seq 1 180); do
	sleep 5
	n=$(ls $P/profile/shader-cache 2>/dev/null | wc -l)
	[ "$n" != "$last" ] && echo "t=$(( $(date +%s) - start ))s files=$n"
	if [ "$n" -gt 1 ] && [ "$n" = "$last" ]; then same=$((same+1)); else same=0; fi
	last=$n
	[ $same -ge 12 ] && break
	pgrep -f "[/]opt/firefox-n950/firefox-n950 --profile $P" >/dev/null || { echo "firefox exited"; break; }
done
pkill -TERM -f "[/]opt/firefox-n950/firefox-n950 --profile $P"; sleep 8
pkill -KILL -f "[/]opt/firefox-n950/firefox-n950 --profile $P" 2>/dev/null
echo "== stamp"; cat $P/profile/shader-cache/stamp
echo "== prefs"; grep gfx-shader-check $P/profile/prefs.js
echo "== warmup/compile errors"; grep -oE "warmup: [A-Za-z]+\(\"[a-z_]+\"|Failed to (compile|link)[^.]*" $P/log | sort | uniq -c
du -sh $P/profile/shader-cache
rm -rf /opt/firefox-n950/shader-cache
cp -r $P/profile/shader-cache /opt/firefox-n950/shader-cache && chmod -R a+rX /opt/firefox-n950/shader-cache && echo "installed $(ls /opt/firefox-n950/shader-cache | wc -l) files"
su user -c "DISPLAY=:0 XAUTHORITY=/home/user/.Xauthority xrefresh"
