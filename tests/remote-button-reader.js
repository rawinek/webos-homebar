// Settings → Remote button: the helper's key reader on a made-up /dev/input,
// with non-blocking devices that answer EAGAIN when they have nothing.
'use strict';
const assert = require('assert');
const RemoteButton = require('../webos10/helper/button');
const SIZE = RemoteButton.SIZE;
function event(type, code, value) {
  const b = Buffer.alloc(SIZE);
  b.writeUInt16LE(type, SIZE - 8); b.writeUInt16LE(code, SIZE - 6); b.writeInt32LE(value, SIZE - 4);
  return b;
}
function fakeFs() {
  const devices = { event0: [], event1: [], event5: null }, open = new Map();
  let nextFd = 10, closed = 0;
  return {
    constants: { O_RDONLY: 0, O_NONBLOCK: 2048 },
    readdirSync: () => ['event0', 'event1', 'event5', 'js0', 'mice'],
    openSync(p, flags) {
      assert.strictEqual(flags & 2048, 2048, 'opened non-blocking');
      const name = p.split('/').pop();
      if (devices[name] === null) { const e = new Error('ENXIO'); e.code = 'ENXIO'; throw e; }
      const fd = nextFd++; open.set(fd, name); return fd;
    },
    readSync(fd, buf) {
      const q = devices[open.get(fd)];
      if (!q.length) { const e = new Error('EAGAIN'); e.code = 'EAGAIN'; throw e; }
      const data = q.shift(); data.copy(buf); return data.length;
    },
    closeSync(fd) { open.delete(fd); closed++; },
    push(name, ...events) { devices[name].push(Buffer.concat(events)); },
    openCount: () => open.size, closed: () => closed
  };
}
function nextCode(reader, ms, fresh) { return new Promise((resolve) => reader.next(ms, fresh, resolve)); }
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
(async () => {
  const fs = fakeFs();
  const reader = new RemoteButton.KeyReader({ fs, pollMs: 5, idleMs: 120, echoMs: 50 });
  // A press right after the request is seen; release, repeat and other events are not presses.
  let p = nextCode(reader, 500, true);
  assert.strictEqual(fs.openCount(), 2, 'the devices that exist are open');
  fs.push('event0', event(4, 4, 7), event(1, 399, 1), event(0, 0, 0), event(1, 399, 2), event(1, 399, 0));
  assert.strictEqual(await p, 399);
  // The same press passed on by Magic Mapper through its own device is one press.
  fs.push('event1', event(1, 399, 1));
  // The second press made before the panel asks again is kept for it.
  await wait(80);
  fs.push('event0', event(1, 401, 1));
  await wait(20);
  assert.strictEqual(await nextCode(reader, 500, false), 401, 'second press not lost, echo dropped');
  // A fresh request forgets presses from before it.
  fs.push('event0', event(1, 402, 1));
  await wait(20);
  p = nextCode(reader, 500, true);
  await wait(20);
  fs.push('event0', event(1, 403, 1));
  assert.strictEqual(await p, 403, 'fresh skips earlier presses');
  // Nothing within the time: 0. A newer request answers the older one with 0.
  assert.strictEqual(await nextCode(reader, 40, false), 0);
  const older = nextCode(reader, 500, false), newer = nextCode(reader, 500, false);
  assert.strictEqual(await older, 0, 'superseded');
  fs.push('event1', event(1, 404, 1));
  assert.strictEqual(await newer, 404);
  // Idle after the last answer: the devices are closed again.
  await wait(200);
  assert.strictEqual(fs.openCount(), 0, 'closed when idle');
  assert(fs.closed() >= 2);
  console.log('PASS remote button reader: non-blocking devices, presses only, echo dropped, quick second press kept, fresh, timeout, superseded, idle close');
})().catch((e) => { console.error(e); process.exit(1); });
