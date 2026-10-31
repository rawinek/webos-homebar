<h1 align="center">Homebar</h1>

<p align="center">
  <b>Your LG TV's home screen as a bar over the picture.</b><br>
  Not a full-screen menu that takes you out of what you were watching.
</p>

<p align="center">
  <a href="https://github.com/rawinek/webos-homebar/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/rawinek/webos-homebar?label=release"></a>
  <img alt="webOS 4, 5, 6, 7 and 10 tested" src="https://img.shields.io/badge/webOS-4%20%7C%205%20%7C%206%20%7C%207%20%7C%2010%20tested-a50034">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/github/license/rawinek/webos-homebar"></a>
</p>

<p align="center">
  <a href="https://buymeacoffee.com/rawin"><img alt="Buy me a coffee" src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" height="44"></a>
</p>

![Homebar over a playing video: seven favourite apps, the HDMI inputs with their devices, Apps and System](docs/screenshots/home.jpg)

Homebar is a home screen for rooted LG webOS TVs. Press HOME and a bar comes
up at the bottom of the screen, over whatever is playing: your favourite apps,
the TV's inputs with the device on each, all your apps and a System page.
The picture stays where it is. Press HOME again, or BACK, and it is gone.

## Highlights

<table>
  <tr>
    <td width="50%"><img src="docs/screenshots/home-input.jpg" alt="An HDMI input focused on the Home row, with the device names under each input"></td>
    <td width="50%"><img src="docs/screenshots/apps.jpg" alt="All apps in a grid of twelve columns over the picture"></td>
  </tr>
  <tr>
    <td><b>Inputs by name or icon.</b> Choose a port number, label, HDMI-CEC name or one of 61 device icons. Hold OK or press YELLOW to edit; two DOWN presses hide an input.</td>
    <td><b>Every app, one row away.</b> Twelve to a row on a 16:9 screen, in the TV's order, A to Z, or the most used first. LG's promotional apps are left out.</td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/settings-theme.jpg" alt="Launcher settings: the Theme setting with its values, Lime previewed live"></td>
    <td><img src="docs/screenshots/edit-favourite.jpg" alt="A favourite in edit mode, with handles to move it"></td>
  </tr>
  <tr>
    <td><b>Settings with a live preview.</b> One menu: language, theme, text size, the clock and the weather, what the row shows, backup and updates. Arrow keys preview values; pointing only highlights them until you click.</td>
    <td><b>Favourites chosen on the TV.</b> Hold OK on an app to add it, up to seven; hold OK on a favourite to move it or take it off the row.</td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/home-terracotta.jpg" alt="The Home row in the light Terracotta theme"></td>
    <td><img src="docs/screenshots/home-larger.jpg" alt="The Home row with the larger text size and a 12-hour clock"></td>
  </tr>
  <tr>
    <td><b>Nine colour themes.</b> The original grey and eight two-colour themes, dark and light. <a href="docs/themes.md">See them all</a>.</td>
    <td><b>Readable from the sofa.</b> Three text sizes, a 24- or 12-hour clock, and a layout that fits HD as well as FHD and UHD screens.</td>
  </tr>
</table>

## What else it does

