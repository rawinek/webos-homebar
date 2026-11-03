"""Real key/pointer regression for edit handles and two distinct DOWN presses."""
import importlib.util,json,tempfile
from pathlib import Path
from PySide6.QtCore import Qt,QUrl,QCoreApplication,QEvent,QPointF
from PySide6.QtGui import QGuiApplication,QKeyEvent
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest
ROOT=Path(__file__).resolve().parents[1]
s=importlib.util.spec_from_file_location('render',ROOT/'tools/render-panel.py');rp=importlib.util.module_from_spec(s);s.loader.exec_module(rp)
app=QGuiApplication([]);out=ROOT/'dist/render-removal';out.mkdir(parents=True,exist_ok=True)
def named(item,name):
 if item.objectName()==name:return item
 for c in item.childItems():
  v=named(c,name)
  if v is not None:return v
 return None
for width,height in [(1920,1080),(1280,720)]:
 with tempfile.TemporaryDirectory() as tmp:
  d=Path(tmp);rp.panel(d);p=d/'FavouriteStore.qml';p.write_text(p.read_text().replace('rawinLauncher','removeTest'+str(width)))
  main=(rp.MAIN%(width,height)).rstrip()[:-1]+'function evaluate(code) { return JSON.stringify(eval(code)) || "null"; } }'
  (d/'main.qml').write_text(main);v=QQuickView();v.engine().setOfflineStoragePath(str(d/'storage'));v.setSource(QUrl.fromLocalFile(str(d/'main.qml')));assert v.status()==QQuickView.Ready,v.errors();v.show();rp.wait(150);root=v.rootObject()
  def js(code):return json.loads(root.evaluate(code))
  def key(code,repeat=False):
   QCoreApplication.sendEvent(v,QKeyEvent(QEvent.KeyPress,code,Qt.NoModifier,'',repeat,1))
   QCoreApplication.sendEvent(v,QKeyEvent(QEvent.KeyRelease,code,Qt.NoModifier,'',repeat,1));rp.wait(60)
  def scene(kind,index=0,size='normal'):
   data=dict(page='home',favs=[x[0] for x in rp.APPS[:7]],inputs=rp.inputs(rp.INPUTS),settings={'lang':'pl','tv':True,'inputText':'icon','size':size,'motion':False,'homeCloseApps':True})
   data[{'fav':'editFav','source':'editSource','action':'editAction'}[kind]]=index
   root.scene(json.dumps(data));js('shell.ready=true;shell.forceActiveFocus()');rp.wait(100)
  def state():return js('({f:shell.favouriteKeys,s:shell.sources.map(function(x){return x.id;}),a:shell.homeActions.map(function(x){return x.action;})})')
  # Close background apps is off until the user turns it on.
  root.scene(json.dumps(dict(page='home',favs=[],inputs=rp.inputs(rp.INPUTS),settings={'lang':'pl','motion':False})));rp.wait(100)
  assert js('shell.homeActions.map(function(x){return x.action;})')==['apps','inputs','system']
  root.scene(json.dumps(dict(page='home',favs=[],inputs=rp.inputs(rp.INPUTS),settings={'lang':'pl','motion':False,'homeCloseApps':True})));rp.wait(100)
  assert js('shell.homeActions.map(function(x){return x.action;})')==['closeApps','apps','inputs','system']
  for kind,index in [('fav',0),('fav',6),('source',0),('source',1),('action',0),('action',1)]:
   scene(kind,index,size='larger');before=state();key(Qt.Key_Down)
   assert state()==before and js('shell.pendingRemoval')
   warning=named(root,'removalWarning');assert warning.isVisible()
   assert warning.x()>=round(96*width/1920)-1 and warning.x()+warning.width()<=width-round(96*width/1920)+1
   assert warning.y()+warning.height()<height
   for n in range(3):key(Qt.Key_Down,repeat=True)
   assert state()==before and js('shell.pendingRemoval')
   v.grabWindow().save(str(out/(str(width)+'-'+kind+str(index)+'.png')))
   key(Qt.Key_Down);after=state()
   assert len(after[{'fav':'f','source':'s','action':'a'}[kind]])==len(before[{'fav':'f','source':'s','action':'a'}[kind]])-1
   assert not js('shell.pendingRemoval')
  # Moving, even against the end of the row, disarms the warning.
  for code in [Qt.Key_Left,Qt.Key_Right,Qt.Key_Up,Qt.Key_Return,461,405]:
   scene('fav');before=state();key(Qt.Key_Down);key(code)
   assert not js('shell.pendingRemoval') and len(state()['f'])==len(before['f'])
  scene('source',1);before=state();key(Qt.Key_Down);key(Qt.Key_Up)
  assert js('shell.editInputIcon') and not js('shell.pendingRemoval')
  key(Qt.Key_Down);assert not js('shell.editInputIcon') and not js('shell.pendingRemoval') and state()==before
  # System never offers deletion; shortcuts have exactly LEFT/RIGHT above them.
  scene('action',3);before=state();key(Qt.Key_Down);key(Qt.Key_Down)
  assert state()==before and not js('shell.pendingRemoval') and not js('shell.editInputIcon')
  row=named(root,'shortcutEditControls');assert row is not None and row.isVisible()
  assert row.mapToScene(QPointF(0,row.height())).y()<row.parentItem().parentItem().mapToScene(QPointF(0,0)).y()
  texts=[]
  def collect(item):
   if item.property('text') is not None:texts.append(item.property('text'))
   for child in item.childItems():collect(child)
  collect(row);assert texts==['‹','›'],texts
  v.grabWindow().save(str(out/(str(width)+'-shortcut-edit.png')))
  # Pointer reordering cancels an armed removal and never opens icon selection.
  scene('action',0);key(Qt.Key_Down);row=named(root,'shortcutEditControls')
  QTest.mouseClick(v,Qt.LeftButton,pos=row.mapToScene(QPointF(row.width()-16*width/1920,row.height()/2)).toPoint());rp.wait(100)
  assert js('shell.editActionIndex')==1 and not js('shell.pendingRemoval') and not js('shell.editInputIcon')
  key(Qt.Key_Down);assert js('shell.pendingRemoval')
  js('shell.foreground=false');assert not js('shell.pendingRemoval')
  v.close();v.deleteLater();QCoreApplication.sendPostedEvents(None,QEvent.DeferredDelete)
print('PASS FHD/HD two-step removal for favourites/TV/HDMI/shortcuts, repeat protection, cancellation, screen bounds and pointer shortcut handles; System protected')
