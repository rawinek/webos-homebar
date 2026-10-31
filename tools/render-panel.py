#!/usr/bin/env python3
"""Draw the panel (ui/Launcher.qml) at any screen size, on a computer.

The panel lays itself out for the size it gets: 1920x1080 on FHD and UHD
TVs, 1280x720 on HD ones. This renders a set of scenes at a size, so a
change can be checked at every size without a TV: Home with seven
favourites and long HDMI-CEC names, a favourite focused, recent apps and
Live TV on the rail, hidden inputs and apps, Apps in each order, System with
an update waiting with its notes, About, the settings and a setting's values,
the weather's place with its code (from the setup server, shared/setup.js,
when one runs on this computer), the weather in each of its symbols, the larger text
size, the key hints hidden, the hidden inputs list, no favourites, a set with two inputs,
editing a favourite or a shortcut, and the shortcuts with System moved between them.

Usage: tools/render-panel.py [--size 1920x1080] [--out dist/render] [--theme default]
Needs Python 3 with PySide6 (pip install PySide6) and a display (or Xvfb);
not the TV. The webOS-only parts of the panel are stubbed out, as in
render-themes.py; the icons are plain coloured squares, so the glow read
from them is their colour.
"""
import shutil
import argparse
import json
import sys
import tempfile
from pathlib import Path

from PySide6.QtCore import QEventLoop, Qt, QTimer, QUrl
from PySide6.QtGui import QColor, QFont, QGuiApplication, QImage, QPainter
from PySide6.QtQuick import QQuickView

ROOT = Path(__file__).resolve().parent.parent
FONTS = "file:///var/lib/webosbrew/rawin-launcher/current/fonts/"
APPS = [("netflix", "Netflix", "#e50914"), ("youtube.leanback.v4", "YouTube", "#ff0033"),
        ("amazon", "Prime Video", "#1a98ff"), ("org.jellyfin.webos", "Jellyfin", "#aa5cc3"),
        ("com.immich.webos", "Immich", "#4250af"), ("cdp-30", "Plex", "#e5a00d"),
        ("com.webos.app.browser", "Web Browser", "#3a7bd5"), ("spotify", "Spotify", "#1db954"),
        ("disney", "Disney+", "#0f3fa0"), ("hbomax", "Max", "#5b2ea6"), ("twitch", "Twitch", "#9146ff"),
        ("kodi", "Kodi", "#17b2e7"), ("steamlink", "Steam Link", "#1b2838"), ("moonlight", "Moonlight", "#1f1f1f"),
        ("emby", "Emby", "#52b54b"), ("vlc", "VLC", "#ff8800"), ("tidal", "TIDAL", "#000000"),
        ("deezer", "Deezer", "#a238ff"), ("weather", "Weather", "#2b8ae6"), ("photos", "Photos", "#e8734a"),
        ("music", "Music", "#fc3c44"), ("gallery", "Gallery", "#8e44ad"), ("news", "News", "#c0392b"),
        ("sport", "Sport", "#27ae60"), ("kids", "Kids", "#f39c12"), ("radio", "Radio", "#16a085"),
        ("podcasts", "Podcasts", "#9b59b6"), ("games", "Games", "#2c3e50"), ("files", "File Manager", "#7f8c8d"),
        ("screensaver", "Screensaver", "#34495e")]
INPUTS = [("PlayStation 5", True), ("Apple TV 4K", True), ("Nintendo Switch", True), ("Chromecast with Google TV", False)]
NOTES = ("### New\n\u2022 The weather in the chip at the top, for a place chosen on a phone.\n"
         "\u2022 The clock, what is on screen and the weather can each be hidden.\n\n### Fixed\n\u2022 Something small.")
INPUTS_SMALL = [("Blu-ray Player", True), ("", False)]

MAIN = '''import QtQuick
Item {
    width: %d; height: %d
    Rectangle { anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#5b7fa3" }
            GradientStop { position: 0.6; color: "#9b8a6e" }
            GradientStop { position: 1.0; color: "#2f3a2c" } } }
    Launcher { id: shell; anchors.fill: parent; foreground: true; nowTitle: "YouTube" }
    // One scene from a JSON spec: the settings (checked like saved ones),
    // the lists the TV would have given, and the page and focus to show.
    function scene(json) {
        var s = JSON.parse(json);
        shell.settings = shell.validSettings(s.settings || {});
        shell.favouriteIds = s.favs; shell.allInputs = s.inputs;
        shell.hiddenIds = s.hidden || []; shell.hiddenInputs = s.hiddenInputs || [];
        shell.usage = s.usage || {};
        shell.updateInfo = {state: s.updateState || "idle", latest: "9.9.9", failed: "", notes: s.notes || ""};
        if (s.weather) shell.weather = s.weather;
        shell.page = "home"; shell.selected = 0; shell.pane = 0;
        shell.editIndex = -1; shell.editSourceIndex = -1; shell.editActionIndex = -1;
        shell.page = s.page; shell.selected = s.selected || 0;
        if (s.setting !== undefined) shell.selected = shell.settingKeys.indexOf(s.setting);
        if (s.editFav !== undefined) { shell.editIndex = s.editFav; shell.selected = s.editFav; }
        if (s.editSource !== undefined) { shell.editSourceIndex = s.editSource; shell.selected = shell.favSlots + s.editSource; }
        if (s.editAction !== undefined) { shell.editActionIndex = s.editAction; shell.selected = shell.favSlots + shell.sourceCount + s.editAction; }
        if (s.pane) { shell.enterValues(); if (s.valueIndex !== undefined) shell.valueIndex = s.valueIndex; }
    }
    // A new app list, as the TV would send one: the glow reader runs through the icons.
    function glow() { shell.applications = shell.applications.slice(0); }
    function focusPanel() { shell.forceActiveFocus(); }
}
'''


