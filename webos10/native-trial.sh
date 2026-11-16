#!/bin/sh
# Experimental System HOME on webOS 6 to 9: a trial that records what the TV did,
# so that a report can say where it stopped. Usage: native-trial.sh begin|verify|end
BASE=/var/lib/webosbrew/rawin-launcher-home
LOG=$BASE/native-trial.log
OUT=/tmp/homebar-native-trial.txt
HOMEAPP=/usr/palm/applications/com.webos.app.home
EXE=/usr/bin/com.webos.app.home
# webOS 6 and 7 (or a sam without blockSystemApp while Home is LG's native
# program): Homebar runs in place of Home's program, and sam keeps calling
# Home a native app. The same choice as in home-takeover.sh.
BLOCK_SCHEMA=/etc/palm/schemas/sam/applicationManager.blockSystemApp.schema
EXE_MODE=
if grep -qE 'release (6|7)\.' /etc/starfish-release; then EXE_MODE=1
elif [ ! -e "$BLOCK_SCHEMA" ] && grep -q '"main"[[:space:]]*:[[:space:]]*"file:///usr/bin/com\.webos\.app\.home"' "$HOMEAPP/appinfo.json" 2>/dev/null; then EXE_MODE=1
fi

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
# A process's command line, its program and state, cut to one line.
proc_line() {
    echo "  pid $1: $({ tr '\000' ' ' <"/proc/$1/cmdline"; } 2>/dev/null | cut -c1-500)"
    echo "    exe: $(readlink "/proc/$1/exe" 2>/dev/null)  $(grep -E '^(State|PPid|Uid):' "/proc/$1/status" 2>/dev/null | tr -s '\t ' ' ' | tr '\n' ' ')"
}
# The parts of a bus role or manifest file that decide who may speak as Home.
role_keys() {
    for f in $(grep -rl "$1" /usr/share/luna-service2 /usr/share/ls2 /etc/luna-service2 2>/dev/null | head -n 12); do
        echo "  $f: $(tr -d '\n\t ' <"$f" 2>/dev/null | grep -o '"\(exeName\|appId\|id\|allowedNames\|type\|trustLevel\|permissions\|outbound\|requiredPermissions\)":\(\[[^]]*\]\|"[^"]*"\)' | head -n 12 | tr '\n' ' ' | cut -c1-600)"
    done
}
snapshot() {
    echo "-- $1"
    echo "type: $(home_type)"
    luna luna://com.webos.applicationManager/getAppInfo '{"id":"com.webos.app.home"}' | tr -d '\n ' | grep -o '"\(main\|folderPath\|vendor\|version\|systemApp\|visible\|nativeLifeCycleInterfaceVersion\)":[^,]*' | tr '\n' ' '; echo
    grep -F " $HOMEAPP " /proc/mounts || echo "no mount over $HOMEAPP"
    grep -F " $EXE " /proc/mounts || echo "no mount over $EXE"
    echo "Home programs running: $(pidof com.webos.app.home 2>/dev/null || echo none)"
    for pid in $(pidof com.webos.app.home 2>/dev/null); do proc_line "$pid"; done
    echo "Home dir inode: $(ls -di "$HOMEAPP" 2>/dev/null)"
    echo "qml-runner hosts for the Home id: $(qml_hosts | tr '\n' ' ')"
    for pid in $(qml_hosts); do proc_line "$pid"; done
    echo "sam running (Home): $(luna luna://com.webos.applicationManager/running '{}' | tr -d '\n ' | grep -o '{[^{}]*"id":"com\.webos\.app\.home"[^{}]*}' | head -n 2 | cut -c1-400)"
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
        # How sam can be made to take another Home here, and which way this
        # trial goes (issue #25: webOS 7 has no blockSystemApp).
        echo "takeover method: $([ -n "$EXE_MODE" ] && echo 'in place of the Home program' || echo 'app folder, sam reads it again')"
        echo "blockSystemApp schema: $([ -e "$BLOCK_SCHEMA" ] && echo present || echo absent)"
        echo "sam schemas: $(ls /etc/palm/schemas/sam 2>/dev/null | grep -i -E 'block|scan|reread|rescan|appinfo|launch' | tr '\n' ' ')"
        echo "sam blockSystemApp call: $(luna luna://com.webos.applicationManager/blockSystemApp '{}' | tr -d '\n' | cut -c1-200)"
        echo "configd blocked-app list: $(luna luna://com.webos.service.config/getConfigs '{"configNames":["profile.blockedAppList"]}' | tr -d '\n' | cut -c1-300)"
        echo "sam preferences: $(ls /var/preferences/com.webos.applicationManager 2>/dev/null | tr '\n' ' ')"
        echo "Home appinfo: $(tr -d '\n' <"$HOMEAPP/appinfo.json" 2>/dev/null | tr -s ' ' | cut -c1-900)"
        echo "Home folder: $(ls "$HOMEAPP" 2>/dev/null | tr '\n' ' ' | cut -c1-300)"
        echo "Home's bus roles (who may speak as Home):"; role_keys 'com\.webos\.app\.home"'
        echo "qml-runner's bus roles:"; role_keys 'qml-runner\|qmlrunner'
        echo "bus hub: $(ls -l /usr/sbin/ls-hubd 2>/dev/null | head -n 1)  api permissions: $(ls -d /usr/share/luna-service2/api-permissions.d 2>/dev/null)"
        echo "qml-runner knows: $(for w in --main @system_native_app interfaceMethod registerApp nativeLifeCycleInterfaceVersion; do printf '%s=%s ' "$w" "$(grep -a -c -e "$w" /usr/bin/qml-runner 2>/dev/null)"; done)"
        echo "Qt: $(ls /usr/lib/libQt5Core.so.5.* 2>/dev/null | head -n 1)"
        echo "Homebar's other Home mounts: $(grep -E ' /usr/(bin/com\.webos\.app\.home|palm/applications/com\.webos\.app\.home)' /proc/mounts | tr '\n' ';')"
        echo "boot hooks: $(ls /var/lib/webosbrew/init.d 2>/dev/null | tr '\n' ' ')"
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
    # A host that dies right after it starts (a refused bus role, a QML
    # error) is a failure too: it has to be there 5 s later.
    if [ -n "$ok" ]; then
        first=$(qml_hosts | tr '\n' ' ')
        sleep 5
        [ -n "$(qml_hosts)" ] || { ok=; log "verify: the host ($first) was gone 5 s later"; }
    fi
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
        echo; echo "-- bus refusals (ls-hubd: Home, qml-runner)"
        { logread 2>/dev/null || cat /var/log/messages 2>/dev/null; } | grep -i -E 'ls-hubd|lshub|LS_REQUIRES|permission|not allowed|denied|no role|security' | grep -i -E 'home|qml' | tail -n 30
        echo; echo "-- system log (Home, SAM, qml)"
        { logread 2>/dev/null || cat /var/log/messages 2>/dev/null; } | grep -i -E 'com\.webos\.app\.home|qml-runner|qmlrunner|LSRegister|rawin' | grep -v -E 'keyPressEvent|LS_DEPRECATED|sdx\.logging|NUDGE|pqcontroller|videooutputd|eplmanager|AudioD|memchute|miracast|airplay' | tail -n 80
    } >"$OUT" 2>&1
    echo "$OUT"
    ;;
  *) echo "usage: $0 begin|verify|end" >&2; exit 2 ;;
esac
