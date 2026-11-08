"""Home row order (issue #21): with the inputs first the sources come before
the favourites, the shortcuts stay last, the favourites are no taller than the
pills, every key (moving, OK, holding OK to edit, moving and removing in edit
mode, BACK from a page) reaches the right tile, and Home opens on the input on
screen. The default order stays exactly as before."""
import importlib.util,json,tempfile
from pathlib import Path
from PySide6.QtCore import Qt,QUrl,QCoreApplication,QEvent,QPointF
from PySide6.QtGui import QGuiApplication,QKeyEvent
from PySide6.QtQuick import QQuickView,QQuickItem
ROOT=Path(__file__).resolve().parents[1]
s=importlib.util.spec_from_file_location('render',ROOT/'tools/render-panel.py');rp=importlib.util.module_from_spec(s);s.loader.exec_module(rp)
app=QGuiApplication([])
count=0
def ok(cond,msg=''):
 global count
 assert cond,msg;count+=1
with tempfile.TemporaryDirectory() as tmp:
 d=Path(tmp);rp.panel(d);p=d/'FavouriteStore.qml';p.write_text(p.read_text().replace('rawinLauncher','rowOrderTest'))
 main=(rp.MAIN%(1920,1080)).rstrip()[:-1]+'function evaluate(code) { return JSON.stringify(eval(code)) || "null"; } }'
 (d/'main.qml').write_text(main);v=QQuickView();v.engine().setOfflineStoragePath(str(d/'storage'));v.setSource(QUrl.fromLocalFile(str(d/'main.qml')));assert v.status()==QQuickView.Ready,v.errors();v.show();rp.wait(150);root=v.rootObject()
 def js(code):return json.loads(root.evaluate(code))
 def key(code):
  QCoreApplication.sendEvent(v,QKeyEvent(QEvent.KeyPress,code,Qt.NoModifier,'',False,1));rp.wait(30)
  QCoreApplication.sendEvent(v,QKeyEvent(QEvent.KeyRelease,code,Qt.NoModifier,'',False,1));rp.wait(80)
 favs=[x[0] for x in rp.APPS[:3]]
 def scene(order,**extra):
  settings={'lang':'en','motion':False,'hints':True}
  if order:settings['rowOrder']=order
  settings.update(extra.pop('settings',{}))
  data=dict(page='home',favs=extra.pop('favs',favs),inputs=rp.inputs(rp.INPUTS),usb=[],settings=settings);data.update(extra)
  root.scene(json.dumps(data));js('shell.ready=true;shell.forceActiveFocus()');rp.wait(150)
 def item(i):
  x=js('(function(){var it=shell.itemAt(%d);return !it?null:it.kind?it.kind+":"+it.id:it.action?"action:"+it.action:"app:"+it.id;})()'%i)
  return x
 def tiles():
  """The rail's tiles on screen, left to right, as (navIndex, x, height)."""
  out=[];stack=[root];found=[]
  while stack:
   o=stack.pop();found.append(o);stack.extend(o.childItems())
  for o in found:
   if o.property('navIndex') is None or o.property('entry') is None or not o.isVisible():continue
   if o.property('size') is None and o.property('lift') is None:continue
   pt=o.mapToScene(QPointF(0,0))
   if pt.y()<700:continue
   out.append((o.property('navIndex'),round(pt.x()),round(o.height())))
  return sorted(set(out),key=lambda t:t[1])

 # The setting: in the Home row group, first; saved values checked.
 ok(js('shell.validSettings({}).rowOrder')=='favourites')
 ok(js('shell.validSettings({rowOrder:"inputs"}).rowOrder')=='inputs')
 ok(js('shell.validSettings({rowOrder:"sideways"}).rowOrder')=='favourites')
 scene(None)
 ok(js('shell.settingKeys.indexOf("rowOrder")')==js('shell.settingKeys.indexOf("sources")')-1,'rowOrder first in the Home row')
 ok(js('shell.optionsFor("rowOrder").map(function(o){return o.id;})')==['favourites','inputs'])
 ok(js('shell.settingFor("rowOrder").title')=='Row order' and js('shell.settingFor("rowOrder").value')=='Favourites, then inputs')

 # Default order: unchanged places.
 ok(item(0)=='app:netflix' and item(3)=='input:com.webos.app.hdmi1' and item(7)=='action:apps',[item(i) for i in range(8)])
 ok(js('shell.favouriteTile')==js('shell.tile'),'large favourites by default')
 t=tiles();ok([n for n,_,_ in t]==list(range(len(t))),t)

 # Inputs first.
 scene('inputs')
 n=js('shell.sourceCount');ok(n==4)
 ok(item(0)=='input:com.webos.app.hdmi1' and item(n)=='app:netflix' and item(n+2)=='app:amazon',[item(i) for i in range(10)])
 ok(item(n+3)=='action:apps' and js('shell.actionStart')==n+3)
 ok(js('shell.favouriteTile')==js('shell.iconLevel'),'favourites second: as tall as the pills (%s)'%js('shell.favouriteTile'))
 t=tiles();ok([k for k,_,_ in t]==list(range(len(t))),'tiles on screen in navigation order: %s'%t)
 pills=[h for k,_,h in t if k<n];favh=[h for k,_,h in t if n<=k<n+3]
 ok(min(pills)>max(favh),'inputs first grow past the favourites: %s'%t)
 # Heading and hints follow the group of the focused place.
 js('shell.selected=1');ok(js('shell.hero.title')=='HDMI 2')
 js('shell.selected=%d'%n);ok(js('shell.hero.title')=='Netflix' and 'edit favourites' in json.dumps(js('shell.hints')))
 js('shell.selected=1');ok('edit inputs' in json.dumps(js('shell.hints')))
 js('shell.selected=%d'%(n+3));ok('edit shortcuts' in json.dumps(js('shell.hints')))
 # Moving along the row crosses from the inputs into the favourites.
 js('shell.selected=%d'%(n-1));key(Qt.Key_Right);ok(js('shell.selected')==n and js('shell.hero.title')=='Netflix')
 key(Qt.Key_Left);ok(js('shell.selected')==n-1)

 # Editing a favourite: hold, move, remove; the focus follows it.
 js('shell.selected=%d;shell.secondaryAction()'%n)
 ok(js('shell.editIndex')==0 and js('shell.editSourceIndex')==-1,'hold on the first favourite edits it')
 key(Qt.Key_Right);ok(js('shell.favouriteKeys')[:2]==['youtube.leanback.v4','netflix'] and js('shell.selected')==n+1 and js('shell.editIndex')==1)
 key(Qt.Key_Left);ok(js('shell.favouriteKeys')[:2]==['netflix','youtube.leanback.v4'] and js('shell.selected')==n)
 key(Qt.Key_Down);key(Qt.Key_Down)
 ok(js('shell.favouriteKeys')==['youtube.leanback.v4','amazon'] and js('shell.selected')==n and js('shell.editIndex')==-1,(js('shell.favouriteKeys'),js('shell.selected')))
 # Editing an input.
 scene('inputs')
 js('shell.selected=1;shell.secondaryAction()');ok(js('shell.editSourceIndex')==1 and js('shell.editIndex')==-1)
 key(Qt.Key_Right);ok(js('shell.sources[2].id')=='com.webos.app.hdmi2' and js('shell.selected')==2)
 key(Qt.Key_Return);ok(js('shell.editSourceIndex')==-1)
 js('shell.selected=0;shell.secondaryAction()');key(Qt.Key_Down);key(Qt.Key_Down)
 ok(js('shell.sourceCount')==3 and item(3)=='app:netflix','a hidden input moves the favourites one place left')
 # Editing a shortcut.
 scene('inputs')
 a=js('shell.actionStart');js('shell.selected=%d;shell.secondaryAction()'%a);ok(js('shell.editActionIndex')==0)
 key(Qt.Key_Right);ok(js('shell.selected')==a+1 and js('shell.homeActions[1].action')=='apps');key(Qt.Key_Return)
 # BACK from Apps lands on the Apps shortcut, wherever it is now.
 js('shell.page="apps";shell.selected=0');key(461)
 ok(js('shell.page')=='home' and item(js('shell.selected'))=='action:apps')
 # OK on the first place opens the input there.
 js('shell.selected=0');ok(js('shell.itemAt(0).id')==js('shell.sources[0].id'))

 # No favourites: the "Add favourites" tile after the inputs.
 scene('inputs',favs=[])
 ok(js('shell.isAddTile(4)') and js('shell.itemAt(4).action')=='apps' and js('shell.hero.title')!='Add favourites')
 js('shell.selected=4');ok(js('shell.hero.title')=='Add favourites' and not js('shell.holdable()'))
 # Live TV on the row, first.
 scene('inputs',settings={'tv':True})
 ok(item(0)=='tv:tv' and item(5)=='app:netflix')

 # Home opens on the input on screen with the inputs first, not by default.
 def reopen(now):
  js('shell.foreground=false');rp.wait(50);js('shell.nowId="%s";shell.foreground=true'%now);rp.wait(80)
 scene('inputs');reopen('com.webos.app.hdmi3');ok(js('shell.selected')==2 and js('shell.hero.title')=='HDMI 3')
 reopen('com.webos.app.livetv');ok(js('shell.selected')==0,'Live TV off the row: the first place')
 scene('inputs',settings={'tv':True});reopen('com.webos.app.livetv');ok(js('shell.selected')==0 and item(0)=='tv:tv')
 reopen('netflix');ok(js('shell.selected')==0,'an app on screen: the first place')
 # The TV's answer arrives after a key: the focus stays where it was moved.
 scene('inputs');reopen('com.webos.app.hdmi1');key(Qt.Key_Right);ok(js('shell.selected')==1)
 js('shell.describe("com.webos.app.hdmi4");shell.focusCurrentInput()');ok(js('shell.selected')==1)
 # ... and before any key it moves to the input it names.
 reopen('com.webos.app.hdmi1');js('shell.describe("com.webos.app.hdmi4");shell.focusCurrentInput()');ok(js('shell.selected')==3)
 scene(None);reopen('com.webos.app.hdmi3');ok(js('shell.selected')==0,'favourites first: Home opens on the first favourite')

 # The icon size (favSize): the first group takes it, the second stays at the pills' height.
 ok(js('shell.optionsFor("favSize").map(function(o){return o.id;})')==['large','medium','small'] and js('shell.validSettings({}).favSize')=='large')
 ok(js('shell.settingKeys.indexOf("favSize")')==js('shell.settingKeys.indexOf("size")')+1,'tile size right after text size, in Look')
 for order in [None,'inputs']:
  for size in ['large','medium','small']:
   for few in [False,True]:
    for text in ['normal','larger']:
     scene(order,favs=favs if few else [x[0] for x in rp.APPS[:7]],settings={'favSize':size,'size':text})
     z=js('shell.sourceZoom');w=js('shell.iconWanted');lvl=js('shell.iconLevel');ft=js('shell.favouriteTile');base=js('shell.sourceBaseHeight')
     used=js('shell.sourcesWidth+shell.favsWidth+shell.actionWidth+(shell.railGroups-1)*shell.railGroupGap');room=js('shell.width-2*shell.margin')
     tag=(order,size,few,text,z,w,lvl,ft,used,room)
     ok(used<=room+1,'the row fits %s'%(tag,))
     if order=='inputs':
      ok(ft<=lvl and z>=1 and round(base*z)<=w+1,'inputs first: favourites small, inputs up to the size %s'%(tag,))
      if size=='small':ok(z==1 and ft==lvl,'small: one height %s'%(tag,))
      if few and size=='large' and text=='normal':ok(abs(base*z-w)<=1,'room to spare: inputs reach the full size %s'%(tag,))
     else:
      ok(z==1 and ft<=w,'favourites first: inputs as they are %s'%(tag,))
 scene(None,settings={'favSize':'small'});js('shell.page="apps"');ok(js('shell.appIconSize')==js('shell.iconLevel') and js('shell.appColumns')>js('Math.floor((shell.width-2*shell.margin+shell.gap)/(shell.tile+shell.gap))'))
 js('shell.page="system"');ok(js('shell.favouriteLift')>0)
 # While editing, the name stays up (the arrows above the row need the room).
 scene('inputs');js('shell.selected=1');lift=js('shell.favouriteLift');js('shell.secondaryAction()');ok(js('shell.favouriteLift')<=0 and lift>=0)
 # "Add favourites" with no favourites: the size of its group, after the inputs when they come first.
 for order,size,ins,want in [(None,'large',True,'wanted'),(None,'small',True,'level'),('inputs','large',True,'level'),('inputs','medium',True,'level'),('inputs','large',False,'wanted'),('inputs','small',False,'level')]:
  scene(order,favs=[],inputs=rp.inputs(rp.INPUTS) if ins else [],settings={'favSize':size})
  at=js('shell.favStart');ok(js('shell.isAddTile(%d)'%at) and js('shell.itemAt(%d).action'%at)=='apps' and at==(js('shell.sourceCount') if order else 0),(order,size,ins,at))
  ok(js('shell.favouriteTile')==js('shell.icon'+('Wanted' if want=='wanted' else 'Level')),(order,size,ins,js('shell.favouriteTile')))
 # Live TV is as tall as the pills, also with a larger text.
 scene('inputs',settings={'tv':True,'size':'larger'});ok(js('shell.tvTileSize')==js('shell.sourceBaseHeight') and js('shell.sourceBaseHeight')>js('shell.px(64)'))
 # Editing a grown pill raises the name by what its arrows need.
 scene('inputs',settings={'tv':True});js('shell.ready=true;shell.selected=1;shell.secondaryAction()')
 ok(js('shell.editRaise')==max(0,js('shell.px(28)')-round((js('shell.tile')-js('shell.editedHeight'))/2)) and js('shell.favouriteLift')==-js('shell.editRaise') and js('shell.editRaise')>0)
 js('shell.editSourceIndex=-1')
 # Settings that change nothing as things stand are left out, and the focus stays on its setting.
 scene(None,settings={'title':False,'weather':False,'homeCloseApps':False})
 keys=js('shell.settingKeys')
 ok('inputHeading' not in keys and 'place' not in keys and 'units' not in keys and 'temperature' not in keys and 'closeAppsMode' not in keys,keys)
 ok([g for g in js('shell.settingGroups.map(function(g){return g.title})')]==['grp_about','grp_look','grp_home','grp_inputs','grp_screen','grp_apps','grp_bar','grp_remote','grp_backup','grp_updates','grp_support'])
 js('shell.page="settings";shell.selected=shell.settingKeys.indexOf("title")');js('shell.setSetting("title",true)')
 ok('inputHeading' in js('shell.settingKeys') and js('shell.settingKeys[shell.selected]')=='title','focus stays on Heading when a row appears before it')
 js('shell.selected=shell.settingKeys.indexOf("timeout")');js('shell.setSetting("title",false)');ok(js('shell.settingKeys[shell.selected]')=='timeout')
 js('shell.setSetting("weather",true);shell.setSetting("homeCloseApps",true)')
 ok(all(k in js('shell.settingKeys') for k in ['place','units','temperature']) and ('closeAppsMode' in js('shell.settingKeys'))==js('shell.memoryOptimizerAvailable'))
 js('shell.page="home"')
 # Apps and Inputs pages keep their own places.
 scene('inputs');js('shell.page="apps";shell.selected=0');ok(js('shell.itemAt(0).id')==js('shell.apps[0].id'))
 js('shell.page="inputs";shell.selected=0');ok(js('shell.itemAt(0).id')==js('shell.allSources[0].id'))
 # A backup carries the order.
 ok(js('shell.validSettings(shell.backupData().settings).rowOrder')=='inputs')
print('PASS row order:',count,'checks')