def inputs(spec):
    return [{"id": "com.webos.app.hdmi%d" % (i + 1), "title": "HDMI %d" % (i + 1), "label": "", "cec": d, "name": d, "present": p}
            for i, (d, p) in enumerate(spec)]


def panel(app_dir):
    """The panel as a desktop Qt 6 can load it, plus Config.js and app icons."""
    q = (ROOT / "ui/Launcher.qml").read_text()
    q = q.replace("import QtGraphicalEffects 1.0\n", "import Qt5Compat.GraphicalEffects\n")
    q = q.replace("import WebOSServices 1.0\n", "").replace("import WebOS.Global 1.0\n", 'import "WebOS.js" as WebOS\n')
    q = q.replace(FONTS, (ROOT / "ui/fonts").as_uri() + "/")
    start = q.index("    Service {\n        id: launchService")
    end = q.index("    Timer { id: launchTimeout;")
    stubs = "".join("    QtObject { id: %s; function callService(a) {} }\n" % name for name in
                    ("launchService", "catalog", "foregroundInfo", "localeService", "inputService", "updateService", "backupService"))
    # Counted, so a test can see the close-apps shortcut call its service.
    stubs += "    QtObject { id: closeAppsService; function callService(a) { shell.notice = 'closeAppsCalled'; } }\n"
    stubs += "    function loadInputs() {}\n    function updateRun(step, channel) {}\n    function backupRun(step, data) {}\n    function restartHomebar() {}\n    function modeRun(mode) { shell.notice = 'mode:' + mode; }\n"
    stubs += "    function buttonLoadRun() {}\n    function buttonCaptureRun(id, fresh) {}\n    function buttonBindRun(code) {}\n    function buttonUnbindRun() {}\n"
    (app_dir / "Launcher.qml").write_text(q[:start] + stubs + q[end:])
    (app_dir / "WebOS.js").write_text(".pragma library\nvar Key_webOS_Back = 461;\nvar Key_webOS_Yellow = 405;\nvar Key_webOS_Red = 403;\n")
    for name in ("FavouriteStore.qml", "Strings.js", "Themes.js", "About.js"):
        (app_dir / name).write_bytes((ROOT / "ui" / name).read_bytes())
    for name in ("DeviceIcons.js", "DeviceIcon.qml"):
        (app_dir / name).write_bytes((ROOT / "ui" / name).read_bytes())
    shutil.copytree(ROOT / "ui/input-icons", app_dir / "input-icons")
    apps = []
    for app_id, title, color in APPS:
        icon = QImage(240, 240, QImage.Format_RGB32)
        icon.fill(QColor(color))
        p = QPainter(icon)
        p.setPen(QColor("#ffffff"))
        p.setFont(QFont("Helvetica", 110, QFont.Bold))
        p.drawText(icon.rect(), Qt.AlignCenter, title[0])
        p.end()
        icon.save(str(app_dir / (app_id + ".png")))
        apps.append({"id": app_id, "title": title, "icon": (app_dir / (app_id + ".png")).as_uri()})
    styles = json.loads((ROOT / "config/launcher.json").read_text()).get("styles", {})
    config = {"version": (ROOT / "VERSION").read_text().strip(), "platform": "Home panel", "webos": "4.10.2",
              "apps": apps, "favourites": [a["id"] for a in apps[:7]], "styles": styles,
              "inputs": inputs(INPUTS), "excluded": [], "exitTarget": True}
    (app_dir / "Config.js").write_text(".pragma library\n" + "".join(
        "var %s = %s;\n" % (k, json.dumps(v)) for k, v in config.items()))


