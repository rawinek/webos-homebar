"""Apps: hold OK opens an app's menu (favourites, hide, and uninstall for an
app the TV marks removable, never Homebar's own helpers), YELLOW still adds the
favourite at once, an uninstall asks first (on No), and an app that leaves the
TV's list leaves the favourites and the hidden list too."""
import importlib.util,json,tempfile
from pathlib import Path
from PySide6.QtCore import Qt,QUrl,QCoreApplication,QEvent
from PySide6.QtGui import QGuiApplication,QKeyEvent
from PySide6.QtQuick import QQuickView
ROOT=Path(__file__).resolve().parents[1]
s=importlib.util.spec_from_file_location('render',ROOT/'tools/render-panel.py');rp=importlib.util.module_from_spec(s);s.loader.exec_module(rp)
app=QGuiApplication([])
with tempfile.TemporaryDirectory() as tmp:
 d=Path(tmp);rp.panel(d);p=d/'FavouriteStore.qml';p.write_text(p.read_text().replace('rawinLauncher','uninstallTest'))
 main=(rp.MAIN%(1920,1080)).rstrip()[:-1]+'function evaluate(code) { return JSON.stringify(eval(code)) || "null"; } }'
 (d/'main.qml').write_text(main);v=QQuickView();v.engine().setOfflineStoragePath(str(d/'storage'));v.setSource(QUrl.fromLocalFile(str(d/'main.qml')));assert v.status()==QQuickView.Ready,v.errors();v.show();rp.wait(150);root=v.rootObject()
 def js(code):return json.loads(root.evaluate(code))
 def key(code):
  QCoreApplication.sendEvent(v,QKeyEvent(QEvent.KeyPress,code,Qt.NoModifier,'',False,1));rp.wait(30)
  QCoreApplication.sendEvent(v,QKeyEvent(QEvent.KeyRelease,code,Qt.NoModifier,'',False,1));rp.wait(80)
 data=dict(page='apps',favs=[x[0] for x in rp.APPS[:2]],inputs=rp.inputs(rp.INPUTS),usb=[],settings={'lang':'en','motion':False,'sort':'name'})
 root.scene(json.dumps(data));js('shell.ready=true;shell.forceActiveFocus()');rp.wait(100)
 # Netflix removable, YouTube not (a system app), and Homebar's own kept.
 js('shell.applications=[{id:"netflix",title:"Netflix",icon:"",removable:true},{id:"youtube.leanback.v4",title:"YouTube",icon:"",removable:false},'
    '{id:"org.webosbrew.hbchannel",title:"Homebrew Channel",icon:"",removable:true}];shell.page="apps"');rp.wait(100)
 count=0
 at=lambda i:js('shell.apps.map(function(a){return a.id;})').index(i)
 def items():return js('shell.appItems.map(function(x){return x.id;})')
 js('shell.selected=%d;shell.secondaryAction()'%at('netflix'))
 assert js('shell.appStep')=='menu' and items()==['favourite','hide','uninstall'],items();count+=1
 key(461);assert js('shell.appStep')=='';count+=1
 js('shell.selected=%d;shell.secondaryAction()'%at('youtube.leanback.v4'));assert items()==['favourite','hide'];count+=1
 js('shell.closeAppMenu();shell.selected=%d;shell.secondaryAction()'%at('org.webosbrew.hbchannel'));assert items()==['favourite','hide'];count+=1
 js('shell.closeAppMenu()')
 # YELLOW toggles the favourite without the menu.
 js('shell.selected=%d'%at('youtube.leanback.v4'));was='youtube.leanback.v4' in js('shell.favouriteKeys')
 js('shell.yellowAction()');assert js('shell.appStep')=='' and ('youtube.leanback.v4' in js('shell.favouriteKeys'))!=was;count+=1
 # The menu's hide works like RED.
 js('shell.selected=%d;shell.secondaryAction()'%at('youtube.leanback.v4'));key(Qt.Key_Down);key(Qt.Key_Return)
 assert 'youtube.leanback.v4' in js('shell.hiddenIds') and js('shell.appStep')=='';count+=1
 # Uninstall asks first, on No; No (BACK) closes without a call.
 js('shell.settings.showHidden=true');js('shell.selected=%d;shell.secondaryAction()'%at('netflix'))
 key(Qt.Key_Down);key(Qt.Key_Down);key(Qt.Key_Return)
 assert js('shell.appStep')=='confirm' and js('shell.appConfirmYes')==False;count+=1
 key(461);assert js('shell.appStep')=='' and js('shell.uninstallCalls')==[];count+=1
 # Yes: the panel asks for it and waits; Netflix then leaves the list.
 js('shell.selected=%d;shell.secondaryAction()'%at('netflix'));key(Qt.Key_Down);key(Qt.Key_Down);key(Qt.Key_Return);key(Qt.Key_Left);key(Qt.Key_Return)
 assert js('shell.appStep')=='removing' and js('shell.uninstallCalls')==['netflix'];count+=1
 assert 'netflix' in js('shell.favouriteKeys');js('shell.hiddenIds=["netflix","youtube.leanback.v4"]')
 js('shell.applications=shell.applications.filter(function(a){return a.id!=="netflix";})');rp.wait(50)
 assert js('shell.appStep')=='done' and 'uninstalled' in js('shell.appText') and 'netflix' not in js('shell.favouriteKeys') and js('shell.hiddenIds')==['youtube.leanback.v4'];count+=1
 key(Qt.Key_Return);assert js('shell.appStep')=='';count+=1
 # An infrared hold (quick presses and releases) opens the menu and its
 # later presses choose nothing; the next real OK does.
 def tap(code,gap):
  QCoreApplication.sendEvent(v,QKeyEvent(QEvent.KeyPress,code,Qt.NoModifier,'',False,1));rp.wait(40)
  QCoreApplication.sendEvent(v,QKeyEvent(QEvent.KeyRelease,code,Qt.NoModifier,'',False,1));rp.wait(gap)
 js('shell.selected=%d'%at('youtube.leanback.v4'));was='youtube.leanback.v4' in js('shell.favouriteKeys')
 for i in range(14):tap(Qt.Key_Return,70)
 rp.wait(400)
 assert js('shell.appStep')=='menu' and js('shell.appChoice')==0 and ('youtube.leanback.v4' in js('shell.favouriteKeys'))==was,(js('shell.appStep'));count+=1
 key(Qt.Key_Return);rp.wait(300);assert js('shell.appStep')=='' and ('youtube.leanback.v4' in js('shell.favouriteKeys'))!=was;count+=1
 # Refused at once: the popup says so.
 js('shell.applications=shell.applications.concat([{id:"netflix",title:"Netflix",icon:"",removable:true}])');rp.wait(50)
 js('shell.selected=%d;shell.secondaryAction();shell.appChoice=2;shell.chooseAppItem();shell.answerUninstall(true);shell.uninstallStarted(false)'%at('netflix'))
 assert js('shell.appStep')=='done' and 'could not' in js('shell.appText');count+=1
print('PASS app uninstall:',count,'checks')
