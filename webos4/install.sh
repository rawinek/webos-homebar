#!/bin/sh
# Homebar installer, the Home panel variant (the panel inside LG's QML Home;
# webOS 4 tested). Run on the TV as root, from the unpacked release:
# sh webos4/install.sh, or sh install.sh, which picks the variant.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
UI=$HERE/../ui
BASE=/var/lib/webosbrew/rawin-launcher
HOOK=/var/lib/webosbrew/init.d/76-rawin-launcher
ROOT=/usr/palm/applications/com.webos.app.home/qml
MAIN=$ROOT/main.qml
CTRL=$ROOT/Controllers/UIController.qml

say() { echo "rawin-launcher: $*"; }
fail() { echo "rawin-launcher: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || fail "run this as root on the TV"
[ -d /var/lib/webosbrew ] || fail "the Homebrew Channel (root) is not set up on this TV"
command -v node >/dev/null || fail "node is missing on this TV"
[ -f "$MAIN" ] && [ -f "$CTRL" ] || fail "LG Home QML not found: this Home is not a QML app (the overlay may fit: sh install.sh --overlay)"

# LG's original files: from the firmware, or from the previous install while
# its mounts hide them.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if grep -qF " $MAIN " /proc/mounts || grep -qF " $CTRL " /proc/mounts; then
    [ -f "$BASE/main.original.qml" ] && [ -f "$BASE/UIController.original.qml" ] || fail "LG Home is already replaced by something else; restore it first"
    cp "$BASE/main.original.qml" "$BASE/UIController.original.qml" "$TMP/"
else
    cp "$MAIN" "$TMP/main.original.qml"
    cp "$CTRL" "$TMP/UIController.original.qml"
fi
# Where Home declares isAppForeground; never mounted over, only read.
[ -f "$ROOT/AppInitializer/SystemProperties.qml" ] && cp "$ROOT/AppInitializer/SystemProperties.qml" "$TMP/SystemProperties.original.qml"
node "$HERE/patch-home.js" "$TMP" || fail "LG Home was not changed (the overlay may fit instead: sh install.sh --overlay)"

say "installing to $BASE"
for f in "$MAIN" "$CTRL"; do
    if grep -qF " $f " /proc/mounts; then umount "$f"; fi
done
# A fresh copy of the panel; files of older versions go.
rm -rf "$BASE/current" "$BASE/restore.sh"
mkdir -p "$BASE/current/fonts"
cp "$TMP/main.original.qml" "$TMP/UIController.original.qml" "$TMP/main.qml" "$TMP/UIController.qml" "$BASE/"
cp "$UI/Launcher.qml" "$UI/FavouriteStore.qml" "$UI/Strings.js" "$UI/Themes.js" "$UI/About.js" "$HERE/Config.js" "$BASE/current/"
cp "$UI"/fonts/* "$BASE/current/fonts/"
cp "$UI/DeviceIcons.js" "$UI/DeviceIcon.qml" "$BASE/current/"
mkdir -p "$BASE/current/input-icons"
cp "$UI"/input-icons/* "$BASE/current/input-icons/"
# The TV's webOS version, shown in the panel's corner with the variant.
webos=$(sed -n 's/.*release \([0-9][0-9.]*\).*/\1/p' /etc/starfish-release 2>/dev/null | head -n 1)
sed -i "s/^var webos = .*/var webos = \"$webos\";/" "$BASE/current/Config.js"
# Older LG Settings versions ignore the target and open the picture menu.
# Inspect the shipped route instead of guessing support from the webOS number.
memory_optimizer=false
if grep -q 'MemoryOptimizer' /usr/palm/applications/com.palm.app.settings/main.js 2>/dev/null; then
    memory_optimizer=true
fi
printf '\nvar memoryOptimizer = %s;\n' "$memory_optimizer" >> "$BASE/current/Config.js"
cp "$HERE/apply.sh" "$HERE/uninstall.sh" "$HERE/../update.sh" "$HERE/../diagnose.sh" "$HERE/../VERSION" "$BASE/"
# The probe (which variant fits) next to diagnose.sh, with the patch it checks with.
cp "$HERE/../probe.sh" "$HERE/patch-home.js" "$BASE/"
# The setup server (the weather and the page to choose its place), started by apply.sh.
mkdir -p "$BASE/setup"
cp "$HERE/../shared/setup.js" "$HERE/../shared/qr.js" "$HERE/../shared/guard.js" "$HERE/../shared/stats.js" "$HERE/../shared/setup.html" "$BASE/setup/"
chmod 755 "$BASE/apply.sh" "$BASE/uninstall.sh" "$BASE/update.sh" "$BASE/probe.sh"
mkdir -p /var/lib/webosbrew/init.d
ln -sf "$BASE/apply.sh" "$HOOK"
sh "$BASE/apply.sh"
say "done. Press HOME on the remote."
# LG's New Home screen, where the TV has one: HOME opens it instead of the
# Basic one the panel lives in.
note=$(sh "$BASE/probe.sh" full-home 2>/dev/null)
[ -n "$note" ] && say "note: $note"
say "uninstall: sh $BASE/uninstall.sh"
