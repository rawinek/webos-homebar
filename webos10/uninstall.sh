#!/bin/sh
# rawin-launcher (webOS 10): give LG Home and the HOME button back and remove
# the launcher, its helper and its files.
BASE=/var/lib/webosbrew/rawin-launcher-home
KEYS=/home/root/.config/lginputhook/keybinds.json

if [ -d "$BASE/mode-switch-lock" ]; then sh "$BASE/mode-switch.sh" settle || exit 1; fi
# Remove only our rules in both mappers before removing the application. An
# unknown active mapper needs manual cleanup rather than a dead HOME shortcut.
if [ -f "$BASE/integration.js" ]; then
    node "$BASE/integration.js" clean uninstall "$BASE/uninstall-mapper-journal.json" || {
        node "$BASE/integration.js" rollback "$BASE/uninstall-mapper-journal.json" || true
        echo 'Mapper cleanup could not be verified. Inspect Diagnose and back up/fix unsupported mapper configuration before retrying uninstall' >&2; exit 1;
    }
fi
if [ -f "$BASE/native-home" ]; then
    sh "$BASE/native-home.sh" release || { echo 'Cannot restore native Home; uninstall stopped' >&2; exit 1; }
fi
[ -f "$BASE/takeover.sh" ] && sh "$BASE/takeover.sh" restore >/dev/null 2>&1
rm -f /var/lib/webosbrew/init.d/10-rawin-launcher /var/lib/webosbrew/init.d/77-rawin-launcher

# HOME back to LG: drop our key, keep any other bindings.
if [ ! -f "$BASE/integration.js" ] && [ -f "$KEYS" ]; then
    node -e '
var fs = require("fs"), f = process.argv[1], k = JSON.parse(fs.readFileSync(f, "utf8"));
Object.keys(k).forEach(function (code) { var v = k[code]; if (v && (v.id === "org.rawin.launcher" || (typeof v.command === "string" && v.command.indexOf("org.rawin.launcher") >= 0))) delete k[code]; });
fs.writeFileSync(f, JSON.stringify(k));' "$KEYS"
fi

luna-send -n 1 luna://com.webos.applicationManager/closeByAppId '{"id":"org.rawin.launcher"}' </dev/null >/dev/null 2>&1
for p in /proc/[0-9]*; do
    [ "$(cat "$p/comm" 2>/dev/null)" = "org.rawin.launc" ] && kill "${p#/proc/}" 2>/dev/null
done
luna-send -i -a com.webos.appInstallService luna://com.webos.appInstallService/dev/remove \
    '{"id":"org.rawin.launcher","subscribe":true}' </dev/null >/dev/null 2>&1 &
PID=$!
# Done when the package's own files are gone; the helper's icon cache (cache/,
# not part of the package) stays behind and is removed here.
APPDIR=/media/developer/apps/usr/palm/applications/org.rawin.launcher
n=0
while [ -f "$APPDIR/appinfo.json" ] && [ $n -lt 60 ]; do
    n=$((n + 1)); sleep 1
done
kill $PID 2>/dev/null
[ -f "$APPDIR/appinfo.json" ] || rm -rf "$APPDIR"
rm -rf "$BASE" /var/lib/webosbrew/rawin-launcher-last-input /var/lib/webosbrew/rawin-launcher-settings.json
# Favourites and settings (the app's LocalStorage).
rm -rf /home/root/.local/share/org.rawin.launcher
echo "rawin-launcher: removed; LG Home and the HOME button are back."
