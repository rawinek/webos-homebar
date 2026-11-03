#!/bin/sh
# rawin-launcher: remove whichever variant is installed. Run on the TV as root.
# A variant's own script that fails is a failed uninstall: say so in the exit code.
found= failed=
for u in /var/lib/webosbrew/rawin-launcher/uninstall.sh /var/lib/webosbrew/rawin-launcher-home/uninstall.sh; do
    if [ -f "$u" ]; then sh "$u" || failed=1; found=1; fi
done
[ -n "$found" ] || echo "rawin-launcher: not installed."
[ -z "$failed" ] || { echo "rawin-launcher: uninstall did not finish; see the message above." >&2; exit 1; }
