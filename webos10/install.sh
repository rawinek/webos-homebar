#!/bin/sh
# Homebar installer, the overlay variant (an overlay app with a root helper;
# webOS 10 tested). Run on the TV as root, from the unpacked release:
# sh webos10/install.sh, or sh install.sh, which picks the variant.
#   --keep-lg-home     leave LG's Home in place (no black stand-in); without the
#                      stand-in LG Home may show briefly when an app exits
#   --replace-lg-home  the stand-in in LG Home's place (the default here)
#   --home-key=CODE    bind this key code as HOME (Input Hook's number for it)
#   --home-key=ask     ask for a press of HOME, also when a key is already bound
#   --home-key-exec    send that press through Input Hook's Execute action with
#                      noSplash/spinner:false, so the app manager shows no
#                      loading spinner when the panel has to start (experiment:
#                      falls back to nothing if Input Hook cannot run commands,
#                      so try it on the B4 before making it the default)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
UI=$HERE/../ui
APP=org.rawin.launcher
SERVICE=$APP.service
APPDIR=/media/developer/apps/usr/palm/applications/$APP
HBC=/media/developer/apps/usr/palm/services/org.webosbrew.hbchannel.service
BASE=/var/lib/webosbrew/rawin-launcher-home
HOOK=/var/lib/webosbrew/init.d/10-rawin-launcher   # before Glasshouse's 20-/50-tvweb hooks
KEYS=/home/root/.config/lginputhook/keybinds.json
HOME_KEY=773   # the remote's HOME button as Input Hook reports it

# Recover using the installed scripts before reading the mode or updating files.
if [ -d "$BASE/mode-switch-lock" ]; then sh "$BASE/mode-switch.sh" recover || exit 1; fi
NATIVE_HOME=
WAS_NATIVE=
[ ! -f "$BASE/native-home" ] || WAS_NATIVE=1
[ ! -f "$BASE/native-home" ] || NATIVE_HOME=1
KEEP_LG_HOME=
ADDITIONAL_OVERLAY=
WAS_ADDITIONAL=
[ ! -f "$BASE/additional-overlay" ] || WAS_ADDITIONAL=1
[ ! -f "$BASE/additional-overlay" ] || { ADDITIONAL_OVERLAY=1; KEEP_LG_HOME=1; }
HOME_KEY_OPT=
HOME_KEY_EXEC=
MANUAL_MAPPER=
TRY=
for a in "$@"; do
    case "$a" in
        --keep-lg-home) KEEP_LG_HOME=1 ;;
        --native-home) NATIVE_HOME=1 ;;
        --try-native) NATIVE_HOME=1; TRY=1 ;;
        --additional-overlay) ADDITIONAL_OVERLAY=1; KEEP_LG_HOME=1 ;;
        --replace-lg-home) KEEP_LG_HOME= ;;
        --home-key=*) HOME_KEY_OPT=${a#--home-key=} ;;
        --home-key-exec) HOME_KEY_EXEC=exec ;;
        *) echo "unknown option: $a" >&2; exit 2 ;;
    esac
done

say() { echo "rawin-launcher: $*"; }
fail() { echo "rawin-launcher: $*" >&2; exit 1; }
luna() { luna-send -n 1 "$1" "$2" </dev/null 2>/dev/null; }

[ "$(id -u)" = 0 ] || fail "run this as root on the TV"
[ -x "$HBC/elevate-service" ] || fail "the Homebrew Channel (root) is not set up on this TV"
if [ -n "$NATIVE_HOME" ]; then
    [ -z "$KEEP_LG_HOME$HOME_KEY_OPT$HOME_KEY_EXEC" ] || fail "--native-home cannot be combined with keep-lg-home or key mapping options"
    if [ -n "$TRY" ]; then
        grep -qE 'release (6|7|8|9)\.' /etc/starfish-release || fail "--try-native-home is for webOS 6 to 9; on 10/11 use --native-home"
        mkdir -p "$BASE"; touch "$BASE/native-trial"
    elif ! { grep -qE 'release (10|11)\.' /etc/starfish-release || [ -f "$BASE/native-trial" ]; }; then
        fail "--native-home currently supports webOS 10/11 only (webOS 6 to 9: --try-native-home, experimental)"
    fi
elif [ -z "$ADDITIONAL_OVERLAY" ]; then
    if [ -f "$HERE/integration.js" ] && node "$HERE/integration.js" legacy-mapper >/dev/null 2>&1; then MANUAL_MAPPER=magic; fi
    [ -n "$MANUAL_MAPPER" ] || [ -d /media/developer/apps/usr/palm/applications/org.webosbrew.inputhook ] ||
        fail "installation blocked: Input Hook is required. Install and open 'Input Hook' from the Homebrew Channel, then run this installer again"
