"""Run the real root shell scripts in a disposable TV filesystem, never over SSH."""
import json, os, re, shutil, signal, subprocess, tempfile, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BASE='/var/lib/webosbrew/rawin-launcher-home'
APP='/media/developer/apps/usr/palm/applications/org.rawin.launcher'
HOME='/usr/palm/applications/com.webos.app.home'
STORE='/home/root/.local/share'
KEYS='/home/root/.config/lginputhook/keybinds.json'
DB='9969c85c6e1c20a73a4ac456d46e31f7'
class TV:
 def __init__(self, mode='legacy', release='10.3.1', mapper=True):
  self.tmp=tempfile.TemporaryDirectory(prefix='homebar-mode-'); self.root=Path(self.tmp.name)
  self.env=dict(os.environ, TV_ROOT=str(self.root),PATH=str(self.root/'bin')+':'+os.environ['PATH'])
  for p in [BASE+'/app',BASE+'/native-app',APP,HOME,'/bin','/proc','/etc','/var/lib/tvweb','/tmp']:(self.p(p)).mkdir(parents=True,exist_ok=True)
  self.put('/usr/bin/qml-runner','runner');self.put('/etc/starfish-release','release '+release);self.put('/proc/mounts','');self.put('/proc/uptime','50.00 10.00')
  self.put(APP+'/appinfo.json',json.dumps({'id':'org.rawin.launcher','type':'qml'}));self.put(APP+'/Config.js','var exitTarget = true;\nvar platform = "overlay";\n')
  for f in ['main.qml','Panel.qml','FavouriteStore.qml','Strings.js','Themes.js','About.js','icon.png']:self.put(APP+'/'+f,'test')
  (self.p(APP+'/fonts')).mkdir()
  self.put(BASE+'/app/appinfo.json','{"type":"web"}');self.put(HOME+'/appinfo.json','{"type":"flutter"}')
  for id,value in [('org.rawin.launcher','app-data'),('com.webos.app.home','old-home-data')]:
   for suffix in ['sqlite','ini','sqlite-wal','sqlite-shm']:self.put(STORE+'/'+id+'/QML/OfflineStorage/Databases/'+DB+'.'+suffix,value+'-'+suffix)
  if mapper:self.put(KEYS,json.dumps({'773':{'action':'launch','id':'org.rawin.launcher'},'1042':{'action':'launch','id':'other.app'},'500':{'action':'launch','id':'org.rawin.launcher'}}))
  for src,dst in [('mode-switch.sh','mode-switch.sh'),('native-home.sh','native-home.sh'),('native-trial.sh','native-trial.sh'),('home-takeover.sh','takeover.sh'),('integration.js','integration.js'),('uninstall.sh','uninstall.sh')]:
   s=(ROOT/'webos10'/src).read_text()
   s=re.sub(r'(?<![\w/])(?:/var/lib/|/media/developer/|/usr/palm/|/usr/bin/qml-runner|/usr/bin/com.webos.app.home|/home/root/|/etc/starfish-release|/proc/|/tmp/)',lambda m:str(self.root)+m[0],s)
   s=s.replace("readdirSync('/proc')", "readdirSync('"+str(self.root)+"/proc')")
   s=s.replace('ls -di ', 'ls -diL ')
   self.put(BASE+'/'+dst,s)
  shutil.copyfile(ROOT/'webos10/native-stage.js',self.p(BASE+'/native-stage.js'))
  # Fake only system boundaries; migrations, keys, journal and decisions are real.
  self.put('/bin/luna-send', '''#!/usr/bin/env python3
import os,sys,json,time
from pathlib import Path
r=Path(os.environ['TV_ROOT']);a=sys.argv;uri=a[-2];params=json.loads(a[-1])
with (r/'calls').open('a') as f:f.write(uri+' '+a[-1]+'\\n')
if uri.endswith('/launch') and (r/'pause-launch').exists():
 (r/'paused').touch()
 while (r/'pause-launch').exists():time.sleep(.02)
if uri.endswith('/launch') and (r/'fail-launch').exists():
 (r/'fail-launch').unlink();print('{"returnValue":false}');sys.exit(0)
if uri.endswith('/dev/remove'):
 (r/'media/developer/apps/usr/palm/applications/org.rawin.launcher/appinfo.json').unlink(missing_ok=True);print('{"returnValue":true}');sys.exit(0)
if uri.endswith('/dev/install'):print('{"state":"installed"}');sys.exit(0)
if uri.endswith('/getAppInfo'):
 info=json.loads((r/'usr/palm/applications/com.webos.app.home/appinfo.json').read_text());print(json.dumps({'returnValue':True,'appInfo':info}))
else:print('{"returnValue":true}')
''')
  self.put('/bin/mount','''#!/usr/bin/env python3
import os,sys
from pathlib import Path
r=Path(os.environ['TV_ROOT']);src=Path(sys.argv[-2]);dst=Path(sys.argv[-1])
if (r/'fail-mount').exists(): (r/'fail-mount').unlink();sys.exit(1)
dst.rename(str(dst)+'.stock');dst.symlink_to(src);(r/'proc/mounts').write_text('fake '+str(dst)+' none rw 0 0\\n')
''')
  self.put('/bin/umount','''#!/usr/bin/env python3
import os,sys
from pathlib import Path
r=Path(os.environ['TV_ROOT']);dst=Path(sys.argv[-1])
if (r/'fail-umount').exists(): (r/'fail-umount').unlink();sys.exit(1)
dst.unlink();Path(str(dst)+'.stock').rename(dst);(r/'proc/mounts').write_text('')
''')
  for name in ['sleep','logger','pidof','kill']:self.put('/bin/'+name,'#!/bin/sh\nexit 0\n')
  for p in (self.root/'bin').iterdir():p.chmod(0o755)
  if mode=='native':
   self.run_native('enable'); self.put(STORE+'/com.webos.app.home/QML/OfflineStorage/Databases/'+DB+'.sqlite','latest-native-data')
  if mode=='overlay':self.switch('overlay')
 def p(self,p):return self.root/p.lstrip('/')
 def put(self,p,s):p=self.p(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s)
 def run(self,script,arg,ok=True):
  r=subprocess.run(['sh',str(self.p(BASE+'/'+script)),arg],env=self.env,text=True,capture_output=True,timeout=20)
  if ok:assert r.returncode==0,(arg,r.stdout,r.stderr)
  else:assert r.returncode!=0,(arg,r.stdout,r.stderr)
  return r
 def switch(self,mode,ok=True):return self.run('mode-switch.sh',mode,ok)
 def run_native(self,mode):return self.run('native-home.sh',mode)
 def keys(self):return json.loads(self.p(KEYS).read_text())
 def foreign(self):
  self.put('/foreign/appinfo.json','{"type":"qml"}')
  subprocess.run(['mount','--bind',str(self.p('/foreign')),str(self.p(HOME))],env=self.env,check=True)
 def clean(self):self.tmp.cleanup()

