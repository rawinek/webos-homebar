// shared/stats.js: parsing /proc and the rates between two asks, with fake files and a fake clock.
const assert=require('assert');
const {parseCpu,parseMem,parseNet,Sampler}=require('../shared/stats');
assert.deepStrictEqual(parseCpu('cpu  100 0 50 800 50 0 0 0 0 0\ncpu0 1 1 1 1'),{busy:150,total:1000});
assert.strictEqual(parseCpu('nothing'),null);
assert.deepStrictEqual(parseMem('MemTotal: 2000 kB\nMemFree: 100 kB\nMemAvailable: 900 kB\n'),{total:2000,avail:900});
assert.deepStrictEqual(parseMem('MemTotal: 2000 kB\nMemFree: 100 kB\nBuffers: 200 kB\nCached: 300 kB\n'),{total:2000,avail:600},'no MemAvailable (old kernel)');
assert.strictEqual(parseMem(''),null);
const dev=(rx,tx)=>'Inter-|   Receive\n face |bytes\n  sit0: 9 0 0 0 0 0 0 0 9 0 0 0 0 0 0 0\n    lo: 777 0 0 0 0 0 0 0 777 0 0 0 0 0 0 0\n  p2p0: 5 0 0 0 0 0 0 0 5 0 0 0 0 0 0 0\n wlan0: '+rx+' 1 0 0 0 0 0 0 '+tx+' 1 0 0 0 0 0 0\n  eth0: 10 1 0 0 0 0 0 0 20 1 0 0 0 0 0 0\n';
assert.deepStrictEqual(parseNet(dev(1000,2000)),{rx:1010,tx:2020},'loopback, tunnels and Wi-Fi Direct are left out');
assert.strictEqual(parseNet('garbage'),null);
let t=0,files;
const set=(busy,total,rx,tx,avail)=>{files={'/proc/stat':'cpu  '+busy+' 0 0 '+(total-busy)+' 0 0 0 0\n','/proc/meminfo':'MemTotal: 2048000 kB\nMemAvailable: '+avail+' kB\n','/proc/net/dev':dev(rx,tx)};};
const s=new Sampler(f=>files[f]||'',()=>t);
set(100,1000,0,0,1024000);
let r=s.sample();
assert.strictEqual(r.ok,true);assert.deepStrictEqual(r.mem,{pct:50,usedMb:1000,totalMb:2000});
assert.strictEqual(r.cpu,null,'no rate on the first ask');assert.strictEqual(r.net,null);
t=500;set(110,1100,5000,5000,1024000);
assert.strictEqual(s.sample(),r,'two askers within a second share the answer');
t=2000;set(300,2000,40000,20000,512000);
r=s.sample();
assert.strictEqual(r.cpu,Math.round(100*200/1000),'busy 200 of 1000 jiffies');
assert.strictEqual(r.net.down,(40000-0)/2,'bytes per second over 2 s since the first sample');
assert.strictEqual(r.net.up,10000);
assert.strictEqual(r.mem.pct,75);
t=2000+20000;set(400,3000,50000,30000,512000);
r=s.sample();assert.strictEqual(r.cpu,null,'a pause longer than 15 s starts a new baseline');assert.strictEqual(r.net,null);
t+=2000;set(500,3400,60000,40000,512000);
r=s.sample();assert.strictEqual(r.cpu,25);assert.strictEqual(r.net.down,5000);
// counters that went backwards (a reset) never show a negative rate
t+=2000;set(10,100,10,10,512000);
r=s.sample();assert(r.net.down>=0&&r.net.up>=0);
// nothing readable at all
const none=new Sampler(()=>'',()=>t);t+=5000;assert.strictEqual(none.sample().ok,false);
console.log('PASS stats: /proc parsing, rates between two asks, pause, reset, unreadable');
