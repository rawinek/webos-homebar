"""Cold native parameters and warm HOME events; needs PySide6, offscreen Qt."""
import importlib.util,json,tempfile
from pathlib import Path
from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
ROOT=Path(__file__).resolve().parents[1]
s=importlib.util.spec_from_file_location('render',ROOT/'tools/render-panel.py');rp=importlib.util.module_from_spec(s);s.loader.exec_module(rp)
app=QGuiApplication([])
with tempfile.TemporaryDirectory() as tmp:
 d=Path(tmp);rp.panel(d)
 with (d/'Config.js').open('a') as f:f.write('\nvar nativeHome = true;\n')
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
  engine.rootContext().setContextProperty('params',{'n':1});rp.wait(300)
  assert win.property('visible') is True and win.property('active') is True,'HOME hid an inactive window'
  print('PASS HOME on a shown but inactive window shows it')
 else: print('SKIP this Qt platform cannot take the focus from the window')
 other.close()
