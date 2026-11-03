"""Exercise device icons, input editing and layout with real desktop Qt events."""
import importlib.util,json,tempfile,hashlib
from pathlib import Path
from PySide6.QtCore import QUrl,Qt,QCoreApplication,QEvent,QPoint,QPointF
from PySide6.QtGui import QGuiApplication,QKeyEvent,QImage,QWheelEvent
from PySide6.QtQuick import QQuickView,QQuickItem
from PySide6.QtTest import QTest
ROOT=Path(__file__).resolve().parents[1]
s=importlib.util.spec_from_file_location('render',ROOT/'tools/render-panel.py');rp=importlib.util.module_from_spec(s);s.loader.exec_module(rp)
app=QGuiApplication([])
manifest=json.loads((ROOT/'ui/input-icons/manifest.json').read_text())
assert len(manifest['icons'])==69
assert sum(x.get('group')=='device' for x in manifest['icons'])==12
assert sum(x.get('group')=='tv' for x in manifest['icons'])==4
assert sum(x.get('group')=='port' for x in manifest['icons'])==4
for icon in manifest['icons']:
 original=ROOT/'ui/input-icons'/(icon['id']+'.svg');png=QImage(str(original.with_suffix('.png')))
 assert hashlib.sha256(original.read_bytes()).hexdigest()==icon['sha256']
 assert not png.isNull() and png.width()==128 and png.height()==128
 assert any(png.pixelColor(x,y).alpha()>0 for x in range(128) for y in range(128)),icon['id']
def visual_item(item,name):
 if item.objectName()==name:return item
 for child in item.childItems():
  result=visual_item(child,name)
  if result is not None:return result
 return None
