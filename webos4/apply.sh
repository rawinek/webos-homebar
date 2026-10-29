#!/bin/sh
# rawin-launcher (webOS 4) boot hook, also run by install.sh. Bind-mounts the
# patched LG Home QML (main.qml, Controllers/UIController.qml) from
# /var/lib/webosbrew/rawin-launcher over the firmware files and restarts only
# the Home process. The read-only rootfs is not changed; a reboot without this
# hook gives LG's Home back. Then it starts the setup server for the weather.
set -eu
# Finish the caller's exec request before ending the Home process that sent it.
# SAM also needs time to retire that process before a launch can start a new one.
if [ "${1:-}" = --restart ]; then
    setsid sh "$0" --reopen </dev/null >/tmp/rawin-launcher-restart.log 2>&1 &
    exit 0
fi
[ "${1:-}" != --reopen ] || sleep 1
base=/var/lib/webosbrew/rawin-launcher
# The system log and, with the seconds since boot, the launcher's boot log
# (cleared with /tmp at every boot; diagnose.sh shows it).
log() { logger -t rawin-launcher "$1"; echo "$(cut -d' ' -f1 /proc/uptime)s $1" >>/tmp/rawin-launcher-boot.log; }
root=/usr/palm/applications/com.webos.app.home/qml
main=$root/main.qml
ctrl=$root/Controllers/UIController.qml
[ -f "$ctrl" ] || ctrl=$root/UserInterfaceLayer/UIController.qml

# Mount each file unless it is already ours; refuse firmware files that are
# neither ours nor the originals the patch was made from (after an update).
mount_patched() {
    target=$1; ours=$2; original=$3
    cmp -s "$target" "$ours" && return 0
    if ! cmp -s "$target" "$original"; then
        log "LG Home changed ($target); original Home kept"
        return 1
    fi
    mount -o bind "$ours" "$target"
}
mount_patched "$main" "$base/main.qml" "$base/main.original.qml" || exit 0
if ! mount_patched "$ctrl" "$base/UIController.qml" "$base/UIController.original.qml"; then
    umount "$main"
    exit 0
fi

# LG Home starts from a CRIU snapshot that already holds the original QML in
# memory; hide Home's snapshot directories so it starts from the files.
mkdir -p "$base/no-checkpoint"
for target in /mnt/lg/cmn_data/checkpoint/com.webos.app.home /tmp/checkpoint/com.webos.app.home; do
    if [ -d "$target" ] && ! grep -qF " $target " /proc/mounts; then
        mount -o bind "$base/no-checkpoint" "$target"
        mount -o remount,bind,ro "$target"
    fi
done

# Stop Home only; the next HOME starts it with the patched QML.
for pid in $(pidof com.webos.app.home || true); do kill -KILL "$pid" || true; done
log 'panel applied to LG Home'

# The setup server: the weather in the status chip and the page to choose its
# place (shared/setup.js) on port 8898. One at a time: an older one goes first.
if [ -f "$base/setup/setup.js" ]; then
    # The pid file survives a reboot, and a number from before it can belong to
    # anything now: only a node running our setup.js is stopped.
    pid=$(cat "$base/setup.pid" 2>/dev/null || true)
    case "$pid" in ''|*[!0-9]*) ;; *)
        case "$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)" in *setup/setup.js*) kill "$pid" 2>/dev/null || true ;; esac ;;
    esac
    setsid node "$base/setup/setup.js" "$base" </dev/null >/dev/null 2>&1 &
    log 'setup server started'
fi

if [ "${1:-}" = --reopen ]; then
    for attempt in 1 2 3 4 5; do
        sleep 1
        luna-send -n 1 luna://com.webos.applicationManager/launch '{"id":"com.webos.app.home","params":{"activateType":"home","launchType":"homeKey"}}' </dev/null
        sleep 1
        if pidof com.webos.app.home >/dev/null; then
            # LG may treat the cold launch as preload. Once the host is running,
            # a warm launch shows its window without synthesising a HOME toggle.
            luna-send -n 1 luna://com.webos.applicationManager/launch '{"id":"com.webos.app.home","params":{"activateType":"home","launchType":"homeKey"}}' </dev/null
            log 'Homebar reopened after restart'
            exit 0
        fi
    done
    log 'Homebar restart: launch failed; press HOME to retry'
    exit 1
fi
