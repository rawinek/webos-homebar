#!/usr/bin/env python3
"""Draw the theme pictures in docs/themes/ from the real panel (ui/Launcher.qml).

For each theme in ui/Themes.js: <id>.png, the lower part of Home with an HDMI
input focused, and <id>-colors.svg, the accent and the base side by side.

Usage: tools/render-themes.py
Needs Python 3 with PySide6 (pip install PySide6) and a display; not the TV.
The webOS-only parts of the panel (Luna services, webOS keys) are stubbed out,
apps get plain coloured icons, and a gradient stands in for the picture.
"""
import json
import shutil
import re
import sys
import tempfile
from pathlib import Path

from PySide6.QtCore import QEventLoop, QRect, Qt, QTimer, QUrl
from PySide6.QtGui import QColor, QFont, QGuiApplication, QImage, QPainter
from PySide6.QtQuick import QQuickView

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs/themes"
FONTS = "file:///var/lib/webosbrew/rawin-launcher/current/fonts/"
APPS = [("netflix", "Netflix", "#e50914"), ("youtube.leanback.v4", "YouTube", "#ff0033"),
        ("amazon", "Prime Video", "#1a98ff"), ("org.jellyfin.webos", "Jellyfin", "#aa5cc3"),
        ("com.immich.webos", "Immich", "#4250af")]
INPUTS = [("PlayStation 5", True), ("Apple TV", True), ("", False), ("", False)]


def themes():
    """(id, accent, base) from ui/Themes.js; for the default, its focused and plain tile."""
    text = (ROOT / "ui/Themes.js").read_text()
    return [(m[0], m[1] or "#f2f3f5", m[2] or "#26282e")
            for m in re.findall(r'\{id: "(\w+)"(?:, accent: "(#\w+)", base: "(#\w+)")?\}', text)]


def panel(app_dir):
    """The panel as a desktop Qt 6 can load it, plus Config.js and app icons."""
    q = (ROOT / "ui/Launcher.qml").read_text()
    q = q.replace("import QtGraphicalEffects 1.0\n", "import Qt5Compat.GraphicalEffects\n")
    q = q.replace("import WebOSServices 1.0\n", "").replace("import WebOS.Global 1.0\n", 'import "WebOS.js" as WebOS\n')
    q = q.replace(FONTS, (ROOT / "ui/fonts").as_uri() + "/")
    start = q.index("    Service {\n        id: launchService")
    end = q.index("    Timer { id: launchTimeout;")
    stubs = "".join("    QtObject { id: %s; function callService(a) {} }\n" % name for name in
                    ("launchService", "catalog", "foregroundInfo", "localeService", "inputService", "updateService", "backupService", "closeAppsService"))
    stubs += "    function loadInputs() {}\n    function updateRun(step, channel) {}\n    function backupRun(step, data) {}\n    function restartHomebar() {}\n    function modeRun(mode) {}\n"
    stubs += "    function buttonLoadRun() {}\n    function buttonCaptureRun(id, fresh) {}\n    function buttonBindRun(code) {}\n    function buttonUnbindRun() {}\n"
    (app_dir / "Launcher.qml").write_text(q[:start] + stubs + q[end:])
    (app_dir / "WebOS.js").write_text(".pragma library\nvar Key_webOS_Back = 461;\nvar Key_webOS_Yellow = 405;\nvar Key_webOS_Red = 403;\n")
    for name in ("FavouriteStore.qml", "Strings.js", "Themes.js", "About.js", "DeviceIcons.js", "DeviceIcon.qml"):
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
    inputs = [{"id": "com.webos.app.hdmi%d" % (i + 1), "title": "HDMI %d" % (i + 1), "label": "", "cec": d, "name": d, "present": p}
              for i, (d, p) in enumerate(INPUTS)]
    styles = json.loads((ROOT / "config/launcher.json").read_text()).get("styles", {})
    config = {"version": "", "platform": "", "apps": apps, "favourites": [a["id"] for a in apps],
              "styles": styles, "inputs": inputs, "excluded": []}
    (app_dir / "Config.js").write_text(".pragma library\n" + "".join(
        "var %s = %s;\n" % (k, json.dumps(v)) for k, v in config.items()))
    # Half size on screen, full size in the picture (a 2x display) or scaled up.
    (app_dir / "main.qml").write_text('''import QtQuick
Item {
    width: 960; height: 540
    Item {
        width: 1920; height: 1080; scale: 0.5; transformOrigin: Item.TopLeft
        Rectangle { anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#5b7fa3" }
                GradientStop { position: 0.6; color: "#9b8a6e" }
                GradientStop { position: 1.0; color: "#2f3a2c" } } }
        Launcher { id: shell; anchors.fill: parent; foreground: true }
    }
    function show(theme, selected) {
        shell.settings = shell.validSettings({lang: "en", theme: theme, exitTo: "last", clock: true, title: true, beta: false});
        shell.page = "home"; shell.selected = selected;
    }
}
''')


def wait(ms):
    loop = QEventLoop()
    QTimer.singleShot(ms, loop.quit)
    loop.exec()


def swatch(path, accent, base):
    path.write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" width="112" height="48" viewBox="0 0 112 48">'
        '<rect x="1" y="1" width="46" height="46" rx="12" fill="%s" stroke="#8888" stroke-width="1"/>'
        '<rect x="57" y="1" width="54" height="46" rx="12" fill="%s" stroke="#8888" stroke-width="1"/>'
        '</svg>\n' % (accent, base))


def main():
    app = QGuiApplication(sys.argv)
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        app_dir = Path(tmp)
        panel(app_dir)
        view = QQuickView()
        view.setSource(QUrl.fromLocalFile(str(app_dir / "main.qml")))
        if view.status() != QQuickView.Ready:
            raise SystemExit("\n".join(e.toString() for e in view.errors()))
        view.show()
        wait(2500)
        root = view.rootObject()
        for theme_id, accent, base in themes():
            root.show(theme_id, len(APPS) + 1)   # HDMI 2: a focused pill, the theme's own glow
            wait(1500)
            shot = view.grabWindow().scaled(1920, 1080, Qt.IgnoreAspectRatio, Qt.SmoothTransformation)
            shot.copy(QRect(0, 700, 1920, 380)).scaled(1280, 253, Qt.IgnoreAspectRatio, Qt.SmoothTransformation) \
                .save(str(OUT / (theme_id + ".png")))
            swatch(OUT / (theme_id + "-colors.svg"), accent, base)
            print("docs/themes/" + theme_id)


if __name__ == "__main__":
    main()
