# Using the launcher

- [Home](#home)
- [Favourites](#favourites)
- [Hiding apps and inputs](#hiding-apps-and-inputs)
- [Apps](#apps)
- [System](#system)
- [Launcher settings](#launcher-settings)
- [Device icons](#device-icons)
- [Backup](#backup)
- [Restarting Homebar](#restarting-homebar)
- [Languages](#languages)
- [Launch method](#launch-method-overlay-builds)
- [Remote button](#remote-button-overlay-modes)

## Home

<img src="screenshots/home.jpg" width="100%" alt="Home over a playing video: seven favourites, HDMI 1 to 4 with the device on HDMI 3 and 4, Apps and System">

HOME on the remote opens the panel over whatever is on screen; the picture
stays visible above it. One row, from the left:

- **Favourites**: up to seven apps. With none yet, an *Add favourites* tile
  opens *Apps*.
- **Sources**: *TV* (Live TV) as a tile the size of the shortcuts, then the
  TV's inputs: HDMI, and DisplayPort or USB-C where a set has them, as many
  as the TV has. Each shows the device
  the TV sees on it: the name set on the TV for that input, else its
  HDMI-CEC name. An input with nothing plugged in is dimmed. Long names are
  cut to what the row has room for. *Input appearance* in the settings chooses
  whether a pill shows the port (`HDMI 2`), that name, or both, in either
  order. *TV* and the inputs are edited
  like the shortcuts: hold OK (or press YELLOW) on one, ← → moves it along
  the row and ▼ twice takes it off; *Launcher settings → Home row → Inputs and TV* lists
  them all with a box each and brings back the ones that are off. While editing
  an input, **▲ opens the device-icon picker; ← → changes its icon**. The edit
  arrows sit together above the tile and disappear while the picker is open.
  The picker centres above the edited tile, shifting only as needed to stay
  inside the screen margins.
  Shortcut move arrows also sit above their tiles, without an icon picker.
  Click **▼ Hide** at the bottom of the picker, or press DOWN, to fold it away. OK, BACK
  or ▼ closes the picker and returns to arranging inputs; another OK/BACK finishes
  editing. The choice is saved immediately for that port, even if it is hidden
  or its CEC name changes. The *TV* tile has the same ▲ picker but offers only
  four television symbols and its original **TV** text. Its choice is independent
  of the HDMI appearance setting. The picker also supports clicking and the scroll wheel.
  Icons include generic devices such as a soundbar, AV receiver, speakers,
  projector or game console, alongside device and brand marks. The picker is
  sorted alphabetically by the names shown in your selected language.
  Choose **Icon only**, **Icon + HDMI**, **Icon + label** or **Icon + CEC** under
  *Launcher settings → Home row → Input appearance*. Icon-only inputs are slightly wider (72 × 64 px at FHD); other arrangements keep the fitted width, capped at 200 px.
  **Input name above favourites** independently chooses **HDMI**, **Label** or
  **CEC** for the large heading (default: HDMI). A missing label falls back to
  CEC, a missing CEC name to the label, and finally to the port name.
  Existing text arrangements stay available and remain the default (see
  [Hiding apps and inputs](#hiding-apps-and-inputs)).
- **Shortcuts** after the inputs: *Apps* and *System*; *Close background apps*
  is off by default (turn it on in *Launcher settings → Shortcuts*) and sits
  first when on. *Memory freeing action* chooses between closing apps
  immediately (`closeAllApps`) and opening LG's Memory Optimizer.
  Closing apps may also close Homebar; press HOME to open it again. The tile's
  name follows that choice. Opening LG's screen does not press *Start*;
  on the tested webOS 25 that button closes recent application windows.
  A shortcut is edited like a
  favourite: hold OK (or press YELLOW) on it, then ← → move it among the
  shortcuts and ▼ twice takes it off the row; *System* can be moved as well, but
  never removed, and *Shortcuts* in the Launcher settings brings the other
  two back. A dot on *System* means a new version of the launcher is there
  (see [Updates](#launcher-settings)).

<img src="screenshots/home-input.jpg" width="100%" alt="An HDMI input focused: its name above the row, the device under each input, the hints for OK, hold OK and RED at the bottom">

The focused item's name shows above the row, and the hints under it say what
OK and the other keys do, the remote's colour keys in their own colour
(YELLOW does what holding OK does, RED hides an app in *Apps*). The chip in the top-right corner shows what is on
screen, the [weather](#weather) and the time; each of the three can be hidden. HOME pressed again closes the panel too (on the Home panel the remote sends it to Homebar as a key; on the overlay HOME toggles it). BACK closes the panel; from *Apps* or *System* it goes
back to Home. The panel fits the TV's screen, HD or FHD/UHD, at the same
proportions. Each input fits its own label or CEC name and optional second
line, with padding, up to 200 px at FHD. Short names keep their pills narrow.
When inputs or shortcuts leave less space, the favourite tiles shrink so
the row keeps both screen margins. Longer input names use the selected
ellipsis or scrolling mode.

With the Magic Remote's pointer, moving it over a favourite, an input or a
tile in *Apps* or *System* focuses it, as the arrows do; a pointer resting
where the panel opens changes nothing, and neither does one hidden by an
arrow press (pointing waits a second after a key). A click opens what it
points at, and a click held does what holding OK does. In *Launcher
settings* pointing only outlines a row or a value: a click opens the row's
values or applies the value, so crossing other rows on the way never
changes anything. The wheel scrolls the settings list, and the *Apps* grid
one row per notch; scrolling never opens anything. Holding OK also works with a
remote that sends it by infrared (a plain remote, or a Magic Remote without
its radio), which repeats a held key as quick presses.

LG's promotional apps (LG Channels, Sports, Alexa, …) are left out of the
launcher's lists. Nothing is uninstalled.

### Confirming removal

While editing a favourite, input, TV tile or optional shortcut, the first DOWN
shows a red warning below it; press DOWN again to remove it from the row. Moving
left/right, opening the icon picker or ending edit mode cancels the warning.
Holding DOWN does not confirm via key auto-repeat. The System/settings tile
cannot be removed. This changes the Home row only; it does not uninstall apps.

## Favourites

Favourites are chosen on the TV:

- In *Apps*, **hold OK** (or press YELLOW) on an app to add it, up to seven.
  A favourite is marked with a dot; holding OK on it again removes it.
- On Home, **hold OK** on a favourite to edit it: ← → move it, ▼ twice removes it,
  OK, BACK or ▲ finish.

<img src="screenshots/edit-favourite.jpg" width="100%" alt="A favourite being edited: an amber ring, handles to move it left or right, and the hint to remove it with the down arrow">

A fresh install starts with none. Favourites outlast updates; an app that is
uninstalled simply drops out of them.

## Hiding apps and inputs

**RED** on an app in *Apps* hides it from the list (and drops it from the
favourites); *Launcher settings → Apps → Hidden apps → Shown dimmed*
shows the hidden apps again, dimmed, so RED on one can bring it back for
good. *TV* and the inputs are taken off the Home row with ▼ twice in their edit
mode (hold OK on one, then press ▼ twice) and come back from *Launcher settings → Home
row → Inputs and TV*: a box for *TV* and each input, and OK switches the chosen one.
Nothing is uninstalled; hidden items are only out of the launcher's lists.

## Apps

<img src="screenshots/apps.jpg" width="100%" alt="All apps, twelve to a row, two rows on screen, favourites marked with a dot">

All installed apps, as many to a row as the screen is wide (twelve on a 16:9
screen), two rows on screen; the row scrolls with the focus. *Launcher
settings → Apps order* puts them in the TV's
order, from A to Z, or the most used first, counted from the launcher's own
launches. An app's glow colour lights the bottom-left corner while it is
focused: the colour the build knows for it, else one read from its icon.

## System

<img src="screenshots/system.jpg" width="100%" alt="The System page: TV settings, Launcher settings (focused), Homebrew Channel, LG Content Store, Back to the picture; the version in the corner">

| Tile | Opens |
| :--- | :--- |
| TV settings | LG's settings app |
| Launcher settings | [Launcher settings](#launcher-settings) |
| PicCap | Only when installed |
| Homebrew Channel | |
| LG Content Store | |
| Original Home | LG's own Home: always with the Home panel; with the overlay only when LG's Home was kept (`--keep-lg-home`, or an untested webOS without `--replace-lg-home`) |
| Back to the picture | Closes the panel |

The launcher's version, the TV's webOS and the variant (Home panel or
overlay) are in the bottom-right corner.

## Launcher settings

<img src="screenshots/settings.jpg" width="100%" alt="Launcher settings: the settings in groups on the left, the languages on the right with a dot on the chosen one">

*System → Launcher settings* opens a menu over most of the screen. On the
left are the settings in groups, each with its value; on the right the
values of the focused one, with a dot on the chosen value. ▲ ▼ move between
the settings; OK or ▶ goes into the values, where ▲ ▼ choose (each value
applies at once, so the menu itself is the preview) and OK or ◀ come back;
BACK closes the menu. *About Homebar*, first, shows the version and a code
to support the project. *Back up*, *Restore* and *Updates* show their status
on the right and act on OK; when a new version is found, *Updates* also
shows what changes in it, from its release notes. *Weather place* shows a
code to scan with a phone, see [Weather](#weather).

The values of *After holding BACK* (overlay), and Home with the text size
at *Larger* and the 12-hour clock:

<img src="screenshots/settings-after-back.jpg" width="100%" alt="The values of After holding BACK on the overlay: Last input or HDMI 1 to 4">

<img src="screenshots/home-larger.jpg" width="100%" alt="Home with the Larger text size and the 12-hour clock">

| Group | Setting | Values |
| :--- | :--- | :--- |
| About | About Homebar | The version, a code to [buy me a coffee](https://buymeacoffee.com/rawin) and where the source is. The menu opens here |
| Look | Language | *System language* (the TV's menu language, when it is one of the [languages](#languages)), or one of them by hand |
| | Theme | Default or one of eight two-colour themes, see [Themes](themes.md) |
| | Text size | Normal, Large or Larger: the names, hints, labels and the menu grow; the tiles and pills keep their size, so the row still fits |
| | Animations | On or off |
| Home row | Inputs and TV | A box for *TV* and each input the TV has, in their row order: OK takes the chosen one off the Home row or puts it back |
| | Input appearance | *Icon only*, *Icon + HDMI*, *Icon + label*, *Icon + CEC*, or the existing text arrangements: *Label only*, *HDMI only*, *CEC only*, *Label, then HDMI*, *HDMI, then label*, and the same pairs for the device's HDMI-CEC name (*CEC, then HDMI*, *HDMI, then CEC*): what a pill shows of the port, the name set on the TV for that input and the CEC name. The label modes fall back to the CEC name when no label is set, and the other way round. A pill drawn with the choice appears below the values. Missing label/CEC names fall back as before. Icons are chosen per input in its edit mode |
| | Input name above favourites | HDMI (default), Label or CEC; independent of the tile appearance, with the same fallback for missing names |
| | Long input names | *Ellipsis* (default) or *Scroll*: a name wider than the 200 px a pill can take either ends in "…", or, while that tile is focused, scrolls slowly to its end and back |
| | Shortcuts | A box for *Free up memory* (off by default) and for the *Apps* shortcut: the same, for the tiles after the inputs |
| | Memory freeing action | *Close background apps* (default) or *Open LG Memory Optimizer*. The first closes apps immediately; the second opens LG's optimiser screen and leaves *Start* to you. The shortcut's title follows the chosen action. The optimiser option is offered only when the TV's LG Settings includes that screen |
| | After holding BACK | Compatibility overlay and System HOME: the last input, TV, any physical input (including hidden ones), or *Do nothing* (Homebar leaves the TV to LG). In System HOME this applies when an app leaves no full-screen card; ordinary HOME over a playing app does not switch inputs. Additional overlay and the older Home panel leave returns to LG |
| Apps | Apps order | The TV's order, A to Z, or the most used first |
| | Hidden apps | Hidden, or shown dimmed in *Apps* (to bring one back with RED) |
| Top bar | Items | A box for the clock, the app on screen and the weather: OK shows the chosen one in the chip or hides it. Three more boxes, **off by default**, add the TV's load to the chip: *Processor* (`CPU 22%`), *Memory* (`RAM 60%`, memory in use, caches not counted) and *Network* (`↓ 35 kB/s  ↑ 5.1 MB/s`, the current rates on the real interfaces). They refresh every two seconds while Home is up, and nothing is read while they are off |
| | Clock format | 24-hour (16:05) or 12-hour (4:05 PM); the backup's time follows it |
| | Weather place | The place of the weather; a code on the right opens a page on a phone to choose it |
| | Temperature | *Automatic* (°F when the TV's language is set for the United States, else °C), Celsius or Fahrenheit |
| | Temperature shown | *Standard temperature* from Open-Meteo, or *Feels like* (`apparent_temperature`, its equivalent of RealFeel) |
| On screen | App name above favourites | Whether the big name of the focused item shows on Home and in *Apps* (System always shows it) |
| | Key hints | The keys and what they do, on the bottom line: shown or hidden (the settings menu and editing favourites keep theirs) |
| | Homebar timeout | *Off* by default, or 3–60 seconds. The panel closes after that much inactivity outside Launcher settings; a key, click, wheel scroll or actual Magic Remote pointer movement starts the count again. The pointer stays visible when the panel hides |
| Backup | Back up favourites and settings | OK writes everything the launcher keeps to a file next to it; the status says when the last backup was made, see [Backup](#backup) |
| | Restore from the backup | OK brings that file back |
| Updates | Updates | The installed version; OK checks, downloads and installs a new release, see [Update](install.md#update). The launcher also looks once a day, the first time Home opens, and shows a dot on *System* and *Launcher settings* when a new version is there |
| | Test builds | Also offer pre-releases as updates |
| Help | Remote button | The remote button that opens Homebar besides HOME, set in Input Hook or Magic Mapper for you; overlay modes only, see [Remote button](#remote-button-overlay-modes) |
| Help | Launch method | *System HOME (native)* or *Additional overlay*, with what the focused one does, the launch checks and a Yes/No popup before anything changes; shown on overlay builds, see [Launch method](#launch-method-overlay-builds) |
| | Restart Homebar | Restarts the Homebar process and opens it again. Use it when the panel stops responding; favourites and settings stay saved |

Up to 0.14 one setting, *Clock bar*, showed or hid the whole chip. When it
was hidden, the clock, the app and the weather start hidden too.

## Device icons

61 local input icons cover PlayStation (including PS3/4/5), Xbox, Apple TV, WiiM, NVIDIA
Shield, PC/laptop, Steam Deck, Nintendo Switch/GameCube, Sega Saturn, Chromecast,
Android TV, Fire TV, Roku, Dune HD, Zidoo, Blu-ray/DVD, Raspberry Pi, Intel NUC,
Sonos, Denon, Yamaha and Cambridge Audio, plus ASUS, Bose, Google, Kodi, LG,
Onkyo, Panasonic, Samsung, Sony, Steam, Xiaomi and XGIMI. Generic symbols include
a soundbar, AV receiver, amplifier, projector, console, decoder, monitor, disc
player, speaker, speakers, streamer, satellite receiver and HDMI. They are
selected manually; Homebar does not guess from device names or change TV settings.
The icons work offline and follow the theme's text colour. Four additional TV
symbols are restricted to the Live TV tile. All icon fields are 48 × 48 px,
including layouts with text. Transparent margins and optical sizing are normalised
without stretching logos; wide wordmarks retain their natural proportions.

Source: [Custom Brand Icons](https://github.com/elax46/custom-brand-icons), MIT.
The included [license and source manifest](../ui/input-icons/README.md) record
provenance; brand marks identify products without implying endorsement.

Generic device symbols and TV-only symbols (screen, classic TV, programme guide
and playback) come from
[Material Design Icons](https://github.com/Templarian/MaterialDesign), Apache 2.0;
licenses and provenance are included with the assets.

## Weather

The chip at the top shows the weather now: a symbol and the temperature,
from [Open-Meteo](https://open-meteo.com), without an account or a key. It
is read each time Home opens and every quarter of an hour while it is up.

By default the place is the one the TV's internet address points to (from
[ip-api.com](https://ip-api.com)), which is often the nearest city of the
internet provider rather than your own. To choose it:

1. Open *System → Launcher settings → Weather place*. A code shows on the right.
2. Scan it with the phone's camera. The phone has to be on the same network
   as the TV.
3. On the page that opens, search for a town or city and tap it. The TV
   shows its weather within a few seconds.

*Use the TV's internet address instead* on the same page goes back to the
automatic place. The page's link works until the TV restarts (or the
launcher is updated); after that, scan the code again.

## Backup

<img src="screenshots/settings-backup.jpg" width="100%" alt="The Back up row focused: its status on the right, and OK to back up">

*Back up favourites and settings* writes the favourites, the settings (the
row's order included), the hidden apps and inputs and the launch counts to
`backup.json` next to the installed launcher:
`/var/lib/webosbrew/rawin-launcher/backup.json` (Home panel) or
`/var/lib/webosbrew/rawin-launcher-home/backup.json` (overlay). *Restore
from the backup* brings it back; the file outlasts updates, and the
uninstaller removes it with the rest. From a computer,
`tools/deploy.py --host <tv-ip> --backup file.json` copies it over, and
`--restore file.json` puts a file on the TV for *Restore*.

## Restarting Homebar

*System → Launcher settings → Restart Homebar* restarts Homebar and opens it
again. Favourites and settings stay. On the Home panel this restarts LG Home's
process, so reopening the bar can take a few seconds.

## Languages

| Language | Code |
| :--- | :--- |
| English | `en` |
| Spanish (Español) | `es` |
| German (Deutsch) | `de` |
| Polish (Polski) | `pl` |
| French (Français) | `fr` |
| Italian (Italiano) | `it` |
| Portuguese, Portugal (Português) | `pt` |
| Portuguese, Brazil (Português do Brasil) | `pt_br` |
| Dutch (Nederlands) | `nl` |
| Czech (Čeština) | `cs` |

The launcher follows the TV's menu language when it is one of these (a TV set
to Portuguese (Brazil) gets `pt_br`, any other Portuguese gets `pt`), and falls
back to English otherwise. A text a language lacks reads in English; Brazilian
Portuguese falls back to Portuguese first. Corrections and new languages are welcome, see
[Development → Adding a language](development.md#adding-a-language).

## Launch method (overlay builds)

**Launcher settings → Help → Launch method** lists the two ways to open Homebar,
with what the focused one does under the list, and the current launch checks:

- **System HOME (native)** makes Homebar the TV's HOME screen. HOME opens it
  directly, with no Input Hook or mapper; LG's Home screen is replaced. webOS 10
  and 11 only.
- **Additional overlay** keeps LG Home (or Luma, Glasshouse) on HOME and adds
  Homebar as an extra bar, opened from a button you assign in Input Hook or
  Magic Mapper, or from its app tile (it is always in LG's app list in this mode).

The older Home-panel integration has no mode switch.

Hover and arrows only move focus. **OK or a click on a method opens a popup that
says what will happen; Yes applies it, No (the default) or BACK cancels.** The
popup lists the restart and any old Homebar mappings to remove. If configuration
changes meanwhile, the popup closes and you review again. Favourites and
settings stay. When the switch is done, Homebar says so once and advises
restarting the TV if anything misbehaves.

System HOME takes the main launcher role. Recognised Homebar `launch`/single
`luna-send` rules in Input Hook and `launch_app` rules in Magic Mapper are backed
up and removed. Conditional entries and lists are handled individually: unrelated
actions and `magic_mapper_settings` are preserved. A remaining conflicting HOME
action blocks takeover. Active supported Magic Mapper is restarted and its new
process checked; old or custom setups that cannot be verified require manual
attention rather than a guessed rewrite.

Additional overlay keeps LG Home, Luma or Glasshouse and does not force HDMI when
an app closes. Choose a button in [Remote button](#remote-button-overlay-modes)
(or set one to `org.rawin.launcher` in your mapper by hand,
[how](install.md#mapping-a-button-to-homebar)), or open the Homebar app tile. Earlier non-HOME shortcuts are restored only if their current
values match the previous cleanup; your later edits are never overwritten.
Homebar does not choose a spare button or uninstall either mapper for you.

Checks run on opening Homebar, entering Launch method and during boot. New
conflicts are reported with instructions. Homebar never reclaims HOME from
another launcher automatically. Even when a later takeover prevents the native
Homebar from owning HOME, its app tile can open its settings to choose an
additional overlay. Restart also targets that fallback instance safely.

An older overlay already opened by a supported Magic Mapper HOME shortcut keeps
that shortcut on update without requiring Input Hook or creating a second HOME
binding. An inactive mapper is reported so you can check its startup.

Updates keep the selected mode. Interrupted changes have a recovery journal;
failed changes restore the previous data and mapper rules where safe. If a
concurrent edit prevents recovery, it is preserved and Diagnose retains the
recovery information. Older releases do not understand these modes: reverting
requires a separate rollback procedure.

Magic Mapper support follows the [upstream configuration format](https://github.com/andrewfraley/magic_mapper#configuring-buttons).
Known 1.0 to 1.2 script layouts are inspected at the standard location, through
the known startup script, or through a running `magic_mapper.py` process. Custom
renamed installations outside these locations need manual checking. Supervised
restart support is required only when changing an active mapper. Unknown layouts are reported as
unverified. Actual coexistence across TVs and mapper versions still needs tests;
local fixtures do not establish full hardware compatibility.

## Remote button (overlay modes)

**Launcher settings → Help → Remote button** puts Homebar on a button of your
remote besides HOME, in Input Hook or Magic Mapper, so you do not have to edit
their files. It is there in the additional overlay and with HOME via mapper; with
System HOME, HOME already opens Homebar.

1. OK on the row opens a popup: press the button that should open Homebar.
2. Homebar shows which button it was, with its code (for example *GREEN (399)*),
   and asks for one more press of the same button. Another button is not saved.
3. The button is saved in the mapper that is running (Input Hook first), and
   pressing it opens Homebar from then on.

With a button saved, OK on the row offers **Change** and **Unpin**; Unpin takes
Homebar's rule out again. One button at a time: a new one replaces the old.
OK, the arrows, BACK, HOME and power cannot be chosen, and a button that already
has another action in the mapper is left alone. BACK cancels while Homebar waits
for a press. It only works where the mapper reads the remote: Input Hook does not
on every TV (the LG C5, for one), and a mapper that is not running gets the rule
for when it runs (Homebar says so). Without Input Hook or Magic Mapper, Homebar
only shows the button's code, to set up in another mapper by hand. A button
Magic Mapper already uses does not reach Homebar while Magic Mapper holds the
remote.