def test():
 count=0
 for old in ['legacy','native','overlay']:
  for new in ['native','overlay']:
   t=TV(old)
   try:
    t.switch(new);assert t.p(BASE+('/native-home' if new=='native' else '/additional-overlay')).exists()
    assert t.keys()['1042']['id']=='other.app'
    if new=='overlay':
     assert not t.p(HOME).is_symlink();assert '773' not in t.keys()
     if old=='native':assert t.p(STORE+'/org.rawin.launcher/QML/OfflineStorage/Databases/'+DB+'.sqlite').read_text()=='latest-native-data'
    else:
     assert t.p(HOME).is_symlink();assert not any(v.get('id')=='org.rawin.launcher' for v in t.keys().values())
    t.switch(new);count+=1
   finally:t.clean()
 for fail in ['fail-mount','fail-launch']:
  t=TV();before=t.p(KEYS).read_bytes();data=t.p(STORE+'/org.rawin.launcher/QML/OfflineStorage/Databases/'+DB+'.sqlite').read_bytes()
  try:
   t.put('/'+fail,'');t.switch('native',False)
   assert not t.p(BASE+'/native-home').exists();assert t.p(KEYS).read_bytes()==before
   assert t.p(STORE+'/org.rawin.launcher/QML/OfflineStorage/Databases/'+DB+'.sqlite').read_bytes()==data
   assert not t.p(BASE+'/mode-switch-lock').exists();count+=1
  finally:t.clean()
 t=TV('native')
 try:
  before=t.p(STORE+'/com.webos.app.home/QML/OfflineStorage/Databases/'+DB+'.sqlite').read_bytes()
  t.put('/fail-launch','');t.switch('overlay',False)
  assert t.p(BASE+'/native-home').exists() and t.p(HOME).is_symlink()
  assert t.p(STORE+'/com.webos.app.home/QML/OfflineStorage/Databases/'+DB+'.sqlite').read_bytes()==before;count+=1
 finally:t.clean()
 for release,glass,foreign in [('9.0',False,False),('10.3',True,False),('10.3',False,True)]:
  t=TV(release=release)
  try:
   if glass:t.put('/var/lib/tvweb/home.json','{"enabled":true}')
   if foreign:t.foreign()
   before=t.p(KEYS).read_bytes();t.switch('native',False);assert t.p(KEYS).read_bytes()==before
   assert not t.p(BASE+'/mode-switch-lock').exists();count+=1
  finally:t.clean()
 # The trial on webOS 9: allowed once the owner asked for it, undone at once when SAM never reports a running QML Home.
 t=TV(release='9.0')
 try:
  t.put(BASE+'/native-trial','');t.put(BASE+'/keep-lg-home','');before=t.p(KEYS).read_bytes();linked=t.p(HOME).is_symlink()
  t.switch('native',False)
  assert not t.p(BASE+'/native-home').exists() and t.p(HOME).is_symlink()==linked and t.p(KEYS).read_bytes()==before
  assert 'Home after' in t.p(BASE+'/native-trial.log').read_text();count+=1
 finally:t.clean()
 # The trial on webOS 6: sam cannot reread Home there, so a script takes the
 # place of Home's program and runs qml-runner on the staged host; given back
 # on the way to the overlay, and at once when no host comes up.
 EXE='/usr/bin/com.webos.app.home'
 for host in [True,False]:
  t=TV(release='6.5.3')
  try:
   t.put(EXE,'lg-home-program');t.p('/usr/bin/qml-runner').chmod(0o755);t.put(HOME+'/appinfo.json','{"type":"native"}');t.put(BASE+'/native-trial','')
   if host:t.put('/proc/4242/cmdline',str(t.root)+'/usr/bin/qml-runner\0--main\0file:///x/main.qml\0{"appId":"com.webos.app.home"}\0')
   t.switch('native',host)
   log=t.p(BASE+'/native-trial.log').read_text();assert 'Home program:' in log and 'qml-runner takes --main' in log,log
   if host:
    assert t.p(BASE+'/native-home').exists() and t.p(EXE).is_symlink() and not t.p(HOME).is_symlink()
    wrapper=t.p(BASE+'/home-exe').read_text()
    assert re.search(r'^exec \S*/usr/bin/qml-runner --main file:///',wrapper,re.M) and BASE+'/native-app/main.qml' in wrapper and '"$@"' in wrapper,wrapper
    assert 'verify: type=native' in log and 'PASS' in log,log
    assert t.run('native-home.sh','check-owner').returncode==0
    t.switch('overlay')
   assert not t.p(EXE).is_symlink() and t.p(EXE).read_text()=='lg-home-program'
   assert not t.p(BASE+'/native-home').exists() or not host;count+=1
  finally:t.clean()
 t=TV(mapper=False)
 try:
  t.switch('native');t.switch('overlay');assert not t.p(KEYS).exists();count+=1
 finally:t.clean()
 t=TV()
 try:
  t.foreign();t.switch('overlay');assert t.p(HOME).resolve()==t.p('/foreign').resolve()
  assert 'closeByAppId {"id":"com.webos.app.home"}' not in t.p('/calls').read_text();count+=1
 finally:t.clean()
 for old,new in [('legacy','native'),('native','overlay'),('overlay','native')]:
  t=TV(old)
  try:
   original=t.p(KEYS).read_bytes();t.put('/pause-launch','')
   proc=subprocess.Popen(['sh',str(t.p(BASE+'/mode-switch.sh')),new],env=t.env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
   for _ in range(300):
    if t.p('/paused').exists():break
    time.sleep(.02)
   assert t.p('/paused').exists(),'did not reach launch phase'
   os.killpg(proc.pid,signal.SIGKILL);proc.wait();t.p('/pause-launch').unlink()
   assert t.p(BASE+'/mode-switch-lock/ready').exists()
   t.switch('recover')
   assert t.p(KEYS).read_bytes()==original
   assert t.p(BASE+'/native-home').exists()==(old=='native')
   assert t.p(BASE+'/additional-overlay').exists()==(old=='overlay')
   assert not t.p(BASE+'/mode-switch-lock').exists();count+=1
  finally:t.clean()
 t=TV('native')
 try:
  t.put('/fail-umount','');t.switch('overlay',False)
  assert t.p(BASE+'/native-home').exists() and t.p(HOME).is_symlink();count+=1
 finally:t.clean()
 t=TV()
 try:
  t.put(KEYS,'invalid json');t.switch('native',False)
  assert t.p(KEYS).read_text()=='invalid json' and not t.p(BASE+'/native-home').exists();count+=1
 finally:t.clean()
 t=TV()
 try:
  keys=t.keys();keys['773']={'action':'launch','id':'another.launcher'};t.put(KEYS,json.dumps(keys))
  before=t.p(KEYS).read_bytes();t.switch('native',False)
  assert t.p(KEYS).read_bytes()==before and not t.p(BASE+'/native-home').exists();count+=1
 finally:t.clean()
 for current in ['native','overlay','fresh-overlay','manual','manual-update']:
  t=TV('legacy' if current=='fresh-overlay' else current,mapper=False)
  manual=current.startswith('manual')
  if current!='native' and not manual:t.foreign()
  if manual:
   t.put('/etc/starfish-release','release 6.5.0')
   t.put('/home/root/magic_mapper.py','VERSION = "1.1.0"\ndef get_button_map(): magic_mapper_config.json\ndef launch_app(inputs): pass')
   mm_config=json.dumps({'home':{'function':'launch_app','inputs':{'app_id':'org.rawin.launcher'}},'green':{'function':'screen_off'}})
   t.put('/home/root/magic_mapper_config.json',mm_config)
   t.put('/var/lib/webosbrew/init.d/start_magic_mapper','SCRIPT='+str(t.p('/home/root/magic_mapper.py'))+'\nPYTHON_PIDFILE=/tmp/magic_mapper_python.pid\nrestart)\n')
   if current=='manual-update':t.put(BASE+'/VERSION','0.17.2')
  try:
   bundle=t.p('/bundle');(bundle/'webos10').mkdir(parents=True);(bundle/'ui').mkdir()
   (bundle/'ui/icon.png').write_text('icon')
   for name in ['update.sh','diagnose.sh','VERSION','probe.sh']:(bundle/name).write_text('test')
   (bundle/'webos4').mkdir();(bundle/'webos4/patch-home.js').write_text('test')
   for name in ['native-home.sh','native-stage.js','native-trial.sh','mode-switch.sh','integration.js','uninstall.sh']:
    source=t.p(BASE+'/'+name)
    if source.exists():shutil.copyfile(source,bundle/'webos10'/name)
    else:(bundle/'webos10'/name).write_text('exit 0')
   shutil.copyfile(t.p(BASE+'/takeover.sh'),bundle/'webos10/home-takeover.sh')
   (bundle/'webos10/boot-hook.sh').write_text('exit 0')
   (bundle/'webos10/home-stub').mkdir();(bundle/'webos10/home-stub/appinfo.json').write_text('{"type":"web"}')
   (bundle/'webos10/org.rawin.launcher_0.17.2_all.ipk').write_text('mock package')
   script=(ROOT/'webos10/install.sh').read_text()
   script=re.sub(r'(?<![\w/])(?:/var/lib/|/media/developer/|/usr/palm/|/usr/bin/qml-runner|/usr/bin/com.webos.app.home|/home/root/|/etc/starfish-release|/tmp/)',lambda m:str(t.root)+m[0],script)
   (bundle/'webos10/install.sh').write_text(script)
   hbc='/media/developer/apps/usr/palm/services/org.webosbrew.hbchannel.service/elevate-service'
   t.put(hbc,'#!/bin/sh\nexit 0\n');t.p(hbc).chmod(0o755)
   t.put('/bin/sed', '''#!/bin/sh
if [ "$1" = -i ]; then shift; exec /usr/bin/sed -i '' "$@"; fi
exec /usr/bin/sed "$@"
''');t.p('/bin/sed').chmod(0o755)
   t.put('/bin/id','#!/bin/sh\necho 0\n');t.p('/bin/id').chmod(0o755)
   t.put('/bin/wget',"#!/bin/sh\necho '{}'\n");t.p('/bin/wget').chmod(0o755)
   t.env['HOMEBAR_WEBOS']='10.3.1'
   r=subprocess.run(['sh',str(bundle/'webos10/install.sh')]+(['--keep-lg-home'] if manual else ['--additional-overlay'] if current=='fresh-overlay' else []),env=t.env,capture_output=True,text=True,timeout=20)
   assert r.returncode==0,(r.stdout,r.stderr)
   assert t.p(BASE+('/manual-home-mapping' if manual else '/native-home' if current=='native' else '/additional-overlay')).exists()
   assert not t.p(KEYS).exists(),'update wrote mapper bindings'
   if manual:
    assert t.p('/home/root/magic_mapper_config.json').read_text()==mm_config
    assert 'existing Magic Mapper HOME shortcut kept' in r.stdout
   elif current!='native':
    assert 'var exitTarget = false;' in t.p(APP+'/Config.js').read_text()
    assert t.p(HOME).resolve()==t.p('/foreign').resolve()
   else:assert t.p(STORE+'/com.webos.app.home/QML/OfflineStorage/Databases/'+DB+'.sqlite').read_text()=='latest-native-data'
   count+=1
  finally:t.clean()
 for current in ['native','overlay']:
  for release in ['10.3.1','11.0.0']:
   t=TV(current,mapper=False)
   try:
    bundle=t.p('/dispatch');(bundle/'webos10').mkdir(parents=True)
    script=(ROOT/'install.sh').read_text()
    script=re.sub(r'(?<![\w/])(?:/var/lib/|/etc/starfish-release)',lambda m:str(t.root)+m[0],script)
    (bundle/'install.sh').write_text(script)
    (bundle/'webos10/install.sh').write_text('echo ARG:$*\n')
    t.env['HOMEBAR_WEBOS']=release
    r=subprocess.run(['sh',str(bundle/'install.sh'),'--overlay'],env=t.env,capture_output=True,text=True,timeout=5)
    assert r.returncode==0,(r.stdout,r.stderr)
    assert ('ARG:--keep-lg-home' in r.stdout)==(current=='overlay'),r.stdout
    r=subprocess.run(['sh',str(bundle/'install.sh'),'--home-panel'],env=t.env,capture_output=True,text=True,timeout=5)
    assert r.returncode!=0 and 'restore the ordinary overlay' in r.stderr
    count+=1
   finally:t.clean()
 t=TV(mapper=False)
 try:
  hbc='/media/developer/apps/usr/palm/services/org.webosbrew.hbchannel.service/elevate-service'
  t.put(hbc,'#!/bin/sh\nexit 0\n');t.p(hbc).chmod(0o755)
  script=(ROOT/'probe.sh').read_text()
  script=re.sub(r'(?<![\w/])(?:/var/lib/|/media/developer/|/usr/palm/|/etc/starfish-release)',lambda m:str(t.root)+m[0],script)
  t.put('/probe.sh',script)
  r=subprocess.run(['sh',str(t.p('/probe.sh')),'additional-overlay'],env=t.env,capture_output=True,text=True,timeout=5)
  assert r.returncode==0,(r.stdout,r.stderr)
  assert not t.p(BASE+'/additional-overlay').exists(),'probe changed mode'
  r=subprocess.run(['sh',str(t.p('/probe.sh')),'overlay'],env=t.env,capture_output=True,text=True,timeout=5)
  assert r.returncode!=0 and 'Input Hook is required' in r.stdout
  count+=1
 finally:t.clean()
 print('PASS',count,'real-shell mode scenarios: migration, no-op, keys, rollback, conflicts, no mapper, foreign Home')
if __name__=='__main__':test()
