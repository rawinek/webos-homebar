// rawin-launcher helper for the overlay variant (webOS 10, and other webOS
// versions tried with it). Elevated with Homebrew's elevate-service, it makes
// the calls a developer app is denied (app inventory, inputs, what is on
// screen, launching) and serves them over HTTP on 127.0.0.1, because
// WebOSServices.Service gives a developer QML app no answers on webOS 10.
// Icons are copied once into the app's cache/ folder and served from there.
// Written for node 8 and later (webOS 5 and later ship it; webOS 3 and 4 have
// node 0.12, which is why they get the Home panel instead): no URL class, no
// recursive mkdir, no optional chaining.
const Service = require('webos-service');
const { execFile } = require('child_process');
const fs = require('fs');
const http = require('http');
const path = require('path');
const urlModule = require('url');
const { AfterExit, cardOf } = require('./after-exit');
const { Preloader, panelRunning, foregroundSafe } = require('./preload');
const setup = require('./setup');
// One copy of the request guard, shared/guard.js: tools/build.py puts it next to
// this file in the package, in the source tree it is two folders up.
let guard;
try { guard = require('./guard'); } catch (e) { guard = require('../../shared/guard'); }
const ModeControl = require('./mode');
const modeControl = new ModeControl(fs, execFile, () => preloader.pause(0));
const RemoteButton = require('./button');
const remoteButton = new RemoteButton();
let restarting = false, updateBusy = false;
function installingUpdate() {
  try { return fs.readFileSync('/tmp/rawin-launcher-update/state', 'utf8').trim() === 'running'; } catch (e) { return false; }
}

const APP = 'org.rawin.launcher';
const APP_DIR = '/media/developer/apps/usr/palm/applications/' + APP;
const CACHE = APP_DIR + '/cache';
const NATIVE_HOME = '/var/lib/webosbrew/rawin-launcher-home/native-home';
function nativeHome() { return fs.existsSync(NATIVE_HOME); }
function nativeHomeMounted() {
  if (!nativeHome()) return false;
  try {
    const home = fs.statSync('/usr/palm/applications/com.webos.app.home');
    const stage = fs.statSync('/var/lib/webosbrew/rawin-launcher-home/native-app');
    return home.ino === stage.ino && home.dev === stage.dev && !modeControl.foreignHome();
  } catch (e) { return false; }
}
function panelId() { return nativeHomeMounted() ? 'com.webos.app.home' : APP; }
const ICON_ROOTS = ['/usr/palm/', '/media/cryptofs/apps/', '/media/developer/apps/', '/mnt/lg/'];
const HTTP_PORT = 8899;
// What the panel may open besides the apps it listed: the inputs, LG's Home
// and the System page's tiles (LG's settings app is not a launch point, so it
// is never in the list), and Live TV, which some TVs leave out of the list too.
const SYSTEM_IDS = /^(com\.webos\.app\.(livetv|hdmi\d|dp\d|usbc\d|home|discovery)|com\.palm\.app\.settings|org\.webosbrew\.(hbchannel|piccap))$/;

const service = new Service(APP + '.service');

function luna(uri, params) {
  return new Promise((resolve) => service.call(uri, params, (m) => resolve(m.payload || {})));
}

// Returns the icon path relative to the app (cache/<name>), copying it when new or changed.
function cachedIcon(id, file) {
  if (!file) return '';
  const real = path.resolve(file);
  const ext = path.extname(real).toLowerCase();
  if (!ICON_ROOTS.some((root) => real.startsWith(root)) || !['.png', '.jpg', '.jpeg'].includes(ext)) return '';
  const name = id.replace(/[^A-Za-z0-9._-]/g, '_') + ext;
  const target = path.join(CACHE, name);
  try {
    const src = fs.statSync(real);
    let fresh = false;
    try { const dst = fs.statSync(target); fresh = dst.size === src.size && dst.mtimeMs >= src.mtimeMs; } catch (e) {}
    if (!fresh) {
      try { fs.mkdirSync(CACHE); } catch (e) { if (e.code !== 'EEXIST') throw e; }
      fs.writeFileSync(target, fs.readFileSync(real));
      fs.chmodSync(target, 0o644);
    }
    return 'cache/' + name;
  } catch (e) {
    return '';
  }
}

