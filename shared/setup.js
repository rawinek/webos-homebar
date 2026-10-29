// Homebar's setup server, on port 8898 in both variants: the overlay's helper
// starts it, and on webOS 4 the boot hook runs it on its own (node setup.js
// <folder>). It does three things:
//   - the weather for the panel's status chip, from Open-Meteo, for the place
//     chosen on a phone or else the one the TV's internet address points to
//     (ip-api.com), both without an account or a key;
//   - the page a phone opens to choose that place (setup.html), which looks
//     the place up with Open-Meteo's geocoding itself;
//   - the address of that page as a QR code, which the panel draws.
// The panel asks on 127.0.0.1 alone (/info, /weather, /stats: the load of the
// TV for the status chip, stats.js; /panel-log). The page and its
// calls (/place) answer anyone on the network who has the token from the
// code, which is new each time the server starts. Only the place is kept, in
// weather.json in the folder given. Plain ES5 over plain HTTP: on webOS 4 this
// runs on node 0.12, whose TLS is too old for most of the web.
'use strict';
var fs = require('fs');
var http = require('http');
var os = require('os');
var path = require('path');
var crypto = require('crypto');
var urlModule = require('url');
var qr = require('./qr');
var guard = require('./guard');
var stats = require('./stats');

var PORT = 8898;
var WEATHER_TTL = 15 * 60 * 1000;
var AUTO_TTL = 6 * 3600 * 1000;
var PANEL_LOG = '/tmp/rawin-launcher-panel.log';

