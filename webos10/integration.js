// Shared launch checks for installation, the helper and boot. Inspect supported
// mapper formats without executing their config, and never equate unreadable
// configuration with an unused HOME. Plain ES5 so probe can load it on old TVs.
'use strict';
var fsDefault = require('fs'), child = require('child_process'), crypto = require('crypto'), path = require('path');
var BASE = '/var/lib/webosbrew/rawin-launcher-home';
var APP = 'org.rawin.launcher', HOME = 'com.webos.app.home';
var IH = '/home/root/.config/lginputhook/keybinds.json';
var MM = '/home/root/magic_mapper.py', START = '/var/lib/webosbrew/init.d/start_magic_mapper';
function object(v) { return v !== null && typeof v === 'object' && !Array.isArray(v); }
function equal(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
function own(v, key) { return Object.prototype.hasOwnProperty.call(v, key); }
function error(code) { var e = new Error(code); e.code = code; return e; }
function Integration(options) {
    options = options || {};
    this.fs = options.fs || fsDefault;
    this.exec = options.execFileSync || child.execFileSync;
    this.processes = options.processes || null;
}
Integration.prototype.read = function(file) {
    try {
        var stat = this.fs.statSync(file);
        if (stat.size > 1024 * 1024) return { state: 'unknown' };
        return { state: 'read', text: this.fs.readFileSync(file, 'utf8'), mode: stat.mode & 511 };
    } catch (e) { return { state: e.code === 'ENOENT' ? 'absent' : 'unknown' }; }
};
Integration.prototype.json = function(file) {
    var r = this.read(file);
    if (r.state === 'read') {
        try { r.value = JSON.parse(r.text); if (!object(r.value)) r.state = 'unknown'; }
        catch (e) { r.state = 'unknown'; }
    }
    return r;
};
Integration.prototype.processList = function() {
    if (this.processes) return this.processes();
    var result = [], fs = this.fs;
    fs.readdirSync('/proc').forEach(function(pid) {
        if (!/^\d+$/.test(pid)) return;
        try { result.push(fs.readFileSync('/proc/' + pid + '/cmdline', 'utf8').split('\u0000').filter(Boolean)); } catch (e) { if(e.code!=='ENOENT' && e.code!=='ESRCH')throw e; }
    });
    return result;
};
// HOME's key: 'home' in Magic Mapper; in Input Hook 773 on the tested Magic
// Remotes, or the code the installer was given (--home-key), which legacyKey
// keeps in home-key. Every other Homebar rule is the extra remote button.
Integration.prototype.homeKey = function(kind) {
    if(kind!=='input')return 'home';
    var saved=this.read(BASE+'/home-key'), code=saved.state==='read' ? saved.text.trim() : '';
    return /^[1-9]\d{0,4}$/.test(code) ? code : '773';
};
Integration.prototype.same = function(a, b) {
    try { var x=this.fs.statSync(a), y=this.fs.statSync(b); return x.ino === y.ino && x.dev === y.dev; } catch (e) { return false; }
};
// Recognise only a single luna-send launch. A command containing the app id
// incidentally, a pipeline or another shell action is not ours to delete.
function ihOwn(v) {
    if (!object(v)) return false;
    if (v.action === 'launch') return v.id === APP;
    if (v.action !== 'exec' || typeof v.command !== 'string') return false;
    var m = /^(?:\/usr\/bin\/)?luna-send\s+-(?:n|t)\s+1\s+luna:\/\/com\.webos\.(?:service\.)?application[Mm]anager\/launch\s+'([^']+)'\s*$/.exec(v.command);
    if (!m) return false;
    try { return JSON.parse(m[1]).id === APP; } catch (e) { return false; }
}
function mmOwn(v) { return object(v) && v.function === 'launch_app' && object(v.inputs) && v.inputs.app_id === APP; }
// The remote's buttons by their kernel code, the number Input Hook and Magic
// Mapper both go by: what Settings → Remote button shows. The coloured ones are
// named by the panel in its language.
var BUTTON_NAMES = {2:'1',3:'2',4:'3',5:'4',6:'5',7:'6',8:'7',9:'8',10:'9',11:'0',113:'Mute',114:'VOL -',115:'VOL +',
    119:'Pause',128:'Stop',139:'Settings',167:'Record',168:'Rewind',174:'Exit',207:'Play',208:'Fast forward',217:'Search',
    358:'Info',362:'Guide',398:'red',399:'green',400:'yellow',401:'blue',402:'CH +',403:'CH -',428:'Voice',771:'Channels',
    787:'Channels',799:'...',829:'SAP',994:'...',1037:'Netflix',1038:'Prime Video',1042:'Disney+',1043:'LG Channels',
    1044:'Rakuten TV',1083:'Search',1086:'Alexa',1107:'Sling',1116:'TV',1117:'Google',1123:'Home Hub',1124:'Accessibility'};