fi
[ -z "$MANUAL_MAPPER" ] || [ -z "$HOME_KEY_OPT$HOME_KEY_EXEC" ] || fail "edit the existing Magic Mapper shortcut in its configuration"
[ -z "$ADDITIONAL_OVERLAY$NATIVE_HOME" ] || [ -z "$HOME_KEY_OPT$HOME_KEY_EXEC" ] || fail "change button mappings in your mapper in this mode"
[ -z "$ADDITIONAL_OVERLAY" ] || [ -n "$KEEP_LG_HOME" ] || fail "switch runtime mode in Launcher settings first"
if [ -z "$NATIVE_HOME$ADDITIONAL_OVERLAY" ] && [ -f "$HERE/integration.js" ]; then
    node "$HERE/integration.js" legacy-check "$MANUAL_MAPPER" || fail "HOME mapping could not be kept safely; use --additional-overlay or fix the reported mapper configuration"
fi
command -v node >/dev/null || fail "node is missing on this TV"
node -e 'process.exit(parseInt(process.versions.node, 10) >= 8 ? 0 : 1)' 2>/dev/null ||
    fail "the helper needs node 8 or newer; this TV has node $(node -v 2>/dev/null) (the Home panel may fit instead: sh install.sh --home-panel)"
IPK=$(ls "$HERE"/org.rawin.launcher_*_all.ipk 2>/dev/null | head -n 1)
[ -n "$IPK" ] || fail "no org.rawin.launcher IPK next to this script"

# Stop the native Home before replacing QML files it imports. Saved data stays.
if [ -f "$BASE/native-home" ]; then
    sh "$HERE/native-home.sh" check-owner || fail "another launcher owns Home; update stopped"
    sh "$HERE/native-home.sh" stop
fi
say "installing $(basename "$IPK")"
cp "$IPK" /tmp/rawin-launcher.ipk
LOG=/tmp/rawin-launcher-install.log
: >"$LOG"   # before the loop below reads it
luna-send -i -a com.webos.appInstallService luna://com.webos.appInstallService/dev/install \
    '{"id":"org.rawin.launcher","ipkUrl":"/tmp/rawin-launcher.ipk","subscribe":true}' </dev/null >"$LOG" 2>&1 &
PID=$!
n=0
until tr -d ' ' <"$LOG" | grep -q '"state":"installed"'; do
    tr -d ' ' <"$LOG" | grep -q -E '"state":"(installfailed|failed)"|errorText' && { kill $PID 2>/dev/null; cat "$LOG" >&2; fail "install failed"; }
    n=$((n + 1)); [ $n -lt 120 ] || { kill $PID 2>/dev/null; fail "install timed out"; }
    sleep 1
done
kill $PID 2>/dev/null || true
rm -f /tmp/rawin-launcher.ipk "$LOG"
# The TV's webOS version, shown in the panel's corner with the variant.
webos=$(sed -n 's/.*release \([0-9][0-9.]*\).*/\1/p' /etc/starfish-release 2>/dev/null | head -n 1)
[ -f "$APPDIR/Config.js" ] && sed -i "s/^var webos = .*/var webos = \"$webos\";/" "$APPDIR/Config.js"

# Older LG Settings versions ignore the target and open the picture menu.
# Inspect the shipped route instead of guessing support from the webOS number.
memory_optimizer=false
if grep -q 'MemoryOptimizer' /usr/palm/applications/com.palm.app.settings/main.js 2>/dev/null; then
    memory_optimizer=true
fi
printf '\nvar memoryOptimizer = %s;\n' "$memory_optimizer" >> "$APPDIR/Config.js"
say "giving the helper root (Homebrew elevate-service)"
"$HBC/elevate-service" "$SERVICE" >/dev/null 2>&1 || fail "elevate-service failed"

say "staging the LG Home stand-in in $BASE"
mkdir -p "$BASE/app"
cp "$HERE"/home-stub/* "$BASE/app/"
cp "$UI/icon.png" "$BASE/app/icon.png"
cp "$HERE/home-takeover.sh" "$BASE/takeover.sh"
cp "$HERE/native-home.sh" "$HERE/native-stage.js" "$HERE/native-trial.sh" "$HERE/mode-switch.sh" "$HERE/integration.js" "$BASE/"
cp "$HERE/uninstall.sh" "$BASE/uninstall.sh"
cp "$HERE/../update.sh" "$HERE/../diagnose.sh" "$HERE/../VERSION" "$BASE/"
# The probe (which variant fits) next to diagnose.sh, with the patch it checks with.
cp "$HERE/../probe.sh" "$HERE/../webos4/patch-home.js" "$BASE/"
chmod 755 "$BASE/takeover.sh" "$BASE/uninstall.sh" "$BASE/update.sh" "$BASE/probe.sh"
if [ -n "$ADDITIONAL_OVERLAY" ] && [ -z "$NATIVE_HOME" ]; then
    if [ -z "$WAS_ADDITIONAL" ]; then sh "$BASE/mode-switch.sh" overlay || fail "additional overlay setup failed"; fi
    sed -i 's/^var exitTarget = .*/var exitTarget = false;/' "$APPDIR/Config.js"
