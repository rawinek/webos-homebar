#!/bin/sh
# Change runtime ownership, not a QML preference. Keep a rollback journal before
# stopping the panel; boot recovery also uses it if power was lost mid-switch.
set -eu
umask 077
BASE=/var/lib/webosbrew/rawin-launcher-home
APP=/media/developer/apps/usr/palm/applications/org.rawin.launcher
STORE=/home/root/.local/share
HOMEAPP=/usr/palm/applications/com.webos.app.home
KEYS=/home/root/.config/lginputhook/keybinds.json
TX=$BASE/mode-switch-lock
DB=9969c85c6e1c20a73a4ac456d46e31f7
# Each switch and recovery, step by step, kept across reboots (unlike /tmp):
# when one fails on a TV, this says where. Cut back to its last part at 64 KB.
LOG=$BASE/mode-switch.log
step=start
log() {
    if [ -f "$LOG" ] && [ "$(wc -c <"$LOG")" -gt 65536 ]; then tail -n 300 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"; fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG" 2>/dev/null || true
}
at() { step=$1; case "$1" in recover:*) log "$1" ;; *) log "${mode:-recover}: $1" ;; esac; }
inode() { ls -di "$1" 2>/dev/null | awk '{print $1}'; }
owned() {
    case "$(node "$BASE/integration.js" owner)" in native|legacy) return 0 ;; *) return 1 ;; esac
}
foreign() {
    case "$(node "$BASE/integration.js" owner)" in lg|native|legacy) return 1 ;; *) return 0 ;; esac
}
stop_current() {
    # In companion mode even a QML Home host can belong to LG/another launcher.
    # Only stop the Home identity when our native stage actually owns its mount.
    if owned && [ "$(inode "$HOMEAPP")" = "$(inode "$BASE/native-app")" ]; then
        sh "$BASE/native-home.sh" stop
    else
        sh "$BASE/native-home.sh" stop-overlay
    fi
}
launch() {
    luna-send -n 1 luna://com.webos.applicationManager/launch "{\"id\":\"$1\"}" </dev/null | grep -q '"returnValue": *true'
}
# The input or app card in front when a switch starts. Restarting the Home host
# replaces it (it opens as a card of its own first) and LG then falls back to Live
# TV, so the card is brought back and the panel opened above it again.
front_card() {
    luna-send -n 1 luna://com.webos.applicationManager/getForegroundAppInfo '{"extraInfo":true}' </dev/null 2>/dev/null |
        node -e 'var s="";process.stdin.on("data",function(d){s+=d}).on("end",function(){try{var a=JSON.parse(s).foregroundAppInfo||[];for(var i=0;i<a.length;i++)if(/CARD$/.test(a[i].windowType||"")&&a[i].appId!=="com.webos.app.home"&&a[i].appId!=="org.rawin.launcher"){console.log(a[i].windowGroupOwnerId||a[i].appId);return}}catch(e){}})' 2>/dev/null || true
}
panel_up() {
    luna-send -n 1 luna://com.webos.applicationManager/getForegroundAppInfo '{"extraInfo":true}' </dev/null 2>/dev/null | grep -q "\"appId\": *\"$1\""
}
return_card() {
    # LG Home itself was in front: it is gone with the switch, and LG would open
    # Live TV. Go to the last input instead, as the helper does after an app exits.
    [ -n "$front" ] || front=$(cat /var/lib/webosbrew/rawin-launcher-last-input 2>/dev/null || true)
    sleep 2
    if [ -n "$front" ] && [ "$(front_card)" != "$front" ]; then
        launch "$front" || true
        sleep 2
    fi
    panel_up "$1" || launch "$1" || true
}
# LG creates the app tile only when the app is installed, and only for a visible
# app. Without it, Additional overlay has no way in before a button is mapped,
# so add the launch point whenever it is missing (best effort, idempotent).
tile() {
    luna-send -n 1 luna://com.webos.applicationManager/listLaunchPoints '{}' </dev/null 2>/dev/null |
        grep -q '"id": *"org.rawin.launcher"' && return 0
    luna-send -n 1 luna://com.webos.service.applicationmanager/addLaunchPoint \
        "{\"id\":\"org.rawin.launcher\",\"title\":\"Homebar\",\"icon\":\"$APP/icon.png\"}" </dev/null >/dev/null 2>&1
}
paths() {
    printf '%s\n' "$BASE/native-home" "$BASE/additional-overlay" "$BASE/keep-lg-home" "$BASE/keys-before-native.json" "$BASE/mapper-backup.json" "$APP/Config.js"
    for id in org.rawin.launcher com.webos.app.home; do
        for suffix in sqlite ini sqlite-journal sqlite-wal sqlite-shm; do
            echo "$STORE/$id/QML/OfflineStorage/Databases/$DB.$suffix"
        done
    done
}
snapshot() {
    paths >"$TX/paths"
    i=0
    while IFS= read -r p; do
        i=$((i+1)); [ ! -f "$p" ] || cp -p "$p" "$TX/$i"
    done <"$TX/paths"
    if [ -f "$BASE/native-home" ]; then echo com.webos.app.home; else echo org.rawin.launcher; fi >"$TX/app"
    touch "$TX/ready"
}
# Whether an app is there to be launched again: the overlay app may have been
# removed since (by hand, or a failed install), and Home is always there.
installed() { [ "$1" = com.webos.app.home ] || [ -f "$APP/appinfo.json" ]; }
# Undo an interrupted switch from its journal. It returns 2 while that switch is
# still running, 1 when something could not be undone, and it never waits on
# what cannot come back: a removed app is not relaunched, and a launcher that
# has taken Home meanwhile keeps it.
recover() {
    if [ -f "$TX/pid" ]; then
        owner=$(cat "$TX/pid")
        if [ "$owner" != "$$" ] && [ -f "/proc/$owner/cmdline" ] &&
           { tr '\000' ' ' <"/proc/$owner/cmdline" | grep -q '/mode-switch.sh '; } &&
           kill -0 "$owner" 2>/dev/null; then
            echo 'A mode change is still running; recovery refused' >&2; return 2
        fi
    fi
    [ -f "$TX/ready" ] || { log 'recover: no journal yet, lock removed'; rm -rf "$TX"; return 0; }
    app=$(cat "$TX/app" 2>/dev/null || echo org.rawin.launcher)
    # Another launcher's Home mount is never touched (only an owned Home is
    # stopped or unmounted below), and its Home is not launched as ours.
    foreign_home=
    if foreign; then foreign_home=1; log 'recover: another launcher owns Home; it keeps it'; fi
    log "recover: journal for $app"
    mapper_recovery=0
    node "$BASE/integration.js" rollback "$TX/mapper-journal.json" || { mapper_recovery=1; log 'recover: mapper journal could not be rolled back'; }
    if [ ! -f "$TX/runtime-restored" ]; then
    at 'recover: stop'; stop_current || return 1
    if owned; then at 'recover: give Home back'; sh "$BASE/takeover.sh" restore || return 1; fi
    at 'recover: files'
    i=0
    while IFS= read -r p; do
        i=$((i+1))
        if [ -f "$TX/$i" ]; then mkdir -p "$(dirname "$p")" && cp -p "$TX/$i" "$p" || return 1; else rm -f "$p" || return 1; fi
    done <"$TX/paths"
    # System HOME cannot come back under a Home another launcher holds: the
    # install continues as the additional overlay next to it instead.
    if [ -n "$foreign_home" ] && [ -f "$BASE/native-home" ]; then
        log 'recover: System HOME given up for the additional overlay'
        sh "$BASE/native-home.sh" copy-back || true
        rm -f "$BASE/native-home"; touch "$BASE/additional-overlay" "$BASE/keep-lg-home"
    fi
    if [ -f "$BASE/native-home" ] && [ -f "$APP/appinfo.json" ]; then at 'recover: stage'; node "$BASE/native-stage.js" "$APP" "$BASE/native-app" || return 1; fi
    # The black stand-in of the mode before may not take (a fresh install never
    # had it; on webOS 11 sam refused it before 0.19.5): LG Home then stays,
    # which is a safe end for a rollback, not a reason to keep the lock.
    if [ -z "$foreign_home" ]; then at 'recover: takeover'; sh "$BASE/takeover.sh" apply || log 'recover: stand-in not taken; LG Home kept'; fi
    touch "$TX/runtime-restored" || return 1
    fi
    if [ -f "$BASE/native-home" ]; then app=com.webos.app.home; elif [ "$app" = com.webos.app.home ]; then app=org.rawin.launcher; fi
    if installed "$app"; then launch "$app" || log "recover: $app did not launch"; else log "recover: $app is not installed; not launched"; fi
    [ "$mapper_recovery" = 0 ] || return 1
    echo '{"ok":false,"error":"launch_failed"}' >"$BASE/mode-result.json"
    rm -rf "$TX"
    log 'recover: done'
}
# Before an install, an uninstall or the boot hook goes on: undo what an
# interrupted switch left. What still cannot be undone is moved aside (kept for
# diagnose.sh) instead of blocking everything after it; only a switch that is
# still running stops the caller.
settle() {
    [ -e "$TX" ] || return 0
    r=0; recover || r=$?
    [ "$r" != 0 ] || return 0
    [ "$r" != 2 ] || return 1
    aside=$TX.failed-$(date +%Y%m%d-%H%M%S)
    mv "$TX" "$aside" || return 1
    log "settle: recovery failed; journal moved to $aside"
    echo "rawin-launcher: an earlier launch method change could not be fully undone; its journal is kept in $aside (see $LOG)" >&2
    return 0
}
case "${1:-}" in
  recover) recover; exit ;;
  settle) settle; exit ;;
  tile) tile; exit ;;
  native|overlay) mode=$1 ;;
  *) echo 'usage: mode-switch.sh native|overlay|recover|settle|tile' >&2; exit 2 ;;