async function inventory() {
  const r = await luna('luna://com.webos.applicationManager/listLaunchPoints', {});
  if (!r.launchPoints) return { returnValue: false, errorText: r.errorText || 'listLaunchPoints failed' };
  const seen = new Set();
  const apps = [];
  for (const p of r.launchPoints) {
    if (seen.has(p.id)) continue;
    seen.add(p.id);
    apps.push({ id: p.id, title: p.title || p.id, icon: cachedIcon(p.id, p.largeIcon || p.icon) });
  }
  return { returnValue: true, apps };
}

const BASE = '/var/lib/webosbrew/rawin-launcher-home';
const UPDATER = BASE + '/update.sh';
// Favourites and settings, as the panel sends them (Launcher settings → Back up).
const BACKUP = BASE + '/backup.json';

// A request's body, up to 64 KB.
function readBody(req) {
  return new Promise((resolve) => {
    const chunks = [];
    let size = 0;
    req.on('data', (c) => { size += c.length; if (size <= 65536) chunks.push(c); });
    req.on('end', () => resolve(size <= 65536 ? Buffer.concat(chunks).toString('utf8') : ''));
    req.on('error', () => resolve(''));
  });
}

// One step of update.sh; its last line of output is the JSON answer.
function updateStep(step, channel) {
  return new Promise((resolve) => {
    execFile('sh', [UPDATER, step, channel], { timeout: 180000 }, (err, stdout) => {
      const line = String(stdout || '').trim().split('\n').pop();
      try { resolve(JSON.parse(line)); } catch (e) { resolve({ ok: false, error: err ? err.message : 'no answer' }); }
    });
  });
}

// Started by the boot hook (or any Luna call); answers immediately.
service.register('ping', (message) => message.respond({ returnValue: true, http: HTTP_PORT, pid: process.pid }));

// --- HTTP on 127.0.0.1 for the panel ---------------------------------

let known = new Set();

function send(res, code, body, type) {
  const data = typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body);
  res.writeHead(code, { 'Content-Type': type || 'application/json', 'Cache-Control': 'no-store' });
  res.end(data);
}

// What changes something on the TV (or on its disk): only the panel asks for
// these, with the X-Homebar header. status, check-free reads stay plain.
function changesState(url, req) {
  const p = url.pathname;
  if (['/launch', '/close-apps', '/exit-target', '/restart', '/backup'].includes(p)) return true;
  if (p === '/update') return String((url.query || {}).step || '') !== 'status';
  if (p === '/mode' || p === '/button') return req.method !== 'GET';
  return false;
}

