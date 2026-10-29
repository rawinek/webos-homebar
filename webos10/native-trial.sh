#!/bin/sh
# Experimental System HOME on webOS 6 to 9: a trial that records what the TV did,
# so that a report can say where it stopped. Usage: native-trial.sh begin|verify|end
BASE=/var/lib/webosbrew/rawin-launcher-home
LOG=$BASE/native-trial.log
OUT=/tmp/homebar-native-trial.txt
HOMEAPP=/usr/palm/applications/com.webos.app.home
EXE=/usr/bin/com.webos.app.home
# webOS 6: Homebar runs in place of Home's program, and sam keeps calling
# Home a native app (home-takeover.sh).
EXE_MODE=
grep -qE 'release 6\.' /etc/starfish-release && EXE_MODE=1

log() { echo "$(date '+%H:%M:%S') up=$(cut -d' ' -f1 /proc/uptime) $*" >>"$LOG"; }
luna() { luna-send -n 1 "$1" "$2" </dev/null 2>/dev/null; }
home_type() { luna luna://com.webos.applicationManager/getAppInfo '{"id":"com.webos.app.home"}' | tr -d '\n ' | sed -n 's/.*"type":"\([a-z]*\)".*/\1/p' | head -n 1; }
# A qml-runner started for the Home id: what SAM runs for a QML Home.
qml_hosts() {
    for cmd in /proc/[0-9]*/cmdline; do
        args=$({ tr '\000' ' ' <"$cmd"; } 2>/dev/null) || continue
        case "$args" in /usr/bin/qml-runner\ *) ;; *) continue ;; esac
        printf '%s' "$args" | grep -qE '"appId"[[:space:]]*:[[:space:]]*"com\.webos\.app\.home"' && echo "${cmd#/proc/}"
    done | sed 's#/cmdline##'
}
snapshot() {
    echo "-- $1"
    echo "type: $(home_type)"
    luna luna://com.webos.applicationManager/getAppInfo '{"id":"com.webos.app.home"}' | tr -d '\n ' | grep -o '"\(main\|folderPath\|vendor\|version\|systemApp\|visible\|nativeLifeCycleInterfaceVersion\)":[^,]*' | tr '\n' ' '; echo
    grep -F " $HOMEAPP " /proc/mounts || echo "no mount over $HOMEAPP"
    grep -F " $EXE " /proc/mounts || echo "no mount over $EXE"
    echo "Home programs running: $(pidof com.webos.app.home 2>/dev/null || echo none)"
    echo "Home dir inode: $(ls -di "$HOMEAPP" 2>/dev/null)"
    echo "qml-runner hosts for the Home id: $(qml_hosts | tr '\n' ' ')"
    echo "foreground: $(luna luna://com.webos.applicationManager/getForegroundAppInfo '{"extraInfo":true}' | tr -d '\n ' | grep -o '"\(appId\|windowType\)":"[^"]*"' | tr '\n' ' ')"
}
case "${1:-}" in
  begin)
    mkdir -p "$BASE"; : >"$LOG"
    {
        echo "Homebar native Home trial"
        echo "date: $(date)"
        echo "homebar: $(cat "$BASE/VERSION" 2>/dev/null || cat "$(dirname "$0")/../VERSION" 2>/dev/null)"
        echo "release: $(cat /etc/starfish-release 2>/dev/null | head -n 2 | tr '\n' ' ')"
        echo "model: $(luna luna://com.webos.service.tv.systemproperty/getSystemInfo '{"keys":["modelName","firmwareVersion","sdkVersion"]}' | tr -d '\n ')"
        echo "uname: $(uname -a)"
        echo "qml-runner: $(ls -l /usr/bin/qml-runner 2>&1 | head -n 1)"
        echo "node: $(node -v 2>&1)"
        echo "Input Hook: $([ -d /media/developer/apps/usr/palm/applications/org.webosbrew.inputhook ] && echo installed || echo no)"
        echo "Glasshouse Home: $(grep -c '"enabled"[[:space:]]*:[[:space:]]*true' /var/lib/tvweb/home.json 2>/dev/null)  Luma takeover: $(grep -c '"enabled"[[:space:]]*:[[:space:]]*true' /var/lib/luma-home/state.json 2>/dev/null)"
        # What decides whether Homebar can run as Home's program (webOS 6).
        echo "Home program: $(ls -l "$EXE" 2>&1 | head -n 1)"
        echo "qml-runner takes --main: $(grep -a -c -e '--main' /usr/bin/qml-runner 2>/dev/null)"
        echo "Home in the bus roles: $(grep -rl 'com\.webos\.app\.home' /usr/share/luna-service2 /usr/share/ls2 2>/dev/null | head -n 8 | tr '\n' ' ')"
        echo "qml-runner in the bus roles: $(grep -rl 'qml-runner\|qmlrunner' /usr/share/luna-service2 /usr/share/ls2 2>/dev/null | head -n 8 | tr '\n' ' ')"
        echo "Home's saved image: $(ls -d /mnt/lg/cmn_data/checkpoint/com.webos.app.home /tmp/checkpoint/com.webos.app.home 2>/dev/null | tr '\n' ' ')"
        snapshot "Home before"
    } >>"$LOG" 2>&1
    ;;
  verify)
    # SAM has to report a QML Home and a qml-runner has to run it; on webOS 6
    # SAM still reports LG's native Home, and the qml-runner is what counts.
    n=0; ok=
    while [ "$n" -lt 25 ]; do
        if { [ -n "$EXE_MODE" ] || [ "$(home_type)" = qml ]; } && [ -n "$(qml_hosts)" ]; then ok=1; break; fi
        n=$((n + 1)); sleep 1
    done
    { log "verify: type=$(home_type) hosts=$(qml_hosts | tr '\n' ' ') after ${n}s -> $([ -n "$ok" ] && echo PASS || echo FAIL)"
      snapshot "Home after"; } >>"$LOG" 2>&1
    [ -n "$ok" ]
    ;;
  end)
    # One file to attach to the report.
    {
        cat "$LOG" 2>/dev/null
        echo; echo "-- boot log"; tail -n 40 /tmp/rawin-launcher-boot.log 2>/dev/null
        echo; echo "-- Homebar's QML host output (/tmp/homebar-home-qml.log)"
        tail -n 60 /tmp/homebar-home-qml.log 2>/dev/null
        echo; echo "-- Home windows (compositor)"
        { logread 2>/dev/null || cat /var/log/messages 2>/dev/null; } | grep -E 'surfaceItem_com\.webos\.app\.home|Swap fullscreen' | grep -v keyPressEvent | tail -n 15
        echo; echo "-- system log (Home, SAM, qml)"
        { logread 2>/dev/null || cat /var/log/messages 2>/dev/null; } | grep -i -E 'com\.webos\.app\.home|qml-runner|qmlrunner|LSRegister|rawin' | grep -v -E 'keyPressEvent|LS_DEPRECATED|sdx\.logging|NUDGE|pqcontroller|videooutputd|eplmanager|AudioD|memchute|miracast|airplay' | tail -n 80
    } >"$OUT" 2>&1
    echo "$OUT"
    ;;
  *) echo "usage: $0 begin|verify|end" >&2; exit 2 ;;
esac