count=0
(ROOT/'dist/render-input-icons').mkdir(parents=True,exist_ok=True)
for width,height in [(1920,1080),(1280,720)]:
 with tempfile.TemporaryDirectory() as tmp:
  d=Path(tmp);rp.panel(d)
  # Qt caches SQL connections by database name across engines in one process.
  # Give each temporary TV its own name as well as its own storage directory.
  store=d/'FavouriteStore.qml';store.write_text(store.read_text().replace('rawinLauncher','inputIconsTest'+str(width)))
  main=rp.MAIN % (width,height)
  main=main.rstrip()[:-1]+"""
    function evaluate(code) { return JSON.stringify(eval(code)) || "null"; }
}"""
  (d/'main.qml').write_text(main)
  view=QQuickView();view.engine().setOfflineStoragePath(str(d/'storage'));view.setSource(QUrl.fromLocalFile(str(d/'main.qml')));assert view.status()==QQuickView.Ready,view.errors()
  view.show();rp.wait(250);root=view.rootObject()
  def js(code):return json.loads(root.evaluate(code))
  def key(code):
   QCoreApplication.sendEvent(view,QKeyEvent(QEvent.KeyPress,code,Qt.NoModifier))
   QCoreApplication.sendEvent(view,QKeyEvent(QEvent.KeyRelease,code,Qt.NoModifier));rp.wait(350)
  settings={'lang':'pl','tv':True,'inputText':'icon','inputIcons':{'com.webos.app.hdmi1':'ps5','com.webos.app.hdmi2':'apple-tv','com.webos.app.hdmi3':'wiim','com.webos.app.hdmi4':'shield'}}
  inputs=rp.inputs([('PlayStation 5',True),('Apple TV',True),('WiiM Ultra',True),('NVIDIA Shield',False)])
  inputs[0]['label']='Konsola';inputs[0]['cec']='PlayStation 5'
  scene=dict(page='home',selected=7,favs=[x[0] for x in rp.APPS[:7]],inputs=inputs,settings=settings)
  root.scene(json.dumps(scene));js('shell.ready=true; shell.forceActiveFocus()');rp.wait(400)
  assert js('shell.validSettings({}).inputText')=='hdmiLabel'
  assert js('shell.validSettings({inputIcons:{"bad":"pc","com.webos.app.hdmi1":"../../x","com.webos.app.hdmi2":"pc"}}).inputIcons')=={'com.webos.app.hdmi2':'pc'}
  assert js('shell.validSettings({inputIcons:[]}).inputIcons')=={}
  assert js('shell.validSettings({inputIcons:null}).inputIcons')=={}
  assert js('shell.sourceTileWidth')==round(64*width/1920)
  assert js('shell.sources.filter(function(s){return s.kind!=="tv";}).every(function(s){return shell.pillWidthFor(s,0)===shell.px(72);})')
  # Hiding every input must not preview TV's text id as a missing PNG.
  js('shell.hiddenInputs=shell.allInputs.map(function(s){return s.id;})');rp.wait(100)
  assert js('shell.sources.length')==1 and js('shell.sources[0].kind')=='tv'
  assert js('shell.previewSource.id')=='com.webos.app.hdmi1'
  assert js('shell.sourceIcon(shell.previewSource)')=='ps5'
  js('shell.allInputs=[]');assert js('shell.previewSource.title')==''
  js('shell.allInputs='+json.dumps(inputs)+';shell.hiddenInputs=[]');rp.wait(100)
  # Heading selection is independent of every tile arrangement.
  assert js('shell.validSettings({}).inputHeading')=='hdmi'
  assert js('shell.validSettings({inputHeading:"bad"}).inputHeading')=='hdmi'
  for layout in ['icon','iconLabel','hdmiCec','label']:
   js('shell.setSetting("inputText",'+json.dumps(layout)+')')
   assert js('shell.sourceHeading(shell.sources[1])')=='HDMI 1'
  js('shell.setSetting("inputHeading","label")');assert js('shell.sourceHeading(shell.sources[1])')=='Konsola'
  js('shell.setSetting("inputHeading","cec")');assert js('shell.sourceHeading(shell.sources[1])')=='PlayStation 5'
  assert js('shell.sourceHeading({title:"HDMI 2",label:"Fallback"})')=='Fallback'
  assert js('shell.sourceHeading({title:"HDMI 2"})')=='HDMI 2'
  assert js('shell.sourceHeading(shell.sources[0])')=='TV'
  js('shell.setSetting("inputHeading","hdmi");shell.setSetting("inputText","icon")')
  # Sort by displayed names in each language, preserving ids and default HDMI.
  assert js('shell.sourceIcon({id:"com.webos.app.hdmi9"})')=='hdmi'
  for language in ['en','es','de','pl','fr','it','pt','nl','cs']:
   js('shell.setSetting("lang",'+json.dumps(language)+')')
   assert js('shell.sortedIconChoices(false).every(function(v,i,a){if(!i)return true;var p=a[i-1];return (p.titleKey?shell.t(p.titleKey):p.title).localeCompare(v.titleKey?shell.t(v.titleKey):v.title)<=0;})')
  js('shell.setSetting("lang","pl")')
  # TV offers only TV symbols and its original label, also alphabetically.
  assert js('shell.validSettings({}).tvIcon')=='tv'
  assert js('shell.validSettings({tvIcon:"xbox"}).tvIcon')=='tv'
  assert js('shell.validSettings({inputIcons:{"com.webos.app.hdmi1":"tv-screen"}}).inputIcons')=={}
  key(405);assert js('shell.editSourceIndex')==0
  controls=visual_item(root,'sourceEditControls');assert controls is not None and controls.isVisible()
  assert controls.mapToScene(QPointF(0,controls.height())).y()<visual_item(root,'tvDeviceGlyph').parentItem().mapToScene(QPointF(0,0)).y()
  view.grabWindow().save(str(ROOT/'dist/render-input-icons'/(str(width)+'-tv-edit.png')))
  key(Qt.Key_Up);assert js('shell.editInputIcon')
  tvchoices=js('shell.editIconChoices.map(function(v){return v.id;})')
  assert set(tvchoices)=={'tv','tv-screen','tv-classic','tv-guide','tv-play'}
  tvnext=tvchoices[(tvchoices.index('tv')+1)%len(tvchoices)]
  key(Qt.Key_Right);assert js('shell.settings.tvIcon')==tvnext
  js('shell.loadSettings()');rp.wait(150);assert js('shell.settings.tvIcon')==tvnext
  assert js('shell.backupData().settings.tvIcon')==tvnext
  assert visual_item(root,'tvDeviceGlyph').width()==round(48*width/1920)
  tvout=ROOT/'dist/render-input-icons';view.grabWindow().save(str(tvout/(str(width)+'-tv-picker.png')))
  key(Qt.Key_Return);key(Qt.Key_Right);assert js('shell.editSourceIndex')==1 and js('shell.settings.tvIcon')==tvnext
  key(Qt.Key_Left);key(461);assert js('shell.editSourceIndex')==-1
  js('shell.setSetting("tv",false);shell.setSetting("tv",true)');assert js('shell.settings.tvIcon')==tvnext
  js('shell.selected=shell.favSlots');key(405);key(Qt.Key_Up);key(Qt.Key_Left)
  assert js('shell.settings.tvIcon')=='tv'
  for offset in range(1,len(tvchoices)+1):
   key(Qt.Key_Right);assert js('shell.settings.tvIcon')==tvchoices[(tvchoices.index('tv')+offset)%len(tvchoices)]
  key(461);key(461)
  js('shell.selected=shell.favSlots+1');key(405);assert js('shell.editSourceIndex')==1
  controls=visual_item(root,'sourceEditControls');assert controls is not None and controls.isVisible()
  tile=visual_item(root,'deviceGlyph').parentItem()
  assert controls.mapToScene(QPointF(0,controls.height())).y()<tile.mapToScene(QPointF(0,0)).y()
  view.grabWindow().save(str(ROOT/'dist/render-input-icons'/(str(width)+'-input-edit.png')))
  key(Qt.Key_Up);assert js('shell.editInputIcon')
  assert visual_item(root,'sourceEditControls') is None
  # DOWN and the footer close only the picker, preserving source edit mode.
  key(Qt.Key_Down);assert not js('shell.editInputIcon') and js('shell.editSourceIndex')==1
  key(Qt.Key_Up)
  footer=visual_item(root,'closeIconPicker');assert footer is not None and footer.isVisible()
  QTest.mouseClick(view,Qt.LeftButton,pos=footer.mapToScene(QPointF(footer.width()/2,footer.height()/2)).toPoint());rp.wait(150)
  assert not js('shell.editInputIcon') and js('shell.editSourceIndex')==1
  key(Qt.Key_Up)
  nextIcon=js('shell.editIconChoices[(shell.sourceIconIndex()+1)%shell.editIconChoices.length].id')
  old=js('shell.sources.map(function(s){return s.id;})');key(Qt.Key_Right)
  assert js('shell.sourceIcon(shell.iconSource)')==nextIcon
  assert js('shell.sources.map(function(s){return s.id;})')==old
  assert not js('shell.launching')
  assert js('shell.backupData().settings.inputIcons["com.webos.app.hdmi1"]')==nextIcon
  # Re-reading settings from LocalStorage keeps the choice.
  js('shell.loadSettings()');assert js('shell.sourceIcon(shell.iconSource)')==nextIcon
  key(Qt.Key_Left);assert js('shell.sourceIcon(shell.iconSource)')=='ps5'
  out=ROOT/'dist/render-input-icons';out.mkdir(parents=True,exist_ok=True)
  rp.wait(200);frame=view.grabWindow();frame.save(str(out/(str(width)+'-picker.png')))
  ratio=frame.width()/width
  cx=round(js('shell.iconEditorCenter()')*ratio);cy=round(js('shell.railY+shell.tile/2')*ratio)
  inset=round(16*width/1920*ratio)
  dark=sum(max(frame.pixelColor(x,y).red(),frame.pixelColor(x,y).green(),frame.pixelColor(x,y).blue())<210 for x in range(cx-inset,cx+inset) for y in range(cy-inset,cy+inset))
  assert dark>5,('selected icon must actually render',width,dark)
  selected=js('shell.selected')
  QTest.mouseClick(view,Qt.LeftButton,pos=QPoint(round(100*width/1920),round(js('shell.railY+shell.tile/2'))));rp.wait(100)
  assert js('shell.selected')==selected and js('shell.editInputIcon') and not js('shell.launching')
  picker=root.findChild(QQuickItem,'inputIconPicker');assert picker is not None
  at=picker.mapToScene(QPointF(picker.width()/2+76*width/1920,84*width/1920)).toPoint()
  QTest.mouseClick(view,Qt.LeftButton,pos=at);rp.wait(200)
  assert js('shell.sourceIcon(shell.iconSource)')==nextIcon
  key(Qt.Key_Left)
  # OK closes just the picker; a further arrow still reorders the input.
  key(Qt.Key_Return);assert not js('shell.editInputIcon') and js('shell.editSourceIndex')==1
  key(Qt.Key_Right);assert js('shell.editSourceIndex')==2
  assert js('shell.sourceIcon(shell.iconSource)')=='ps5'
  key(Qt.Key_Left);key(461)
  assert js('shell.editSourceIndex')==-1
  assert js('shell.settings.inputIcons["com.webos.app.hdmi1"]')=='ps5'
  # A physical OK hold enters source edit without launching it.
  js('shell.selected=shell.favSlots+1')
  QTest.keyPress(view,Qt.Key_Return);rp.wait(850);QTest.keyRelease(view,Qt.Key_Return);rp.wait(350)
  assert js('shell.editSourceIndex')==1 and not js('shell.launching')
  key(Qt.Key_Up);key(461);assert not js('shell.editInputIcon')
  key(461);assert js('shell.editSourceIndex')==-1
  for mode,expected in [('iconHdmi','HDMI 1'),('iconLabel','Konsola'),('iconCec','PlayStation 5')]:
   js('shell.setSetting("inputText",'+json.dumps(mode)+')');rp.wait(200)
   assert js('shell.inputTexts(shell.allInputs[0]).primary')==expected
   assert visual_item(root,'deviceGlyph').width()==round(48*width/1920)
   assert js('shell.sources.filter(function(s){return s.kind!=="tv";}).every(function(s){var w=shell.pillWidthFor(s,0);return w>=shell.sourceMinWidth && w<=shell.px(200);})')
   view.grabWindow().save(str(out/(str(width)+'-'+mode+'.png')))
  # Long text scrolls inside its box; the enlarged icon never moves with it.
  js('shell.setSetting("inputOverflow","scroll");shell.selected=shell.favSlots+1');rp.wait(250)
  glyph=visual_item(root,'deviceGlyph');position=glyph.mapToScene(QPointF(0,0))
  rp.wait(1750)
  assert visual_item(root,'inputPrimaryText').x()<0
  assert abs(visual_item(root,'deviceGlyph').mapToScene(QPointF(0,0)).x()-position.x())<0.1
  js('shell.setSetting("inputOverflow","ellipsis")');rp.wait(100)
  assert visual_item(root,'inputPrimaryText').x()==0
  # Label and CEC fallbacks stay consistent with the existing arrangements.
  assert js('shell.inputTexts({title:"HDMI 1",label:"Fallback"}).primary')=='Fallback'
  js('shell.setSetting("inputText","iconLabel")');assert js('shell.inputTexts({title:"HDMI 1",cec:"CEC fallback"}).primary')=='CEC fallback'
  assert js('shell.inputTexts({title:"HDMI 1"}).primary')=='HDMI 1'
  js('shell.setSetting("inputText","icon"); shell.setSetting("size","larger")');rp.wait(250)
  assert js('shell.sources.filter(function(s){return s.kind!=="tv";}).every(function(s){return shell.pillWidthFor(s,0)===shell.px(72);})')
  view.grabWindow().save(str(out/(str(width)+'-icon-only.png')))
  # Hiding and restoring never loses the icon assignment.
  js('shell.toggleHiddenInput("com.webos.app.hdmi1"); shell.toggleHiddenInput("com.webos.app.hdmi1")')
  assert js('shell.settings.inputIcons["com.webos.app.hdmi1"]')=='ps5'
  for theme in ['terracotta','cobalt']:
   js('shell.setSetting("theme",'+json.dumps(theme)+')');rp.wait(250)
   view.grabWindow().save(str(out/(str(width)+'-'+theme+'.png')))
  js('shell.page="settings"; shell.selected=shell.settingKeys.indexOf("inputText"); shell.enterValues(); shell.valueIndex=shell.valueOptions.map(function(v){return v.id;}).indexOf("iconCec")')
  rp.wait(350);values=root.findChild(QQuickItem,'inputValueList');assert values.property('contentY')>0
  preview=visual_item(root,'inputAppearancePreview');assert preview is not None and preview.isVisible()
  assert preview.y()>=values.y()+values.height()+round(16*width/1920)
  assert abs(preview.x()+preview.width()/2-preview.parentItem().width()/2)<1
  assert preview.y()+preview.height()<=preview.parentItem().height()+0.1
  before=values.property('contentY');choice=js('shell.settings.inputText')
  at=values.mapToScene(QPointF(values.width()/2,values.height()/2))
  event=QWheelEvent(at,at,QPoint(),QPoint(0,120),Qt.NoButton,Qt.NoModifier,Qt.NoScrollPhase,False)
  QCoreApplication.sendEvent(view,event);rp.wait(300)
  assert values.property('contentY')<before and js('shell.settings.inputText')==choice
  key(Qt.Key_Up);key(Qt.Key_Down);rp.wait(250)
  view.grabWindow().save(str(out/(str(width)+'-settings.png')))
  js('shell.pane=0;shell.selected=shell.settingKeys.indexOf("inputHeading");shell.enterValues()');rp.wait(100)
  assert js('shell.valueOptions.map(function(v){return v.id;})')==['hdmi','label','cec']
  assert js('shell.settingFor("inputText").title')=='Wygląd wejść'
  assert js('shell.settingFor("inputHeading").title')=='Nazwa wejścia nad ulubionymi'
  key(Qt.Key_Down);key(Qt.Key_Return)
  assert js('shell.settings.inputHeading')=='label'
  js('shell.loadSettings()');assert js('shell.backupData().settings.inputHeading')=='label'
  view.grabWindow().save(str(out/(str(width)+'-heading-settings.png')))
  view.close();view.deleteLater();QCoreApplication.sendPostedEvents(None,QEvent.DeferredDelete)
  count+=1
print('PASS 65 icon assets, alphabetical translated names and independent heading, restricted TV picker/restore/persistence and equal 48px fields; Qt editing/hold/keys, persistence, reorder/hide, backups, 4 layouts/fallbacks and FHD/HD renders')