const server = http.createServer(async (req, res) => {
  const url = urlModule.parse(req.url || '/', true);
  const query = url.query || {};
  try {
    if (!guard.hostOk(req, HTTP_PORT)) return send(res, 403, { returnValue: false, errorText: 'host' });
    if (changesState(url, req) && !guard.marked(req)) return send(res, 403, { returnValue: false, errorText: 'header' });
    if (url.pathname === '/ping') {
      return send(res, 200, { ok: true, pid: process.pid, rss: process.memoryUsage().rss, node: process.versions.node });
    }
    if (url.pathname === '/apps') {
      const inv = await inventory();
      if (inv.apps) known = new Set(inv.apps.map((a) => a.id));
      return send(res, inv.returnValue ? 200 : 502, inv);
    }
    if (url.pathname === '/inputs') {
      return send(res, 200, await luna('luna://com.webos.service.eim/getAllInputStatus', {}));
    }
    // Whether LG's Home is still the real one (installed with --keep-lg-home, or
    // the stand-in is not mounted): then the panel offers "Original Home".
    if (url.pathname === '/home') {
      // Same test as takeover.sh: the Home folder is the staged stand-in.
      let mounted = false;
      try {
        const home = fs.statSync('/usr/palm/applications/com.webos.app.home');
        const stage = fs.statSync('/var/lib/webosbrew/rawin-launcher-home/' + (nativeHome() ? 'native-app' : 'app'));
        mounted = home.ino === stage.ino && home.dev === stage.dev;
      } catch (e) {}
      return send(res, 200, { returnValue: true, lgHome: !mounted, nativeHome: nativeHomeMounted(), configuredNativeHome: nativeHome() });
    }
    if (url.pathname === '/foreground') {
      return send(res, 200, await luna('luna://com.webos.applicationManager/getForegroundAppInfo', { extraInfo: true }));
    }
    if (url.pathname === '/launch') {
      // Only launch points we listed, plus the inputs and LG's own Home.
      const id = String(query.id || '');
      if (!known.size) { const inv = await inventory(); if (inv.apps) known = new Set(inv.apps.map((a) => a.id)); }
      if (!known.has(id) && !SYSTEM_IDS.test(id)) return send(res, 403, { returnValue: false, errorText: 'unknown id' });
      if (id === 'com.webos.app.home') returner.noteHomeRequest();
      // Launch parameters (the Settings page to open) as JSON, up to 2 KB.
      const params = {};
      if (query.params) {
        try {
          const given = JSON.parse(String(query.params));
          if (given && typeof given === 'object') for (const k in given) if (Object.prototype.hasOwnProperty.call(given, k)) params[k] = given[k];
        } catch (e) { return send(res, 400, { returnValue: false, errorText: 'params must be JSON' }); }
      }
      return send(res, 200, await luna('luna://com.webos.applicationManager/launch', { id, params }));
    }
    if (url.pathname === '/close-apps') {
      // LG also closes our overlay; the watchdog preloads it again afterward.
      return send(res, 200, await luna('luna://com.webos.applicationManager/closeAllApps', {}));
    }
    if (url.pathname === '/mode') {
      if (req.method === 'GET') return send(res, 200, modeControl.status());
      if (req.method !== 'POST') return send(res, 405, { ok: false, error: 'method' });
      if (!/^application\/json(?:\s*;|$)/i.test(String((req.headers || {})['content-type'] || '')))
        return send(res, 415, { ok: false, error: 'launch_confirm' });
      let body;
      try { body = JSON.parse(await readBody(req)); } catch (e) {}
      if (restarting || updateBusy || installingUpdate()) return send(res, 409, { ok: false, error: 'busy' });
      // Finish the response before the shell stops the QML host. The mode
      // journal survives both that host and a helper/system restart.
      if (!body || typeof body.fingerprint !== 'string' || !/^[a-f0-9]{64}$/.test(body.fingerprint))
        return send(res, 409, { ok: false, error: 'launch_confirm' });
      let replied = false;
      const result = modeControl.start(body && body.mode, () => {
        preloader.pause(150000);
        send(res, 200, { ok: true, pending: true }); replied = true;
      }, body.fingerprint);
      if (!replied) send(res, result.ok ? 200 : 409, result);
      return;
    }
    // Settings → Remote button (overlay modes): a press read for the panel, then
    // the binding written to the mapper, or taken out again.
    if (url.pathname === '/button') {
      if (req.method === 'GET') return send(res, 200, remoteButton.status());
      if (req.method !== 'POST') return send(res, 405, { ok: false, error: 'method' });
      let body = null;
      try { body = JSON.parse(await readBody(req)); } catch (e) {}
      const step = body && body.step;
      if (step !== 'unbind' && nativeHome()) return send(res, 409, { ok: false, error: 'button_native' });
      if (modeControl.isBusy()) return send(res, 409, { ok: false, error: 'busy' });
      if (step === 'capture') return remoteButton.capture(body.fresh === true, (r) => send(res, 200, r));
      if (step === 'bind') { const r = remoteButton.bind(body.code); return send(res, r.ok ? 200 : 409, r); }
      if (step === 'unbind') { const r = remoteButton.unbind(); return send(res, r.ok ? 200 : 409, r); }
      return send(res, 400, { ok: false, error: 'step' });
    }
    if (url.pathname === '/restart' && req.method === 'POST') {
      if (modeControl.isBusy() || restarting || updateBusy || installingUpdate()) return send(res, 409, { ok: false, error: 'busy' });
      // Reply first: closing the overlay tears down the QML request that asked
      // for it. The helper is a separate resident service, so it can launch a
      // clean process once applicationManager has removed the old one.
      send(res, 200, { ok: true });
      restarting = true;
      preloader.pause(15000);   // this closes and starts the app itself
      setTimeout(() => {
        const id = panelId();
        const launch = () => setTimeout(() => {
          luna('luna://com.webos.applicationManager/launch', { id: id, params: { restart: true }, keepAlive: true });
          restarting = false;
        }, 400);
        if (nativeHomeMounted()) {
          execFile('/bin/sh', ['/var/lib/webosbrew/rawin-launcher-home/native-home.sh', 'stop'], (err) => {
            if (err) { restarting = false; note('native Home restart failed: ' + err.message); }
            else launch();
          });
        } else {
          luna('luna://com.webos.applicationManager/closeByAppId', { id: id });
          launch();
        }
      }, 50);
      return;
    }
    if (url.pathname === '/state') {
      return send(res, 200, { lastInput: returner.lastInput, target: returner.target, card: returner.card,
                             subscribed: subscribed, preload: nativeHome() ? { mode: 'system Home', running: nativeHomeMounted() && panelRunning(fs, '/usr/palm/applications/com.webos.app.home') } : preloader.state(), nativeHome: nativeHome(), events: events });
    }
    // The TV's UI language ("pl-PL"), for the launcher's "system language".
    if (url.pathname === '/locale') {
      const r = await luna('luna://com.webos.settingsservice/getSystemSettings', { keys: ['localeInfo'] });
      const info = r.settings && r.settings.localeInfo;
      return send(res, 200, { returnValue: true, locale: (info && info.locales && info.locales.UI) || '' });
    }
    // Where to go after an app exits or LG Home shows up: "last" or an input.
    if (url.pathname === '/exit-target') {
      const id = String(query.id || 'last');
      returner.setTarget(id);
      const saved = returner.none ? 'none' : returner.target || 'last';
      saveSettings({ exitTo: saved });
      return send(res, 200, { returnValue: true, exitTo: saved });
    }
    // Updates: update.sh next to the installed launcher (check, download, install, status).
    if (url.pathname === '/update') {
      if (modeControl.isBusy() || restarting || updateBusy) return send(res, 409, { ok: false, error: 'busy' });
      const step = String(query.step || '');
      if (!['check', 'download', 'install', 'status'].includes(step)) return send(res, 400, { ok: false, error: 'unknown step' });
      if (step !== 'status' && installingUpdate()) return send(res, 409, { ok: false, error: 'busy' });
      const channel = query.channel === 'test' ? 'test' : 'stable';
      updateBusy = true;
      try { return send(res, 200, await updateStep(step, channel)); }
      finally { updateBusy = false; }
    }
    // The backup file: written from the panel, read back for info and restore.
    if (url.pathname === '/backup' && req.method === 'POST') {
      let data = null;
      try { data = JSON.parse(await readBody(req)); } catch (e) {}
      if (!data || typeof data !== 'object' || !data.saved) return send(res, 400, { ok: false, error: 'not a backup' });
      fs.writeFileSync(BACKUP, JSON.stringify(data));
      return send(res, 200, { ok: true });
    }
    if (url.pathname === '/restore') {
      let text = 'null';
      try { text = fs.readFileSync(BACKUP, 'utf8'); } catch (e) {}
      return send(res, 200, text);
    }
    if (url.pathname.startsWith('/cache/')) {
      const name = path.basename(url.pathname);
      return send(res, 200, fs.readFileSync(path.join(CACHE, name)), name.endsWith('.png') ? 'image/png' : 'image/jpeg');
    }
    send(res, 404, { returnValue: false, errorText: 'not found' });
  } catch (e) {
    send(res, 500, { returnValue: false, errorText: String(e) });
  }
});
server.on('error', (e) => console.error('rawin-launcher http: ' + e.message));
server.listen(HTTP_PORT, '127.0.0.1');