function start(base) {
  var placeFile = path.join(base, 'weather.json');
  var page = fs.readFileSync(path.join(__dirname, 'setup.html'));
  var token = crypto.randomBytes(6).toString('hex');
  var rev = 0;
  var auto = null, autoAt = 0, autoWaiting = null;
  var cache = {};
  var sampler = new stats.Sampler(function (file) { try { return fs.readFileSync(file, 'utf8'); } catch (e) { return ''; } });

  function getJSON(url, done) {
    var finished = false;
    function finish(err, value) { if (!finished) { finished = true; done(err, value); } }
    var req = http.get(url, function (res) {
      var chunks = [];
      res.on('data', function (c) { chunks.push(c); });
      res.on('end', function () {
        if (res.statusCode !== 200) return finish(new Error('HTTP ' + res.statusCode));
        try { finish(null, JSON.parse(Buffer.concat(chunks).toString('utf8'))); } catch (e) { finish(e); }
      });
    });
    req.on('error', function (e) { finish(e); });
    req.setTimeout(8000, function () { req.abort(); finish(new Error('timeout')); });
  }

  function savedPlace() {
    try {
      var p = JSON.parse(fs.readFileSync(placeFile, 'utf8'));
      if (p && validPlace(p)) return {name: p.name, lat: p.lat, lon: p.lon, auto: false};
    } catch (e) {}
    return null;
  }
  function validPlace(p) {
    return typeof p.name === 'string' && p.name.length > 0 && p.name.length <= 80 &&
      typeof p.lat === 'number' && p.lat >= -90 && p.lat <= 90 &&
      typeof p.lon === 'number' && p.lon >= -180 && p.lon <= 180;
  }
  // Where the TV's internet address points to, asked again after six hours;
  // calls made while one is on the way wait for it.
  function autoPlace(done) {
    if (auto && Date.now() - autoAt < AUTO_TTL) return done(auto);
    if (autoWaiting) return autoWaiting.push(done);
    autoWaiting = [done];
    getJSON('http://ip-api.com/json/?fields=status,city,lat,lon', function (err, r) {
      if (!err && r && r.status === 'success' && typeof r.lat === 'number') {
        auto = {name: String(r.city || ''), lat: r.lat, lon: r.lon, auto: true};
        autoAt = Date.now();
      }
      var waiting = autoWaiting;
      autoWaiting = null;
      waiting.forEach(function (f) { f(auto); });
    });
  }
  function currentPlace(done) {
    var p = savedPlace();
    if (p) return done(p);
    autoPlace(done);
  }
  // The weather now, kept for a quarter of an hour per place and unit.
  function weather(units, done) {
    currentPlace(function (place) {
      if (!place) return done({ok: false, error: 'no place'});
      var key = place.lat + ',' + place.lon + ',' + units, hit = cache[key];
      if (hit && Date.now() - hit.at < WEATHER_TTL) return done(hit.value);
      getJSON('http://api.open-meteo.com/v1/forecast?latitude=' + place.lat + '&longitude=' + place.lon +
        '&current=temperature_2m,apparent_temperature,weather_code,is_day&timezone=auto' + (units === 'f' ? '&temperature_unit=fahrenheit' : ''),
      function (err, r) {
        var c = r && r.current;
        if (err || !c || typeof c.temperature_2m !== 'number') {
          // The last answer for that place, if any, rather than nothing.
          return done(hit ? hit.value : {ok: false, error: err ? err.message : 'no answer'});
        }
        // apparent_temperature is Open-Meteo's feels-like temperature. Keep
        // both values in one cached reply: changing the panel preference then
        // needs no additional network request.
        var value = {ok: true, temp: Math.round(c.temperature_2m), apparent: typeof c.apparent_temperature === 'number' ? Math.round(c.apparent_temperature) : null,
          code: c.weather_code, day: c.is_day === 1, units: units, place: place.name};
        cache[key] = {at: Date.now(), value: value};
        done(value);
      });
    });
  }

  // The TV's address on the home network: wired, then wireless, then any.
  function lanAddress() {
    var all = os.networkInterfaces(), names = Object.keys(all), found = '';
    names.sort(function (a, b) { return rank(a) - rank(b); });
    function rank(n) { return /^eth/.test(n) ? 0 : /^(wlan|wl)/.test(n) ? 1 : 2; }
    names.some(function (n) {
      return (all[n] || []).some(function (a) {
        if (a.family === 'IPv4' && !a.internal && !/^169\.254\./.test(a.address)) { found = a.address; return true; }
        return false;
      });
    });
    return found;
  }

  function send(res, code, body, type) {
    var data = typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body);
    res.writeHead(code, {'Content-Type': type || 'application/json; charset=utf-8', 'Cache-Control': 'no-store'});
    res.end(data);
  }
  function readBody(req, done) {
    var chunks = [], size = 0;
    req.on('data', function (c) { size += c.length; if (size <= 4096) chunks.push(c); });
    req.on('end', function () { done(size <= 4096 ? Buffer.concat(chunks).toString('utf8') : ''); });
    req.on('error', function () { done(''); });
  }
  function isLocal(req) {
    var a = req.connection && req.connection.remoteAddress;
    return a === '127.0.0.1' || a === '::ffff:127.0.0.1' || a === '::1';
  }
  // What the Home panel went through (loading, focus, keys), sent by the
  // patched LG Home on a webOS it was not tested on: nothing else records it
  // there. diagnose.sh prints the file; it is cut back to the newer half at
  // 64 KB and is gone after a reboot.
  function panelLog(text) {
    var line = new Date().toISOString() + ' ' + String(text).replace(/[\r\n]+/g, ' ').slice(0, 1000) + '\n';
    try {
      if (fs.statSync(PANEL_LOG).size > 65536) {
        var old = fs.readFileSync(PANEL_LOG, 'utf8');
        fs.writeFileSync(PANEL_LOG, old.slice(old.indexOf('\n', old.length / 2) + 1));
      }
    } catch (e) {}
    try { fs.appendFileSync(PANEL_LOG, line); } catch (e) {}
  }
  function placeInfo(p) { return p ? {name: p.name, auto: !!p.auto} : null; }

  var server = http.createServer(function (req, res) {
    var url = urlModule.parse(req.url || '/', true), query = url.query || {};
    try {
      if (url.pathname === '/info' && isLocal(req) && guard.hostOk(req, PORT)) {
        var ip = lanAddress(), link = ip ? 'http://' + ip + ':' + PORT + '/?t=' + token : '';
        return currentPlace(function (p) {
          send(res, 200, {ok: true, url: link, qr: link ? qr.encode(link) : null, place: placeInfo(p), rev: rev});
        });
      }
      if (url.pathname === '/stats' && isLocal(req) && guard.hostOk(req, PORT)) {
        return send(res, 200, sampler.sample());
      }
      if (url.pathname === '/weather' && isLocal(req) && guard.hostOk(req, PORT)) {
        return weather(query.units === 'f' ? 'f' : 'c', function (w) { send(res, 200, w); });
      }
      if (url.pathname === '/panel-log' && req.method === 'POST' && isLocal(req) && guard.hostOk(req, PORT)) {
        return readBody(req, function (text) { panelLog(text); send(res, 200, {ok: true}); });
      }
      if (url.pathname === '/' && req.method === 'GET') return send(res, 200, page, 'text/html; charset=utf-8');
      if (url.pathname === '/place') {
        if (query.t !== token) return send(res, 403, {ok: false, error: 'expired'});
        if (req.method !== 'POST') return currentPlace(function (p) { send(res, 200, {ok: true, place: placeInfo(p)}); });
        return readBody(req, function (text) {
          var p = null;
          try { p = JSON.parse(text); } catch (e) {}
          if (p && p.auto === true) {
            try { fs.unlinkSync(placeFile); } catch (e) {}
          } else if (p && validPlace(p)) {
            // Here, not in the handler's try: this runs after the request was
            // read, and an error nobody catches ends the whole process.
            try { fs.writeFileSync(placeFile, JSON.stringify({name: p.name, lat: p.lat, lon: p.lon})); }
            catch (e) { return send(res, 500, {ok: false, error: 'not saved'}); }
          } else return send(res, 400, {ok: false, error: 'not a place'});
          rev++;
          currentPlace(function (now) { send(res, 200, {ok: true, place: placeInfo(now)}); });
        });
      }
      send(res, 404, {ok: false, error: 'not found'});
    } catch (e) {
      send(res, 500, {ok: false, error: String(e)});
    }
  });
  server.on('error', function (e) { console.error('homebar setup: ' + e.message); });
  server.listen(PORT, '0.0.0.0');
  return server;
}

module.exports = {start: start, PORT: PORT};

// On its own (webOS 4): the folder holds weather.json and setup.pid, which the
// boot hook and the uninstaller stop this process by.
if (require.main === module) {
  var folder = process.argv[2] || __dirname;
  try { fs.writeFileSync(path.join(folder, 'setup.pid'), String(process.pid)); } catch (e) {}
  start(folder);
}
