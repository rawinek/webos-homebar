"""Free up memory closes only the apps in the background (never the one on
screen, Homebar's helpers or LG's own), a click where there is no tile closes
Homebar on every page but the settings menu (not while editing or with a popup
up), and the AMOLED themes are black and white: full dark with no glow, grey icons
and white key badges, then the colour keys, the icons and the glow come back
one by one; the shade as deep as the other themes'; names in every
language."""
import importlib.util,json,tempfile
from pathlib import Path
from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView
ROOT=Path(__file__).resolve().parents[1]
s=importlib.util.spec_from_file_location('render',ROOT/'tools/render-panel.py');rp=importlib.util.module_from_spec(s);s.loader.exec_module(rp)
app=QGuiApplication([])
count=0
def ok(cond,msg=''):
 global count
 assert cond,msg;count+=1
with tempfile.TemporaryDirectory() as tmp:
 d=Path(tmp);rp.panel(d);p=d/'FavouriteStore.qml';p.write_text(p.read_text().replace('rawinLauncher','amoledTest'))
 main=(rp.MAIN%(1920,1080)).rstrip()[:-1]+'function evaluate(code) { return JSON.stringify(eval(code)) || "null"; } }'
 (d/'main.qml').write_text(main);v=QQuickView();v.engine().setOfflineStoragePath(str(d/'storage'));v.setSource(QUrl.fromLocalFile(str(d/'main.qml')));assert v.status()==QQuickView.Ready,v.errors();v.show();rp.wait(150);root=v.rootObject()
 js=lambda c:json.loads(root.evaluate(c))
 def scene(**st):
  root.scene(json.dumps(dict(page='home',favs=[a[0] for a in rp.APPS[:3]],inputs=rp.inputs(rp.INPUTS),settings=dict({'lang':'en','motion':False},**st))));js('shell.ready=true;shell.forceActiveFocus()');rp.wait(120)

 # Free up memory: which running apps are closed.
 scene()
 running=[{'id':i} for i in ['netflix','youtube.leanback.v4','com.webos.app.home','org.rawin.launcher','org.rawin.launcher.service','org.webosbrew.hbchannel',
          'com.webos.app.hdmi1','com.webos.app.livetv','com.palm.app.settings','com.webos.app.notificationcenter','amazon','netflix']]
 ok(js('shell.closeIds(%s,"youtube.leanback.v4")'%json.dumps(running))==['netflix','amazon'],js('shell.closeIds(%s,"youtube.leanback.v4")'%json.dumps(running)))
 ok(js('shell.closeIds([], "")')==[])
 js('shell.notice="";shell.runCloseApps()');ok(js('shell.notice')=='closeAppsCalled','the shortcut still goes through closeAppsService')

 # A click on no tile closes Homebar: where it may.
 scene()
 for page in ['home','apps','inputs','system']:
  js('shell.page="%s";shell.selected=0'%page);ok(js('shell.backgroundClosable()'),page)
 js('shell.page="settings"');ok(not js('shell.backgroundClosable()'),'settings menu')
 js('shell.page="home";shell.selected=0;shell.secondaryAction()');ok(js('shell.editIndex')==0 and not js('shell.backgroundClosable()'),'editing')
 js('shell.editIndex=-1');ok(js('shell.backgroundClosable()'))
 for popup in ['shell.appStep="menu"','shell.buttonStep="wait"','shell.modeConfirm="native"','shell.pendingRemoval="x"']:
  js(popup);ok(not js('shell.backgroundClosable()'),popup)
  js('shell.appStep="";shell.buttonStep="";shell.modeConfirm="";shell.pendingRemoval=""')
 js('shell.closeReason=""');js('shell.closeHome("pointer")');ok(js('shell.closeReason')=='pointer')

 # AMOLED.
 scene(theme='amoled')
 ok(js('shell.mono') and js('shell.theme.scrim')=='#000000' and js('shell.theme.chip')=='#000000' and js('shell.theme.focus')=='#ffffff')
 ok(js('String(shell.keyYellow)')==js('String(shell.keyRed)'),'colour keys as white badges')
 ok(js('shell.warning')=='#ffffff' and js('shell.theme.handle').endswith('000000'),'warnings, edit frames and arrows in white')
 ok(js('shell.greyIcons') and js('shell.whiteKeys') and not js('shell.glow'),'full dark')
 ok(js('shell.settingFor("theme").value')=='AMOLED (full dark)' and 'amoled' in js('shell.optionsFor("theme").map(function(o){return o.id})'))
 # The shade under the row is as deep as in the other themes, solid only under the settings menu.
 from PySide6.QtQuick import QQuickItem
 scrim=root.findChild(QQuickItem,'scrim');ok(scrim is not None)
 ok(not scrim.property('solid'),'shade like the others, not a solid band')
 js('shell.page="settings"');ok(scrim.property('solid'),'solid under the menu');js('shell.page="home"')
 scene(theme='amoled_keys')
 ok(js('shell.mono') and js('shell.greyIcons') and not js('shell.whiteKeys') and not js('shell.glow') and js('String(shell.keyRed)')!=js('String(shell.keyYellow)'),'colour keys')
 ok(js('shell.settingFor("theme").value')=='AMOLED (colour buttons)')
 scene(theme='amoled_apps')
 ok(js('shell.mono') and not js('shell.greyIcons') and not js('shell.whiteKeys') and not js('shell.glow') and js('shell.neutral')=='#000000','colour apps, dark behind them')
 ok(js('shell.settingFor("theme").value')=='AMOLED (colour apps)')
 scene(theme='amoled_glow')
 ok(js('shell.mono') and not js('shell.greyIcons') and not js('shell.whiteKeys') and js('shell.glow') and js('shell.theme.chip')=='#000000','colour apps and glow')
 ok(js('shell.neutral')!='#000000','a grey glow for what is not an app')
 ok(js('shell.settingFor("theme").value')=='AMOLED (colour apps and background)')
 scene(theme='amoled');ok(js('shell.neutral')=='#000000' and js('shell.greyIcons'),'the shared palette untouched')
 # Shade behind Homebar: in every theme; off hides the shade and the glow, not under the menu.
 keys=lambda:sum([g['keys'] for g in js('shell.settingGroups')],[])
 for th in ['amoled','amoled_glow','default','lime']:
  scene(theme=th);ok('shade' in keys() and js('shell.shade') and scrim.property('visible') and js('shell.settingFor("shade").value')=='On',th)
  scene(theme=th,shade=False);ok(not js('shell.glow') and not scrim.property('visible'),th+' off')
  js('shell.page="settings"');ok(scrim.property('visible'),'kept under the menu');js('shell.page="home"')
 scene(theme='amoled_glow');ok(js('shell.glow'))
 scene(theme='default');ok(not js('shell.mono') and js('String(shell.keyRed)')!=js('String(shell.keyYellow)'),'other themes keep their colours')
 strings=(ROOT/'ui/Strings.js').read_text()
 ok(all(strings.count(k)==10 for k in ['theme_amoled:','theme_amoled_keys:','theme_amoled_apps:','theme_amoled_glow:','set_shade:']) and strings.count('close_apps_none:')==10)
print('PASS AMOLED, Free up memory and closing by pointer:',count,'checks')
