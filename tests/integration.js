const assert=require('assert'),fs=require('fs'),os=require('os'),path=require('path');
const Integration=require('../webos10/integration');
const BASE='/var/lib/webosbrew/rawin-launcher-home',IH='/home/root/.config/lginputhook/keybinds.json',MM='/home/root/magic_mapper.py',CFG='/home/root/magic_mapper_config.json';
const own={function:'launch_app',inputs:{app_id:'org.rawin.launcher'}};
function fixture(){
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'homebar-integration-'));const real=p=>typeof p==='number'?p:path.join(dir,p);
 const mapped={};for(const method of ['statSync','existsSync','readFileSync','readdirSync','unlinkSync','openSync'])mapped[method]=function(p,...args){return fs[method](real(p),...args);};
 for(const method of ['writeFileSync','fsyncSync','closeSync'])mapped[method]=function(p,...args){return fs[method](real(p),...args);};
 mapped.realpathSync=p=>fs.realpathSync(real(p)).slice(fs.realpathSync(dir).length);
 mapped.renameSync=(a,b)=>fs.renameSync(real(a),real(b));
 const put=(p,v)=>{fs.mkdirSync(path.dirname(real(p)),{recursive:true});fs.writeFileSync(real(p),typeof v==='string'?v:JSON.stringify(v));};
 put('/usr/bin/qml-runner','runner');put('/etc/starfish-release','release 10.3.1');put('/proc/mounts','');fs.mkdirSync(real(BASE),{recursive:true});
 let processes=[],restarts=0,failReload=false;
 const integration=new Integration({fs:mapped,processes:()=>processes,execFileSync:(bin,args)=>{if(args[1]==='restart'){restarts++;if(failReload)throw Error('reload failed');put('/tmp/magic_mapper_python.pid',String(100+restarts));put('/proc/'+(100+restarts)+'/cmdline','python\u0000'+MM+'\u0000');}}});
 return {dir,put,real,integration,json:p=>JSON.parse(fs.readFileSync(real(p),'utf8')),
  mm(config,active=false){put(MM,'VERSION = "1.1.0"\ndef get_button_map():\n magic_mapper_config.json\ndef launch_app(inputs): pass');put(CFG,config);put('/var/lib/webosbrew/init.d/start_magic_mapper','SCRIPT=/home/root/magic_mapper.py\nPYTHON_PIDFILE=/tmp/magic_mapper_python.pid\nrestart)');if(active)processes=[['python',MM]];},
  fail:()=>failReload=true,setProcesses:p=>processes=p,restarts:()=>restarts,cleanup:()=>fs.rmSync(dir,{recursive:true,force:true})};
}
let count=0;
function check(fn){const f=fixture();try{fn(f);count++;}finally{f.cleanup();}}
check(f=>{const r=f.integration.inspect();assert(r.nativeSupported);assert.strictEqual(r.blockers.length,0);});
check(f=>{f.put(IH,{'773':{action:'launch',id:'org.rawin.launcher'},'1042':{action:'launch',id:'other'}});f.integration.clean('native',BASE+'/journal');assert(!f.json(IH)['773']);assert(f.json(IH)['1042']);f.integration.rollback(BASE+'/journal');assert(f.json(IH)['773']);});
for(const value of [own,[own], [{...own,appId:'com.webos.app.hdmi1'},own]])check(f=>{f.mm({magic_mapper_settings:{exclusive_mode:true},home:value,green:{function:'screen_off'}});const r=f.integration.inspect();assert.strictEqual(r.cleanup,1);assert.strictEqual(r.blockers.length,0);f.integration.clean('native',BASE+'/journal');assert(!f.json(CFG).home);assert(f.json(CFG).green);assert(f.json(CFG).magic_mapper_settings.exclusive_mode);f.integration.rollback(BASE+'/journal');assert.deepStrictEqual(f.json(CFG).home,value);});
check(f=>{f.mm({home:[own,{function:'screen_off'}]});assert(f.integration.inspect().blockers.some(i=>i.code==='launch_home_mapping'));assert.throws(()=>f.integration.clean('native',BASE+'/journal'));assert.strictEqual(f.json(CFG).home.length,2);});
for(const value of ['disabled',{function:'curl',inputs:{url:'http://example.invalid'}}])check(f=>{f.mm({home:value});assert(f.integration.inspect().blockers.length);});
check(f=>{f.mm({yellow:[own,{function:'screen_off'}]});f.integration.clean('native',BASE+'/journal');assert.deepStrictEqual(f.json(CFG).yellow,[{function:'screen_off'}]);f.integration.restore('overlay',BASE+'/restore');assert.strictEqual(f.json(CFG).yellow.length,2);});
check(f=>{f.mm({home:own,green:own});f.integration.clean('native',BASE+'/journal');f.integration.restore('overlay',BASE+'/restore');assert(!f.json(CFG).home);assert.deepStrictEqual(f.json(CFG).green,own);});
check(f=>{f.mm({green:own});f.integration.clean('native',BASE+'/journal');f.put(CFG,{green:{function:'screen_off'},magic_mapper_settings:{block_mouse:true}});assert(f.integration.restore('overlay',BASE+'/restore'));assert.strictEqual(f.json(CFG).green.function,'screen_off');assert(f.json(CFG).magic_mapper_settings.block_mouse);});
check(f=>{f.mm({home:own},true);f.integration.clean('native',BASE+'/journal');assert.strictEqual(f.restarts(),1);});
check(f=>{f.mm({home:own},true);f.put('/var/lib/webosbrew/init.d/start_magic_mapper','old version');assert(f.integration.inspect().blockers.some(i=>i.code==='launch_reload_unknown'));});
check(f=>{f.mm({home:own});f.put(CFG,'invalid');assert(f.integration.inspect().blockers.some(i=>i.code==='launch_config_unknown'));});
check(f=>{f.mm({home:own});const r=f.integration.inspect();f.put(CFG,{home:own,green:own});assert.throws(()=>f.integration.clean('native',BASE+'/journal',r.fingerprint),/launch_changed/);});
check(f=>{assert(Integration.ihOwn({action:'exec',command:`/usr/bin/luna-send -n 1 luna://com.webos.applicationManager/launch '{"id":"org.rawin.launcher"}'`}));assert(!Integration.ihOwn({action:'exec',command:'echo org.rawin.launcher; do-other-things'}));});
check(f=>{f.mm({home:own});f.put(MM,'VERSION = "9.0.0"\ndef get_button_map(): magic_mapper_config.json\ndef launch_app(x): pass');assert(f.integration.inspect().blockers.some(i=>i.code==='launch_config_unknown'));});
check(f=>{f.mm({home:own},true);f.fail();assert.throws(()=>f.integration.clean('native',BASE+'/journal'),/launch_reload_failed/);assert(!f.json(CFG).home);assert.throws(()=>f.integration.rollback(BASE+'/journal'),/launch_reload_failed/);assert.deepStrictEqual(f.json(CFG).home,own);});
check(f=>{f.mm({home:own});f.integration.clean('native',BASE+'/journal');f.put(CFG,{home:{function:'screen_off'}});assert.throws(()=>f.integration.rollback(BASE+'/journal'),/launch_rollback_changed/);assert.strictEqual(f.json(CFG).home.function,'screen_off');});
check(f=>{f.mm({home:own});f.put(BASE+'/mapper-backup.json','invalid');assert.throws(()=>f.integration.clean('native',BASE+'/journal'),/launch_config_unknown/);assert.deepStrictEqual(f.json(CFG).home,own);});
check(f=>{f.put('/proc/mounts','other /usr/bin/com.webos.app.home none rw 0 0');assert.strictEqual(f.integration.inspect().owner,'other');assert.throws(()=>f.integration.assertNative(),/launch_home_other/);});
check(f=>{f.put(BASE+'/home-exe','#!/bin/sh');f.put('/usr/bin/qml-runner','runner');fs.symlinkSync(f.real(BASE+'/home-exe'),f.real('/usr/bin/com.webos.app.home'));f.put('/proc/mounts','/dev/x /usr/bin/com.webos.app.home ext4 rw 0 0');assert.strictEqual(f.integration.inspect().owner,'native','our script over the Home program (webOS 6 trial)');});
check(f=>{f.put('/proc/mounts','other /usr/palm/applications/com.webos.app.home/qml/main.qml none rw 0 0');assert.strictEqual(f.integration.inspect().owner,'other');});
check(f=>{f.put('/var/lib/tvweb/home.json',{enabled:true});assert.strictEqual(f.integration.inspect().owner,'other');f.put(BASE+'/additional-overlay','');const r=f.integration.inspect();assert(r.blockers.length);assert(!r.issues.some(i=>i.code==='launch_home_other'));});
check(f=>{f.put(IH,{'773':{action:'launch',id:'other'}});assert.throws(()=>f.integration.assertNative(),/launch_home_mapping/);assert.throws(()=>f.integration.legacyKey('773',false),/launch_home_mapping/);assert.strictEqual(f.json(IH)['773'].id,'other');});
check(f=>{f.put(IH,{'773':{action:'exec',command:'echo org.rawin.launcher'},'500':{action:'launch',id:'org.rawin.launcher'}});f.integration.clean('uninstall',BASE+'/journal');assert(f.json(IH)['773']);assert(!f.json(IH)['500']);});
check(f=>{f.mm({home:[own,{function:'screen_off'}],green:own});f.integration.clean('uninstall',BASE+'/journal');assert.deepStrictEqual(f.json(CFG).home,[{function:'screen_off'}]);assert(!f.json(CFG).green);});
check(f=>{f.put(IH,{});f.integration.legacyKey('1042',true);assert(Integration.ihOwn(f.json(IH)['1042']));assert(!f.json(IH)['773']);});
check(f=>{f.mm({home:own,green:own});f.integration.clean('native',BASE+'/journal');f.integration.restore('legacy',BASE+'/restore');assert.deepStrictEqual(f.json(CFG).home,own);assert.deepStrictEqual(f.json(CFG).green,own);});
check(f=>{f.mm({home:own});const r=f.integration.inspect();assert(!('files' in f.integration.publicReport(r)));assert(!JSON.stringify(f.integration.publicReport(r)).includes('exclusive_mode'));});
check(f=>{f.put(IH,{'773':{action:'pass'}});assert.strictEqual(f.integration.inspect().blockers.length,0);f.integration.clean('native',BASE+'/journal');assert.strictEqual(f.json(IH)['773'].action,'pass');});
check(f=>{f.mm({home:{function:'press_button',inputs:{button:'home'}}});assert.strictEqual(f.integration.inspect().blockers.length,0);});
check(f=>{f.mm({magic_mapper_settings:{exclusive_mode:false},home:{function:'press_button',inputs:{button:'home'}}});assert(f.integration.inspect().blockers.length);});
check(f=>{f.put(IH,{'773':{action:'launch',id:'org.rawin.launcher'}});f.integration.clean('native',BASE+'/journal');const journal=f.json(BASE+'/journal');f.put(IH,journal.entries[0].after.slice(0,1));f.integration.rollback(BASE+'/journal');assert(f.json(IH)['773']);});
check(f=>{f.put('/shared/keys.json',{'773':{action:'launch',id:'org.rawin.launcher'}});fs.mkdirSync(path.dirname(f.real(IH)),{recursive:true});fs.symlinkSync(f.real('/shared/keys.json'),f.real(IH));f.integration.clean('native',BASE+'/journal');assert(fs.lstatSync(f.real(IH)).isSymbolicLink());assert.deepStrictEqual(f.json('/shared/keys.json'),{});f.integration.rollback(BASE+'/journal');assert(f.json(IH)['773']);});
check(f=>{f.mm({home:own});f.put('/shared/magic.json',f.json(CFG));fs.unlinkSync(f.real(CFG));fs.symlinkSync(f.real('/shared/magic.json'),f.real(CFG));f.integration.clean('native',BASE+'/journal');assert(fs.lstatSync(f.real(CFG)).isSymbolicLink());assert(!f.json(CFG).home);});
check(f=>{f.put(IH,{'773':{action:'unknown_action'}});assert(f.integration.inspect().blockers.some(i=>i.code==='launch_config_unknown'));});
check(f=>{f.mm({magic_mapper_settings:{exclusive_mode:'false'},home:{function:'press_button',inputs:{button:'home'}}});assert(f.integration.inspect().blockers.length);});
// Input Hook removed (app, service, config) but its /tmp/inputhook lock is still
// there: only a stale file, so uninstall may go on; while the app is installed or
// a process of it runs, a missing config stays unknown.
check(f=>{f.put('/tmp/inputhook','');assert.strictEqual(f.integration.inspect().blockers.length,0);});
check(f=>{f.put('/tmp/inputhook','');f.put('/media/developer/apps/usr/palm/applications/org.webosbrew.inputhook/appinfo.json','{}');assert(f.integration.inspect().blockers.some(i=>i.code==='launch_config_unknown'));});
check(f=>{f.put('/tmp/inputhook','');f.setProcesses([['node','/media/developer/apps/usr/palm/services/org.webosbrew.inputhook.service/service.js']]);assert(f.integration.inspect().blockers.some(i=>i.code==='launch_config_unknown'));});
check(f=>{f.put('/tmp/inputhook','');f.setProcesses([['sh','-c','touch /tmp/inputhook; grep inputhook /proc/mounts']]);assert.strictEqual(f.integration.inspect().blockers.length,0);});
check(f=>{f.put('/etc/starfish-release','release 9.2.2');const r=f.integration.inspect();assert(!r.nativeSupported&&!r.trial,'webOS 9 without the trial');});
check(f=>{f.put('/etc/starfish-release','release 9.2.2');f.put(BASE+'/native-trial','');const r=f.integration.inspect();assert(r.nativeSupported&&r.trial,'webOS 9 with the trial');});
check(f=>{f.put('/etc/starfish-release','release 7.5.0');f.put(BASE+'/native-trial','');assert(f.integration.inspect().nativeSupported);});
check(f=>{f.put('/etc/starfish-release','release 6.3.2');assert(!f.integration.inspect().nativeSupported,'webOS 6 without the trial');});
check(f=>{f.put('/etc/starfish-release','release 6.5.3');f.put(BASE+'/native-trial','');const r=f.integration.inspect();assert(r.nativeSupported&&r.trial,'webOS 6 with the trial');});
check(f=>{f.put('/etc/starfish-release','release 5.5.0');f.put(BASE+'/native-trial','');assert(!f.integration.inspect().nativeSupported,'webOS 5 stays out');});
check(f=>{f.put(BASE+'/native-trial','');const r=f.integration.inspect();assert(r.nativeSupported&&!r.trial,'webOS 10 is not a trial');});
console.log('PASS',count,'integration cases: schema-aware cleanup, preservation, conditional lists, reload, rollback, changed config');