def wait(ms):
    loop = QEventLoop()
    QTimer.singleShot(ms, loop.quit)
    loop.exec()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--size", default="1920x1080", help="the panel's size (default: 1920x1080; HD TVs: 1280x720)")
    parser.add_argument("--out", default=str(ROOT / "dist/render"), help="output directory (default: dist/render)")
    parser.add_argument("--theme", default="default", help="a theme id from ui/Themes.js")
    args = parser.parse_args()
    w, h = (int(v) for v in args.size.split("x"))
    app = QGuiApplication(sys.argv)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        app_dir = Path(tmp)
        panel(app_dir)
        (app_dir / "main.qml").write_text(MAIN % (w, h))
        view = QQuickView()
        view.setSource(QUrl.fromLocalFile(str(app_dir / "main.qml")))
        if view.status() != QQuickView.Ready:
            raise SystemExit("\n".join(e.toString() for e in view.errors()))
        view.show()
        wait(800)
        root = view.rootObject()
        root.glow()
        wait(2500)
        favs = [a[0] for a in APPS[:7]]
        base = {"favs": favs, "inputs": inputs(INPUTS), "settings": {"theme": args.theme}}
        theme = {"theme": args.theme}

        def scene(name, **spec):
            full = dict(base)
            full.update(spec)
            return name, full
        scenes = [
            scene("home-hdmi2", page="home", selected=8),
            scene("home-fav0", page="home", selected=0, settings=dict(theme, hours="12")),
            scene("home-tv", page="home", selected=0, settings=dict(theme, tv=True)),
            scene("home-tv-labels", page="home", selected=8, settings=dict(theme, tv=True, inputText="labelHdmi")),
            scene("home-hidden-shown", page="home", selected=10, settings=dict(theme, showHidden=True), hiddenInputs=["com.webos.app.hdmi4"], hidden=["kids"]),
            scene("apps", page="apps", selected=14),
            scene("apps-az-hidden", page="apps", selected=13, settings=dict(theme, sort="az", showHidden=True), hidden=["kids", "kodi"]),
            scene("system-update", page="system", selected=1, updateState="available"),
            scene("settings-about", page="settings", setting="about"),
            scene("settings", page="settings", setting="theme"),
            scene("settings-end", page="settings", setting="beta", updateState="available"),
            scene("settings-update", page="settings", setting="update", updateState="available", notes=NOTES),
            scene("settings-place", page="settings", setting="place"),
            scene("settings-temperature", page="settings", setting="temperature", pane=1, valueIndex=1),
            scene("settings-restart", page="settings", setting="restart"),
            scene("settings-inputs", page="settings", setting="sources", pane=1, valueIndex=2, settings=dict(theme, tv=True)),
            scene("settings-shortcuts", page="settings", setting="homeShortcuts", pane=1, valueIndex=1),
            scene("settings-topbar", page="settings", setting="topBar", pane=1, valueIndex=1),
            scene("settings-input-text", page="settings", setting="inputText", pane=1, valueIndex=2),
            scene("settings-input-overflow", page="settings", setting="inputOverflow", pane=1, valueIndex=1),
            scene("settings-hints", page="settings", setting="hints", settings=dict(theme, hints=False)),
            scene("settings-timeout", page="settings", setting="timeout", pane=1, valueIndex=3, settings=dict(theme, timeout=10)),
            scene("settings-values", page="settings", setting="theme", pane=1, valueIndex=3),
            scene("home-larger", page="home", selected=8, settings=dict(theme, size="larger")),
            scene("home-nohints", page="home", selected=0, settings=dict(theme, hints=False)),
            scene("home-nofavs", page="home", selected=0, favs=[]),
            scene("home-2inputs", page="home", selected=3, favs=favs[:3], inputs=inputs(INPUTS_SMALL)),
            scene("home-shortcuts", page="home", selected=11, settings=dict(theme, homeActionOrder=["system", "apps", "closeApps"])),
            scene("home-shortcut-focus", page="home", selected=13),
            scene("home-shortcut-close", page="home", selected=11),
            scene("home-edit-fav", page="home", editFav=2),
            scene("home-edit-shortcut", page="home", settings=dict(theme), editAction=1),
            scene("home-edit-system", page="home", settings=dict(theme), editAction=2),
            scene("home-edit-input", page="home", settings=dict(theme, tv=True), editSource=1),
            scene("home-edit-input-last", page="home", settings=dict(theme, tv=True), editSource=4),
            scene("home-edit-fav-first", page="home", editFav=0),
        ]
        scenes += [scene("weather-%d-%s" % (code, "day" if day else "night"), page="home", selected=0, weather={"ok": True, "temp": -3 + code % 30, "apparent": -5 + code % 30, "code": code, "day": day})
                   for code, day in ((0, True), (0, False), (2, True), (2, False), (3, True), (45, True), (61, True), (73, True), (95, True))]
        scenes.append(scene("weather-apparent", page="home", selected=0, settings=dict(theme, temperature="apparent"), weather={"ok": True, "temp": 18, "apparent": 23, "code": 2, "day": True}))
        for name, spec in scenes:
            root.scene(json.dumps(spec))
            wait(700)
            target = out / ("%s-%s.png" % (args.size, name))
            view.grabWindow().save(str(target))
            print(target)


if __name__ == "__main__":
    main()
