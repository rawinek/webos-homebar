// The TV's load for the panel's status chip: processor, memory and network,
// read from /proc. Nothing runs between two asks: the rates are the change
// since the previous ask, so the first one (or one after a long pause) has
// memory only. Plain ES5: on webOS 4 this runs on node 0.12.
'use strict';

// "cpu  user nice system idle iowait irq softirq steal ..." → busy and total jiffies.
function parseCpu(text) {
  var m = /^cpu\s+(.*)$/m.exec(text || '');
  if (!m) return null;
  var v = m[1].trim().split(/\s+/).map(Number);
  if (v.length < 4 || v.some(isNaN)) return null;
  var total = 0, i;
  for (i = 0; i < Math.min(v.length, 8); i++) total += v[i];   // user..steal; guest is counted in user
  var idle = v[3] + (v[4] || 0);
  return {busy: total - idle, total: total};
}

// MemTotal and what can be had without swapping (MemAvailable, else free + buffers + cache), in kB.
function parseMem(text) {
  function kb(name) {
    var m = new RegExp('^' + name + ':\\s+(\\d+)', 'm').exec(text || '');
    return m ? Number(m[1]) : null;
  }
  var total = kb('MemTotal');
  if (!total) return null;
  var avail = kb('MemAvailable');
  if (avail === null) avail = (kb('MemFree') || 0) + (kb('Buffers') || 0) + (kb('Cached') || 0);
  return {total: total, avail: Math.min(avail, total)};
}

// Bytes received and sent on the real interfaces: not loopback, tunnels, dummies or Wi-Fi Direct.
var VIRTUAL = /^(lo|sit\d*|ip6tnl\d*|ip6gre\d*|gre\d*|tunl\d*|dummy\d*|p2p\d*|bond\d*)$/;
function parseNet(text) {
  var rx = 0, tx = 0, found = false;
  String(text || '').split('\n').forEach(function (line) {
    var m = /^\s*([^:\s]+):\s*(.*)$/.exec(line);
    if (!m || VIRTUAL.test(m[1])) return;
    var f = m[2].trim().split(/\s+/).map(Number);
    if (f.length < 9 || isNaN(f[0]) || isNaN(f[8])) return;
    rx += f[0]; tx += f[8]; found = true;
  });
  return found ? {rx: rx, tx: tx} : null;
}

// read(path) gives a file's text (or '' when it cannot be read); now() is in ms.
function Sampler(read, now) {
  this.read = read;
  this.now = now || Date.now;
  this.prev = null;
  this.last = null;
  this.lastAt = 0;
}
Sampler.prototype.PAUSE = 15000;    // a baseline older than this is not a rate any more
Sampler.prototype.REUSE = 900;      // two askers at once get the same answer

Sampler.prototype.sample = function () {
  var t = this.now();
  if (this.last && t - this.lastAt < this.REUSE) return this.last;
  var cpu = parseCpu(this.read('/proc/stat')), net = parseNet(this.read('/proc/net/dev')), mem = parseMem(this.read('/proc/meminfo'));
  var out = {ok: !!(cpu || mem || net), cpu: null, mem: null, net: null};
  if (mem) {
    var used = mem.total - mem.avail;
    out.mem = {pct: Math.round(100 * used / mem.total), usedMb: Math.round(used / 1024), totalMb: Math.round(mem.total / 1024)};
  }
  var p = this.prev;
  if (p && t - p.t <= this.PAUSE && t > p.t) {
    var secs = (t - p.t) / 1000;
    if (cpu && p.cpu && cpu.total > p.cpu.total) out.cpu = Math.max(0, Math.min(100, Math.round(100 * (cpu.busy - p.cpu.busy) / (cpu.total - p.cpu.total))));
    if (net && p.net) out.net = {down: Math.max(0, (net.rx - p.net.rx) / secs), up: Math.max(0, (net.tx - p.net.tx) / secs)};
  }
  this.prev = {t: t, cpu: cpu, net: net};
  this.last = out;
  this.lastAt = t;
  return out;
};

module.exports = {parseCpu: parseCpu, parseMem: parseMem, parseNet: parseNet, Sampler: Sampler};
