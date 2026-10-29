#!/bin/sh
# Homebar: which variant fits this TV, and why. Changes nothing. Run on the
# TV as root:
#   sh probe.sh            the report for both variants (what install.sh --probe shows)
#   sh probe.sh panel      exit 0 when the Home panel fits; the reasons on stdout
#   sh probe.sh overlay    the same for the overlay
#   sh probe.sh full-home  a word on LG's New Home screen, where a TV has one
# The release holds it next to install.sh, which uses it; the installers put
# it next to diagnose.sh, with patch-home.js, so an installed TV can run it.
HERE=$(cd "$(dirname "$0")" && pwd)
HOME_QML=/usr/palm/applications/com.webos.app.home/qml
# Home's UI controller: in Controllers/ on the ribbon Home (webOS 4 and 5), in
# UserInterfaceLayer/ on the full-screen Home (webOS 6).
UICTRL=$HOME_QML/Controllers/UIController.qml
[ -f "$UICTRL" ] || UICTRL=$HOME_QML/UserInterfaceLayer/UIController.qml
APPS=/media/developer/apps/usr/palm/applications
HBC=/media/developer/apps/usr/palm/services/org.webosbrew.hbchannel.service
PANEL_BASE=/var/lib/webosbrew/rawin-launcher
# patch-home.js: in webos4/ in the release, next to this script once installed.
PATCH=$HERE/webos4/patch-home.js
[ -f "$PATCH" ] || PATCH=$HERE/patch-home.js

say() { echo "rawin-launcher: $*"; }
# A check's reasons (one or more lines, some already prefixed), indented.
detail() { printf '%s\n' "$1" | sed 's/^rawin-launcher: //; s/^/rawin-launcher:   /'; }

# Whether LG's Home is a QML app the patch fits. The originals come from the
# firmware, or from the installed copy while its mounts hide them;
# SystemProperties.qml (where Home declares isAppForeground) is only read.
panel_why=
panel_fits() {
    [ -f "$HOME_QML/main.qml" ] || { panel_why="LG Home is not a QML app (no $HOME_QML/main.qml)"; return 1; }
    [ -f "$UICTRL" ] ||
        { panel_why="LG Home is a QML app, but has no UIController.qml (in Controllers/ or UserInterfaceLayer/): not a Home the panel is made for"; return 1; }
    command -v node >/dev/null || { panel_why="node is missing on this TV"; return 1; }
    [ -f "$PATCH" ] || { panel_why="patch-home.js is missing next to this script"; return 1; }
    tmp=$(mktemp -d)
    if grep -qF " $HOME_QML/main.qml " /proc/mounts || grep -qF " $UICTRL " /proc/mounts; then
        if [ -f "$PANEL_BASE/main.original.qml" ] && [ -f "$PANEL_BASE/UIController.original.qml" ]; then
            cp "$PANEL_BASE/main.original.qml" "$PANEL_BASE/UIController.original.qml" "$tmp/"
        else
            rm -rf "$tmp"; panel_why="LG Home is already replaced by something else; restore it first"; return 1
        fi
    else
        cp "$HOME_QML/main.qml" "$tmp/main.original.qml"
        cp "$UICTRL" "$tmp/UIController.original.qml"
    fi
    [ -f "$HOME_QML/AppInitializer/SystemProperties.qml" ] && cp "$HOME_QML/AppInitializer/SystemProperties.qml" "$tmp/SystemProperties.original.qml"
    panel_why=$(node "$PATCH" --check "$tmp" 2>&1)
    r=$?
    rm -rf "$tmp"
    # The full-screen Home of webOS 6 is new to the patch: never picked on its own.
    if [ "$r" = 0 ] && [ "$UICTRL" != "$HOME_QML/Controllers/UIController.qml" ]; then
        panel_why="$panel_why
This is the full-screen Home of webOS 6, which the panel has not run in yet: it is only installed on request (sh install.sh --home-panel)"
        return 1
    fi
    return $r
}
# Some webOS 4 and 5 TVs (the 2019 UM series, a 2020 NANO80) also have LG's "New" Home screen,
# com.webos.app.fullhome: with the TV's Home screen setting on New it is the
# one HOME opens, so the panel, which lives in the Basic one, never shows.
FULL_HOME=com.webos.app.fullhome
full_home_note() {
    [ -d "/usr/palm/applications/$FULL_HOME" ] || return 0
    if pidof "$FULL_HOME" >/dev/null 2>&1; then
        echo "LG's New Home screen ($FULL_HOME) is running: the panel only shows with the TV's Home screen setting on Basic"
    else
        echo "this TV also has LG's New Home screen ($FULL_HOME): keep the TV's Home screen setting on Basic"
    fi
}
# Whether the overlay and its helper have what they need.
overlay_why=
overlay_fits() {
    [ -x "$HBC/elevate-service" ] || { overlay_why="the Homebrew Channel (root) is not set up on this TV"; return 1; }
    if [ "$1" != native ] && [ "$1" != additional ] && [ ! -f /var/lib/webosbrew/rawin-launcher-home/native-home ] && [ ! -f /var/lib/webosbrew/rawin-launcher-home/additional-overlay ]; then
        integration=$HERE/webos10/integration.js
        [ -f "$integration" ] || integration=$HERE/integration.js
        [ -d "$APPS/org.webosbrew.inputhook" ] || { [ -f "$integration" ] && node "$integration" legacy-mapper >/dev/null 2>&1; } ||
            { overlay_why="Input Hook is required for the overlay. Install and open 'Input Hook' from the Homebrew Channel, then run this installer again; it sends the HOME button to Homebar"; return 1; }
    fi
    command -v node >/dev/null || { overlay_why="node is missing on this TV"; return 1; }
    node -e 'process.exit(parseInt(process.versions.node, 10) >= 8 ? 0 : 1)' 2>/dev/null ||
        { overlay_why="the helper needs node 8 or newer; this TV has node $(node -v 2>/dev/null)"; return 1; }
    if [ "$1" = native ] || [ -f /var/lib/webosbrew/rawin-launcher-home/native-home ]; then
        overlay_why="the Homebrew Channel and node $(node -v 2>/dev/null) are there; system Home mode needs no Input Hook"
    elif [ "$1" = additional ] || [ -f /var/lib/webosbrew/rawin-launcher-home/additional-overlay ]; then
        overlay_why="the Homebrew Channel and node $(node -v 2>/dev/null) are there; additional overlay keeps the user's button mapping"
    elif [ ! -d "$APPS/org.webosbrew.inputhook" ]; then
        overlay_why="the Homebrew Channel, existing Magic Mapper shortcut and node $(node -v 2>/dev/null) are there"
    else
        overlay_why="the Homebrew Channel, Input Hook and node $(node -v 2>/dev/null) are there"
    fi
    return 0
}

