// Homebar, the Home panel variant (webOS 4, and any webOS whose LG Home is a
// QML app): build patched copies of LG Home's main.qml and
// Controllers/UIController.qml from the firmware originals.
//
// main.qml gets a Loader for the launcher panel (current/Launcher.qml) on top
// of LG's UI, which stays in the same process, so LG's window, lifecycle and
// HOME handling are kept. LG's own ribbon is shown only when the panel asks
// for it ("Original Home"); BLUE comes back.
//
// LG's Home differs between webOS versions, so the patch is made of pieces.
// The ones the panel cannot do without must be found, exactly once: the
// QtQuick import, the root element and its id, the UI controller, and the
// foreground state and window interface the panel reads. The others (focus
// coming back, the BLUE key, LG's hidden mode, voice and "Home shown" paths)
// go in where they match and are reported where they do not, so a Home that
// was never tested gets the panel with what fits instead of nothing.
//
// Usage: node patch-home.js [--check] <dir>
//   reads <dir>/main.original.qml and <dir>/UIController.original.qml (and,
//   when there, <dir>/SystemProperties.original.qml, Home's
//   AppInitializer/SystemProperties.qml, which is only read) and
//   writes <dir>/main.qml and <dir>/UIController.qml; with --check it only
//   says whether the panel fits (exit 0) or not (exit 1) and writes nothing.
// Plain ES5 for old node versions (webOS 3 and 4 have node 0.12).
'use strict';
var fs = require('fs');
var path = require('path');

var args = process.argv.slice(2);
var check = args[0] === '--check';
if (check) args.shift();
var dir = args[0];
if (!dir) {
  console.error('usage: node patch-home.js [--check] <dir>');
  process.exit(2);
}

var notes = [];
function refuse(what) {
  console.error('rawin-launcher: LG Home differs from the tested one (' + what + '); nothing changed');
  process.exit(1);
}
// The one match of re in text, or null when it matches never or more than once.
function once(text, re) {
  var m = re.exec(text);
  if (!m) return null;
  if (re.exec(text.slice(m.index + m[0].length))) return null;
  return m;
}
// Puts replacement (text, or a function of the match) in place of the one
// match. A required piece that is missing refuses the whole patch; an
// optional one is noted and skipped.
function replaceOnce(text, re, replacement, what, required) {
  var m = once(text, re);
  if (!m) {
    var reason = what + (re.exec(text) ? ' found more than once' : ' not found');
    if (required) refuse(reason);
    notes.push(reason + '; skipped');
    return text;
  }
  var out = typeof replacement === 'function' ? replacement(m) : replacement;
  return text.slice(0, m.index) + out + text.slice(m.index + m[0].length);
}

