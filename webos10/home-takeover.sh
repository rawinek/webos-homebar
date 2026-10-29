#!/bin/sh
# rawin-launcher (webOS 10): put a black stand-in in LG Home's place, or
# give LG Home back. Usage: home-takeover.sh apply|restore|status
#
# The stand-in (app/, a black web page under the id com.webos.app.home) is
# bind-mounted over /usr/palm/applications/com.webos.app.home; the read-only
# rootfs is not touched and the mount ends with a reboot (the boot hook applies
# it again). sam reads the app again after a block and release of the one app
# (the same two calls Glasshouse uses on webOS 10), then LG's Flutter Home is
# stopped. From then on everything that opens Home opens the black page and
# the helper goes back to the last input, so LG's launcher never shows.
# No check for webosbrew_failsafe: the Homebrew Channel sets that flag during
# every normal start while it runs the init.d hooks, and in real failsafe mode
# it runs no hooks at all.
HOMEAPP=/usr/palm/applications/com.webos.app.home
BASE=/var/lib/webosbrew/rawin-launcher-home
STAGE=$BASE/app
HOME_TYPE=web
if [ -f "$BASE/native-home" ]; then STAGE=$BASE/native-app; HOME_TYPE=qml; fi
# webOS 6 (trial): sam cannot read a mounted Home again there (it has no
# blockSystemApp), and LG's Home is a native program that sam starts with its
# launch data. The program is what gets replaced: a script bind-mounted over
# it runs the TV's qml-runner on the staged QML host with that same data.
# qml-runner calls sam on the app's behalf under its own bus name, so the
# role tied to LG's program does not matter.
EXE=/usr/bin/com.webos.app.home
WRAPPER=$BASE/home-exe
EXE_MODE=
if [ -f "$BASE/native-home" ] && grep -qE 'release 6\.' /etc/starfish-release; then EXE_MODE=1; fi
CHECKPOINTS="/mnt/lg/cmn_data/checkpoint/com.webos.app.home /tmp/checkpoint/com.webos.app.home"
TAG=rawin-launcher
# The system log and, with the seconds since boot, the launcher's boot log
# (cleared with /tmp at every boot; diagnose.sh shows it).
log() { logger -t $TAG "$1"; echo "$(cut -d' ' -f1 /proc/uptime)s $1" >>/tmp/rawin-launcher-boot.log; }

inode() { ls -di "$1" 2>/dev/null | awk '{print $1}'; }
mounted() {
  if [ -n "$EXE_MODE" ]; then
    [ -n "$(inode "$WRAPPER")" ] && [ "$(inode "$EXE")" = "$(inode "$WRAPPER")" ] || return 1
    [ ! -f "$BASE/integration.js" ] || [ "$(node "$BASE/integration.js" owner)" = native ]
    return
  fi
  [ -n "$(inode "$STAGE")" ] && [ "$(inode "$HOMEAPP")" = "$(inode "$STAGE")" ] || return 1
  # A later nested/binary mount can replace Home while its directory stays ours.
  [ ! -f "$BASE/integration.js" ] || case "$(node "$BASE/integration.js" owner)" in native|legacy) return 0 ;; *) return 1 ;; esac
}

luna() { luna-send -n 1 "luna://com.webos.applicationManager/$1" "$2" 2>/dev/null; }
ok() { grep -q '"returnValue": *true'; }

# sam reads one system app again after it is blocked and released; the release
# is sent whatever the block answered, so Home is never left blocked.
reread() {
  luna blockSystemApp '{"id":"com.webos.app.home"}' >/dev/null
  for _ in 1 2 3; do
    luna releaseBlockSystemApp '{"id":"com.webos.app.home"}' | ok && return 0
    sleep 1
  done
  return 1
}

# Whether sam reports Home's type as $1 within 20 s.
home_type_is() {
  for _ in $(seq 20); do
    luna getAppInfo '{"id":"com.webos.app.home"}' | grep -q "\"type\": *\"$1\"" && return 0
    sleep 1
  done
  return 1
}

