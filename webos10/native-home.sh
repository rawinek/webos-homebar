#!/bin/sh
# Experimental direct Home on webOS 10/11 (and a trial on 6 to 9). No Input Hook, no native UI rewrite:
# SAM starts the TV's QML runner under the Home identity. Restore is explicit.
set -eu
BASE=/var/lib/webosbrew/rawin-launcher-home
# During an upgrade, check with the incoming module before it is installed.
INTEGRATION=$(cd "$(dirname "$0")" && pwd)/integration.js
APP=/media/developer/apps/usr/palm/applications/org.rawin.launcher
HOME_ID=com.webos.app.home
DB=9969c85c6e1c20a73a4ac456d46e31f7
STORE=/home/root/.local/share
luna() { luna-send -n 1 "luna://com.webos.applicationManager/$1" "$2" </dev/null; }
# webOS 10/11, or 6 to 9 where the owner started the trial (install.sh --try-native-home).
native_ok() { grep -qE 'release (10|11)\.' /etc/starfish-release || { [ -f "$BASE/native-trial" ] && grep -qE 'release (6|7|8|9)\.' /etc/starfish-release; }; }
stop_panels() {
    mode=${1:-all}
    # Directory identity alone misses another launcher's nested/binary mount.
    if [ "$mode" = all ]; then
      case "$(node "$INTEGRATION" owner)" in lg|native|legacy) ;; *) mode=overlay ;; esac
    fi
    # "home" is the sweep after LG's Home was given back: only a QML host that
    # SAM preloaded from the stand-in just before the unmount may still run.
    if [ "$mode" != home ]; then luna closeByAppId '{"id":"org.rawin.launcher"}' >/dev/null 2>&1 || true; fi
    if [ "$mode" = all ]; then luna closeByAppId '{"id":"com.webos.app.home"}' >/dev/null 2>&1 || true; fi
    # System Home can survive closeByAppId. Match only our two QML hosts,
    # never another application or the firmware's native/Flutter launcher.
    for cmd in /proc/[0-9]*/cmdline; do
        args=$({ tr '\000' ' ' <"$cmd"; } 2>/dev/null) || continue
        case "$args" in /usr/bin/qml-runner\ *) ;; *) continue ;; esac
        if printf '%s' "$args" | grep -qE '"appId"[[:space:]]*:[[:space:]]*"(com\.webos\.app\.home|org\.rawin\.launcher)"'; then
            if [ "$mode" = overlay ] && ! printf '%s' "$args" | grep -q '"org.rawin.launcher"'; then continue; fi
            if [ "$mode" = home ] && ! printf '%s' "$args" | grep -q 'com.webos.app.home'; then continue; fi
            pid=${cmd#/proc/}; pid=${pid%/cmdline}
            kill "$pid" 2>/dev/null || true
            sleep 1
            [ ! -f "$cmd" ] || kill -KILL "$pid" 2>/dev/null || true
        fi
    done
}
copy_store() {
    src=$STORE/$1/QML/OfflineStorage/Databases
    dst=$STORE/$2/QML/OfflineStorage/Databases
    [ -f "$src/$DB.sqlite" ] || return 0
    mkdir -p "$dst"
    # Keep a rollback copy before replacing only Homebar's database, not any
    # other data owned by LG Home. Both processes are stopped during copying.
    for suffix in sqlite ini sqlite-journal sqlite-wal sqlite-shm; do
        if [ ! -f "$src/$DB.$suffix" ]; then
            case "$suffix" in sqlite-*) rm -f "$dst/$DB.$suffix" ;; esac
            continue
        fi
        if [ -f "$dst/$DB.$suffix" ]; then cp -p "$dst/$DB.$suffix" "$BASE/before-native-$2.$suffix"; fi
        cp -p "$src/$DB.$suffix" "$dst/$DB.$suffix"
    done
}
case "${1:-status}" in
  check-owner) node "$INTEGRATION" check ;;
  enable) exec sh "$BASE/mode-switch.sh" native ;;
  activate)
    native_ok || { echo 'Native Home currently supports webOS 10/11 only' >&2; exit 1; }
    [ ! -f "$BASE/keep-lg-home" ] || { echo 'Disable keep-lg-home before enabling native Home' >&2; exit 1; }
    trial=
    grep -qE 'release (10|11)\.' /etc/starfish-release || trial=1
    [ -z "$trial" ] || sh "$BASE/native-trial.sh" begin
    was_native=
    [ ! -f "$BASE/native-home" ] || was_native=1
    # Check ownership before stopping any system Home host.
    sh "$0" check-owner
    stop_panels
    if [ ! -f "$BASE/native-home" ]; then
      sh "$BASE/takeover.sh" restore
      copy_store org.rawin.launcher "$HOME_ID"
    fi
    node "$BASE/native-stage.js" "$APP" "$BASE/native-app"
    touch "$BASE/native-home"
    if ! sh "$BASE/takeover.sh" apply; then
      sh "$BASE/takeover.sh" restore || true
      rm -f "$BASE/native-home"
      echo 'Native Home failed; LG Home restored. Input Hook mapping was not changed.' >&2
      exit 1
    fi
    luna launch '{"id":"com.webos.app.home"}' | grep -q '"returnValue": *true'
    launched=$?
    # On a webOS where this is only a trial, SAM has to report a QML Home with
    # a running qml-runner, or LG Home is given back at once.
    if [ -n "$trial" ] && ! sh "$BASE/native-trial.sh" verify; then
      sh "$BASE/takeover.sh" restore || true
      rm -f "$BASE/native-home"
      echo 'The native Home did not come up on this webOS; LG Home restored.' >&2
      exit 1
    fi
    exit "$launched"
    ;;
  release)
    if [ -f "$BASE/native-home" ]; then
      if [ "$(node "$INTEGRATION" owner)" = native ]; then
        stop_panels
        sh "$BASE/takeover.sh" restore
      else
        stop_panels overlay
      fi
      copy_store "$HOME_ID" org.rawin.launcher
      rm -f "$BASE/native-home"
    fi
    ;;
  disable)
    if [ -f "$BASE/native-home" ]; then
      case "$(node "$INTEGRATION" owner)" in lg|native|legacy) ;; *) echo 'Another or unknown launcher owns Home; disable refused' >&2; exit 1 ;; esac
    fi
    if [ -f "$BASE/native-home" ]; then
      stop_panels
      copy_store "$HOME_ID" org.rawin.launcher
      sh "$BASE/takeover.sh" restore
      rm -f "$BASE/native-home"
      node "$INTEGRATION" restore legacy "$BASE/disable-mapper-journal.json"
      # Restore only our old bindings, without overwriting any new user binding.
      KEYS=/home/root/.config/lginputhook/keybinds.json
      if [ ! -f "$BASE/mapper-backup.json" ] && [ -f "$BASE/keys-before-native.json" ]; then
        node -e 'var fs=require("fs"),f=process.argv[1],b=JSON.parse(fs.readFileSync(process.argv[2],"utf8")),k=fs.existsSync(f)?JSON.parse(fs.readFileSync(f,"utf8")):{};Object.keys(b).forEach(function(c){var v=b[c];if(!k[c]&&require(process.argv[3]).ihOwn(v))k[c]=v;});fs.writeFileSync(f,JSON.stringify(k));' "$KEYS" "$BASE/keys-before-native.json" "$INTEGRATION"
      fi
      sh "$BASE/takeover.sh" apply
      luna launch '{"id":"org.rawin.launcher"}'
    fi
    echo 'Standard overlay restored. Check your mapper configuration before using HOME.'
    ;;
  stop-overlay) stop_panels overlay ;;
  stop-home) stop_panels home ;;
  copy-back) copy_store "$HOME_ID" org.rawin.launcher ;;
  stop) stop_panels ;;
  status) sh "$BASE/takeover.sh" status ;;
  *) echo 'usage: native-home.sh enable|disable|status' >&2; exit 2 ;;
esac