// What goes into LG's root element. ROOT is the root element's id.
function injection(ROOT) {
  return [
    '',
    '    // Homebar: the panel on top of LG Home, in LG\'s own process.',
    '    property bool cleanHomeStock: false',
    // Kept separate from cleanHomeStock: a timeout must hide just Homebar,
    // without opening LG\'s ribbon or closing Home (which hides the pointer).
    '    property bool cleanHomeHidden: false',
    '    // LG Home\'s own foreground state (systemProperties), or true on a Home',
    '    // that has none to read: the panel shows whenever Home is in front and',
    '    // LG\'s ribbon was not asked for.',
    '    property bool cleanHomeForeground: true',
    '    onCleanHomeForegroundChanged: {',
    '        ' + ROOT + '.cleanHomeLog("foreground " + cleanHomeForeground);',
    '        if (cleanHomeForeground) { cleanHomeStock = false; cleanHomeHidden = false; if (cleanHomeLoader.item) cleanHomeLoader.item.forceActiveFocus(); }',
    '    }',
    '    onCleanHomeStockChanged: ' + ROOT + '.cleanHomeLog("LG Home shown " + cleanHomeStock)',
    '    onCleanHomeHiddenChanged: ' + ROOT + '.cleanHomeLog("panel hidden " + cleanHomeHidden)',
    // On a Home never tested, nothing else records what the panel went
    // through: LG's own log lines and QML warnings do not reach
    // /var/log/messages. The setup server keeps these lines in
    // /tmp/rawin-launcher-panel.log, which diagnose.sh prints.
    '    property int cleanHomeKeys: 0',
    '    function cleanHomeLog(text) {',
    '        try {',
    '            var x = new XMLHttpRequest();',
    '            x.open("POST", "http://127.0.0.1:8898/panel-log");',
    '            x.send(String(text));',
    '        } catch (e) {}',
    '    }',
    '    function cleanHomeName(item) {',
    '        for (var p = item; p; p = p.parent) {',
    '            if (p === cleanHomeLoader.item) return "panel" + (p === item ? "" : " " + String(item).split("(")[0]);',
    '            if (p === uiController) return "LG Home" + (p === item ? "" : " " + String(item).split("(")[0]);',
    '        }',
    '        return item ? String(item).split("(")[0] : "none";',
    '    }',
    // Window.window is Qt 5.7 and later: written into main.qml it would stop
    // LG Home from loading on Qt 5.6 (webOS 4), so the Loader makes a reader
    // at run time, where an error is caught and the window stays unknown.
    '    property var cleanHomeWin: null',
    '    property var cleanHomeWinReader: null',
    '    function cleanHomeWindow() { return ' + ROOT + '.cleanHomeWin || null; }',
    '    onCleanHomeWinChanged: {',
    '        var w = cleanHomeWin;',
    '        if (!w) return;',
    '        ' + ROOT + '.cleanHomeLog(' + ROOT + '.cleanHomeWindowInfo());',
    '        w.activeFocusItemChanged.connect(function () {',
    '            try { ' + ROOT + '.cleanHomeLog("focus " + ' + ROOT + '.cleanHomeName(w.activeFocusItem)); } catch (e) {}',
    '        });',
    '    }',
    // The window LG's executable made (type, size, colour), as far as QML can
    // read it: whether the app underneath can show through depends on it.
    '    function cleanHomeWindowInfo() {',
    '        var w = ' + ROOT + '.cleanHomeWindow(), out = [];',
    '        if (!w) return "window: not readable";',
    '        for (var k in w) {',
    '            try {',
    '                var v = w[k];',
    '                if (typeof v === "string" || typeof v === "number" || typeof v === "boolean") out.push(k + "=" + String(v).slice(0, 80));',
    '                else if (v && typeof v === "object" && /propert|type/i.test(k)) out.push(k + "=" + JSON.stringify(v).slice(0, 300));',
    '            } catch (e) {}',
    '        }',
    '        return "window: " + out.join(" ");',
    '    }',
    '    Connections {',
    '        target: ' + ROOT,
    '        ignoreUnknownSignals: true',
    '        onActiveChanged: ' + ROOT + '.cleanHomeLog("Home active " + ' + ROOT + '.active)',
    '    }',
    '    Loader {',
    '        id: cleanHomeLoader',
    '        z: 500',
    '        anchors.fill: parent',
    '        source: "file:///var/lib/webosbrew/rawin-launcher/current/Launcher.qml"',
    '        visible: !' + ROOT + '.cleanHomeStock && !' + ROOT + '.cleanHomeHidden',
    // On the Loader, not the root: LG's root has its own Component.onCompleted.
    '        Component.onCompleted: {',
    '            try {',
    '                ' + ROOT + '.cleanHomeWinReader = Qt.createQmlObject("import QtQuick 2.4; import QtQuick.Window 2.2; Item { property var w: Window.window }", cleanHomeLoader);',
    '                ' + ROOT + '.cleanHomeWin = Qt.binding(function () { return ' + ROOT + '.cleanHomeWinReader.w; });',
    '            } catch (e) { ' + ROOT + '.cleanHomeLog("window: not readable (" + e + ")"); }',
    '        }',
    '        onStatusChanged: {',
    '            ' + ROOT + '.cleanHomeLog("panel status " + ["null", "ready", "loading", "error"][status] +',
    '                (status === Loader.Error ? ": " + Qt.createComponent(source).errorString() : ""));',
    '            if (status === Loader.Error) ' + ROOT + '.cleanHomeStock = true;',
    '        }',
    // Keys the panel left unanswered come up here on their way to LG's UI.
    '        Keys.onPressed: {',
    '            if (' + ROOT + '.cleanHomeKeys < 40) { ' + ROOT + '.cleanHomeKeys++; ' + ROOT + '.cleanHomeLog("key " + event.key + " not taken by the panel"); }',
    '            event.accepted = false;',
    '        }',
    '        onLoaded: {',
    '            item.hostWindow = ' + ROOT + ';',
    '            var props = null;',
    '            try { props = systemProperties; } catch (e) {}',
    '            if (props && props.isAppForeground !== undefined)',
    '                ' + ROOT + '.cleanHomeForeground = Qt.binding(function() { return systemProperties.isAppForeground; });',
    '            item.ready = props && props.isAppReadyToUse !== undefined',
    '                ? Qt.binding(function() { return systemProperties.isAppReadyToUse; }) : true;',
    '            item.foreground = Qt.binding(function() { return ' + ROOT + '.cleanHomeForeground && !' + ROOT + '.cleanHomeStock && !' + ROOT + '.cleanHomeHidden; });',
    '            item.forceActiveFocus();',
    '            ' + ROOT + '.cleanHomeLog("panel loaded; foreground " + ' + ROOT + '.cleanHomeForeground + ", ready " + item.ready + ", panel has focus " + item.activeFocus);',
    '        }',
    '    }',
    '    Connections {',
    '        target: cleanHomeLoader.item',
    '        ignoreUnknownSignals: true',
    '        onTimeoutRequested: { ' + ROOT + '.cleanHomeHidden = true; }',
    '        onStockRequested: {',
    '            ' + ROOT + '.cleanHomeStock = true;',
    '            try { uiController.currentMode = "main"; uiController.startApp(); } catch (e) {}',
    '            uiController.forceActiveFocus();',
    '        }',
    '        onCloseRequested: { interfaces.application.closeApp(); }',
    '    }',
    '    Rectangle {',
    '        z: 600',
    '        visible: ' + ROOT + '.cleanHomeStock && ' + ROOT + '.cleanHomeForeground',
    '        anchors.right: parent.right; anchors.rightMargin: 60; y: 45',
    '        width: 450; height: 58; radius: 29; color: "#152d32"',
    '        Text { anchors.centerIn: parent; text: "BLUE · back to Homebar"; color: "#8be2cb"; font.pixelSize: 22 }',
    '        MouseArea { anchors.fill: parent; onClicked: { ' + ROOT + '.cleanHomeStock = false; if (cleanHomeLoader.item) cleanHomeLoader.item.forceActiveFocus(); } }',
    '    }',
    ''
  ].join('\n');
}

