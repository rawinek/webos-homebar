"""Actual top-level installer decisions with disposable TV paths and stub installers."""
import importlib.util, json, re, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
s=importlib.util.spec_from_file_location('mode_shell',ROOT/'tests/mode-switch.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
def run(release='10.3.1',panel=False,setup=lambda t:None,expected='native',args=(),fails=False):
 t=m.TV(release=release,mapper=False)
 try:
  setup(t);bundle=t.p('/bundle');(bundle/'webos10').mkdir(parents=True);(bundle/'webos4').mkdir()
  script=(ROOT/'install.sh').read_text()
  script=re.sub(r'(?<![\w/])(?:/var/lib/|/etc/starfish-release)',lambda v:str(t.root)+v[0],script)
  (bundle/'install.sh').write_text(script)
  (bundle/'webos10/integration.js').write_text(t.p(m.BASE+'/integration.js').read_text())
  (bundle/'probe.sh').write_text('if [ "$1" = panel ]; then exit '+('0' if panel else '1')+'; fi\nexit 0\n')
  (bundle/'webos10/install.sh').write_text('echo OVERLAY_ARGS:$*\n')
  (bundle/'webos4/install.sh').write_text('echo PANEL_INSTALL\n')
  result=subprocess.run(['sh',str(bundle/'install.sh'),*args],env=dict(t.env,HOMEBAR_WEBOS=release),text=True,capture_output=True,timeout=8)
  if fails:
   assert result.returncode!=0,result.stdout
   return result.stderr
  assert result.returncode==0,(result.stdout,result.stderr)
  output=result.stdout
  if expected=='panel':assert 'PANEL_INSTALL' in output,output
  else:
   assert 'OVERLAY_ARGS:' in output,output
   assert ('--native-home' in output)==(expected=='native'),output
   assert ('--additional-overlay' in output)==(expected=='overlay'),output
  return output
 finally:t.clean()
def magic(t,key='home'):
 t.put('/home/root/magic_mapper.py','VERSION = "1.1.0"\ndef get_button_map(): magic_mapper_config.json\ndef launch_app(inputs): pass')
 t.put('/home/root/magic_mapper_config.json',json.dumps({key:{'function':'launch_app','inputs':{'app_id':'org.rawin.launcher'}}}))
 t.put('/var/lib/webosbrew/init.d/start_magic_mapper','SCRIPT='+str(t.p('/home/root/magic_mapper.py'))+'\nPYTHON_PIDFILE=/tmp/magic_mapper_python.pid\nrestart)\n')
run('6.5.0',setup=magic,expected='legacy')
run('6.5.0',setup=lambda t:magic(t,'green'),expected='overlay')
run('6.5.0',setup=lambda t:(magic(t),t.put(m.BASE+'/VERSION','0.17.2')),expected='legacy')
run();run('11.0.0');run('4.10.0',panel=True,expected='panel')
run('6.5.0',expected='legacy');run('9.0.0',expected='legacy')
run(setup=lambda t:t.foreign(),expected='overlay')
run(setup=lambda t:t.put(m.KEYS,json.dumps({'773':{'action':'launch','id':'other.launcher'}})),expected='overlay')
run(setup=lambda t:t.put('/home/root/magic_mapper.py','unknown fork'),expected='overlay')
run(setup=lambda t:t.put(m.BASE+'/VERSION','0.17.2'),expected='legacy')
run('4.10.0',setup=lambda t:t.put('/var/lib/webosbrew/rawin-launcher/VERSION','0.17.2'),expected='panel')
# Files of LG's QML Home patched by another tool do not turn a fresh install into the additional overlay.
run('4.10.0',panel=True,setup=lambda t:t.put('/proc/mounts','fake '+str(t.p('/usr/palm/applications/com.webos.app.home/qml/Components/CustomRibbon.qml'))+' ext4 rw 0 0\n'),expected='panel')
# The trial of the native Home: webOS 6 to 9 only, and it says so.
for release in ('6.5.3','7.5.0','8.3.0','9.2.2'):
 out=run(release,args=('--try-native-home',),expected='legacy');assert '--try-native' in out and '--keep-lg-home' not in out,out
for release in ('10.3.1','11.0.0','5.5.0','4.10.0'):
 assert '--try-native-home is for' in run(release,args=('--try-native-home',),fails=True)
run(args=('--overlay',),expected='legacy');run(args=('--additional-overlay',),expected='overlay')
print('PASS 15 install policies: fresh defaults, supported native, ribbon, compatibility, other Home, unknown mapper, existing installs and explicit choices')