- **Device icons** for inputs and TV: choose a brand or a generic device,
  such as a soundbar, console or projector. Show an icon alone or with text;
  choose the input heading separately. [How to edit them](docs/using.md#device-icons).
- **Safer editing**: a red warning appears before a second DOWN press removes
  a favourite, input or optional shortcut from the Home row.
- **Ten languages**, the TV's own by default: English, Spanish, German,
  Polish, French, Italian, Portuguese (Portugal and Brazil), Dutch and Czech.
- **The TV's load**, if you want it: processor, memory and network speed as
  small figures in the top bar (off by default, *Launcher settings → Top bar*).
- **The weather** in the corner, next to the clock, from Open-Meteo with no
  account or key. The place is chosen on a phone, from a code on the TV.
- **Updates itself** from this repository's releases, in *Launcher settings
  → Updates*, with what is new in each; a dot on *System* says when one is
  there.
- **Backup and restore** of favourites and settings in one file.
- **A remote button for Homebar** (overlay): press it twice in *Launcher
  settings → Help → Remote button*; Homebar sets it in Input Hook or Magic
  Mapper, and Unpin takes it out again.
- **After an app exits or BACK is held** (System HOME and the older overlay):
  the TV goes back to the last input, a chosen one, or does nothing; choose
  in *Launcher settings → After holding BACK*.
- Nothing of LG's is uninstalled, and the TV's system partition is not
  written to. The uninstaller gives LG's Home back at once.

## How Homebar opens

Homebar is one panel, put on the screen in the way the TV allows. The
installer picks the method from what the TV has; *Launcher settings → Help →
Launch method* changes it where more than one fits.

| Method | What it is | Needs | Typical TV |
| :--- | :--- | :--- | :--- |
| **Home panel** | The panel runs *inside* LG's own QML Home, which keeps HOME, its window and its lifecycle | Root only | webOS 4 and 5 (e.g. LG C9) |
| **System HOME (native)** | Homebar replaces LG's Home: HOME opens it directly. On webOS 9 to 11 LG's own Home is a Flutter app; Homebar puts its own QML host in its place | Root only; no Input Hook, no mapper | webOS 10 and 11 (e.g. LG B4); a trial on 6 to 9 (works on an LG C1, webOS 6.5) |
| **Additional overlay** | A separate app and root helper next to your Home. LG Home (or Luma, Glasshouse) keeps HOME; Homebar opens from its **app tile** or from a button you choose in its settings | Input Hook or Magic Mapper for a button (not for the tile) | webOS 6 or newer (checked on 10) |

The overlay can also take HOME itself, through a binding in Input Hook
(*HOME via mapper*): that is what webOS 6 to 9 get by default, and what earlier
installs use. An update never changes the method.

## Compatibility

| webOS (LG's name) | Method | Status |
| :--- | :--- | :--- |
| 3.x (2016–2017) | Home panel, if the patch fits | Untested |
| 4.x (webOS 4.0 / 4.5, 2018–2019) | Home panel (on a TV with two Home screens, set to *Basic*) | Tested on 4.10 (LG C9, and UM7100, B9 and E9 by users) |
| 5.x (webOS 5.0, 2020) | Home panel | Tested on 5.6 (LG NANO80, UN73 and UN90, by users) |
| 6.x (webOS 6.0, 2021) | Overlay, HOME via Input Hook (or the additional overlay); System HOME as a trial | Tested on 6.3 and 6.5 (LG C1 and UP78, by users); System HOME on a C1 (6.5.3, by a user) |
| 7.x (webOS 22, 2022) | Overlay, HOME via Input Hook; System HOME as a trial | Overlay tested on 7.5 (by a user); System HOME untested |
| 8.x, 9.x (webOS 23, 24) | Overlay, HOME via Input Hook; System HOME as a trial | Untested |
| 10.x (webOS 25, 2025) | **System HOME (native)**, or the additional overlay | Tested on 10.3: LG B4 (System HOME), LG UR78 (overlay, by a user) |
| 11.x (webOS 26, 2026) | System HOME | Untested |

LG names webOS after the year since 2022 (webOS 25 is version 10.x), and an
older TV can be updated to a newer webOS, so go by the version the TV reports.
`sh install.sh --probe` shows it, says which method fits, and changes nothing.
More in [Compatibility](docs/compatibility.md).

## Install

You need a rooted TV with the
[Homebrew Channel](https://github.com/webosbrew/webos-homebrew-channel) and a
root shell (SSH or telnet). Log in to the TV as root, then:

```sh
cd /tmp
curl -fL -o rawin-launcher.tar.gz https://github.com/rawinek/webos-homebar/releases/latest/download/rawin-launcher.tar.gz
rm -rf rawin-launcher && tar xzf rawin-launcher.tar.gz
sh rawin-launcher/install.sh
```

The installer prints the webOS it found and the method it picked, then each
step. **Press HOME on the remote when it is done** (additional overlay: open
the Homebar app tile, or press the button you mapped).

- **webOS 10 and 11:** a fresh install becomes System HOME. If another
  launcher owns HOME or a mapper cannot be checked, it installs the additional
  overlay instead and says why; nothing is overwritten.
- **webOS 6 to 9:** the overlay, with HOME bound through *Input Hook*:
  install and open it from the Homebrew Channel first (a supported Magic
  Mapper HOME shortcut works too). `--additional-overlay` leaves HOME to LG
  and opens Homebar from its app tile or a button you map.
- **webOS 4 and 5:** the Home panel; nothing else is needed.
- Choose by hand: `--native-home`, `--additional-overlay`, `--home-panel`,
  `--overlay`. All options, installing without internet on the TV, updating
  and uninstalling: [Install, update, uninstall](docs/install.md).
- **Additional overlay: a button:** *Launcher settings → Help → Remote
  button* asks you to press it twice and sets it in Input Hook or Magic Mapper.
  By hand it is a mapper rule that launches the app id `org.rawin.launcher`
  ([Mapping a button to Homebar](docs/install.md#mapping-a-button-to-homebar)).
  The app tile works without one.

**Update:** *System → Launcher settings → Updates* (from 0.10.0 on).
**Uninstall:** `sh /var/lib/webosbrew/rawin-launcher/uninstall.sh` (Home panel)
or `sh /var/lib/webosbrew/rawin-launcher-home/uninstall.sh` (overlay and
System HOME); LG's Home comes back at once.

### Trying a TV that is not on the list

```sh
sh rawin-launcher/install.sh --probe             # what would be installed, and why; changes nothing
sh rawin-launcher/install.sh                      # the method that fits
sh rawin-launcher/install.sh --try-native-home    # webOS 6, 7, 8 or 9: a trial of System HOME
```

The trial gives LG's Home back at once if the app manager does not take
Homebar's, and writes `/tmp/homebar-native-trial.txt`. Whether it worked or
not, open an [issue](https://github.com/rawinek/webos-homebar/issues) with the
TV model, the webOS version, what HOME did, and that file (for an ordinary
install, the file from `diagnose.sh`). That is how new TVs get on the list. See
[Trying System HOME on webOS 6 to 9](docs/install.md#trying-system-home-on-webos-6-to-9).

Homebar was called **rawin-launcher** until 0.12.0. The release file and the
folders on the TV keep that name, so earlier installs update in place, and the
old GitHub address leads here.

## Documentation

- [Install, update, uninstall](docs/install.md)
- [Using the launcher](docs/using.md): favourites, hiding, System, every setting, backup, languages
- [Themes](docs/themes.md)
- [Compatibility](docs/compatibility.md)
- [How it works](docs/how-it-works.md): both variants, what is changed on the TV
- [Troubleshooting](docs/troubleshooting.md): `diagnose.sh`, getting LG's Home back
- [Development](docs/development.md): build from source, adding a language or a theme

Problems: run `diagnose.sh` (see [Troubleshooting](docs/troubleshooting.md#diagnose))
and attach its file to an [issue](https://github.com/rawinek/webos-homebar/issues).

## Support

I build free apps and tools and share them on GitHub. If you enjoy my
projects, you can support my work by
[buying me a coffee](https://buymeacoffee.com/rawin) ☕ (the code is also in
*Launcher settings → About Homebar* on the TV).

## Credits

- [webOS Homebrew Channel](https://github.com/webosbrew/webos-homebrew-channel)
  for root, `elevate-service` and the boot hooks.
- [Glasshouse](https://github.com/rorygallagher2024/glasshouse) showed how the
  app manager re-reads LG's Home on webOS 10 (block and release of one app);
  [Luma](https://github.com/ecklf/lg-luma) is the other launcher that takes
  over HOME, on webOS 5, 6, 10 and 11.
- [Magic Mapper](https://github.com/andrewfraley/magic_mapper) and Input Hook
  are the two button mappers Homebar can work with.
- Device icons: [Custom Brand Icons](https://github.com/elax46/custom-brand-icons)
  (MIT) and [Material Design Icons](https://github.com/Templarian/MaterialDesign)
  (Apache 2.0); see `ui/input-icons/`.
- [Inter](https://github.com/rsms/inter) typeface, SIL Open Font License 1.1.
- Video in the screenshots: *Big Buck Bunny* © Blender Foundation,
  [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/).

## Disclaimer

Unofficial; not affiliated with or endorsed by LG Electronics. It runs as root
on your TV and replaces how its home screen works. Use at your own risk.

## License

MIT, see [LICENSE](LICENSE). The Inter font is under the SIL Open Font License
1.1 (`ui/fonts/OFL.txt`).
