# Development

- [Build from source](#build-from-source)
- [Another webOS version, on purpose](#another-webos-version-on-purpose)
- [Configuration](#configuration)
- [Layout](#layout)
- [Checking the layout](#checking-the-layout)
- [Device icons](#device-icons)
- [Adding a language](#adding-a-language)
- [Adding a theme](#adding-a-theme)
- [Theme pictures](#theme-pictures)

## Build from source

Python 3 on any computer:

```sh
python3 tools/build.py                   # dist/rawin-launcher.tar.gz
python3 tools/build.py --config my.json  # with your own favourites
python3 tools/deploy.py --host <tv-ip>   # build, copy over SSH and run install.sh
```

`deploy.py` needs key-based root SSH to the TV; `--identity <key>` picks the
key, `--keep-lg-home` and `--uninstall` do what they say, `--backup file`
and `--restore file` copy the TV's `backup.json` either way, and anything
after `--` goes to `install.sh` on the TV (`-- --probe` only says which
method fits; `-- --additional-overlay` or `-- --try-native-home` choose one).
The archive holds every method; on the TV `install.sh` picks the one the TV has
the makings for.

## Another webOS version, on purpose

`HOMEBAR_WEBOS=<version>` makes `install.sh` and `probe.sh` take the TV for
that webOS version (`HOMEBAR_WEBOS=9.1 sh install.sh --probe` shows what the
installer would do on a webOS 9 TV with this TV's makings). The variant is
still chosen by what the TV has; the version only decides what counts as
tested and whether the overlay replaces LG's Home by default. On webOS 6 to 9
it does not enable System HOME; that is `--try-native-home` (see
[Install](install.md#trying-system-home-on-webos-6-to-9)).

## Configuration

`config/launcher.json` holds the defaults baked into a build:

- `favourites`: up to seven app ids, empty by default. Apps that are not
  installed are skipped. Preset favourites only fill a fresh install: once
  favourites are edited on the TV, that list stays, also through updates.
- `styles`: the glow colour per app id (`{"accent": "#e50914"}`).
- `excluded`: launch points never listed (LG's promotional apps).

## Layout

| Path | What |
| :--- | :--- |
| `ui/` | The panel shared by both variants: `Launcher.qml`, texts in `Strings.js`, colours in `Themes.js`, the About page's links and QR code in `About.js`, LocalStorage in `FavouriteStore.qml`, fonts, device choices in `DeviceIcons.js` and the tinted masks in `DeviceIcon.qml` / `input-icons/` |
| `webos4/` | The Home panel: the LG Home patch, boot hook and scripts |
| `webos10/` | The overlay: the overlay app, helper, HTTP bridge, Home stand-in and scripts |
| `shared/` | The setup server of both variants: the weather, the page to choose its place on a phone, and that page's QR code |
| `tools/` | Build, deploy, the app icon (`make-icon.py`), the theme pictures (`render-themes.py`) and the panel at any size (`render-panel.py`) |
| `config/` | Build defaults, see [Configuration](#configuration) |

For the overlay, `tools/build.py` turns `ui/Launcher.qml` into the app's
`Panel.qml`, swapping its Luna Service elements for
`webos10/panel-bridge.qml` (HTTP to the helper). The top-level `install.sh`
picks the variant by what the TV has (`probe.sh`, which the installers also
put next to `diagnose.sh` on the TV), see
[Compatibility](compatibility.md#how-homebar-opens).

## Checking the layout

The panel is drawn for 1920×1080 and scaled to the size it gets: `u` in
`Launcher.qml` is that scale and every length goes through `px()`, so a new
element is placed in 1080p numbers (`shell.px(24)`) and follows the screen.
Positions hang from the bottom and the right edge (`shell.height - px(…)`,
`anchors.right`), never from the top left, so a wider screen gets more rail
and more columns. Text goes through `pt()`, which also takes the text size
setting. `tools/render-panel.py` draws a set of scenes (Home with seven
favourites and long HDMI-CEC names, Live TV and every input, favourites,
inputs or shortcuts being edited, hidden apps, Apps in each order, System
with an update waiting, the settings menu on a setting, on its values, on
the Inputs, Shortcuts and Top bar switches and on an action, the larger
text size, no favourites, two inputs) at a size:

```sh
python3 -m pip install PySide6
python3 tools/render-panel.py                     # dist/render/1920x1080-*.png
python3 tools/render-panel.py --size 1280x720     # an HD TV
python3 tools/render-panel.py --size 2560x1080    # a wider screen
```

Check at least 1920×1080 and 1280×720 after a change to the panel.

For an interactive desktop window, use `python3 tools/simulate-panel.py
--size 1280x720`. Arrows and Enter act as the remote, Escape/Backspace goes
back, and F2 opens the panel again after BACK or its timeout hides it. Mouse
and wheel events use the panel's normal handlers. TV services are stubbed.

## Device icons

The input and TV catalogues in `ui/DeviceIcons.js` use stable ids: saved choices
belong to a physical input, so changing an icon title or sort order must not
change its id. Generic device names are translated in all ten languages;
brand names stay as supplied. The TV picker has a separate restricted list.

`ui/input-icons/manifest.json` records each original SVG URL, pinned revision,
SHA-256 and licence. Preserve the original SVG and include the upstream licence
and notice when adding an entry. Regenerate the optically sized PNG masks with:

```sh
QT_QPA_PLATFORM=offscreen python3 tools/prepare-input-icons.py
```

`DeviceIcon.qml` tints a 128px mask and uses a smooth mipmapped texture; the
48px icon field stays the same with or without text. Do not rasterise into the
small field first: focus scaling makes those edges visibly jagged on a TV.
Both installers package the component and its assets; building needs no SVG
plugin on the TV and does not download artwork.

With PySide6 installed, the focused checks are:

```sh
QT_QPA_PLATFORM=offscreen python3 tests/input-icons.py
QT_QPA_PLATFORM=offscreen python3 tests/input-icons-visual.py
QT_QPA_PLATFORM=offscreen python3 tests/input-icons-quality.py
QT_QPA_PLATFORM=offscreen python3 tests/icon-picker-position.py
QT_QPA_PLATFORM=offscreen python3 tests/edit-removal.py
```

The visual audit writes contact sheets to `dist/icon-audit/`. The other tests
exercise real Qt keys, mouse and wheel events, saved choices, independent
headings, popup anchoring and two-step removal. Desktop tests do not replace
checking the Magic Remote's pointer and held keys on an actual TV.

## Tests

With PySide6 installed (Qt 6, for the QML ones) and Node:

```sh
for t in tests/*.js; do node $t; done
for t in tests/*.py; do QT_QPA_PLATFORM=offscreen python3 $t; done
```

They cover the launch-method scripts against a fake TV root (`mode-switch.py`,
`install-policy.py`, `integration.js`), the settings menu and its Yes/No popup
(`mode-menu.py`), the HTTP bridge, the after-exit logic and the icon and
removal flows. The QML tests share one LocalStorage on the computer (the
`QML/OfflineStorage` folder of the Python app); a leftover saved language or
favourites there can fail `mode-bridge.py`, and deleting that database fixes it.
None of this replaces trying a method on a real TV.

## Adding a language

Copy the `en` table in `ui/Strings.js`, translate it and add the code to
`languages` and `names` (a regional variant such as `pt_br` also needs a case
in `supported()` and a fallback in `get()`). The Inter font covers Latin, Greek and Cyrillic
scripts; others would need a font with their glyphs. Corrections to the
translations are welcome.

## Adding a theme

1. Add `{id: "<id>", accent: "#RRGGBB", base: "#RRGGBB"}` to `themes` in
   `ui/Themes.js`. The order there is the order OK goes through on the TV.
2. Add `theme_<id>` with the theme's name to every language in
   `ui/Strings.js` (English is used where one is missing).
3. Run `tools/render-themes.py` and add the theme to [Themes](themes.md).

`palette()` in `Themes.js` makes every colour from the two: a base with a
relative luminance over 0.4 counts as light (light tiles, dark text), the
shade is always a near-black of the base, and the text on the accent is white
unless the accent's luminance is over 0.3. Pick an accent that stands out from
the base; nothing checks the contrast for you.

## Theme pictures

`tools/render-themes.py` draws `docs/themes/<id>.png` and
`docs/themes/<id>-colors.svg` for every theme from the real `Launcher.qml`, on
a computer:

```sh
python3 -m pip install PySide6
python3 tools/render-themes.py
```

Run it on the default Qt platform, not `QT_QPA_PLATFORM=offscreen`: the
software renderer cannot draw the rounded app icons, and they come out blank.

It stubs the webOS-only parts (Luna services, webOS keys), gives the apps plain
coloured icons and puts a gradient where the picture would be.
