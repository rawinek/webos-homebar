# Troubleshooting

- [Diagnose](#diagnose)
- [HOME does nothing (System HOME)](#home-does-nothing-system-home)
- [HOME does nothing (overlay)](#home-does-nothing-overlay)
- [HOME right after a boot opens LG's Home (overlay)](#home-right-after-a-boot-opens-lgs-home-overlay)
- [An update fails](#an-update-fails)
- [An untested webOS](#an-untested-webos)
- [Getting LG's Home back](#getting-lgs-home-back)

## Diagnose

`diagnose.sh` collects what is needed to look into a problem into one file:

```sh
sh /var/lib/webosbrew/rawin-launcher/diagnose.sh        # Home panel
sh /var/lib/webosbrew/rawin-launcher-home/diagnose.sh   # overlay
sh rawin-launcher/diagnose.sh                           # from the unpacked release
```

`No such file or directory` means that this copy was installed before
`diagnose.sh` was included, or that the other variant's path was used. Find
an installed copy with:

```sh
find /var/lib/webosbrew -maxdepth 2 -name diagnose.sh -print
```

Run the path it prints. If it prints nothing, unpack the current release and
run `sh rawin-launcher/diagnose.sh` from its parent directory.

It writes `/tmp/rawin-launcher-diagnose.txt`: the TV model, webOS and firmware
versions, whether the screen is UHD, which variant fits (`probe.sh`, next to
`diagnose.sh` in the release and in the installed copy), what is installed
and whether the patched Home QML is in place, what the launcher sees (apps,
inputs with their device names, the app on screen), the HOME button binding,
the boot log (`/tmp/rawin-launcher-boot.log`: what the boot hook did, with the
seconds since boot) and the launcher's lines from the system log. No IP addresses, serial numbers or
accounts. Copy it to a computer with
`ssh root@<tv-ip> cat /tmp/rawin-launcher-diagnose.txt > diagnose.txt`
and attach it to an [issue](https://github.com/rawinek/webos-homebar/issues).

`probe.sh` on its own says which variant fits and why, and changes nothing:
`sh /var/lib/webosbrew/rawin-launcher/probe.sh` (or `…/rawin-launcher-home/probe.sh`,
or `sh rawin-launcher/probe.sh` from the release).

## HOME opens LG's Home, not Homebar (Home panel)

On a webOS 4 or 5 TV with two Homes (see
[Compatibility](compatibility.md#webos-versions)) the TV's *Home screen*
setting has to be *Basic*. With *New*, HOME opens LG's full-screen Home
(`com.webos.app.fullhome`) and the panel, which lives in the Basic Home,
never shows. Set it to *Basic*; nothing needs to be installed again.
`diagnose.sh` shows which Home is running (*Home running*).

## With Glasshouse (overlay)

Homebar and [Glasshouse](https://github.com/rorygallagher2024/glasshouse)'s
Home both want the HOME button. With Glasshouse's Home switched on, Homebar
leaves Home to it: no black stand-in, and from 0.15.3 the helper no longer
switches the TV to an input when Glasshouse's Home comes up (before, it
flashed and went to HDMI 1). HOME opens Homebar only while Input Hook has
it; if HOME opens Glasshouse instead, `diagnose.sh` shows what Input Hook
does with the key (*HOME button (Input Hook)*).

## HOME does nothing (System HOME)

On webOS 10 and 11 (and the trial on 6 to 9) HOME is Homebar's own Home. If it
shows LG's Home, nothing, or a black screen:

- `sh /var/lib/webosbrew/rawin-launcher-home/takeover.sh status` says whether
  the Homebar host is mounted ("stand-in mounted") or LG's Home is. The same
  folder's `diagnose.sh` shows the mode, the Home owner and the boot log.
- **Restart the TV.** The app manager keeps what it read about Home until it
  restarts; if a switch between methods went wrong, a restart clears it.
- Another launcher owning HOME (Glasshouse's or Luma's Home switched on)
  blocks System HOME; *Launcher settings → Launch method* says so. Use the
  additional overlay, or switch their takeover off first.
- Switch back in *Launcher settings → Launch method*, or run the
  [uninstaller](install.md#uninstall); both give LG's Home back.

## HOME does nothing (overlay)

In the additional overlay HOME stays with LG on purpose: open Homebar from its
app tile, or from the button you chose in *Launcher settings → Help → Remote
button* (or mapped by hand in Input Hook or Magic Mapper to launch
`org.rawin.launcher`). If that button does nothing, check that the mapper runs
and reads the remote: the popup says so when Homebar saves it. The rest of this section is for HOME via Input Hook.

Run from a terminal, the installer asks for a press of HOME and binds the
key Input Hook logs for it; without a press, or from the panel's updater, it
binds `773`, the HOME button of the tested Magic Remote. If HOME does
nothing, run the installer again from a terminal with
`sh install.sh --overlay --home-key=ask` and press HOME when asked, or read
the code from Input Hook's log (`/tmp/lginput-hook-*.log`) after a press and
give it with `--home-key=CODE`.

## HOME right after a boot opens LG's Home (overlay)

The Homebrew Channel runs its boot hooks some 35 s into a boot, and
nothing of the launcher's runs before them. The launcher's hook is named to
run among the first and starts Input Hook as its first step, so HOME
reaches the panel a few seconds after the hooks begin: on the tested B4
the TV shows its input from about 20 s, the hooks begin at 35 to 37 s and
the first HOME that reached the panel came at 42 s. A HOME before that
opens LG's Home once; it is stopped when the stand-in takes its place a
moment later, and the TV goes back to the input. A TV woken from standby
does not boot, so this is only seen after a power cut, a `reboot` or a
firmware update. The boot log in `diagnose.sh` shows when each step ran.

## No weather in the chip

- *Launcher settings → Weather* has to be *Shown*. Without an internet
  connection the chip leaves the weather out until one is there.
- `diagnose.sh` shows whether the setup server on port 8898 answers
  (*Weather (setup server)*). With the Home panel it starts at boot, or
  again with `sh /var/lib/webosbrew/rawin-launcher/apply.sh`; with the
  overlay the helper runs it.
- The phone page does not open: the phone has to be on the same network as
  the TV, and some routers (guest networks, "AP isolation") keep devices
  apart. A page that says it has expired is from before the TV's last
  restart: scan the code again.

## An update fails

The panel says which step failed (check, download or install) and OK tries
again. The installer's output is in `/tmp/rawin-launcher-update/install.log`.
The [manual update](install.md#by-hand-any-version-and-once-from-before-0100)
works for any version.

## An untested webOS

`sh install.sh --probe` (or `probe.sh`, see [Diagnose](#diagnose)) says
which method fits the TV and why, before anything is changed;
`--home-panel`, `--native-home`, `--additional-overlay` and `--overlay` force one;
`--try-native-home` tries System HOME on webOS 6 to 9 and writes
`/tmp/homebar-native-trial.txt` to attach to an issue. What can happen on a webOS that
was never tested:

- **The installer finds no variant.** It says what is missing for each: a
  Home that is not a QML app, or whose files differ too much for the patch;
  for the overlay the Homebrew Channel, Input Hook or a node older than 8.
- **Home panel: LG's ribbon shows instead of the panel**, with a *BLUE · back
  to Homebar* badge in the corner. The panel failed to load; LG's Home is
  still usable. `diagnose.sh` has the error lines; the overlay may work
  instead (`sh install.sh --overlay`, after `uninstall.sh`).
- **Home panel: the panel shows but something of LG's stays in the way**
  (a voice prompt, LG's ribbon on a hidden-mode change). The patch reported
  those pieces as skipped at install time; an issue with the install output
  and `diagnose.sh` helps.
- **Overlay: HOME does nothing.** See [above](#home-does-nothing-overlay).
- **Overlay: the panel is empty or says the helper is not answering.**
  `luna-send -n 1 luna://org.rawin.launcher.service/ping '{}'` and
  `wget -q -O - http://127.0.0.1:8899/ping` show whether the helper runs;
  `diagnose.sh` has its answers and its event list, and the boot log says
  whether the boot hook found it.
- **Overlay with `--replace-lg-home`: the app manager does not take the
  stand-in.** The script unmounts it and leaves LG's Home; nothing is lost.

Whatever happens, `uninstall.sh` gives LG's Home and the HOME button back.

## Getting LG's Home back

- The [uninstaller](install.md#uninstall) gives LG's Home and the HOME button
  back at once.
- Home panel: deleting `/var/lib/webosbrew/init.d/76-rawin-launcher` and
  rebooting gives LG's Home back, since the bind mounts end with a reboot.
- System HOME: *Launcher settings → Launch method → Additional overlay*, or
  `sh /var/lib/webosbrew/rawin-launcher-home/native-home.sh disable`; then
  restart the TV if Home still looks wrong.
- Overlay: `sh /var/lib/webosbrew/rawin-launcher-home/takeover.sh restore`
  gives LG's Home back until the next boot; `takeover.sh status` shows which
  Home the TV has. If the app manager does not accept the stand-in, the script
  unmounts it and leaves LG's Home.
- If a boot hook ever crashes the start-up, the Homebrew Channel's failsafe mode
  skips all hooks on the next boot.
