"""The Home panel in a made-up full-screen Home shaped like webOS 6's (no
focusIn(), the root hands focus to LG's controller): after the patch the panel
gets the focus and the remote's keys, and what it went through reaches the
panel log. Runs the patched main.qml in Qt (offscreen) with a stand-in panel
and a stand-in setup server on 127.0.0.1:8898."""
import http.server, json, os, pathlib, subprocess, sys, tempfile, threading
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
from PySide6.QtCore import QUrl, QTimer, Qt, QEvent
from PySide6.QtGui import QGuiApplication, QKeyEvent
from PySide6.QtQuick import QQuickView

ROOT = pathlib.Path(__file__).resolve().parent.parent
lines = []
class Log(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('Content-Length') or 0)
        lines.append(self.rfile.read(n).decode())
        self.send_response(200); self.end_headers(); self.wfile.write(b'{}')
    def log_message(self, *a): pass
srv = http.server.HTTPServer(('127.0.0.1', 8898), Log)
threading.Thread(target=srv.serve_forever, daemon=True).start()

t = tempfile.TemporaryDirectory(); d = pathlib.Path(t.name)
(d/'main.original.qml').write_text('''import QtQuick 2.4
FocusScope {
    id: rootWindow
    width: 1920; height: 1080
    visible: true
    focus: true
    property bool active: true
    onActiveFocusChanged: {
        rootWindow.focus = (activeFocus && rootWindow.active) ? (uiController.forceActiveFocus(), true) : false;
    }
    property var systemProperties: QtObject { property bool isAppForeground: true; property bool isAppReadyToUse: true }
    property var interfaces: QtObject { property var application: QtObject { function closeApp() {} } }
    function keyPressEvent(keyCode) {
        uiController.fivewayKeyEvent(keyCode);
    }
    Component.onCompleted: { var x = systemProperties.isAppForeground; var y = interfaces.application; }
    // UI Controller
    UIController {
        id: uiController
        anchors.fill: parent
    }
}
''')
(d/'UIController.original.qml').write_text('''import QtQuick 2.4
FocusScope {
    id: root
    property bool isHiddenMode: false
    property string currentMode: ""
    function startApp() {}
    function fivewayKeyEvent(k) {}
    Keys.onPressed: event.accepted = true
}
''')
(d/'SystemProperties.original.qml').write_text('import QtQuick 2.4\nItem {\n    property bool isAppForeground: true\n}\n')
p = subprocess.run(['node', str(ROOT/'webos4/patch-home.js'), str(d)], capture_output=True, text=True)
assert p.returncode == 0, p.stdout + p.stderr
assert 'focus hand-over' not in p.stdout, p.stdout          # the webOS 6 hand-over was found and patched
main = (d/'main.qml').read_text()
main = main.replace('import WebOS.Global 1.0', 'import "WebOS.js" as WebOS')
main = main.replace('file:///var/lib/webosbrew/rawin-launcher/current/Launcher.qml', QUrl.fromLocalFile(str(d/'Panel.qml')).toString())
(d/'main.qml').write_text(main)
(d/'WebOS.js').write_text('.pragma library\nvar Key_webOS_Blue = 0x01200014;\n')
# The stand-in panel answers Right and leaves Up to LG's UI.
(d/'Panel.qml').write_text('''import QtQuick 2.4
FocusScope {
    property var hostWindow
    property bool ready
    property bool foreground
    property int rights: 0
    signal timeoutRequested()
    signal stockRequested()
    signal closeRequested()
    Keys.onPressed: { if (event.key === Qt.Key_Right) { rights++; event.accepted = true; } }
}
''')

app = QGuiApplication(sys.argv)
view = QQuickView(); view.setSource(QUrl.fromLocalFile(str(d/'main.qml')))
assert view.status() == QQuickView.Ready, [e.toString() for e in view.errors()]
view.show()
root = view.rootObject()
def key(k):
    for kind in (QEvent.KeyPress, QEvent.KeyRelease):
        QGuiApplication.sendEvent(view, QKeyEvent(kind, k, Qt.NoModifier))
def step():
    # Home coming back to the front: LG's root takes the focus and hands it on.
    root.setProperty('focus', False); root.forceActiveFocus()
    key(Qt.Key_Right); key(Qt.Key_Right); key(Qt.Key_Up)
    QTimer.singleShot(600, app.quit)
QTimer.singleShot(300, step)
QTimer.singleShot(5000, app.quit)
app.exec()
srv.shutdown()
panel = root.findChild(object, 'cleanHomeLoader')
text = '\n'.join(lines)
assert 'panel status ready' in text, text
assert 'panel loaded; foreground true, ready true' in text, text
assert 'window: ' in text and 'window: not readable' not in text, text
assert 'key %d not taken by the panel' % int(Qt.Key_Up) in text, text
assert '\nfocus panel' in text and 'focus LG Home' not in text, text
assert 'TypeError' not in text
item = [o for o in root.findChildren(object) if o.property('rights') is not None]
assert item and item[0].property('rights') == 2, 'the panel did not get the Right presses'
print('PASS Home panel on a webOS 6 shaped Home: focus and keys reach the panel, the panel log records it')
