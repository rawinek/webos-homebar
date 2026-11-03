"""The Inputs page: every source, USB drives and AV off the Home row until put
on it, hold OK there toggles a source, BACK returns to its shortcut; and one
edit mode at a time on Home."""
import importlib.util,json,tempfile
from pathlib import Path
from PySide6.QtCore import Qt,QUrl,QCoreApplication,QEvent
from PySide6.QtGui import QGuiApplication,QKeyEvent
from PySide6.QtQuick import QQuickView
ROOT=Path(__file__).resolve().parents[1]
s=importlib.util.spec_from_file_location('render',ROOT/'tools/render-panel.py');rp=importlib.util.module_from_spec(s);s.loader.exec_module(rp)
app=QGuiApplication([])
with tempfile.TemporaryDirectory() as tmp:
 d=Path(tmp);rp.panel(d);p=d/'FavouriteStore.qml';p.write_text(p.read_text().replace('rawinLauncher','inputsTest'))
 main=(rp.MAIN%(1920,1080)).rstrip()[:-1]+'function evaluate(code) { return JSON.stringify(eval(code)) || "null"; } }'
 (d/'main.qml').write_text(main);v=QQuickView();v.engine().setOfflineStoragePath(str(d/'storage'));v.setSource(QUrl.fromLocalFile(str(d/'main.qml')));assert v.status()==QQuickView.Ready,v.errors();v.show();rp.wait(150);root=v.rootObject()
 def js(code):return json.loads(root.evaluate(code))
 def key(code):
  QCoreApplication.sendEvent(v,QKeyEvent(QEvent.KeyPress,code,Qt.NoModifier,'',False,1));rp.wait(30)
  QCoreApplication.sendEvent(v,QKeyEvent(QEvent.KeyRelease,code,Qt.NoModifier,'',False,1));rp.wait(80)
 data=dict(page='home',favs=[x[0] for x in rp.APPS[:3]],inputs=rp.inputs(rp.INPUTS)+rp.EXTRA_INPUTS,usb=rp.USB,settings={'lang':'en','motion':False})
 root.scene(json.dumps(data));js('shell.ready=true;shell.forceActiveFocus()');rp.wait(100)
 count=0
 # HDMI is on the row, AV and the drive are not, but the Inputs page lists all, Live TV first.
 row=js('shell.sources.map(function(x){return x.id;})')
 assert row==['com.webos.app.hdmi%d'%i for i in range(1,5)],row;count+=1
 listed=js('shell.allSources.map(function(x){return x.id;})')
 assert listed[0]=='tv' and 'usb:usb_1' in listed and 'com.webos.app.externalinput.av1' in listed,listed;count+=1
 # The Inputs shortcut sits in front of System and opens the page.
 actions=js('shell.homeActions.map(function(x){return x.action;})')
 assert actions==['apps','inputs','system'],actions;count+=1
 js('shell.selected=shell.favSlots+shell.sourceCount+shell.homeActionIndex("inputs")');key(Qt.Key_Return);rp.wait(300)
 assert js('shell.page')=='inputs';count+=1
 # Hold-OK's action on the drive puts it on the row, and again takes it off.
 at=listed.index('usb:usb_1');js('shell.selected=%d;shell.secondaryAction()'%at)
 assert 'usb:usb_1' in js('shell.sources.map(function(x){return x.id;})') and js('shell.shownInputs')==['usb:usb_1'];count+=1
 js('shell.secondaryAction()')
 assert 'usb:usb_1' not in js('shell.sources.map(function(x){return x.id;})') and js('shell.shownInputs')==[];count+=1
 # An HDMI input leaves the row the old way (hiddenInputs).
 js('shell.selected=1;shell.secondaryAction()')
 assert js('shell.hiddenInputs')==['com.webos.app.hdmi1'];count+=1
 # The drive opens in the media player, on that drive.
 assert js('shell.itemAt(%d).type'%at)=='usb' and js('shell.usbApp()') in ('com.webos.app.mediadiscovery','com.webos.app.photovideo');count+=1
 # BACK goes home onto the Inputs shortcut.
 key(461);rp.wait(300)
 assert js('shell.page')=='home' and js('shell.selected')==js('shell.favSlots+shell.sourceCount+shell.homeActionIndex("inputs")');count+=1
 # One edit at a time: holding a source while a favourite is edited ends that edit,
 # so ▼ then hides the source, never the favourite.
 js('shell.selected=0;shell.secondaryAction()');assert js('shell.editIndex')==0
 js('shell.selected=shell.favSlots;shell.secondaryAction()')
 assert js('shell.editIndex')==-1 and js('shell.editSourceIndex')==0;count+=1
 js('shell.selected=shell.favSlots+shell.sourceCount;shell.secondaryAction()')
 assert js('shell.editSourceIndex')==-1 and js('shell.editActionIndex')==0;count+=1
 js('shell.editActionIndex=-1')
 # A saved shortcut order from before the page gets Inputs in front of System.
 assert js('shell.homeActionOrderFor(["system","apps","closeApps"])')==['inputs','system','apps','closeApps'];count+=1
print('PASS Inputs page:',count,'checks')