var main = fs.readFileSync(path.join(dir, 'main.original.qml'), 'utf8');
if (main.indexOf('cleanHomeLoader') >= 0) {
  console.error('rawin-launcher: main.original.qml is already patched; restore the firmware file first');
  process.exit(1);
}
// What the panel reads from LG's Home: whether Home is in front, and the
// window interface that closes it. Home in front is systemProperties.isAppForeground:
// main.qml holds the systemProperties object, and isAppForeground is declared
// in SystemProperties.qml (main.qml itself need not use it; 4.10's does not).
var sysPath = path.join(dir, 'SystemProperties.original.qml');
var sysProps = fs.existsSync(sysPath) ? fs.readFileSync(sysPath, 'utf8') : '';
if (!/\bsystemProperties\b/.test(main)) refuse('no systemProperties');
if (!/^[ \t]*property[ \t]+\w+[ \t]+isAppForeground\b/m.test(sysProps) && main.indexOf('systemProperties.isAppForeground') < 0)
  refuse('no systemProperties.isAppForeground');
if (main.indexOf('interfaces.application') < 0) refuse('no interfaces.application');
// The root element and its id (rootWindow on the tested firmware).
var rootAt = /^[A-Z]\w*\s*\{/m.exec(main);
if (!rootAt) refuse('no root element');
var rootId = /^[ \t]*id:[ \t]*(\w+)[ \t]*$/m.exec(main.slice(rootAt.index));
if (!rootId) refuse('the root element has no id');
var ROOT = rootId[1];
if (ROOT !== 'rootWindow') notes.push('the root element is ' + ROOT + ' (rootWindow on the tested firmware)');

main = replaceOnce(main, /^import QtQuick \d+\.\d+[ \t]*$/m, function (m) {
  return m[0] + (/^import WebOS\.Global /m.test(main) ? '' : '\nimport WebOS.Global 1.0');
}, 'the QtQuick import', true);
// The panel goes in before LG's "//UI Controller" comment, or, without one,
// right after the root element's id.
if (once(main, /^[ \t]*\/\/ ?UI Controller[ \t]*$/m)) {
  main = replaceOnce(main, /^[ \t]*\/\/ ?UI Controller[ \t]*$/m, function (m) { return injection(ROOT) + '\n' + m[0]; }, 'the UI Controller comment', true);
} else {
  main = replaceOnce(main, new RegExp('^[ \\t]*id:[ \\t]*' + ROOT + '[ \\t]*$', 'm'), function (m) { return m[0] + '\n' + injection(ROOT); }, 'the root id', true);
  notes.push('no "//UI Controller" comment; the panel goes in after the root id');
}
// LG's own UI: shown only when asked for, or while the panel failed to load.
main = replaceOnce(main, /^([ \t]*)id:[ \t]*uiController[ \t]*$/m, function (m) {
  var ind = m[1];
  return [m[0],
    ind + 'visible: ' + ROOT + '.cleanHomeStock || cleanHomeLoader.status !== Loader.Ready',
    ind + 'enabled: visible',
    ind + 'focus: ' + ROOT + '.cleanHomeStock'].join('\n');
}, 'the UI controller (id: uiController)', true);
// Focus coming back to Home goes to the panel, not LG's ribbon.
main = replaceOnce(main, /^([ \t]*)function focusIn\(\)[ \t]*\{/m, function (m) {
  return m[0] + '\n' + m[1] + '    ' + ROOT + '.cleanHomeStock = false; ' + ROOT + '.cleanHomeHidden = false;';
}, 'function focusIn()', false);
// Without focusIn() (the full-screen Home of webOS 6) the root hands focus to
// LG's controller whenever Home becomes active, and the panel, which has to
// answer the remote, never gets it: keys reach the window and go nowhere.
if (!/^[ \t]*function focusIn\(\)/m.test(main)) main = replaceOnce(main, /\(uiController\.forceActiveFocus\(\), true\)/, function (m) {
  return '((' + ROOT + '.cleanHomeStock || !cleanHomeLoader.item ? uiController : cleanHomeLoader.item).forceActiveFocus(), true)';
}, "the root's focus hand-over", false);
// BLUE, while LG's ribbon is shown, brings the panel back.
main = replaceOnce(main, /^([ \t]*)function keyPressEvent\((\w+)\)[ \t]*\{/m, function (m) {
  var ind = m[1] + '    ', key = m[2];
  return [m[0],
    ind + 'if (' + ROOT + '.cleanHomeKeys < 40) { ' + ROOT + '.cleanHomeKeys++; ' + ROOT + '.cleanHomeLog("keyPressEvent " + ' + key + ' + ", LG Home shown " + ' + ROOT + '.cleanHomeStock); }',
    ind + 'if (' + ROOT + '.cleanHomeHidden) {',
    ind + '    ' + ROOT + '.cleanHomeHidden = false;',
    ind + '    if (cleanHomeLoader.item) cleanHomeLoader.item.forceActiveFocus();',
    ind + '    return;',
    ind + '}',
    ind + 'if (' + ROOT + '.cleanHomeStock && ' + key + ' === WebOS.Key_webOS_Blue) {',
    ind + '    ' + ROOT + '.cleanHomeStock = false;',
    ind + '    if (cleanHomeLoader.item) cleanHomeLoader.item.forceActiveFocus();',
    ind + '    return;',
    ind + '}'].join('\n');
}, 'function keyPressEvent(keyCode)', false);

// LG's controller: hide, voice and the "Home shown" path only act while LG's
// own ribbon is the visible UI. Each piece is optional: a Home without it
// keeps the panel, with LG's ribbon possibly reacting to that one thing.
var ctrl = fs.readFileSync(path.join(dir, 'UIController.original.qml'), 'utf8');
ctrl = replaceOnce(ctrl, /if\(root\.isHiddenMode && state !== "hidden"\)/, 'if(root.isHiddenMode && state !== "hidden" && ' + ROOT + '.cleanHomeStock)', "LG's hidden mode", false);
ctrl = replaceOnce(ctrl, /interfaces\.voice\.register\(\);/, 'if(' + ROOT + '.cleanHomeStock) interfaces.voice.register();', 'the voice registration', false);
ctrl = replaceOnce(ctrl, /if\(homeShown\) \{/, 'if(homeShown && ' + ROOT + '.cleanHomeStock) {', 'the homeShown path', false);

notes.forEach(function (n) { console.log('rawin-launcher: note: ' + n); });
if (check) {
  console.log('rawin-launcher: LG Home fits the panel' + (notes.length ? ' (with ' + notes.length + ' difference' + (notes.length > 1 ? 's' : '') + ' from the tested firmware)' : ''));
  process.exit(0);
}
fs.writeFileSync(path.join(dir, 'main.qml'), main);
fs.writeFileSync(path.join(dir, 'UIController.qml'), ctrl);
console.log('rawin-launcher: LG Home patched');
