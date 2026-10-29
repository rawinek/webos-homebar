"""probe.sh and the Home-panel scripts on both Home layouts: Controllers/ (ribbon, webOS 4 and 5)
and UserInterfaceLayer/ (full-screen Home, webOS 6), with disposable TV paths and made-up QML."""
import re, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
MAIN='''import QtQuick 2.12
FocusScope {
    id: rootWindow
    property SystemProperties systemProperties: SystemProperties { appId: rootWindow.appId }
    function focusIn() { interfaces.application.show(); }
    // UI Controller
    UIController {
        id: uiController
        function keyPressEvent(keyCode) { }
    }
}
'''
CTRL='Item {\n    function f() { if(homeShown) { } }\n}\n'
SYS='Item {\n    property bool isAppForeground: false\n}\n'
def tv(layout):
    t=tempfile.TemporaryDirectory();r=Path(t.name)
    q=r/'usr/palm/applications/com.webos.app.home/qml'
    (q/layout).mkdir(parents=True);(q/'AppInitializer').mkdir()
    (q/'main.qml').write_text(MAIN);(q/layout/'UIController.qml').write_text(CTRL);(q/'AppInitializer/SystemProperties.qml').write_text(SYS)
    (r/'proc').mkdir();(r/'proc/mounts').write_text('');(r/'var/lib/webosbrew').mkdir(parents=True)
    return t,r
def probe(r,*args):
    s=(ROOT/'probe.sh').read_text()
    s=re.sub(r'(?<![\w/])(?:/usr/palm/|/var/lib/|/proc/|/etc/)',lambda m:str(r)+m[0],s)
    (r/'probe.sh').write_text(s)
    return subprocess.run(['sh',str(r/'probe.sh'),'panel'],capture_output=True,text=True,env={'PATH':__import__('os').environ['PATH'],'HOMEBAR_PATCH':str(ROOT/'webos4/patch-home.js')},timeout=20)
# the script finds patch-home.js next to itself
for layout,expect_fit in (('Controllers',True),('UserInterfaceLayer',False)):
    t,r=tv(layout)
    try:
        (r/'patch-home.js').write_bytes((ROOT/'webos4/patch-home.js').read_bytes())
        p=probe(r)
        out=p.stdout+p.stderr
        if expect_fit: assert p.returncode==0,out
        else:
            assert p.returncode==1,out
            assert 'full-screen Home of webOS 6' in out and '--home-panel' in out,out
            assert 'fits the panel' in out,out   # the patch itself accepted the made-up Home
    finally:t.cleanup()
# no controller at all
t,r=tv('Other')
try:
    (r/'patch-home.js').write_bytes((ROOT/'webos4/patch-home.js').read_bytes())
    p=probe(r);assert p.returncode==1 and 'no UIController.qml' in p.stdout+p.stderr,p.stdout+p.stderr
finally:t.cleanup()
# every Home-panel script knows both layouts
for f in ('webos4/install.sh','webos4/apply.sh','webos4/uninstall.sh','diagnose.sh','probe.sh'):
    assert 'UserInterfaceLayer/UIController.qml' in (ROOT/f).read_text(),f
print('PASS Home panel layouts: ribbon fits, full-screen Home only on request, no controller refused, scripts know both')
