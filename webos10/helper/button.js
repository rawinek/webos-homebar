// Settings → Remote button: one remote button besides HOME that opens
// Homebar in the overlay modes. The panel asks for a press twice, shows which
// button it was, and the binding is written to Input Hook or Magic Mapper by
// the shared launch module, which never takes over a button that has another
// action. Without either mapper the panel only shows the code it read.
'use strict';
const fsDefault = require('fs');
let Integration;
try { Integration = require('./integration'); } catch (e) { Integration = require('../integration'); }

// The presses come straight from the kernel's input devices: the code Input
// Hook and Magic Mapper go by, whichever of them runs. The devices are opened
// non-blocking and read every few milliseconds while the panel waits: a
// blocking read would hold one of node's few worker threads until the next
// key, and a separate reader process took seconds to start and to end.
// struct input_event is 16 bytes for a 32-bit node (webOS ships one even with
// a 64-bit kernel, which then hands it the 32-bit layout), 24 for a 64-bit one.
const SIZE = process.arch === 'arm' || process.arch === 'ia32' ? 16 : 24;
const EV_KEY = 1;
class KeyReader {
  constructor(options = {}) {
    this.fs = options.fs || fsDefault;
    this.dir = options.dir || '/dev/input';
    this.pollMs = options.pollMs || 30;
    // The devices stay open between the two presses (and a little after), so
    // a quick second press is not lost while the panel asks for it.
    this.idleMs = options.idleMs || 15000;
    // Magic Mapper holding the remote passes a button on through its own
    // device: the same press can arrive twice, a few milliseconds apart.
    this.echoMs = options.echoMs || 150;
    this.fds = []; this.queue = []; this.waiter = null; this.timer = null; this.idle = null;
    this.last = { code: 0, at: 0 };
    this.chunk = Buffer.alloc(SIZE * 64);
  }
  open() {
    if (this.timer) return;
    let names = [];
    try { names = this.fs.readdirSync(this.dir).filter((n) => /^event\d+$/.test(n)); } catch (e) {}
    const flags = this.fs.constants.O_RDONLY | this.fs.constants.O_NONBLOCK;
    names.forEach((n) => { try { this.fds.push(this.fs.openSync(this.dir + '/' + n, flags)); } catch (e) {} });
    this.timer = setInterval(() => this.poll(), this.pollMs);
  }
  close() {
    clearInterval(this.timer); clearTimeout(this.idle);
    this.timer = null; this.idle = null;
    this.fds.forEach((fd) => { try { this.fs.closeSync(fd); } catch (e) {} });
    this.fds = []; this.queue = [];
  }
  poll() {
    this.fds = this.fds.filter((fd) => {
      for (;;) {
        let n;
        try { n = this.fs.readSync(fd, this.chunk, 0, this.chunk.length, null); }
        catch (e) {
          if (e.code === 'EAGAIN' || e.code === 'EWOULDBLOCK') return true;
          try { this.fs.closeSync(fd); } catch (ignore) {}
          return false;   // the device went away (a remote disconnected)
        }
        if (!n) return true;
        for (let at = 0; at + SIZE <= n; at += SIZE) {
          // A press is value 1; a held button repeats with 2 and lets go with 0.
          if (this.chunk.readUInt16LE(at + SIZE - 8) === EV_KEY && this.chunk.readInt32LE(at + SIZE - 4) === 1)
            this.press(this.chunk.readUInt16LE(at + SIZE - 6));
        }
        if (n < this.chunk.length) return true;
      }
    });
  }
  press(code) {
    const now = Date.now();
    if (code === this.last.code && now - this.last.at < this.echoMs) return;
    this.last = { code: code, at: now };
    if (this.waiter) this.waiter(code); else this.queue.push(code);
  }
  // The next press, or 0 after ms. fresh: only presses from now on count (the
  // first of the two); otherwise one made since the last answer is taken. A
  // newer request answers the one before with 0.
  next(ms, fresh, done) {
    this.open();
    clearTimeout(this.idle);
    if (this.waiter) this.waiter(0);
    if (fresh) this.queue = [];
    if (this.queue.length) return this.answer(done, this.queue.shift());
    const timeout = setTimeout(() => finish(0), ms);
    const finish = (code) => { clearTimeout(timeout); this.waiter = null; this.answer(done, code); };
    this.waiter = finish;
  }
  answer(done, code) {
    clearTimeout(this.idle);
    this.idle = setTimeout(() => { if (!this.waiter) this.close(); }, this.idleMs);
    done(code);
  }
}

// Long enough to find the remote; the panel says how long it waits.
const CAPTURE_MS = 10000;
class RemoteButton {
  constructor(options = {}) {
    this.integration = options.integration || new Integration();
    this.reader = options.reader || new KeyReader();
  }
  status() {
    const s = this.integration.buttons();
    s.bound.forEach((b) => { b.name = b.name || this.integration.buttonName(b.code); });
    return Object.assign({ ok: true }, s);
  }
  capture(fresh, done) {
    this.reader.next(CAPTURE_MS, fresh, (code) => done({ ok: true, code: code, name: code ? this.integration.buttonName(code) : '' }));
  }
  bind(code) { return this.run(() => this.integration.bindButton(code)); }
  unbind() { return this.run(() => this.integration.unbindButton()); }
  run(change) {
    try { change(); return this.status(); } catch (e) { return { ok: false, error: e.code || 'launch_failed' }; }
  }
}
RemoteButton.KeyReader = KeyReader;
RemoteButton.SIZE = SIZE;
module.exports = RemoteButton;
