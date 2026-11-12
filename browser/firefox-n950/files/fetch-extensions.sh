#!/bin/sh
# Downloads the add-ons firefox-n950 comes with from addons.mozilla.org into
# DIR/distribution/extensions (DIR: the installed Firefox, /opt/firefox-n950).
# Firefox installs them into each profile at its next start; each can be
# switched off or removed in Add-ons and themes (about:addons) when a page
# does not work with it.
#
#   uBO Lite: blocks ads and trackers with declarative rules, so no filter
#     lists are loaded and matched in JavaScript (lighter than uBlock Origin)
#   I still don't care about cookies: hides or answers cookie banners
#
# The files are signed by Mozilla and named after their add-on IDs, as
# Firefox expects.
set -eu
DIR=${1:?usage: fetch-extensions.sh <firefox directory>}
DEST=$DIR/distribution/extensions
mkdir -p "$DEST"
fetch() {
	curl -fsSL -o "$DEST/$1.xpi.part" "https://addons.mozilla.org/firefox/downloads/latest/$2/latest.xpi"
	mv "$DEST/$1.xpi.part" "$DEST/$1.xpi"
}
fetch uBOLiteRedux@raymondhill.net ublock-origin-lite
fetch idcac-pub@guus.ninja istilldontcareaboutcookies
ls -l "$DEST"