// The weather and the page to choose its place on a phone (shared/setup.js).
setup.start(BASE);

// --- After an app exits, or LG Home shows up: back to the last input --------

const LAST_INPUT_FILE = '/var/lib/webosbrew/rawin-launcher-last-input';
const SETTINGS_FILE = '/var/lib/webosbrew/rawin-launcher-settings.json';
function readSettings() {
  try { return JSON.parse(fs.readFileSync(SETTINGS_FILE, 'utf8')); } catch (e) { return {}; }
}
function saveSettings(change) {
  try { fs.writeFileSync(SETTINGS_FILE, JSON.stringify(Object.assign(readSettings(), change))); } catch (e) {}
}
const events = [];
function note(text) {
  events.push(new Date().toISOString().slice(11, 23) + ' ' + text);
  if (events.length > 30) events.shift();
}
let savedInput = '';
try { savedInput = fs.readFileSync(LAST_INPUT_FILE, 'utf8').trim(); } catch (e) {}
// Glasshouse's Home in LG Home's place (the same test as takeover.sh): then
// Home is its, and the helper does not take the TV away from it.
function glasshouseHome() {
  try { return /"enabled"\s*:\s*true/.test(fs.readFileSync('/var/lib/tvweb/home.json', 'utf8')); } catch (e) { return false; }
}
const returner = new AfterExit({
  lastInput: savedInput,
  nativeHome: () => nativeHomeMounted(),
  homeTaken: () => (nativeHome() && !nativeHomeMounted()) || fs.existsSync(BASE + '/additional-overlay') || modeControl.isBusy() || modeControl.foreignHome() || glasshouseHome(),
  target: readSettings().exitTo,
  save: (id) => { try { fs.writeFileSync(LAST_INPUT_FILE, id); } catch (e) {} },
  launch: (id) => luna('luna://com.webos.applicationManager/launch', { id }).then((r) => note('launch ' + id + ': ' + r.returnValue)),
  log: note
});