esac
expected=${2:-}
[ -z "$expected" ] || node "$BASE/integration.js" match "$expected"
[ ! -e "$TX" ] || { echo 'A mode change or recovery is already pending' >&2; exit 1; }
if foreign && [ "$mode" = native ]; then
    echo 'Another launcher owns Home; disable its Home replacement first' >&2; exit 1
fi
if [ "$mode" = native ]; then
    { grep -qE 'release (10|11)\.' /etc/starfish-release || { [ -f "$BASE/native-trial" ] && grep -qE 'release (6|7|8|9)\.' /etc/starfish-release; }; } || { echo 'Native Home currently supports webOS 10/11 only' >&2; exit 1; }
    sh "$BASE/native-home.sh" check-owner
elif [ -f "$BASE/additional-overlay" ] && [ ! -f "$BASE/native-home" ]; then
    exit 0
fi
mkdir "$TX"
echo "$$" >"$TX/pid"
if [ -f "$BASE/native-home" ]; then echo com.webos.app.home; else echo org.rawin.launcher; fi >"$TX/app"
log "$mode: begin"
trap 'code=$?; trap - EXIT HUP INT TERM; if [ "$code" != 0 ]; then log "$mode: failed at $step (exit $code)"; tail -n 20 /tmp/rawin-launcher-boot.log 2>/dev/null | sed "s/^/    boot log: /" >>"$LOG" 2>/dev/null; if [ -f "$TX/ready" ]; then recover || true; else launch "$(cat "$TX/app")" || true; rm -rf "$TX"; fi; fi; exit "$code"' EXIT
trap 'exit 1' HUP INT TERM
# Once a process is stopped, copied SQLite files are consistent, including WAL.
# Register recovery only after the complete journal has been written.
front=$(front_card)
at stop; stop_current
at journal; snapshot
[ -z "$expected" ] || node "$BASE/integration.js" match "$expected"
if [ "$mode" = native ]; then
    rm -f "$BASE/keep-lg-home"
    at 'mappers'; node "$BASE/integration.js" clean native "$TX/mapper-journal.json" "$expected"
    # Its messages go to the installer or the panel as before, and into the log.
    at 'activate System HOME'
    if ! sh "$BASE/native-home.sh" activate 2>"$TX/activate.txt"; then
        cat "$TX/activate.txt" >&2; sed 's/^/    /' "$TX/activate.txt" >>"$LOG"; false
    fi
    cat "$TX/activate.txt" >&2
    rm -f "$BASE/additional-overlay"
else
    if owned; then at 'give Home back'; sh "$BASE/takeover.sh" restore; fi
    if [ -f "$BASE/native-home" ]; then sh "$BASE/native-home.sh" copy-back; fi
    rm -f "$BASE/native-home"
    touch "$BASE/additional-overlay" "$BASE/keep-lg-home"
    at 'mappers'; node "$BASE/integration.js" restore overlay "$TX/mapper-journal.json" >"$TX/result.json"
    node "$BASE/integration.js" clean overlay "$TX/mapper-journal.json"
    at 'overlay app'; node -e 'var fs=require("fs"),f=process.argv[1],s=fs.readFileSync(f,"utf8");fs.writeFileSync(f,s.replace(/^var exitTarget = .*$/m,"var exitTarget = false;"));' "$APP/Config.js"
    tile || true
    launch org.rawin.launcher
fi
at 'card'; if [ -f "$BASE/native-home" ]; then return_card com.webos.app.home; else return_card org.rawin.launcher; fi
log "$mode: done"
if [ -f "$TX/result.json" ]; then cat "$TX/result.json"; else echo '{"restoreSkipped":false}'; fi
rm -rf "$TX"
# The helper keeps this result after the old QML process has gone away.