case "$1" in
    additional-overlay) overlay_fits additional; r=$?; printf '%s\n' "$overlay_why"; exit $r ;;
    panel) panel_fits; r=$?; printf '%s\n' "$panel_why"; full_home_note; exit $r ;;
    full-home) full_home_note ;;
    native-home)
        grep -qE 'release (10|11)\.' /etc/starfish-release || [ -f /var/lib/webosbrew/rawin-launcher-home/native-trial ] || { echo 'Native Home requires webOS 10/11 (webOS 6 to 9: install.sh --try-native-home)'; exit 1; }
        [ -x /usr/bin/qml-runner ] || { echo 'qml-runner is missing'; exit 1; }
        overlay_fits native; r=$?; printf '%s\n' "$overlay_why"
        [ "$r" = 0 ] || exit "$r"
        integration=$HERE/webos10/integration.js
        [ -f "$integration" ] || integration=$HERE/integration.js
        [ ! -f "$integration" ] || node "$integration" check
        exit $? ;;

    overlay) overlay_fits; r=$?; printf '%s\n' "$overlay_why"; exit $r ;;
    "")
        if panel_fits; then say "Home panel: fits"; else say "Home panel: does not fit"; fi
        detail "$panel_why"
        note=$(full_home_note)
        [ -n "$note" ] && detail "$note"
        if overlay_fits; then say "overlay: fits"; else say "overlay: requirements not met"; fi
        detail "$overlay_why"
        integration=$HERE/webos10/integration.js
        [ -f "$integration" ] || integration=$HERE/integration.js
        if [ -f "$integration" ] && command -v node >/dev/null 2>&1; then
            say "launch configuration (read-only):"
            node "$integration" inspect
        fi
        ;;
    *) echo "usage: $0 [panel|overlay|full-home]" >&2; exit 2 ;;
esac
