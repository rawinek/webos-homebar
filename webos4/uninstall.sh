#!/bin/sh
# rawin-launcher (webOS 4): give LG Home back and remove the launcher.
BASE=/var/lib/webosbrew/rawin-launcher
ROOT=/usr/palm/applications/com.webos.app.home/qml
for f in "$ROOT/main.qml" "$ROOT/Controllers/UIController.qml" "$ROOT/UserInterfaceLayer/UIController.qml"; do
    if grep -qF " $f " /proc/mounts; then umount "$f"; fi
done
# Unhide Home's CRIU snapshots, unless another hook still wants them hidden.
if ! ls /var/lib/webosbrew/init.d/ 2>/dev/null | grep -q home-tuning; then
    for target in /mnt/lg/cmn_data/checkpoint/com.webos.app.home /tmp/checkpoint/com.webos.app.home; do
        if grep -qF " $target " /proc/mounts; then umount -l "$target"; fi
    done
fi
rm -f /var/lib/webosbrew/init.d/76-rawin-launcher
# The setup server (weather), started by apply.sh.
# (the pid file survives a reboot: only a node running our setup.js is stopped)
pid=$(cat "$BASE/setup.pid" 2>/dev/null)
case "$pid" in ''|*[!0-9]*) ;; *)
    case "$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null)" in *setup/setup.js*) kill "$pid" 2>/dev/null ;; esac ;;
esac
rm -rf "$BASE"
# Favourites and settings: the "rawinLauncher" LocalStorage database in LG Home's
# data (Qt names the files after the MD5 of the database name).
rm -f /home/root/.local/share/com.webos.app.home/QML/OfflineStorage/Databases/9969c85c6e1c20a73a4ac456d46e31f7.*
for pid in $(pidof com.webos.app.home); do kill -KILL "$pid"; done
echo "rawin-launcher: removed; LG Home is back (press HOME)."
