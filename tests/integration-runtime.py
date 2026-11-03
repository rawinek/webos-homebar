"""Post-install ownership changes, mapper reload failures and uninstall on the fake TV."""
import importlib.util,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
s=importlib.util.spec_from_file_location('mode_shell',ROOT/'tests/mode-switch.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
CFG='/home/root/magic_mapper_config.json';MM='/home/root/magic_mapper.py'
OWN={'function':'launch_app','inputs':{'app_id':'org.rawin.launcher'}}
def mapper(t,active=False):
 t.put(MM,'VERSION = "1.1.0"\ndef get_button_map(): magic_mapper_config.json\ndef launch_app(inputs): pass')
 t.put(CFG,json.dumps({'magic_mapper_settings':{'exclusive_mode':True},'home':[OWN],'green':{'function':'screen_off'}}))
 if not active:return
 # Emulate only the supervisor/PID boundary. No actual remote or Python mapper.
 t.put('/var/lib/webosbrew/init.d/start_magic_mapper',f'''#!/bin/sh
SCRIPT={t.p(MM)}
PYTHON_PIDFILE=/tmp/magic_mapper_python.pid
case "$1" in
 restart)
  if [ -f "$TV_ROOT/fail-mm" ]; then rm -f "$TV_ROOT/fail-mm"; exit 1; fi
  if [ -f "$TV_ROOT/fail-mm-always" ]; then exit 1; fi
  echo 7001 >"$TV_ROOT/tmp/magic_mapper_python.pid"
  mkdir -p "$TV_ROOT/proc/7001"
  printf 'python\\000%s\\000' "$SCRIPT" >"$TV_ROOT/proc/7001/cmdline"
  ;;
esac
''')
 t.put('/tmp/magic_mapper_python.pid','7000\n');t.put('/proc/7000/cmdline','python\0'+str(t.p(MM))+'\0')
count=0
for active in [False,True]:
 t=m.TV()
 try:
  mapper(t,active);before=t.p(CFG).read_bytes();t.switch('native');assert not json.loads(t.p(CFG).read_text()).get('home')
  t.switch('overlay');assert not json.loads(t.p(CFG).read_text()).get('home');assert t.keys()['500']['id']=='org.rawin.launcher';count+=1
 finally:t.clean()
for permanent in [False,True]:
 t=m.TV()
 try:
  mapper(t,True);before=t.p(CFG).read_bytes();keys=t.p(m.KEYS).read_bytes();t.put('/fail-mm-always' if permanent else '/fail-mm','')
  t.switch('native',False);assert t.p(CFG).read_bytes()==before;assert t.p(m.KEYS).read_bytes()==keys
  assert not t.p(m.BASE+'/native-home').exists()
  if permanent:
   assert t.p(m.BASE+'/mode-switch-lock/runtime-restored').exists()
   t.put(m.STORE+'/org.rawin.launcher/QML/OfflineStorage/Databases/'+m.DB+'.sqlite','settings-after-failure')
   t.p('/fail-mm-always').unlink();t.switch('recover')
   assert t.p(m.STORE+'/org.rawin.launcher/QML/OfflineStorage/Databases/'+m.DB+'.sqlite').read_text()=='settings-after-failure'
  assert not t.p(m.BASE+'/mode-switch-lock').exists();count+=1
 finally:t.clean()
t=m.TV('native')
try:
 subprocess.run(['umount',str(t.p(m.HOME))],env=t.env,check=True);t.foreign()
 t.switch('overlay');assert t.p(m.HOME).resolve()==t.p('/foreign').resolve();assert not t.p(m.BASE+'/native-home').exists();count+=1
finally:t.clean()
for mode in ['native','overlay']:
 t=m.TV(mode)
 try:
  mapper(t,False)
  if mode=='overlay':t.foreign()
  # Unknown foreign actions on HOME must survive uninstall, own launch rules go.
  t.put(CFG,json.dumps({'home':[OWN,{'function':'screen_off'}],'green':OWN}))
  t.run('uninstall.sh','',True)
  assert json.loads(t.p(CFG).read_text())=={'home':[{'function':'screen_off'}]}
  assert t.keys()=={'1042':{'action':'launch','id':'other.app'}}
  if mode=='overlay':assert t.p(m.HOME).resolve()==t.p('/foreign').resolve()
  else:assert not t.p(m.HOME).is_symlink()
  count+=1
 finally:t.clean()
# A step that fails stops the uninstall with an error, nothing removed after it:
# LG Home that cannot be given back must not be reported as removed.
t=m.TV('overlay')
try:
 t.put(m.BASE+'/takeover.sh','#!/bin/sh\nexit 1\n')
 r=t.run('uninstall.sh','',False)
 assert 'removed' not in r.stdout and t.p(m.BASE+'/uninstall.sh').exists() and t.p(m.APP+'/appinfo.json').exists(),(r.stdout,r.stderr)
 count+=1
finally:t.clean()
for target in ['/usr/palm/applications/com.webos.app.home/main.qml','/usr/bin/com.webos.app.home']:
 t=m.TV('native')
 try:
  t.put('/proc/mounts',t.p('/proc/mounts').read_text()+'foreign '+str(t.p(target))+' none rw 0 0\n')
  before=t.p('/proc/mounts').read_text()
  t.switch('overlay')
  assert t.p('/proc/mounts').read_text()==before,(target,before,t.p('/proc/mounts').read_text())
  assert t.p(m.HOME).is_symlink()
  calls=t.p('/calls').read_text().splitlines()
  # Only the normal app may be closed after a foreign nested takeover.
  assert not any('closeByAppId' in x and 'com.webos.app.home' in x for x in calls[-2:])
  count+=1
 finally:t.clean()
t=m.TV('native')
try:
 t.put('/calls','')
 t.switch('overlay')
 calls=t.p('/calls').read_text().splitlines()
 block=next(i for i,x in enumerate(calls) if '/blockSystemApp ' in x)
 release=next(i for i,x in enumerate(calls[block+1:],block+1) if '/releaseBlockSystemApp ' in x)
 assert any('/closeByAppId ' in x and 'com.webos.app.home' in x for x in calls[block+1:release]),calls
 count+=1
finally:t.clean()
print('PASS',count,'runtime shell cases: active/inactive Magic Mapper, reload rollback/recovery, preserving later foreign HOME')