let subscribed = false;
// What is in front, as preload.js sees it: 'free' (nothing, the panel, LG's
// Home or an input), 'app' (an app, where only a quiet start is allowed) or
// 'unknown' before the first answer.
let frontState = 'unknown';
function onForeground(payload) {
  if (!payload || !payload.foregroundAppInfo) return;
  const card = cardOf(payload);
  if (card !== returner.card) note('card ' + (card || 'empty'));
  returner.onForeground(card);
  const ids = (payload.foregroundAppInfo || []).map((a) => a.appId || '');
  const state = ids.length && !foregroundSafe(ids) ? 'app' : 'free';
  if (state === frontState) return;
  frontState = state;
  // Let after-exit's switch to an input happen first (and an app's own launch
  // take its first frame; ours is a hidden, quiet start), then look for the
  // panel. The wait is small on purpose: every app launch closes the panel,
  // and a HOME pressed just after wants it back.
  clearTimeout(preloadSoon);
  preloadSoon = setTimeout(() => { if (!nativeHome()) preloader.tick(frontState).catch(() => {}); },
                           state === 'app' ? 2500 : 3000);
}
let preloadSoon = null;
// The panel is started hidden at boot and kept across HOMEs; if the system
// closed it, this brings it back within a minute so the next HOME is a show.
const preloader = new Preloader({
  isRunning: () => panelRunning(fs),
  // keepAlive asks the app manager to keep the panel while other apps run;
  // a webOS that does not know the flag is launched the plain way instead.
  // quiet starts it with no window at all, for a start while an app is in
  // front (the panel maps its window for a moment otherwise, to take the
  // app manager's spinner down).
  launch: async (quiet) => {
    const params = quiet ? { preload: true, quiet: true } : { preload: true };
    const r = await luna('luna://com.webos.applicationManager/launch',
                         { id: APP, params: params, keepAlive: true, noSplash: true, spinner: false });
    if (r && r.returnValue) return r;
    return luna('luna://com.webos.applicationManager/launch', { id: APP, params: params });
  },
  log: note
});
setInterval(() => { if (!nativeHome()) preloader.tick(frontState).catch(() => {}); }, 10000);
try {
  const sub = service.subscribe('luna://com.webos.applicationManager/getForegroundAppInfo', { extraInfo: true, subscribe: true });
  sub.on('response', (m) => { subscribed = true; onForeground(m.payload); });
} catch (e) {
  note('subscribe failed: ' + e.message);
}
// Fallback only if the subscription never answered: poll once a second.
setInterval(() => {
  if (subscribed) return;
  luna('luna://com.webos.applicationManager/getForegroundAppInfo', { extraInfo: true }).then(onForeground);
}, 1000);

// Stay resident while the HTTP server is needed: an open activity keeps
// webos-service from exiting on idle.
try {
  service.activityManager.create('rawin-launcher-http', () => {});
} catch (e) {
  console.error('rawin-launcher keepalive: ' + e.message);
}
