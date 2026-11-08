// Free up memory on the overlay: the helper closes the apps running in the
// background one by one (closeByAppId), never the one on screen, Homebar, its
// helpers or LG's own, and no longer calls closeAllApps. The function is taken
// from the helper's source and run against a stand-in luna.
const fs = require('fs'), vm = require('vm'), assert = require('assert'), path = require('path');
const source = fs.readFileSync(path.join(__dirname, '../webos10/helper/service.js'), 'utf8');
const pick = (start, end) => source.slice(source.indexOf(start), source.indexOf(end));
assert(source.indexOf("applicationManager/closeAllApps'") < 0, 'closeAllApps is no longer called');
const calls = [], notes = [];
const replies = {
  'luna://com.webos.applicationManager/running': { returnValue: true, running: [
    { id: 'netflix' }, { id: 'youtube.leanback.v4' }, { id: 'amazon' }, { id: 'org.rawin.launcher' }, { id: 'org.rawin.launcher.service' },
    { id: 'org.webosbrew.hbchannel' }, { id: 'com.webos.app.home' }, { id: 'com.webos.app.hdmi1' }, { id: 'com.webos.app.notificationcenter' }, { id: 'netflix' }] },
  'luna://com.webos.applicationManager/getForegroundAppInfo': { returnValue: true, appId: 'org.rawin.launcher',
    foregroundAppInfo: [{ appId: 'org.rawin.launcher' }, { appId: 'youtube.leanback.v4', windowGroupOwnerId: 'youtube.leanback.v4' }] },
  'luna://com.webos.applicationManager/listLaunchPoints': { returnValue: true, launchPoints: [
    { id: 'netflix' }, { id: 'youtube.leanback.v4' }, { id: 'amazon' }, { id: 'org.rawin.launcher' }, { id: 'org.webosbrew.hbchannel' }, { id: 'com.webos.app.hdmi1' }] }
};
const context = {
  APP: 'org.rawin.launcher', Set, Array, Promise,
  KEEP_APPS: new Set(['org.rawin.launcher', 'org.webosbrew.hbchannel', 'org.webosbrew.inputhook']),
  luna: (uri, params) => { calls.push([uri, params]); return Promise.resolve(uri.endsWith('/closeByAppId') ? { returnValue: params.id !== 'amazon' } : replies[uri]); },
  note: (t) => notes.push(t)
};
vm.runInNewContext(pick('const SYSTEM_IDS', 'const service = new Service') + '\n' + pick('async function closeBackgroundApps', "const BASE = '") + '\nthis.run = closeBackgroundApps;', context);
context.run().then((r) => {
  const closedIds = calls.filter((c) => c[0].endsWith('/closeByAppId')).map((c) => c[1].id);
  assert.strictEqual(closedIds.join(), 'netflix,amazon');
  assert.strictEqual(JSON.stringify(r), JSON.stringify({ returnValue: true, closed: 1, tried: 2 }));
  assert(/closed 1 of 2 \(netflix, amazon\)/.test(notes[0]), notes[0]);
  replies['luna://com.webos.applicationManager/running'] = { returnValue: false, errorText: 'denied' };
  return context.run();
}).then((r) => {
  assert.strictEqual(r.returnValue, false);
  console.log('PASS close background apps: on-screen app, Homebar and LG apps kept, failures counted');
}).catch((e) => { console.error(e); process.exit(1); });
