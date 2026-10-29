# Compatibility

- [How Homebar opens](#how-homebar-opens)
- [webOS versions](#webos-versions)
- [Screen sizes](#screen-sizes)
- [Tested TVs](#tested-tvs)
- [Trying an untested webOS](#trying-an-untested-webos)

## How Homebar opens

Homebar is one panel (`ui/Launcher.qml`), put on the screen in one of three
ways. The installer picks by what the TV has, not by its version number:

| Method | What it is | Needs | Where it fits |
| :--- | :--- | :--- | :--- |
| **Home panel** | The panel is loaded *inside* LG's Home, a QML app (webOS 4 and 5: the ribbon Home, e.g. LG C9); LG's HOME handling, window and lifecycle are kept | Root | webOS 3 to 5, where the patch fits |
| **System HOME (native)** | Homebar replaces LG's Home. On webOS 9 to 11 LG's Home is a Flutter app; Homebar's own QML host (run by the system's `qml-runner`, with a native lifecycle) is mounted under LG Home's id (`com.webos.app.home`), so HOME, BACK out of an app and waking all open it. LG's files stay underneath, and the mount ends with a reboot (a boot hook applies it again) | Root; no Input Hook, no mapper | webOS 10 and 11 (tested on 10.3); webOS 6 to 9 as a trial (works on an LG C1 with 6.5.3) |
| **Additional overlay** | A separate overlay app plus a root helper; LG Home (or Luma, Glasshouse) keeps HOME. Homebar opens from its app tile or from a button mapped in Input Hook or Magic Mapper | The tile: nothing; a button: Input Hook or Magic Mapper; node 8 or newer | webOS 6 or newer (checked on 10) |

The overlay can also bind HOME itself through Input Hook (*HOME via mapper*;
on webOS 10 with a black stand-in in LG Home's place). That is the default on
webOS 6 to 9 and what installs before 0.19.0 use. An update keeps whichever
method an install has; on webOS 10 and 11 it can be changed in *Launcher
settings → Help → Launch method*.

`sh install.sh --probe` says which one fits and why, and changes nothing;
`--home-panel`, `--native-home`, `--additional-overlay` and `--overlay` force
one. The same check is `probe.sh`, next to `install.sh` in the release and
next to `diagnose.sh` once installed; `diagnose.sh` runs it.

The Home panel's patch is made of pieces. The ones the panel cannot do
without must match (the root element, LG's UI controller, Home's foreground
state, `isAppForeground`, declared in Home's `SystemProperties.qml`); the
rest (focus coming back, the BLUE key, LG's hidden mode, voice) go in where
they match and are reported where they do not, so a Home that differs a
little still gets the panel. "QML app" here means a Home whose UI is QML
under `/usr/palm/applications/com.webos.app.home/qml/`; the app manager
reports webOS 4's as `native`, a program that loads that QML.

## webOS versions

LG gives webOS two numbers, and they are easy to mix up. The TV itself, the
installer and `diagnose.sh` report the system's own version (10.3.1); LG's
site, the box and the TV's spec sheets use a name, which since 2022 is a
year: webOS 22 is version 7, webOS 25 is version 10. The model year alone
does not say which one a TV has either: with LG's *webOS Re:New* updates an
older TV can get a newer webOS (an LG UR78 from 2023 updated to webOS 25
reports 10.3.2). This page goes by the version the TV reports, with LG's
name next to it.

| The TV reports | LG calls it | First on (model year) | LG Home | Method the installer picks | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1.x – 2.x | webOS 1.0 – 2.0 | 2014–2015 | Web app | — (no variant fits: no QML Home, node 0.10) | Not supported |
| 3.x | webOS 3.0, 3.5 | 2016–2017 | QML | Home panel, if the patch fits | Untested |
| 4.x | webOS 4.0, 4.5 | 2018–2019 | QML | Home panel | **Tested on 4.10** (webOS 4.5) |
| 5.x | webOS 5.0 | 2020 | QML, the same kind of ribbon as 4.x | Home panel (the patch fits; else the overlay) | **Tested on 5.6** (LG NANO80 and UN73, by users) |
| 6.x | webOS 6.0 | 2021 | QML, a new full-screen Home | Overlay, HOME via Input Hook; LG's Home kept unless `--replace-lg-home`. System HOME: `--try-native-home` trial. The Home panel in LG's full-screen Home: `--home-panel`, experimental (no picture behind it: that Home covers the app) | **Tested on 6.3 and 6.5** (LG C1 and UP78, by users); System HOME **works on a C1 with 6.5.3** (by a user) |
| 7.x | webOS 22 | 2022 | QML, as far as known; the full-screen Home | Overlay, HOME via Input Hook; LG's Home kept unless `--replace-lg-home` | Overlay **tested on 7.5** (a 2022 TV, by a user); System HOME: `--try-native-home` trial, untested |
| 8.x | webOS 23 | 2023 | QML, as far as known; the full-screen Home | Most likely the overlay, as on 6.x | Untested; System HOME: `--try-native-home` trial |
| 9.x | webOS 24 | 2024 | Flutter, like 10.x | Overlay, HOME via Input Hook; LG's Home kept unless `--replace-lg-home`. System HOME is the most likely next one to work: Glasshouse and Luma replace LG's Home on it | Untested; System HOME: `--try-native-home` trial |
| 10.x | webOS 25 | 2025 | Flutter | System HOME (Homebar as the TV's Home); the additional overlay when another launcher owns HOME; the overlay with the black stand-in for installs that bound HOME in Input Hook | **Tested on 10.3** (System HOME on a B4, overlay on a UR78) |
| 11.x | webOS 26 | 2026 | Flutter, like 10.x | System HOME, as on 10.x (Glasshouse and Luma report it working) | Untested on hardware |

What the untested rows rest on:

- **Home panel.** LG's Home was a QML app
  (`/usr/palm/applications/com.webos.app.home/qml`) from webOS 3 to 5, and the
  patch needs only the few things every one of them has. It was written against
  the ribbon Home of webOS 4; the full-screen Home of webOS 6 is a different
  app, so there the installer goes on with the overlay (it went on an LG C1 with
  webOS 6.3.2).
- **Overlay.** It needs what the Homebrew Channel gives any rooted TV and a node
  new enough for the helper (webOS 3 and 4 ship node 0.12, webOS 5 node 8,
  webOS 6 and later node 12 or newer). A button needs Input Hook or Magic Mapper.
- **System HOME** is the same idea as the black stand-in: the app manager is
  made to reread an app mounted under LG Home's id (a block and release of the
  one app, as [Glasshouse](https://github.com/rorygallagher2024/glasshouse)
  does). Glasshouse reports its replacement Home working on webOS 7, 9 and 10
  (11 experimentally) and [Luma](https://github.com/ecklf/lg-luma) lists
  takeover on 5, 6, 10 and 11 and fails on 4. On webOS 5 and 6 the app manager
  cannot reread a mounted Home manifest, so Luma replaces LG Home's program
  instead; Homebar's trial does the same on webOS 6, with a script that runs the
  system's `qml-runner` on Homebar's host (it worked on an LG C1, webOS 6.5.3).
  Hence the gate on 10/11 and the opt-in trial on 6 to 9.

Other models with the tested webOS versions may work. If the patch does not
fit a webOS 4 TV's Home (another firmware), the installer says so and stops
without changing anything.

Some webOS 4 and 5 TVs (the 2019 UM series, a 2020 NANO80 and UN73, for
three) have two Homes and a *Home
screen* setting to choose between them: *Basic*, LG's ribbon
(`com.webos.app.home`), and *New*, a full-screen one
(`com.webos.app.fullhome`). The panel lives in the Basic one, so on these
TVs the Home screen has to be set to *Basic*; with *New*, HOME opens LG's
New Home and the panel never shows. The TV keeps the choice in its
*general* settings: `defaultApps.home` is `com.webos.app.home` for Basic.
`--probe`, the installer and
`diagnose.sh` say when a TV has the New Home, and whether it is the one
running.

## Screen sizes

The panel lays itself out for the screen it gets. LG's UI runs at 1920×1080
on FHD and UHD TVs (the TV scales it to the panel) and at 1280×720 on HD
ones; the panel scales every length with the screen, keeps the rail inside
the right margin whatever the TV's inputs are called, and fills a wider
screen with more columns in *Apps*. The overlay takes the screen's size
when it is smaller than FHD and stays at 1920×1080 otherwise; the Home panel
fills LG's window. `tools/render-panel.py` draws the panel at any size on a
computer, see [Development](development.md#checking-the-layout).

The TV's inputs are read from the TV: a set with two HDMI ports shows two
pills, one with DisplayPort or USB-C shows those too.

## Tested TVs

| TV | webOS (LG's name) | Firmware | Method | Last tested with |
| :--- | :--- | :--- | :--- | :--- |
| LG OLED55C9PLA (C9, 2019) | 4.10.2 (webOS 4.5) | 05.50.00 | Home panel | 0.19.2 |
| LG OLED77B46LA (B4, 2024) | 10.3.1 (webOS 25) | 33.31.68 | System HOME (native) and additional overlay | 0.19.1 |
| LG 43UR78006LK (UR78, 2023, updated to webOS 25) | 10.3.2 (webOS 25) | 33.31.75 | Overlay, LG's Home kept (`--keep-lg-home`) | 0.14.0, by a user |
| LG 43UM7100PLB (UM71, 2019) | 4.10.2 (webOS 4.5) | 05.40.97 | Home panel, with the TV's Home screen on *Basic* | 0.14.1, by a user |
| LG OLED55B9PLA (B9, 2019) | 4.10.2 (webOS 4.5) | 05.50.00 | Home panel | 0.15.1, by a user |
| LG OLED55E9PLA (E9, 2019) | 4.10.2 (webOS 4.5) | 05.50.00 | Home panel, with the TV's Home screen on *Basic* | 0.16.0, by a user |
| LG 55NANO803NA (NANO80, 2020) | 5.6.2 (webOS 5.0) | 04.64.00 | Home panel | 0.15.2, by a user |
| LG 55UN731C0SC (UN73, 2020) | 5.6.2 (webOS 5.0) | 04.64.00 | Home panel, with the TV's Home screen on *Basic* | 0.15.3, by a user |
| LG 75UN9070AUD (UN90, 2020) | 5.6.2 (webOS 5.0) | 04.64.00 | Home panel, with the TV's Home screen on *Basic* | 0.17.1, by a user |
| LG OLED55C16LA (C1, 2021) | 6.3.2 (webOS 6.0) | 03.34.80 | Overlay, LG's Home kept | 0.14.0, by a user |
| LG 43UP78006LB (UP78, 2021) | 6.5.3 (webOS 6.0) | 03.53.45 | Overlay, LG's Home kept | 0.15.1, by a user |
| LG OLED65C11LB (C1, 2021) | 6.5.3 (webOS 6.0) | 03.53.45 | System HOME (trial, `--try-native-home`) | 0.19.2-rc4, by a user |
| A 2022 LG TV (family HE_DTV_C22P) | 7.5.8 (webOS 22) | 04.56.35 | Overlay, LG's Home kept | 0.16.0, by a user |

## Trying an untested webOS

`sh install.sh` on an untested webOS says so and goes on with the method that
fits; `--probe` first shows what it would do. Two more things help:

- **webOS 6, 7, 8 or 9:** `sh install.sh --try-native-home` tries System HOME. It
  checks within 25 seconds that the app manager runs Homebar's Home and gives
  LG's Home back at once if not; it writes `/tmp/homebar-native-trial.txt`
  ([details](install.md#trying-system-home-on-webos-6-to-9)).
- **Any other TV:** the file from `diagnose.sh` (see
  [Troubleshooting](troubleshooting.md#diagnose)).

Whether it worked or not, open a
[GitHub issue](https://github.com/rawinek/webos-homebar/issues) with the TV
model, the webOS version (*Settings → General → About this TV*), the method
that was installed, what HOME did, and that file. What can go wrong and how to
get LG's Home back is in
[Troubleshooting → An untested webOS](troubleshooting.md#an-untested-webos).

How each method works is in [How it works](how-it-works.md).