# LG's own Home process: flutter-client running the Home id (webOS 10), or
# the QML Home's own process on a webOS where Home is a QML app and the
# overlay was chosen anyway. The stand-in itself runs in the web app manager.
lg_home_pids() {
  for cmd in /proc/[0-9]*/cmdline; do
    { tr '\0' ' ' < "$cmd"; } 2>/dev/null | grep -q '^/usr/bin/flutter-client .*-i com\.webos\.app\.home ' || continue
    pid=${cmd#/proc/}
    echo "${pid%/cmdline}"
  done
  pidof com.webos.app.home 2>/dev/null | tr ' ' '\n'
}

# The program sam starts for Home on webOS 6, and LG's saved image of its
# running Home (CRIU), which sam would restore instead of starting anything:
# an empty folder is mounted over each image folder while Homebar is Home.
write_wrapper() {
  cat >"$WRAPPER" <<EOF
#!/bin/sh
# Homebar (webOS 6 trial): sam starts this in place of LG Home's program, with
# its launch data; qml-runner runs Homebar's QML host with that data instead.
exec /usr/bin/qml-runner --main file://$STAGE/main.qml "\$@" >>/tmp/homebar-home-qml.log 2>&1
EOF
  chmod 755 "$WRAPPER"
}
hide_checkpoints() {
  mkdir -p "$BASE/no-checkpoint"
  for target in $CHECKPOINTS; do
    [ -d "$target" ] || continue
    grep -qF " $target " /proc/mounts || mount -o bind "$BASE/no-checkpoint" "$target"
  done
}
show_checkpoints() {
  for target in $CHECKPOINTS; do
    if [ "$(inode "$target")" = "$(inode "$BASE/no-checkpoint")" ]; then umount "$target" 2>/dev/null; fi
  done
}

case "$1" in
  apply)
    [ -f "$STAGE/appinfo.json" ] || exit 0
    if [ -f "$BASE/native-home" ]; then node "$BASE/integration.js" check || exit 1; fi
    # Installed with --keep-lg-home: LG's Home stays.
    [ -e "$BASE/keep-lg-home" ] && exit 0
    if grep -q '"enabled"[[:space:]]*:[[:space:]]*true' /var/lib/tvweb/home.json 2>/dev/null; then
      log 'Glasshouse Home is on: LG Home left to it'
      exit 0
    fi
    if [ -f "$BASE/integration.js" ]; then
      case "$(node "$BASE/integration.js" owner)" in lg|native|legacy) ;; *) log 'another or unknown Home owner; refusing takeover'; exit 1 ;; esac
    fi
    # sam answers only once it is up (at boot this hook runs early).
    for _ in $(seq 60); do luna getAppInfo '{"id":"com.webos.app.home"}' | ok && break; sleep 2; done
    log 'stand-in: app manager up'
    if [ -n "$EXE_MODE" ]; then
      if ! mounted && grep -qE " ($EXE|$HOMEAPP)(/[^ ]*)? " /proc/mounts; then
        log 'another Home mount is present; refusing takeover'
        exit 1
      fi
      [ -x /usr/bin/qml-runner ] && [ -f "$STAGE/main.qml" ] || { log 'no qml-runner or no staged host: LG Home kept'; exit 1; }
      if ! mounted; then
        write_wrapper
        hide_checkpoints
        mount --bind "$WRAPPER" "$EXE" || { show_checkpoints; log 'mount over the Home program failed: LG Home kept'; exit 1; }
      fi
      # LG's running Home goes; sam starts the program again when Home is
      # next asked for, and that is now the script.
      for pid in $(pidof com.webos.app.home 2>/dev/null); do kill "$pid" 2>/dev/null; done
      log 'qml Homebar in place of the Home program'
      exit 0
    fi
    # Never stack a takeover over an unrelated launcher or a different mode.
    if ! mounted && grep -qF " $HOMEAPP " /proc/mounts; then
      log 'another Home mount is present; refusing takeover'
      exit 1
    fi
    # The type LG's Home has (flutter on webOS 9 to 11, qml before): what restore waits for.
    mounted || [ -f "$BASE/home-type-orig" ] || luna getAppInfo '{"id":"com.webos.app.home"}' | tr -d '\n ' | sed -n 's/.*"type":"\([a-z]*\)".*/\1/p' | head -n 1 >"$BASE/home-type-orig"
    mounted || mount --bind "$STAGE" "$HOMEAPP" || { log 'mount failed: LG Home kept'; exit 1; }
    if reread && home_type_is "$HOME_TYPE"; then
      for pid in $(lg_home_pids); do kill "$pid" 2>/dev/null; done
      log "$HOME_TYPE Homebar in LG Home place"
    else
      umount "$HOMEAPP" 2>/dev/null
      reread
      log 'sam did not take the stand-in: LG Home kept'
      exit 1
    fi
    ;;
  restore)
    # Never close or reread a Home instance owned by a different launcher.
    mounted || exit 0
    if [ -n "$EXE_MODE" ]; then
      # Stopped before and after the unmount: sam may start the script again
      # in between (it preloads Home), and only LG's program may remain.
      sh "$BASE/native-home.sh" stop
      umount "$EXE" || exit 1
      sh "$BASE/native-home.sh" stop-home
      show_checkpoints
      luna closeByAppId '{"id":"com.webos.app.home"}' >/dev/null
      log 'LG Home program given back'
      exit 0
    fi
    # SAM's preload manager can respawn the QML host between stopping it and
    # unmounting its files. Block Home first, then stop again under that block.
    # Releasing below happens only after the original manifest is visible.
    luna blockSystemApp '{"id":"com.webos.app.home"}' >/dev/null
    [ ! -f "$BASE/native-home" ] || sh "$BASE/native-home.sh" stop
    if mounted && ! umount "$HOMEAPP"; then reread; exit 1; fi
    reread || exit 1
    orig=$(cat "$BASE/home-type-orig" 2>/dev/null); [ -n "$orig" ] || orig=flutter
    home_type_is "$orig"
    [ ! -f "$BASE/native-home.sh" ] || sh "$BASE/native-home.sh" stop-home
    # The black page may still run in the web app manager; sam then takes it for
    # the running Home and every launch of Home waits on it. Close it there.
    luna-send -n 1 luna://com.webos.service.webappmanager/killApp '{"appId":"com.webos.app.home"}' </dev/null >/dev/null 2>&1
    luna closeByAppId '{"id":"com.webos.app.home"}' >/dev/null
    log 'LG Home given back'
    ;;
  status)
    if mounted; then echo "stand-in mounted$([ -n "$EXE_MODE" ] && echo ' over the Home program')"; else echo "LG Home"; fi
    luna getAppInfo '{"id":"com.webos.app.home"}' | grep -o '"type": *"[a-z]*"'
    echo "LG Home pids: $(lg_home_pids | tr '\n' ' ')"
    ;;
  *)
    echo "usage: $0 apply|restore|status" >&2
    exit 2
    ;;
esac
