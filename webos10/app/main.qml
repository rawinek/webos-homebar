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
    Component.onCompleted: {
        var startup = startupParams();
        preloaded = isPreload(startup);   // ends the binding
        if (preloaded && !isQuiet(startup)) { win.visible = true; mapTimer.start(); }
        // Launching the regular app tile while takeover is enabled must bring
        // the Home instance forward, not leave two independent panels running.
        initialized = true;
        if (!nativeHome) home.http("/home", function(r) {
            if (r.nativeHome) home.http("/launch?id=com.webos.app.home", function() { win.hide(); Qt.quit(); });
        });
    }
    Timer { id: mapTimer; interval: 500; onTriggered: if (!home.foreground) win.visible = false }
    color: "transparent"
    readonly property bool nativeHome: Config.nativeHome === true
    appId: nativeHome ? "com.webos.app.home" : "org.rawin.launcher"
    title: "Homebar"

    // Each launch: HOME while the panel is up hides it, otherwise shows it;
    // the boot hook's preload only makes sure the process is there.
    onLaunchParamsChanged: {
        if (!initialized) return;
        if (isPreload(launchParams)) return;
        // Settings → Remote button waiting for a press: the press may be the
        // button already bound to Homebar, whose launch must not hide the panel.
        if (win.visible && home.foreground && (home.buttonStep === "first" || home.buttonStep === "second")) return;
        if (win.visible && home.foreground) hide(); else show();
    }

    function show() {
        hideTimer.stop(); mapTimer.stop();
        win.visible = true;
        home.foreground = true;
        home.forceActiveFocus();
        home.loadInputs();
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
        onCloseRequested: win.hide()
        // A timeout is not a BACK press: hide this overlay window only, so
        // the system keeps the Magic Remote pointer where it is.
        onTimeoutRequested: win.hide()
        // Original LG Home: SAM opens it as a card; we step aside.
        onStockRequested: http("/launch?id=com.webos.app.home", function() { win.hide(); })
        Component.onCompleted: { home.ready = true; home.loadInputs(); if (!win.preloaded) home.forceActiveFocus(); }
    }
}
