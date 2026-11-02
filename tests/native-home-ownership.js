const assert=require('assert'),fs=require('fs'),vm=require('vm');
const source=fs.readFileSync('webos10/helper/service.js','utf8');
const functions=source.slice(source.indexOf('function sameFile('),source.indexOf('const ICON_ROOTS'));
const route=source.slice(source.indexOf("    if (url.pathname === '/home')"),source.indexOf("    if (url.pathname === '/foreground')"));
// exe: the webOS 6 way, Homebar's script mounted over LG Home's program while
// Home's folder stays LG's; only counted for a configured System HOME.
for(const [configured,mounted,foreign,exe] of [[false,false,false,false],[true,true,false,false],[true,false,true,false],[true,true,true,false],
                                            [true,false,false,true],[true,false,true,true],[false,false,false,true],[true,false,false,false]]){
 const ino=p=>p.endsWith('/home-exe')?7:p==='/usr/bin/com.webos.app.home'?(exe?7:8):p.includes('native-app')?(mounted?1:2):1;
 const ctx={modeControl:{foreignHome:()=>foreign},nativeHome:()=>configured,APP:'org.rawin.launcher',fs:{statSync:p=>({ino:ino(p),dev:1})},url:{pathname:'/home'},res:{},send:(r,s,b)=>ctx.answer=b};
 vm.runInNewContext(functions,ctx);vm.runInNewContext('(function(){'+route+'})()',ctx);
 const ours=configured&&(mounted||exe)&&!foreign;
 assert.strictEqual(ctx.nativeHomeMounted(),ours);
 assert.strictEqual(ctx.panelId(),ours?'com.webos.app.home':'org.rawin.launcher');
 assert.strictEqual(ctx.answer.nativeHome,ours);
 assert.strictEqual(ctx.answer.configuredNativeHome,configured);
 // Without System HOME the mock's overlay stand-in (app) is always in Home's folder.
 assert.strictEqual(ctx.answer.lgHome,!(configured?mounted||exe:true));
}
console.log('PASS actual helper ownership: normal app stays accessible and restart avoids foreign Home after later takeover');

const wiring=source.slice(source.indexOf('const returner = new AfterExit'),source.indexOf('let subscribed = false;'));
for(const [native,mounted,companion,busy,foreign] of [[true,true,false,false,false],[true,false,false,false,true],[false,false,true,false,false],[true,true,false,true,false],[false,false,false,false,false]]) {
 const context={AfterExit:class {constructor(options){return options;}},savedInput:'',BASE:'/base',
 nativeHome:()=>native,nativeHomeMounted:()=>mounted,fs:{existsSync:()=>companion},modeControl:{isBusy:()=>busy,foreignHome:()=>foreign},glasshouseHome:()=>false,
 readSettings:()=>({exitTo:'com.webos.app.hdmi1'}),note:()=>{},luna:()=>Promise.resolve({}),LAST_INPUT_FILE:'/last'};
 vm.runInNewContext(wiring+';globalThis.options=returner;',context);
 assert.strictEqual(context.options.nativeHome(),mounted);
 assert.strictEqual(context.options.homeTaken(),(native&&!mounted)||companion||busy||foreign);
}
console.log('PASS native return wiring allows owned native Home only, respects companion/migration/foreign owner');
