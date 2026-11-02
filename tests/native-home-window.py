"""Cold native parameters and warm HOME events; needs PySide6, offscreen Qt."""
import importlib.util,json,tempfile
from pathlib import Path
from PySide6.QtCore import QUrl, Qt
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
ROOT=Path(__file__).resolve().parents[1]
s=importlib.util.spec_from_file_location('render',ROOT/'tools/render-panel.py');rp=importlib.util.module_from_spec(s);s.loader.exec_module(rp)
app=QGuiApplication([])
with tempfile.TemporaryDirectory() as tmp:
 d=Path(tmp);rp.panel(d)
 with (d/'Config.js').open('a') as f:f.write('\nvar nativeHome = true;\nvar webos = "11.2.0";\n')
 q=(ROOT/'webos10/app/main.qml').read_text().replace('import Eos.Window 0.1','').replace('WebOSWindow {','Window {\n    property string appId\n    property string windowType')
 q=q.replace('    Panel {','    Launcher {').replace('Qt.application.arguments','testNativeArguments')
 args=['qml-runner',json.dumps({'appId':'com.webos.app.home','parameters':{'preload':True}})]
 q=q.replace('    id: win','    id: win\n    property var testNativeArguments: '+json.dumps(args))
 (d/'main.qml').write_text(q)
 engine=QQmlApplicationEngine();engine.rootContext().setContextProperty('params',{})
 engine.load(QUrl.fromLocalFile(str(d/'main.qml')));assert engine.rootObjects()
 win=engine.rootObjects()[0];rp.wait(700)
 assert win.property('preloaded') is True and win.property('visible') is False
 print('PASS cold native parameters start hidden')
 engine.rootContext().setContextProperty('params',{'source':'HOME'});rp.wait(250)
 assert win.property('visible') is True
 print('PASS first HOME shows preloaded host')
 engine.rootContext().setContextProperty('params',{});rp.wait(300)
 assert win.property('visible') is False
 print('PASS second HOME hides host')
 engine.rootContext().setContextProperty('params',{});rp.wait(300)
 assert win.property('visible') is True
 print('PASS repeated empty params still show on next HOME')
 # A webOS 11 TV: the panel's window was still shown but had lost the focus to
 # the picture; HOME must bring it up, not take it for "close".
 from PySide6.QtGui import QWindow
 other=QWindow();other.resize(100,100);other.show();other.requestActivate();rp.wait(200)
 if not win.property('active'):
  seen=[];win.visibleChanged.connect(lambda v:seen.append(v))
  engine.rootContext().setContextProperty('params',{'n':1});rp.wait(300)
  assert win.property('visible') is True and win.property('active') is True,'HOME hid an inactive window'
  assert seen[:2]==[False,True],('shown but inactive: unmapped and mapped again',seen)
  print('PASS HOME on a shown but inactive window maps it again and shows it')
 else: print('SKIP this Qt platform cannot take the focus from the window')
 other.close()
 # webOS 11 (issue #16): BACK only hid the window and the TV kept the remote on
 # the hidden Home, so the card underneath is launched again to take it back.
 home=[o for o in win.findChildren(object) if o.property('closeReason') is not None][0]
 if not win.property('visible'):engine.rootContext().setContextProperty('params',{'n':2});rp.wait(300)
 # BACK closes on its release: the window stays for the release the compositor delivers.
 from PySide6.QtTest import QTest
 win.requestActivate();rp.wait(200);home.forceActiveFocus()
 home.setProperty('httpCalls',[]);win.setProperty('backMode','')
 QTest.keyPress(win,Qt.Key_Escape);rp.wait(300)
 assert win.property('visible') is True,'BACK press alone must not close'
 QTest.keyRelease(win,Qt.Key_Escape);rp.wait(400)
 assert win.property('visible') is False and not any('launch' in c or 'home-key' in c for c in home.property('httpCalls')),home.property('httpCalls')
 print('PASS BACK closes the panel on its release, and only hides it by default')
 engine.rootContext().setContextProperty('params',{'n':6});rp.wait(300);assert win.property('visible') is True
 home.setProperty('httpCalls',[]);win.setProperty('backMode','key');home.closeHome('back');rp.wait(300)
 assert '/home-key' in home.property('httpCalls') and win.property('visible') is True,home.property('httpCalls')
 rp.wait(1000);assert win.property('visible') is False,'no relaunch came: hidden anyway'
 print('PASS back-mode key sends a HOME key through the TV, and hides without an answer')
 engine.rootContext().setContextProperty('params',{'n':3});rp.wait(300);assert win.property('visible') is True
 home.setProperty('httpCalls',[]);win.setProperty('backMode','card');home.closeHome('back');rp.wait(300)
 assert win.property('visible') is False and '/foreground' in home.property('httpCalls'),home.property('httpCalls')
 print('PASS back-mode card hides and looks up the card underneath afresh')
 engine.rootContext().setContextProperty('params',{'n':5});rp.wait(300);assert win.property('visible') is True
 home.setProperty('httpCalls',[]);win.setProperty('backMode','home');home.closeHome('back');rp.wait(300)
 calls=home.property('httpCalls');assert any(c.startswith('/launch?id=com.webos.app.home') for c in calls),calls
 assert win.property('visible') is True,'back-mode home waits for the relaunch'
 rp.wait(1000);assert win.property('visible') is False,'no relaunch came: hidden anyway'
 print('PASS back-mode home asks the app manager, and hides after a second without an answer')
 engine.rootContext().setContextProperty('params',{'n':4});rp.wait(300)
 home.setProperty('httpCalls',[]);win.setProperty('backMode','');home.closeHome('home');rp.wait(300)
 assert win.property('visible') is False and not any('launch' in c for c in home.property('httpCalls')),'a HOME key close launches nothing'
 print('PASS a HOME that reached the panel as a key only hides it')
