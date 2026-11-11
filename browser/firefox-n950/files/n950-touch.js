// Touchscreen and multitouch on the N950 (installed into
// /opt/firefox-n950/defaults/pref/): touch events for pages, panning and
// pinch-zoom through APZ, double-tap zoom, touch-radius hit testing.
pref("dom.w3c_touch_events.enabled", 1);
pref("apz.allow_zooming", true);
pref("apz.allow_double_tap_zooming", true);
pref("ui.touch.radius.enabled", true);
pref("ui.touch.radius.leftmm", 4);
pref("ui.touch.radius.rightmm", 4);
pref("ui.touch.radius.topmm", 6);
pref("ui.touch.radius.bottommm", 4);
pref("ui.touch_activation.duration_ms", 50);
pref("layout.css.touch_action.enabled", true);