// OK, the arrows, BACK and HOME drive the panel, and power stays the TV's.
var RESERVED_BUTTONS = [28, 103, 105, 106, 108, 116, 412, 773];
// Magic Mapper's own names for the codes, read from its BUTTONS table: its
// configuration is keyed by name, and only the codes it lists can be mapped.
function mmButtons(source) {
    var block = /^BUTTONS\s*=\s*\{([\s\S]*?)^\}/m.exec(source || ''), names = {}, re = /^\s*(\d+)\s*:\s*["']([^"']+)["']/gm, m;
    if (!block) return names;
    while ((m = re.exec(block[1]))) names[m[1]] = m[2];
    return names;
}
function actions(v) { return Array.isArray(v) ? v : [v]; }
function removeOwn(value, kind) {
    if (kind === 'input') return ihOwn(value) ? undefined : value;
    if (Array.isArray(value)) {
        var keep = value.filter(function(a) { return !mmOwn(a); });
        return keep.length ? keep : undefined;
    }
    return mmOwn(value) ? undefined : value;
}
function inputSchema(map) {
    return Object.keys(map).every(function(key) {
        var v=map[key];
        if(!/^(0|[1-9]\d*)$/.test(key) || Number(key)>65535 || !object(v))return false;
        if(v.action==='ignore' || v.action==='pass')return true;
        if(v.action==='replace')return typeof v.keycode==='number' && v.keycode>=0 && v.keycode<=65535 && Math.floor(v.keycode)===v.keycode;
        if(v.action==='exec')return typeof v.command==='string' && v.command.length>0 && v.command.indexOf('\u0000')<0;
        return v.action==='launch' && typeof v.id==='string' && v.id.length>0 && v.id.indexOf('\u0000')<0 && (!own(v,'params') || object(v.params));
    });
}
function mapperBool(value) { return value===true || /^(yes|true)$/i.test(String(value)); }
function homePass(value, kind, settings) {
    if(kind==='input')return object(value) && (value.action==='pass' ||
        (value.action==='launch' && value.id===HOME && (!value.params || (object(value.params) && !Object.keys(value.params).length))));
    var list=actions(value);
    var exclusive=!settings || !own(settings,'exclusive_mode') || mapperBool(settings.exclusive_mode);
    if(settings && mapperBool(settings.ir_input_enabled) && own(settings,'ir_exclusive_mode') && !mapperBool(settings.ir_exclusive_mode))exclusive=false;
    return exclusive && list.length===1 && object(list[0]) &&
        list[0].function==='press_button' && object(list[0].inputs) && list[0].inputs.button==='home';
}
Integration.prototype.ownership = function() {
    var mounts=this.read('/proc/mounts'), glass=this.json('/var/lib/tvweb/home.json'), owner='lg';
    if (mounts.state !== 'read' || glass.state === 'unknown') owner='unknown';
    if (glass.state === 'read' && glass.value.enabled === true) owner='other';
    var homeMounts=mounts.state === 'read' ? mounts.text.split('\n').filter(function(line) {
        var target=line.split(/\s+/)[1] || '', home='/usr/palm/applications/'+HOME;
        return target===home || target.indexOf(home+'/')===0 || target==='/usr/bin/com.webos.app.home';
    }) : [];
    // webOS 6 trial: Homebar's script over LG Home's program, and nothing else.
    var exeOnly=homeMounts.length && homeMounts.every(function(line) {return line.split(/\s+/)[1]==='/usr/bin/com.webos.app.home';});
    if (exeOnly) {
        owner=this.same('/usr/bin/com.webos.app.home', BASE+'/home-exe') ? 'native' : 'other';
        if (glass.state === 'read' && glass.value.enabled === true) owner='other';
    } else if (homeMounts.length) {
        owner=this.same('/usr/palm/applications/'+HOME, BASE+'/native-app') ? 'native' :
              this.same('/usr/palm/applications/'+HOME, BASE+'/app') ? 'legacy' : 'other';
        if (glass.state === 'read' && glass.value.enabled === true) owner='other';
        if(homeMounts.some(function(line) {return line.split(/\s+/)[1]!=='/usr/palm/applications/'+HOME;}))owner='other';
    }
    return {owner:owner,homeMounts:homeMounts,glass:glass};
};
Integration.prototype.inspect = function() {
    var self=this, issues=[], blockers=[], files=[], signatures=[], processes=[], processUnknown=false;
    function issue(code, source, blocking) {
        var item={code:code, source:source || ''};
        if (!(current==='overlay' && (code==='launch_home_other' || code==='launch_home_mapping'))) issues.push(item);
        if (blocking) blockers.push(item);
    }
    var release=this.read('/etc/starfish-release');
    var trial=release.state === 'read' && /release (6|7|8|9)\./.test(release.text) && this.fs.existsSync(BASE+'/native-trial');
    var nativeSupported=release.state === 'read' && (/release (10|11)\./.test(release.text) || trial) && this.fs.existsSync('/usr/bin/qml-runner');
    var current=this.fs.existsSync(BASE+'/native-home') ? 'native' : this.fs.existsSync(BASE+'/additional-overlay') ? 'overlay' : 'legacy';
    var ownership=this.ownership(), owner=ownership.owner, homeMounts=ownership.homeMounts, glass=ownership.glass;
    if (owner === 'other') issue('launch_home_other','',true);
    if (owner === 'unknown') issue('launch_home_unknown','',true);
    try { processes=this.processList(); } catch (e) { processUnknown=true; issue('launch_scan_unknown','',true); }
    var ih=this.json(IH), inputInstalled=this.fs.existsSync('/media/developer/apps/usr/palm/applications/org.webosbrew.inputhook');
    if (ih.state==='read' && !inputSchema(ih.value))ih.state='unknown';
    // Input Hook leaves /tmp/inputhook behind when it starts. Without its config
    // that is an unknown mapping, unless the app is gone too and no process of
    // it runs: then only the stale lock is left (until the next boot).
    var ihRunning=processUnknown || processes.some(function(argv) { return argv.some(function(arg) { return /org\.webosbrew\.inputhook|lginputhook/i.test(arg); }); });
    var staleLock=ih.state === 'absent' && !inputInstalled && !ihRunning && this.fs.existsSync('/tmp/inputhook');
    if (ih.state === 'unknown' || (ih.state === 'absent' && this.fs.existsSync('/tmp/inputhook') && !staleLock)) issue('launch_config_unknown','Input Hook',true);
    if (ih.state === 'read') files.push({kind:'input',file:this.fs.realpathSync ? this.fs.realpathSync(IH) : IH,data:ih,active:this.fs.existsSync('/tmp/inputhook')});
    var mmScripts=[MM], runningScripts=[];
    processes.forEach(function(argv) {
        argv.forEach(function(arg) {
            if (arg === 'magic_mapper.py') { processUnknown=true; issue('launch_scan_unknown','Magic Mapper',true); }
            if (/\/(?:magic_mapper\.py)$/.test(arg)) {
                if (mmScripts.indexOf(arg)<0) mmScripts.push(arg);
                if (runningScripts.indexOf(arg)<0) runningScripts.push(arg);
            }
        });
    });
    var launcher=this.read(START), mmInstalled=false;
    var declared=launcher.state==='read' && /^SCRIPT=["']?([^\s"']+)["']?\s*$/m.exec(launcher.text);
    if(declared && declared[1].charAt(0)==='/' && declared[1].indexOf('$')<0) {
        if(mmScripts.indexOf(declared[1])<0)mmScripts.push(declared[1]);
    } else if(launcher.state!=='absent') { mmInstalled=true; issue('launch_config_unknown','Magic Mapper',true); }
    mmScripts.forEach(function(script) {
        if(processes.some(function(argv) {return argv.indexOf(script)>=0;}) && runningScripts.indexOf(script)<0)runningScripts.push(script);
    });
    mmScripts.forEach(function(script) {
        var source=self.read(script), config=path.join(path.dirname(script),'magic_mapper_config.json'), data=self.json(config);
        var active=runningScripts.indexOf(script)>=0;
        if(data.state==='read' && own(data.value,'magic_mapper_settings') && !object(data.value.magic_mapper_settings))data.state='unknown';
        if (source.state === 'absent' && data.state === 'absent' && !active) return;
        mmInstalled=true;
        var recognised=source.state==='read' && /^VERSION\s*=\s*["']1\.[0-2]\.\d+["']/m.test(source.text) && /def get_button_map\(/.test(source.text) && /magic_mapper_config\.json/.test(source.text) && /def launch_app\(/.test(source.text);
        var match=launcher.state==='read' && /^SCRIPT=["']?([^\s"']+)["']?\s*$/m.exec(launcher.text);
        var reloadable=!!(match && match[1]===script && /\brestart\)/.test(launcher.text) && /^PYTHON_PIDFILE=\/tmp\/magic_mapper_python\.pid\s*$/m.test(launcher.text));
        signatures.push([script,source.text || source.state,launcher.text || launcher.state]);
        if (!recognised || data.state!=='read' || processUnknown) issue('launch_config_unknown','Magic Mapper',true);
        else files.push({kind:'magic',file:self.fs.realpathSync ? self.fs.realpathSync(config) : config,data:data,active:active,reloadable:reloadable,script:script,source:source.text});
    });
    var cleanup=0, mapped=[], restoreSkipped=false;
    files.forEach(function(f) {
        f.changes=[];
        Object.keys(f.data.value).forEach(function(key) {
            if (key==='magic_mapper_settings') return;
            var before=f.data.value[key], after=removeOwn(before,f.kind);
            if (!equal(before,after)) { f.changes.push({key:key,before:before,after:after}); cleanup++; mapped.push({source:f.kind==='input'?'Input Hook':'Magic Mapper',key:key}); }
            var isHome=key===self.homeKey(f.kind);
            if (isHome && after!==undefined && !homePass(after,f.kind,f.data.value.magic_mapper_settings)) issue('launch_home_mapping',f.kind==='input'?'Input Hook':'Magic Mapper',true);
        });
        if (f.kind==='magic' && f.active && f.changes.length && !f.reloadable) issue('launch_reload_unknown','Magic Mapper',true);
        signatures.push([f.file,f.data.text,f.active,f.reloadable || false]);
    });
    if (inputInstalled && this.fs.existsSync('/tmp/inputhook') && runningScripts.length) issue('launch_two_mappers','',false);
    var companionMapped=files.some(function(f) {
        return Object.keys(f.data.value).some(function(key) {
            return key!==self.homeKey(f.kind) && !equal(f.data.value[key],removeOwn(f.data.value[key],f.kind));
        });
    });
    if(current!=='native')files.forEach(function(f) {if(f.changes.length && !f.active)issue('launch_mapper_inactive',f.kind==='magic'?'Magic Mapper':'Input Hook',false);});
    var homeOwn=files.some(function(f) { return f.changes.some(function(c) {return c.key===self.homeKey(f.kind);}); });
    if (current==='overlay' && (!companionMapped || homeOwn)) issue('launch_button_setup','',false);
    if (current==='native' && cleanup) issue('launch_mapping_returned','',false);
    if (current==='native' && owner==='lg') issue('launch_home_missing','',false);
    var result=this.json(BASE+'/mode-result.json');
    if (result.state==='read' && result.value.restoreSkipped) { restoreSkipped=true; issue('launch_restore_skipped','',false); }
    var fingerprint=crypto.createHash('sha256').update(JSON.stringify([current,owner,homeMounts,glass.text || glass.state,signatures,
        ih.state,mmInstalled,processUnknown])).digest('hex');
    return {nativeSupported:nativeSupported,trial:trial,current:current,owner:owner,issues:issues,blockers:blockers,cleanup:cleanup,mapped:mapped,
        legacyMagicReady:files.some(function(f) {return f.kind==='magic' && (f.active || f.reloadable) && f.changes.some(function(c) {return c.key==='home';});}),
        homeMapped:homeOwn,companionMapped:companionMapped,magicInstalled:mmInstalled,inputInstalled:inputInstalled,restoreSkipped:restoreSkipped,
        migrationAvailable:current==='legacy' && nativeSupported && blockers.length===0,fingerprint:fingerprint,files:files};
};
Integration.prototype.publicReport = function(report) {
    var out={}; Object.keys(report).forEach(function(k) { if(k!=='files')out[k]=report[k]; }); return out;
};
Integration.prototype.legacyMapper = function() {
    var report=this.inspect();
    var configured=report.legacyMagicReady;
    if(!configured || report.blockers.some(function(i) {return i.code!=='launch_home_other' && !(i.code==='launch_home_mapping' && i.source==='Magic Mapper');}))throw error('launch_config_unknown');
    return true;
};
Integration.prototype.assertNative = function(expected) {
    var report=this.inspect();
    if (!report.nativeSupported) throw error('launch_unsupported');
    if (report.blockers.length) throw error(report.blockers[0].code);
    if (expected && report.fingerprint!==expected) throw error('launch_changed');
    return report;
};
Integration.prototype.atomic = function(file,text,mode) {
    var tmp=file+'.homebar-tmp';
    var fd=this.fs.openSync(tmp,'wx',mode || 384);
    try { this.fs.writeFileSync(fd,text); this.fs.fsyncSync(fd); }
    catch(e) { try { this.fs.unlinkSync(tmp); } catch(ignore) {} throw e; }
    finally { this.fs.closeSync(fd); }
    try { this.fs.renameSync(tmp,file); } catch(e) { try { this.fs.unlinkSync(tmp); } catch(ignore) {} throw e; }
};
Integration.prototype.saveMapper = function(entry, text) {
    if(entry.kind!=='input') { this.atomic(entry.file,text,entry.mode); return; }
    // Input Hook's own configuration API saves in place. Keep that inode for
    // older watchers too; the migration journal also covers an interrupted write.
    this.fs.writeFileSync(entry.file,text,{mode:entry.mode || 384});
    var fd=this.fs.openSync(entry.file,'r');
    try { this.fs.fsyncSync(fd); } finally { this.fs.closeSync(fd); }
};
Integration.prototype.reload = function(changed) {
    var self=this;
    changed.forEach(function(f) {
        if(f.kind!=='magic' || !f.active)return;
        if(!f.reloadable)throw error('launch_reload_unknown');
        var previous=self.read('/tmp/magic_mapper_python.pid').text;
        try { self.exec('/bin/sh',[START,'restart'],{timeout:15000,stdio:'pipe'}); } catch(e) { throw error('launch_reload_failed'); }
        var running=false;
        for(var i=0;i<8;i++) {
            var pid=self.read('/tmp/magic_mapper_python.pid').text || '';
            var command=self.read('/proc/'+pid.trim()+'/cmdline');
            running=/^\d+\s*$/.test(pid) && pid!==previous && command.state==='read' && command.text.split('\u0000').indexOf(f.script)>=0;
            if(running)break;
            self.exec('/bin/sleep',['1'],{timeout:2000,stdio:'pipe'});
        }
        if(!running)throw error('launch_reload_failed');
    });
};
// Journal before each write. Recovery compares the live content with our write,
// so a user edit made in the meantime is never overwritten by a rollback.
Integration.prototype.writeChanges = function(changes,journal) {
    var self=this, saved=this.json(journal), entries=saved.state==='read' ? saved.value.entries : [];
    changes.forEach(function(f) {
        var live=self.read(f.file);
        if(live.state!=='read' || live.text!==f.before)throw error('launch_changed');
        entries.push(f);self.atomic(journal,JSON.stringify({entries:entries}),384);
        if(self.read(f.file).text!==f.before)throw error('launch_changed');
        self.saveMapper(f,f.after);
    });
    this.reload(changes);
};
Integration.prototype.clean = function(target,journal,expected) {
    var report=target==='native' ? this.assertNative(expected) : this.inspect(), self=this, writes=[];
    if(target==='uninstall' && report.blockers.some(function(i) {return /unknown/.test(i.code);}))throw error('launch_config_unknown');
    report.files.forEach(function(f) {
        var next=JSON.parse(f.data.text), changes=f.changes.filter(function(c) {return target==='native' || target==='uninstall' || c.key===self.homeKey(f.kind);});
        if(!changes.length)return;
        if(f.kind==='magic' && f.active && !f.reloadable)throw error('launch_reload_unknown');
        changes.forEach(function(c) { if(c.after===undefined)delete next[c.key];else next[c.key]=c.after; });
        writes.push({kind:f.kind,file:f.file,script:f.script,active:f.active,reloadable:f.reloadable,
            before:f.data.text,after:JSON.stringify(next,null,2)+'\n',mode:f.data.mode,changes:changes});
    });
    var old=this.json(BASE+'/mapper-backup.json');
    if(old.state==='unknown' || (old.state==='read' && !Array.isArray(old.value.entries)))throw error('launch_config_unknown');
    this.writeChanges(writes,journal);
    var history=old.state==='read' ? old.value.entries : [];
    this.atomic(BASE+'/mapper-backup.json',JSON.stringify({entries:history.concat(writes)}),384);
};
Integration.prototype.restore = function(target,journal) {
    var saved=this.json(BASE+'/mapper-backup.json'), report=this.inspect(), self=this, writes=[], skipped=false;
    if(saved.state==='unknown' || (saved.state==='read' && !Array.isArray(saved.value.entries)))return true;
    if(saved.state!=='read')return false;
    saved.value.entries.slice().reverse().forEach(function(entry) {
        var f=report.files.filter(function(x) {return x.file===entry.file;})[0];
        if(!f){skipped=true;return;}
        var before=f.data.text, next=JSON.parse(before), restored=[];
        entry.changes.forEach(function(c) {
            if(target==='overlay' && c.key===self.homeKey(entry.kind))return;
            var live=own(next,c.key) ? next[c.key] : undefined;
            if(equal(live,c.after)) {Object.defineProperty(next,c.key,{value:c.before,writable:true,enumerable:true,configurable:true});restored.push(c.key);}
            else if(!equal(live,c.before))skipped=true;
        });
        if(!restored.length)return;
        if(f.kind==='magic' && f.active && !f.reloadable){skipped=true;return;}
        var after=JSON.stringify(next,null,2)+'\n';
        writes.push({kind:f.kind,file:f.file,script:f.script,active:f.active,reloadable:f.reloadable,before:before,after:after,mode:f.data.mode});
        f.data.text=after;f.data.value=next;
    });
    this.writeChanges(writes,journal);
    return skipped;
};
Integration.prototype.rollback = function(journal) {
    var data=this.json(journal), self=this, reload=[];
    if(data.state!=='read')return;
    data.value.entries.slice().reverse().forEach(function(f) {
        var live=self.read(f.file);
        var partial=false;
        if(f.kind==='input' && live.state==='read' && f.after.indexOf(live.text)===0) {
            try { JSON.parse(live.text); } catch(e) { partial=true; }
        }
        if(live.state==='read' && (live.text===f.after || partial)) {
            self.saveMapper(f,f.before);reload.push(f);
        } else if(live.state!=='read' || live.text!==f.before)throw error('launch_rollback_changed');
        else if(f.active)reload.push(f);
    });
    this.reload(reload);
};
// HOME via mapper: HOME's code in Input Hook launches Homebar. Only the rule
// on the earlier HOME code is replaced; the extra remote button stays.
Integration.prototype.legacyKey = function(key, execute) {
    if (!/^[1-9]\d{0,4}$/.test(key) || Number(key)>65535) throw error('launch_unknown');
    var data=this.json(IH), next=data.state==='absent' ? {} : data.value, previous=this.homeKey('input');
    if(data.state==='unknown')throw error('launch_config_unknown');
    if(own(next,key) && !ihOwn(next[key]))throw error('launch_home_mapping');
    if(own(next,previous) && ihOwn(next[previous]))delete next[previous];
    next[key]=execute ? {action:'exec',command:"/usr/bin/luna-send -n 1 luna://com.webos.applicationManager/launch '{\"id\":\"org.rawin.launcher\",\"noSplash\":true,\"spinner\":false}'"} : {action:'launch',id:APP};
    var file=data.state==='read' && this.fs.realpathSync ? this.fs.realpathSync(IH) : IH;
    this.saveMapper({kind:'input',file:file,mode:data.mode || 384},JSON.stringify(next));
    this.atomic(BASE+'/home-key',key+'\n',420);
};
// The HOME code for the installer: the one kept in home-key, else (installs
// before it was kept) 773 when that is Homebar's, else the first Homebar rule.
Integration.prototype.legacyHome = function() {
    var data=this.json(IH), saved=this.read(BASE+'/home-key');
    if(saved.state==='read')return this.homeKey('input');
    if(data.state!=='read')return '';
    if(own(data.value,'773') && ihOwn(data.value['773']))return '773';
    return Object.keys(data.value).filter(function(k) {return ihOwn(data.value[k]);})[0] || '';
};
// Settings → Remote button: one button besides HOME opens Homebar. It goes
// to the mapper that is running (Input Hook first), or else to the one that is
// installed; a button with someone else's action is never taken over.
Integration.prototype.buttonTarget = function(report) {
    var input=report.files.filter(function(f) {return f.kind==='input';})[0];
    var magic=report.files.filter(function(f) {return f.kind==='magic';})[0];
    if(!input && report.inputInstalled && this.json(IH).state==='absent')
        input={kind:'input',file:IH,data:{state:'absent',text:'',value:{},mode:384},active:this.fs.existsSync('/tmp/inputhook')};
    if(input && input.active)return input;
    if(magic && magic.active)return magic;
    return input || magic || null;
};
// What Settings → Remote button shows: Homebar's extra button(s), where a new
// one would go (none: Homebar only reads the code for the user to set it up
// elsewhere), whether that mapper runs now, and a reason it cannot be used.
Integration.prototype.buttons = function(report) {
    report=report || this.inspect();
    var self=this, bound=[], target=this.buttonTarget(report), blocked=report.blockers.filter(function(i) {return /unknown/.test(i.code);})[0];
    report.files.forEach(function(f) {
        var codes={}, names=f.kind==='magic' ? mmButtons(f.source) : {};
        Object.keys(names).forEach(function(c) { codes[names[c]]=Number(c); });
        Object.keys(f.data.value).forEach(function(key) {
            if(key==='magic_mapper_settings' || key===self.homeKey(f.kind))return;
            var v=f.data.value[key];
            if(equal(v,removeOwn(v,f.kind)))return;
            var code=f.kind==='input' ? Number(key) : codes[key];
            bound.push({mapper:f.kind,key:key,code:code || 0,name:BUTTON_NAMES[code] || (f.kind==='magic' ? key : '')});
        });
    });
    return {mapper:target ? target.kind : '',active:!!(target && target.active),bound:bound,blocked:blocked ? blocked.code : ''};
};
Integration.prototype.buttonName = function(code) { return BUTTON_NAMES[code] || ''; };
// The mapper files with Homebar's extra button taken out (HOME stays as the
// launch method set it), plus the new button in target when one is given.
// The mode switch's backup loses its extra-button entries too: restoring one
// later would bring back a button that was changed or unpinned here.
Integration.prototype.writeButtons = function(report, target, key) {
    var self=this, writes=[], files=report.files.slice();
    if(target && files.indexOf(target)<0)files.push(target);
    files.forEach(function(f) {
        var next=f.data.state==='read' ? JSON.parse(f.data.text) : {}, before=JSON.stringify(next);
        Object.keys(next).forEach(function(k) {
            if(k==='magic_mapper_settings' || k===self.homeKey(f.kind))return;
            var after=removeOwn(next[k],f.kind);
            if(after===undefined)delete next[k]; else next[k]=after;
        });
        if(f===target)next[key]=f.kind==='input' ? {action:'launch',id:APP} : {function:'launch_app',inputs:{app_id:APP}};
        if(JSON.stringify(next)===before)return;
        if(f.kind==='magic' && f.active && !f.reloadable)throw error('launch_reload_unknown');
        writes.push({entry:{kind:f.kind,file:f.file,script:f.script,active:f.active,reloadable:f.reloadable,mode:f.data.mode || 384},
            before:f.data.state==='read' ? f.data.text : null,after:JSON.stringify(next,null,2)+'\n'});
    });
    writes.forEach(function(w) {
        var live=self.read(w.entry.file);
        if(w.before===null ? live.state!=='absent' : (live.state!=='read' || live.text!==w.before))throw error('launch_changed');
        self.saveMapper(w.entry,w.after);
    });
    this.reload(writes.map(function(w) {return w.entry;}));
    var backup=this.json(BASE+'/mapper-backup.json');
    if(backup.state==='read' && Array.isArray(backup.value.entries)) {
        var kept=backup.value.entries.map(function(e) {
            var c={}; Object.keys(e).forEach(function(k) {c[k]=e[k];});
            c.changes=(e.changes || []).filter(function(ch) {return ch.key===self.homeKey(e.kind);});
            return c;
        }).filter(function(e) {return e.changes.length;});
        if(!equal(kept,backup.value.entries))this.atomic(BASE+'/mapper-backup.json',JSON.stringify({entries:kept}),384);
    }
};
Integration.prototype.bindButton = function(code) {
    code=Number(code);
    if(!(code>0 && code<=65535 && Math.floor(code)===code))throw error('button_unknown');
    if(RESERVED_BUTTONS.indexOf(code)>=0 || String(code)===this.homeKey('input'))throw error('button_reserved');
    var report=this.inspect(), state=this.buttons(report), target=this.buttonTarget(report);
    if(state.blocked)throw error(state.blocked);
    if(!target)throw error('button_no_mapper');
    var key=target.kind==='input' ? String(code) : mmButtons(target.source)[code];
    if(!key)throw error('button_unsupported');
    var current=own(target.data.value,key) ? target.data.value[key] : undefined;
    if(current!==undefined && removeOwn(current,target.kind)!==undefined)throw error('button_taken');
    this.writeButtons(report,target,key);
    return this.buttons();
};
Integration.prototype.unbindButton = function() {
    var report=this.inspect(), state=this.buttons(report);
    if(state.blocked)throw error(state.blocked);
    this.writeButtons(report,null,null);
    return this.buttons();
};
Integration.ihOwn=ihOwn;Integration.mmOwn=mmOwn;Integration.mmButtons=mmButtons;
module.exports=Integration;
var messages={
    launch_home_other:'Another launcher owns HOME. Disable its takeover or choose --additional-overlay.',
    launch_home_unknown:'HOME ownership could not be verified. Use --additional-overlay or inspect Diagnose.',
    launch_config_unknown:'Mapper configuration could not be verified. Fix it or choose --additional-overlay.',
    launch_home_mapping:'HOME has another action assigned. Keep it with --additional-overlay, or remove the conflicting rule first.',
    launch_reload_unknown:'Active Magic Mapper cannot be reloaded safely. Update or stop it first.',
    launch_reload_failed:'Magic Mapper did not restart correctly. Check /tmp/magic_mapper.log.',
    launch_changed:'Configuration changed. Review and confirm again.',
    launch_scan_unknown:'A running mapper could not be inspected. Use --additional-overlay or inspect Diagnose.',
    launch_rollback_changed:'A concurrent mapper edit was preserved. The recovery journal was retained for inspection.',
    launch_unsupported:'Direct system HOME requires webOS 10/11 (or the trial on 6 to 9) and qml-runner.',
    button_reserved:'OK, the arrows, BACK, HOME and power cannot open Homebar.',
    button_taken:'That button already has another action in the mapper.',
    button_no_mapper:'Neither Input Hook nor Magic Mapper is installed.',
    button_unsupported:'Magic Mapper does not know that button.',
    button_unknown:'Not a button code.'
};
if(require.main===module) {
    var integration=new Integration(), cmd=process.argv[2];
    try {
        if(cmd==='owner')console.log(integration.ownership().owner);
        else if(cmd==='inspect')console.log(JSON.stringify(integration.publicReport(integration.inspect())));
        else if(cmd==='legacy-mapper')integration.legacyMapper();
        else if(cmd==='button-status')console.log(JSON.stringify(integration.buttons()));
        else if(cmd==='button-bind')console.log(JSON.stringify(integration.bindButton(process.argv[3])));
        else if(cmd==='button-unbind')console.log(JSON.stringify(integration.unbindButton()));
        else if(cmd==='legacy-home')console.log(integration.legacyHome());
        else if(cmd==='legacy-key')integration.legacyKey(process.argv[3],process.argv[4]==='exec');
        else if(cmd==='legacy-check') { var legacy=integration.inspect(); var problem=legacy.blockers.filter(function(i) {return i.code!=='launch_home_other' && !(process.argv[3]==='magic' && i.code==='launch_home_mapping' && i.source==='Magic Mapper');})[0]; if(problem)throw error(problem.code); }
        else if(cmd==='check')integration.assertNative(process.argv[3]);
        else if(cmd==='match') { if(integration.inspect().fingerprint!==process.argv[3])throw error('launch_changed'); }
        else if(cmd==='clean')integration.clean(process.argv[3],process.argv[4],process.argv[5]);
        else if(cmd==='restore')console.log(JSON.stringify({restoreSkipped:integration.restore(process.argv[3],process.argv[4])}));
        else if(cmd==='rollback')integration.rollback(process.argv[3]);
        else if(cmd==='select') {
            var r=integration.inspect();
            console.log(r.blockers.length ? 'overlay' : r.nativeSupported ? 'native' : (r.homeMapped && (r.inputInstalled || r.legacyMagicReady)) ? 'mapped' : (r.magicInstalled || r.cleanup) ? 'overlay' : 'legacy');
        } else throw error('launch_unknown');
    } catch(e) {console.error((e.code || 'launch_unknown')+': '+(messages[e.code] || 'Launch configuration could not be changed safely. Inspect Diagnose.'));process.exit(1);}
}
