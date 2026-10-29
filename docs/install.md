# Install, update, uninstall

- [Requirements](#requirements)
- [Install](#install)
- [Update](#update)
- [Uninstall](#uninstall)
- [Launch method](#launch-method)
- [Trying System HOME on webOS 7 to 9](#trying-system-home-on-webos-7-to-9)

## Requirements

- A rooted TV with the [Homebrew Channel](https://github.com/webosbrew/webos-homebrew-channel)
  and a root shell (SSH or telnet, enabled in the Homebrew Channel settings).
- **Home panel** (webOS 4 and 5): nothing more; it uses the TV's own node.
- **System HOME** (webOS 10 and 11): node 8 or newer (the TVs have it); no
  Input Hook and no mapper.
- **Additional overlay** (webOS 6 or newer): node 8 or newer. It opens from its
  app tile with nothing else; for a button, Input Hook or Magic Mapper.
- **Overlay with HOME via mapper** (the default on webOS 6 to 9): Input Hook, or
  an existing supported Magic Mapper HOME shortcut to Homebar. Install and open
  Input Hook from the Homebrew Channel first if you do not have it.
- The TV's own `node`, `tar` and `curl`/`wget` (present on the tested TVs).
- For the Home panel on a TV with LG's two Home screens (some 2019 models):
  the TV's *Home screen* setting on *Basic*, see
  [Compatibility](compatibility.md#webos-versions).

Which webOS versions work, and which method a TV gets, is in
[Compatibility](compatibility.md#how-homebar-opens).

## Install

Log in to the TV as root (`ssh root@<tv-ip>`, or `telnet <tv-ip>`), then:

```sh
cd /tmp
curl -fL -o rawin-launcher.tar.gz https://github.com/rawinek/webos-homebar/releases/latest/download/rawin-launcher.tar.gz
rm -rf rawin-launcher && tar xzf rawin-launcher.tar.gz
sh rawin-launcher/install.sh
```

With wget instead of curl: `wget -O rawin-launcher.tar.gz <the same URL>`.
This always takes the latest release; for another one, download
`rawin-launcher.tar.gz` from its page under
[Releases](https://github.com/rawinek/webos-homebar/releases). The installer
says which webOS it found, picks the method the TV has the makings for,
prints each step and ends with "Press HOME on the remote" (additional overlay:
"Open Homebar with your configured button or app tile"). The file and the
folder keep the project's first name, `rawin-launcher`, as do the installed
files (see [How it works → Names](how-it-works.md#names)).

Installer options:

| Option | What it does |
| :--- | :--- |
| `--probe` | Only says which variant fits this TV and why; changes nothing |
| `--home-panel` | The panel inside LG's Home, or fail (no overlay instead). On the full-screen Home of webOS 6 it is experimental and only installed with this flag |
| `--overlay` | The overlay app with the root helper, or fail |
| `--keep-lg-home` | Overlay: leave LG's Home in place; *System → Original Home* opens it |
| `--replace-lg-home` | Overlay on an untested webOS: put the black stand-in in LG Home's place anyway (on webOS 10 it always is) |
| `--native-home` | System HOME on webOS 10/11, without an Input Hook binding. See [Launch method](#launch-method) |
| `--try-native-home` | A trial of System HOME on **webOS 7, 8 or 9** (not 10/11, not 6 or older): it writes a log to report. See [Trying System HOME on webOS 7 to 9](#trying-system-home-on-webos-7-to-9) |
| `--additional-overlay` | Keep the main Home (LG's, Luma's or Glasshouse's); Homebar is added and you map a button to it |
| `--home-key=CODE` | Overlay: bind this key code as HOME (the number Input Hook logs for it) |
| `--home-key=ask` | Overlay: ask for a press of HOME, also when a key is already bound |
| `--home-key-exec` | Overlay: send that press through Input Hook's *Execute* action with `noSplash`/`spinner:false`, so the app manager does not show its loading spinner when the panel has to start. Experimental: Input Hook must be able to run commands, so try it and keep the plain binding if HOME stops opening the panel |
| `--try-webos10` | The same as `--overlay`; older instructions use it |

On the overlay the installer, run from a terminal, asks for a press of HOME
and binds the key Input Hook logs for it (15 s; without a press, the tested
Magic Remote's `773`). An install that finds the launcher already bound to a
key keeps that key; an update from the panel never asks. The panel is started
hidden at boot and kept across HOMEs, and the helper starts it again if the
system closed it, so a HOME is normally a show rather than a start (see
[How it works](how-it-works.md#the-overlay-webos-6-and-later)).

### Without internet on the TV

The download can fail with no internet, or on older TVs that lack current TLS
certificates. Download `rawin-launcher.tar.gz` on a computer and copy it over:

```sh
cat rawin-launcher.tar.gz | ssh root@<tv-ip> 'cat > /tmp/rawin-launcher.tar.gz'
```

then continue on the TV with `tar xzf` and `install.sh` as above.

## Update

Favourites and settings are kept by every update, manual or from the TV, and
so are the variant and the `--keep-lg-home` choice.

### From the TV (0.10.0 and later)

1. Open *System → Launcher settings → Updates*. The launcher checks GitHub
   each time the settings open and shows *Up to date* or *Version x.y.z is
   available*.
2. OK downloads the new release and checks its SHA-256 against the one
   GitHub publishes (*x.y.z downloaded and verified*).
3. A second OK installs it with the same `install.sh` (*Installing x.y.z…*).
   The launcher restarts by itself after a few seconds.

*Launcher settings → Test builds* also offers pre-releases. If a step fails,
the panel says so and OK tries again; the installer's output is in
`/tmp/rawin-launcher-update/install.log`.

Behind the button is `update.sh` next to the installed launcher, run as root
(Home panel: through the Homebrew Channel's `exec` service; overlay: by the
helper). It can also be run by hand, one step at a time:

```sh
sh /var/lib/webosbrew/rawin-launcher/update.sh check   # overlay: /var/lib/webosbrew/rawin-launcher-home/update.sh
sh /var/lib/webosbrew/rawin-launcher/update.sh download
sh /var/lib/webosbrew/rawin-launcher/update.sh install
```

### By hand (any version, and once from before 0.10.0)

Versions before 0.10.0 have no updater, so the first update goes the same way
as the install: log in to the TV as root and run the four
[install commands](#install) again. The installer replaces the old version in
place; nothing needs to be uninstalled first. On the overlay add
`--keep-lg-home` again if it was installed with it. Press HOME afterwards;
*System* shows the new version in its corner, with the TV's webOS and the
variant.

## Uninstall

On the TV, from the unpacked release or the installed copy:

```sh
sh rawin-launcher/uninstall.sh
# or, without the release:
sh /var/lib/webosbrew/rawin-launcher/uninstall.sh        # Home panel
sh /var/lib/webosbrew/rawin-launcher-home/uninstall.sh   # overlay
```

LG's Home and the HOME button are given back at once; nothing needs a reboot.
What the uninstaller removes is listed in
[How it works → What it changes on the TV](how-it-works.md#what-it-changes-on-the-tv).

## Launch method

What a fresh install picks, in this order:

1. **Home panel** where LG's QML Home fits the patch (webOS 3 to 5).
2. **System HOME (native)** on webOS 10 and 11 when the launch checks pass.
3. **Additional overlay**, with an explanation, when another launcher owns HOME
   or a mapper configuration cannot be checked: no foreign HOME mapping is ever
   overwritten.
4. Otherwise the **overlay with HOME via Input Hook** (webOS 6 to 9). A
   recognised Magic Mapper HOME shortcut to Homebar is kept without a second
   Input Hook binding.

Choose explicitly from the unpacked release:

```sh
sh install.sh --native-home          # direct system HOME; checks conflicts
sh install.sh --additional-overlay   # keep the main Home; choose your own button
sh install.sh --overlay              # previous mapper-based overlay
sh install.sh --probe                # read-only capabilities and launch checks
```

Existing installations retain their mode. Legacy users on supported TVs receive
an offer under **Launcher settings → Help → Launch method**. Applying it is an
explicit change, not a silent update migration. An unknown or conflicting HOME
rule must be resolved first, or use the additional overlay instead.

Recognised Homebar rules in Input Hook and supported Magic Mapper configurations
are backed up and removed during a system-HOME transition. Other actions,
conditions and mapper settings stay. Active supported Magic Mapper is restarted;
a failed reload rolls back the change. Additional overlay restores earlier
non-HOME shortcuts only where the current rule has not been changed by the user.
Assign its button to `org.rawin.launcher` in your mapper, or use the app tile
([how](#mapping-a-button-to-homebar)).

Uninstall removes only recognised Homebar rules from both mappers. If an
unsupported mapper cannot be updated safely, it stops with instructions to inspect
and fix the unsupported configuration first. It does not uninstall either mapper.

System HOME has been checked on an LG B4 (webOS 10.3): install, switching both
ways in the settings, restarts. webOS 11, other launchers and the full matrix
of mapper versions are tested locally only so far; reports are welcome.

### Mapping a button to Homebar

In the additional overlay Homebar opens from its **app tile** with nothing
set up. For a button, make the mapper *launch the app* `org.rawin.launcher`
(the name Homebar's app has; not "Homebar"):

- **Input Hook** (`/home/root/.config/lginputhook/keybinds.json`, or its app):
  the key is the button's **uinput code**, not its key id. Press the button
  once and read the code from `/tmp/lginput-hook-*.log`
  (`uinput_code=1086` for the Alexa button of an LG B4).
  ```json
  { "1086": { "action": "launch", "id": "org.rawin.launcher" } }
  ```
- **Magic Mapper** (`/home/root/magic_mapper_config.json`): a button from its
  list, with the `launch_app` function. Its list has no SOURCE/INPUT entry, so
  use one it has or add the code to its script (see its README).
  ```json
  { "green": { "function": "launch_app", "inputs": { "app_id": "org.rawin.launcher" } } }
  ```

Do not map HOME this way in the additional overlay: HOME stays with LG Home,
Luma or Glasshouse. Homebar does not choose a button for you; switching
methods only backs up and restores its own earlier rules, as described above.

### Trying System HOME on webOS 7 to 9

System HOME is tested on webOS 10 only. Other launchers replace LG's Home on
webOS 7 and 9 as well (Glasshouse), so it may work there, but nobody has tried
Homebar's version. If you would like to find out on your TV (Homebrew Channel
and a root shell as for any install):

```sh
sh install.sh --try-native-home
```

What it does: it allows System HOME on this TV, switches to it, and checks
within 25 seconds that the app manager reports a QML Home and that a
`qml-runner` runs it. **If that check fails, LG Home is given back at once** and
the trial option is removed again. If it passes, press HOME and see what
happens. In either case it writes the log to `/tmp/homebar-native-trial.txt`;
the same text is in `sh /var/lib/webosbrew/rawin-launcher-home/diagnose.sh`
output. Copy it off the TV with

```sh
ssh root@<tv-ip> cat /tmp/homebar-native-trial.txt > homebar-native-trial.txt
```

and attach it to a [GitHub issue](https://github.com/rawinek/webos-homebar/issues)
together with the TV model, the webOS version (*Settings → General → About*)
and what you saw when pressing HOME (Homebar, LG Home, a black screen, nothing).
While the trial is on, *Launcher settings → Launch method* shows that it is
experimental and offers both modes, so you can switch back to *Additional
overlay* there. Uninstalling (`sh /var/lib/webosbrew/rawin-launcher-home/uninstall.sh`)
gives LG Home back. webOS 6 and older are not covered: there the app manager
cannot reread a replaced Home, and other launchers use a different method.