fi
if [ -n "$NATIVE_HOME" ]; then
    rm -f "$BASE/keep-lg-home"
    if [ -n "$WAS_NATIVE" ]; then sh "$BASE/native-home.sh" activate; else sh "$BASE/mode-switch.sh" native; fi || {
        # A failed trial leaves LG Home in place, and no trial option behind.
        if [ -n "$TRY" ]; then
            rm -f "$BASE/native-trial"
            say "trial log: $(sh "$BASE/native-trial.sh" end)"
            say "the native Home did not work on this TV; LG Home is back. Please attach that file to a GitHub issue (docs/install.md)."
        fi
        fail "native Home activation failed; see $BASE/native-home.sh status"
    }
    if [ -n "$TRY" ]; then
        say "trial log: $(sh "$BASE/native-trial.sh" end)"
        say "native Home is running on this TV. Press HOME and note what you see; then attach the log to a GitHub issue (docs/install.md)."
    fi
elif [ -n "$KEEP_LG_HOME" ]; then
    touch "$BASE/keep-lg-home"
    sh "$BASE/takeover.sh" restore >/dev/null 2>&1 || true
else
    rm -f "$BASE/keep-lg-home"
    # Here and not only from the boot hook, which runs it in the background:
    # over SSH that could end with the session, before LG's Home is stopped.
    say "LG Home -> black stand-in"
    sh "$BASE/takeover.sh" apply >/dev/null 2>&1 || say "LG Home kept: the app manager did not take the stand-in"
fi

if [ -z "$NATIVE_HOME$ADDITIONAL_OVERLAY" ] && [ -n "$MANUAL_MAPPER" ]; then
    touch "$BASE/manual-home-mapping"
    say "existing Magic Mapper HOME shortcut kept; no Input Hook binding created"
elif [ -z "$NATIVE_HOME$ADDITIONAL_OVERLAY" ]; then
rm -f "$BASE/manual-home-mapping"
if [ -n "$HOME_KEY_EXEC" ]; then
    say "HOME button ($HOME_KEY) -> rawin-launcher, Input Hook Execute without the spinner"
else
    say "HOME button ($HOME_KEY) -> rawin-launcher (Input Hook)"
fi
mkdir -p "$(dirname "$KEYS")"
[ -f "$KEYS" ] || echo '{}' > "$KEYS"
[ -f "$KEYS.before-rawin-launcher" ] || cp -p "$KEYS" "$KEYS.before-rawin-launcher"
# The HOME button's code: the one given (--home-key=CODE), else the one
# already bound as HOME (an earlier install, an update from the panel; not
# the extra button chosen in Launcher settings), else the one pressed now,
# when someone is at a terminal (or --home-key=ask), else 773, the tested
# Magic Remote's. Input Hook logs each key it sees; the first code logged
# after the prompt is taken.
bound=$(node "$BASE/integration.js" legacy-home 2>/dev/null | head -n 1)
case "$HOME_KEY_OPT" in
    ask) bound= ;;
    "") ;;
    *) bound=$HOME_KEY_OPT ;;
esac
if [ -n "$bound" ]; then
    HOME_KEY=$bound
    say "HOME is key $HOME_KEY"
elif [ -t 0 ] && log=$(ls -t /tmp/lginput-hook-*.log 2>/dev/null | head -n 1) && [ -n "$log" ]; then
    before=$(wc -l <"$log")
    say "press HOME on the remote now to bind it (15 s; otherwise key $HOME_KEY, the tested Magic Remote's, is used)"
    n=0
    while [ $n -lt 15 ]; do
        sleep 1; n=$((n + 1))
        code=$(tail -n +$((before + 1)) "$log" | grep -v 'Keybinds reloaded' | grep -o -E '[0-9]{3,4}' | head -n 1)
        [ -n "$code" ] && { HOME_KEY=$code; break; }
    done
    say "HOME is key $HOME_KEY"
fi
node "$BASE/integration.js" legacy-key "$HOME_KEY" "$HOME_KEY_EXEC"

elif [ -n "$ADDITIONAL_OVERLAY" ]; then
    say "additional overlay: existing mapper bindings preserved; HOME belongs to your main launcher"
else
    say "HOME -> system Homebar QML host (native takeover, no Input Hook mapping)"
fi

mkdir -p /var/lib/webosbrew/init.d
rm -f /var/lib/webosbrew/init.d/77-rawin-launcher   # the hook's name up to 0.14.0
cp "$HERE/boot-hook.sh" "$HOOK"
chmod 755 "$HOOK"
sh "$HOOK"
n=0
until wget -q -O - http://127.0.0.1:8899/ping >/dev/null 2>&1; do
    n=$((n + 1)); [ $n -lt 30 ] || fail "the helper did not start (see: luna-send -n 1 luna://$SERVICE/ping '{}')"
    sleep 2
done
if [ -n "$ADDITIONAL_OVERLAY" ] && [ -z "$NATIVE_HOME" ]; then sh "$BASE/mode-switch.sh" tile || true; fi
if [ -n "$ADDITIONAL_OVERLAY" ] && [ -z "$NATIVE_HOME" ]; then say "done. Open Homebar with your configured button or app tile."; else say "done. Press HOME on the remote."; fi
say "uninstall: sh $BASE/uninstall.sh"
