#!/bin/sh
# Homebar: install the variant for this TV. Run on the TV as root from the
# unpacked release: sh install.sh [options]
#
# Three methods, and the TV gets the one it has the makings for, not the one
# its version number says (probe.sh decides; see docs/compatibility.md):
#   Home panel  the panel inside LG's own QML Home (webOS 3 to 5, e.g. an LG C9;
#               webOS 4 and 5 tested)
#   system HOME Homebar replaces LG's Home: no Input Hook, no mapper (webOS 10
#               and 11; a trial on 7 to 9 with --try-native-home)
#   overlay     an overlay app with a root helper next to LG's Home: HOME bound
#               in Input Hook, or an app tile / a mapped button (--additional-overlay)
# Options:
#   --home-panel       the Home panel, or fail (no overlay instead)
#   --overlay          the overlay, or fail (needs Input Hook and node 8+)
#   --native-home      system HOME on webOS 10/11 (the default there on a fresh install)
#   --try-native-home  a trial of that on webOS 7, 8 or 9: it writes a log to report
#   --additional-overlay  keep the main Home; configure a button in your mapper
#   --probe            only say which variant fits and why; change nothing
#   --keep-lg-home     overlay: leave LG's Home in place (no black stand-in)
#   --replace-lg-home  overlay on an untested webOS: put the black stand-in in
#                      LG Home's place anyway (on webOS 10 it always is)
#   --try-webos10      the same as --overlay (older instructions use it)
# HOMEBAR_WEBOS=<version> overrides the detected webOS version (testing).
HERE=$(cd "$(dirname "$0")" && pwd)
PROBE=$HERE/probe.sh

say() { echo "rawin-launcher: $*"; }
fail() { echo "rawin-launcher: $*" >&2; exit 1; }
detail() { printf '%s\n' "$1" | sed 's/^rawin-launcher: //; s/^/rawin-launcher:   /'; }

version=${HOMEBAR_WEBOS:-${RAWIN_LAUNCHER_WEBOS:-$(sed -n 's/.*release \([0-9][0-9.]*\).*/\1/p' /etc/starfish-release 2>/dev/null | head -n 1)}}
major=${version%%.*}
force=
probe=
keep=
replace=
native=
additional=
trial=
pass=
for a in "$@"; do
    case "$a" in
        --home-panel) force=panel ;;
        --overlay|--try-webos10) force=overlay ;;
        --native-home) native=1; force=overlay; pass="$pass --native-home" ;;
        --try-native-home) native=1; trial=1; force=overlay; pass="$pass --try-native" ;;
        --additional-overlay) additional=1; force=overlay; keep=1; pass="$pass --additional-overlay" ;;
        --probe) probe=1 ;;
        --keep-lg-home) keep=1 ;;
        --replace-lg-home) replace=1 ;;
        *) pass="$pass $a" ;;
    esac
done

# LG's name for it: from version 7 on, the year (webOS 22 is 7.x, webOS 25
# is 10.x); people often know only that one.
name=
case "$major" in
    ''|*[!0-9]*|[1-6]) ;;
    *) name=", which LG calls webOS $((major + 15))" ;;
esac
case "$major" in
    4|5|6|10) tested="tested on $major.x" ;;
    *) tested="untested; 4.x, 5.x, 6.x and 10.x are the tested ones" ;;
esac
say "webOS ${version:-unknown}$name ($tested)"
if [ -n "$trial" ]; then
    case "$major" in
        7|8|9) say "trial of the native System HOME (experimental): LG Home is given back at once if it does not come up" ;;
        10|11) fail "--try-native-home is for webOS 7 to 9; use --native-home here" ;;
        *) fail "--try-native-home is for webOS 7 to 9 only (this is ${version:-unknown})" ;;
    esac
fi

if [ -n "$probe" ]; then
    if [ -n "$native" ]; then sh "$PROBE" native-home
    elif [ -n "$additional" ]; then sh "$PROBE" additional-overlay
    else sh "$PROBE"; fi
    say "probe only; nothing was changed"
    exit 0
fi

if [ -d /var/lib/webosbrew/rawin-launcher-home/mode-switch-lock ]; then
    sh /var/lib/webosbrew/rawin-launcher-home/mode-switch.sh recover || fail "mode recovery failed"
fi
# Keep an explicitly enabled native Home across updates without needing a mapper.
if [ "$force" = panel ] && { [ -f /var/lib/webosbrew/rawin-launcher-home/native-home ] || [ -f /var/lib/webosbrew/rawin-launcher-home/additional-overlay ]; }; then
    fail "restore the ordinary overlay before changing installation variants"
fi
if [ -f /var/lib/webosbrew/rawin-launcher-home/additional-overlay ]; then force=overlay; keep=1; fi
if [ -f /var/lib/webosbrew/rawin-launcher-home/native-home ]; then
    force=overlay
    native=1
fi
# Existing installs keep their launch policy. Fresh installs choose a safe
# default; another Home or an unverifiable mapper gets a companion, never an
# automatic takeover. The same inspector supplies the settings UI.
if [ -z "$force" ] && [ -f /var/lib/webosbrew/rawin-launcher-home/VERSION ]; then force=overlay; fi
if [ -z "$force" ] && [ -f /var/lib/webosbrew/rawin-launcher/VERSION ]; then force=panel; fi
# A Home that fits the panel gets the panel whatever else is mounted under it: files
# patched by other tools (a Home-tuning hook, say) are not another launcher's Home.
if [ -z "$force" ] && sh "$PROBE" panel >/dev/null 2>&1; then force=panel; fi
choice=
if [ -z "$force" ] && [ -f "$HERE/webos10/integration.js" ] && command -v node >/dev/null 2>&1; then
    choice=$(node "$HERE/webos10/integration.js" select 2>/dev/null) || fail "launch configuration could not be checked; run --probe"
    if [ "$choice" = mapped ]; then force=overlay; say "compatibility overlay selected: keeping the existing mapper shortcut"; fi
    if [ "$choice" = overlay ]; then
        force=overlay; additional=1; keep=1; pass="$pass --additional-overlay"
        say "additional overlay selected: keeping HOME and existing mapper settings; open the app tile or configure another button"
    fi
fi
variant=$force
if [ -z "$variant" ]; then
    if panel_why=$(sh "$PROBE" panel 2>&1); then variant=panel
    elif [ "$choice" = native ]; then
        variant=overlay; native=1; pass="$pass --native-home"
        say "system HOME selected: no mapper required; recognised old Homebar mappings will be backed up and removed"
    elif overlay_why=$(sh "$PROBE" overlay 2>&1); then variant=overlay
    else
        { say "installation blocked; see the requirements below"
          say "Home panel: does not fit"; detail "$panel_why"
          say "overlay: requirements not met"; detail "$overlay_why"; } >&2
        fail "see docs/compatibility.md; sh install.sh --probe repeats this check"
    fi
fi

case "$variant" in
    panel)
        say "installing the Home panel (the panel inside LG's Home)"
        exec sh "$HERE/webos4/install.sh" $pass
        ;;
    overlay)
        # LG's Home is replaced by the black stand-in on webOS 10, where that is
        # tested; elsewhere it stays unless asked otherwise.
        if [ -n "$keep" ]; then pass="$pass --keep-lg-home"
        elif [ "$major" != 10 ] && [ -z "$replace$native" ]; then
            say "LG's Home stays in place on this webOS (--replace-lg-home puts the black stand-in there too)"
            pass="$pass --keep-lg-home"
        fi
        say "installing the overlay (an overlay app with a root helper)"
        exec sh "$HERE/webos10/install.sh" $pass
        ;;
esac
