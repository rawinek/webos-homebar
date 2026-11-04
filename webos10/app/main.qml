// Homebar overlay (webOS 10 and the untested versions tried with it): the
// shared panel (Panel.qml, generated from ui/Launcher.qml by tools/build.py)
// in a developer QML overlay window run by qml-runner. HOME relaunches the
// app; qml-runner resets the "params" context property, which shows the
// panel, or hides it when it is already up. BACK hides the window but keeps
// the process, so the next HOME is a show, not a start. The boot hook
// launches the app with {"preload": true}: then the window is shown for a
// moment with nothing drawn (so the app manager takes its loading spinner
// down) and hidden, and the first HOME after a boot is a show too.
import QtQuick 2.4
import QtQuick.Window 2.2
import Eos.Window 0.1
import "Config.js" as Config

WebOSWindow {
    id: win
    windowType: "_WEBOS_WINDOW_TYPE_OVERLAY"
    // The TV's UI plane: 1920×1080 on FHD and UHD sets (the TV scales it to
    // the panel), 1280×720 on HD ones. A screen reported smaller than FHD is
    // taken at its size; anything else stays at the tested 1920×1080. The
    // panel lays itself out for whatever size it gets.
    readonly property bool smallScreen: Screen.width > 0 && Screen.height > 0 && Screen.width < 1920
    width: smallScreen ? Screen.width : 1920
    height: smallScreen ? Screen.height : 1080
    property var launchParams: typeof params !== "undefined" ? params : null
    // Whether the process was started hidden: read once from the launch that
    // started it, then a plain value. The boot hook's preload can land after
    // a HOME already started the app (right after a boot), and must not hide
    // a panel that is up.
    property bool preloaded: isPreload(startupParams())
    property bool initialized: false
    function startupParams() {
        // SAM's native lifecycle passes cold-launch arguments as "parameters";
        // developer QML apps use the params context property. Read argv only at
        // startup: later HOME events must follow the live params context.
        if (nativeHome) {
            var args = Qt.application.arguments;
            for (var i=1; i<args.length; i++) {
                try {
                    var meta = JSON.parse(args[i]);
                    if (meta.appId === "com.webos.app.home" && meta.parameters)
                        return meta.parameters;
                } catch (e) {}
            }
        }
        return launchParams;
    }
    function isPreload(p) { return p !== null && p !== undefined && p.preload === true; }
    // A quiet start is the helper preloading the panel while another app is
    // in front: then the window is not mapped at all, so nothing can flash
    // over the picture (there is no spinner to take down either).
    function isQuiet(p) { return p !== null && p !== undefined && p.quiet === true; }
    visible: !preloaded
    // The app manager keeps its loading spinner on screen until a launched
    // app shows a window: a preloaded start maps the window for a moment,
    // with the panel faded out (nothing is drawn), and hides it again.
    // How BACK closes Homebar as System HOME: it hides the window ("none").
    // On an LG G5 (webOS 11) the remote then stayed with the hidden panel,
    // which neither the app manager's relaunch ("home"), launching the card
    // underneath again ("card") nor a HOME key through the TV's input path
    // ("key") cured: BACK never reached the panel there. The window now claims
    // BACK (at start, below). The other ways stay selectable with back-mode in
    // the launcher's folder (read at each show), for trying them on a TV; the
    // panel log records what came of each.
    property string backMode: ""
    function closeByBack() {
        var mode = !nativeHome ? "none" : backMode || "none";
        note("BACK close: mode " + mode);
        if (mode === "key") {
            home.http("/home-key", function(r) { note("BACK close: HOME key sent " + (r.returnValue === true)); },
                      function(s) { note("BACK close: sending HOME failed " + s); }, {});
            backFallback.restart();
        } else if (mode === "home") {
            home.http("/launch?id=com.webos.app.home&params=" + encodeURIComponent(JSON.stringify({activateType: "home", launchType: "homeKey"})),
                      function() { note("BACK close: Home launched"); }, function(s) { note("BACK close: launching Home failed " + s); });
            backFallback.restart();
        } else {
            hide();
            // The card in front now, looked up afresh: what the panel saw
            // when it opened may have changed since.
            if (mode === "card") home.http("/foreground", function(r) {
                var list = r.foregroundAppInfo || [], front = "";
                for (var i = 0; i < list.length && !front; i++)
                    if (/CARD$/.test(list[i].windowType || "") && list[i].appId !== "com.webos.app.home") front = list[i].windowGroupOwnerId || list[i].appId;
                if (!front) { note("BACK close: no card underneath"); return; }
                home.http("/launch?id=" + encodeURIComponent(front), function(l) { note("BACK close: " + front + " launched " + (l.returnValue === true)); },
                          function(s) { note("BACK close: launching " + front + " failed " + s); });
            });
        }
        afterBack.count = 0; afterBack.interval = 600; afterBack.restart();
    }
    // "key" and "home": the relaunch they bring hides the panel as HOME does; if
    // none comes, the panel is hidden anyway.
    Timer { id: backFallback; interval: 1000; onTriggered: if (win.visible && home.foreground) { note("BACK close: no relaunch came; hiding"); hide(); } }
    // What the TV has in front after a BACK close, twice: whether Home still
    // counts as shown there tells the ways out apart.
    Timer {
        id: afterBack; property int count: 0; interval: 600; repeat: true
        onTriggered: {
            var when = "BACK +" + (count === 0 ? "0.6" : "2.4") + " s";
            home.http("/foreground", function(r) {
                var list = r.foregroundAppInfo || [], parts = [];
                for (var i = 0; i < list.length; i++) parts.push(list[i].appId + "/" + String(list[i].windowType || "").replace("_WEBOS_WINDOW_TYPE_", ""));
                note(when + ": in front " + (parts.join(", ") || "nothing"));
            });
            if (++count >= 2) stop(); else interval = 1800;
        }
    }

    Component.onCompleted: {
        // Homebar answers BACK itself, and says so with the access policy LG's
        // own overlays carry (Luma sets the same). Without it the compositor of
        // webOS 11 kept BACK: it hid the panel without telling it and left the
        // remote on the invisible window until HOME (an LG G5). webOS 10 adds the
        // policy to overlay windows by itself. One key at a time: the map takes
        // new keys and passes each to the compositor; assigning it whole fails.
        try {
            win.windowProperties["_WEBOS_ACCESS_POLICY_KEYS_BACK"] = "true";
            note("BACK claimed: " + win.windowProperties["_WEBOS_ACCESS_POLICY_KEYS_BACK"]);
        } catch (e) { note("BACK not claimed: " + e); }
        // A held BACK reaches apps as EXIT: the compositor turns the long press
        // into that key (StarfishKeyFilter). Unclaimed, the compositor handled
        // EXIT itself and hid the panel the way BACK did before (issue #18), so
        // Homebar claims it too and closes on it.
        try {
            win.windowProperties["_WEBOS_ACCESS_POLICY_KEYS_EXIT"] = "true";
            note("EXIT claimed: " + win.windowProperties["_WEBOS_ACCESS_POLICY_KEYS_EXIT"]);
        } catch (e) { note("EXIT not claimed: " + e); }
        var startup = startupParams();
        preloaded = isPreload(startup);   // ends the binding
        if (preloaded && !isQuiet(startup)) { win.visible = true; mapTimer.start(); }
        // Launching the regular app tile while takeover is enabled must bring
        // the Home instance forward, not leave two independent panels running.
        initialized = true;
        home.http("/home", function(r) {
            win.backMode = r.backMode || "";
            if (!nativeHome && r.nativeHome) home.http("/launch?id=com.webos.app.home", function() { win.hide(); Qt.quit(); });
        });
    }
    Timer { id: mapTimer; interval: 500; onTriggered: if (!home.foreground) win.visible = false }
    color: "transparent"
    readonly property bool nativeHome: Config.nativeHome === true
    appId: nativeHome ? "com.webos.app.home" : "org.rawin.launcher"
    title: "Homebar"

    // What each HOME found and did, for diagnose.sh (/tmp/rawin-launcher-panel.log,
    // kept by the setup server): on a webOS 11 TV a first HOME sometimes did
    // nothing, as if taken for "close" while nothing was on screen.
    // Numbered: the posts can reach the server out of order.
    property int noteCount: 0
    function note(what) {
        try {
            var x = new XMLHttpRequest();
            x.open("POST", "http://127.0.0.1:8898/panel-log");
            x.send("#" + (++noteCount) + " " + (nativeHome ? "home: " : "overlay: ") + what + " | window " + (win.visible ? "shown" : "hidden")
                   + (win.active ? ", active" : ", inactive") + ", panel " + (home.foreground ? "up" : "down"));
        } catch (e) {}
    }
    onActiveChanged: if (initialized) note("window " + (active ? "active" : "inactive"))
    onVisibleChanged: if (initialized) note("window " + (visible ? "shown" : "hidden"))

    // Each launch: HOME while the panel is up hides it, otherwise shows it;
    // the boot hook's preload only makes sure the process is there.
    onLaunchParamsChanged: {
        if (!initialized) return;
        note("launch " + JSON.stringify(launchParams || {}).slice(0, 160));
        if (isPreload(launchParams)) return;
        // Settings → Remote button waiting for a press: the press may be the
        // button already bound to Homebar, whose launch must not hide the panel.
        if (win.visible && home.foreground && (home.buttonStep === "first" || home.buttonStep === "second")) return;
        // Up means up on the screen too. A window that is shown but has no focus
        // is not on screen (after the TV wakes from standby, or under LG's
        // screensaver), and showing it again changes nothing: it is unmapped
        // and mapped anew. Before, that took a second HOME (the first hid it).
        if (win.visible && home.foreground && win.active) { note("-> hide"); hide(); }
        else if (win.visible) { note("-> map again"); hideTimer.stop(); win.visible = false; remapTimer.restart(); }
        else { note("-> show"); show(); }
    }
    Timer { id: remapTimer; interval: 60; onTriggered: show() }

    function show() {
        hideTimer.stop(); mapTimer.stop(); remapTimer.stop();
        win.visible = true;
        // The window takes the focus too: the next HOME goes by it (see above).
        win.requestActivate();
        home.foreground = true;
        home.forceActiveFocus();
        home.loadInputs();
        // back-mode is read again at each show, so trying another needs no restart.
        home.http("/home", function(r) { win.backMode = r.backMode || ""; });
        noteClaims();
    }
    // The claims as the window holds them now, at each show: the notes from
    // the start can be lost when the panel starts before the setup server
    // (the G5's log had none from System HOME, issue #20).
    function noteClaims() {
        try {
            note("claims: BACK " + win.windowProperties["_WEBOS_ACCESS_POLICY_KEYS_BACK"] + ", EXIT "
                 + win.windowProperties["_WEBOS_ACCESS_POLICY_KEYS_EXIT"] + ", key mask " + win.keyMask);
        } catch (e) { note("claims: " + e); }
    }
    function hide() {
        home.foreground = false;   // runs the panel's 180 ms fade-out
        hideTimer.restart();
    }
    Timer { id: hideTimer; interval: 200; onTriggered: win.visible = false }

    Panel {
        id: home
        anchors.fill: parent
        foreground: !win.preloaded
        onCloseRequested: if (home.closeReason === "back") win.closeByBack(); else win.hide()
        // A timeout is not a BACK press: hide this overlay window only, so
        // the system keeps the Magic Remote pointer where it is.
        onTimeoutRequested: win.hide()
        // Original LG Home: SAM opens it as a card; we step aside.
        onStockRequested: http("/launch?id=com.webos.app.home", function() { win.hide(); })
        Component.onCompleted: { home.ready = true; home.loadInputs(); if (!win.preloaded) home.forceActiveFocus(); }
    }
}
