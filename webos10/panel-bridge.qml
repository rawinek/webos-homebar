// Fragment, not a standalone file: tools/build.py puts it into Panel.qml in
// place of ui/Launcher.qml's Service elements (from "Service { id:
// launchService" up to "Timer { id: launchTimeout").
    // Overlay variant: Luna goes through the root helper over HTTP (webOS 10
    // answers nothing to a developer QML app). Same callService() shape as
    // the Service elements it replaces in ui/Launcher.qml.
    readonly property string helper: "http://127.0.0.1:8899"
    // GET, or POST with a JSON body.
    function http(pathname, done, failed, body) {
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            var answer = null;
            try { answer = JSON.parse(xhr.responseText); } catch (e) {}
            if (xhr.status === 200 && answer) { if (done) done(answer); }
            else if (failed) failed(xhr.status, answer);
        };
        var post = body !== undefined && body !== null;
        xhr.open(post ? "POST" : "GET", helper + pathname);
        // The helper refuses requests that change something without this: a web
        // page in the TV's browser cannot add it to a cross-origin request.
        xhr.setRequestHeader("X-Homebar", "1");
        if (post) { xhr.setRequestHeader("Content-Type", "application/json"); xhr.send(JSON.stringify(body)); }
        else xhr.send();
    }
    function loadInputs() {
        http("/inputs", function(r) { setInputs(r.devices ? inputsFrom(r.devices) : []); });
    }
    QtObject {
        id: launchService
        function callService(p) {
            // Parameters (LG's Settings page to open, e.g. the memory
            // optimiser) go along as JSON; the helper passes them on.
            var path = "/launch?id=" + encodeURIComponent(p.id);
            if (p.params) path += "&params=" + encodeURIComponent(JSON.stringify(p.params));
            shell.http(path, function(r) {
                launching = false; launchTimeout.stop();
                if (r.returnValue) closeHome();
                else message = t("err_launch");
            }, function(status) {
                launching = false; launchTimeout.stop();
                // A refusal (4xx) is the helper answering no; no answer at all
                // (status 0) or an error of its own is the helper not working.
                message = status >= 400 && status < 500 ? t("err_launch") : t("err_helper");
            });
        }
    }
    // The helper can be a moment behind the panel: a HOME in the second
    // between Input Hook and the helper coming up after a boot, or an update
    // replacing the helper. A failed app list is asked for again every 1.5 s,
    // up to ten times in a row, while the panel is up.
    Timer {
        id: helperRetry
        interval: 1500
        property int left: 10
        onTriggered: if (shell.foreground) { catalog.callService({}); loadInputs(); }
    }
    function helperMissing() {
        if (helperRetry.running || helperRetry.left <= 0) return;
        helperRetry.left--;
        helperRetry.restart();
    }
    // Closing every app in the background: closeAllApps, called by the helper.
    QtObject {
        id: closeAppsService
        function callService(p) {
            shell.http("/close-apps", function(r) {
                notice = r.returnValue ? t("close_apps_done") : t("close_apps_failed");
                catalog.callService({});
            }, function() { notice = t("err_unavailable"); });
        }
    }
    QtObject {
        id: catalog
        function callService(p) {
            shell.http("/apps", function(r) {
                helperRetry.left = 10;
                if (!r.apps) return;
                var next = [];
                for (var i=0; i<r.apps.length; i++) {
                    var a = r.apps[i];
                    if (Config.excluded.indexOf(a.id) >= 0) continue;
                    next.push({id: a.id, title: a.title, icon: a.icon ? shell.helper + "/" + a.icon : ""});
                }
                if (same(next, applications)) return;
                applications = next;
                if (page === "apps") selected = Math.max(0, Math.min(selected, apps.length-1));
            }, helperMissing);
        }
    }
    // The TV's language and the BACK-hold target go through the helper too.
    // Asked once at start, with whether LG's Home is still there to open.
    QtObject {
        id: localeService
        function callService(p) {
            shell.http("/locale", function(r) { if (r.locale) systemLang = r.locale; });
            shell.http("/home", function(r) { stockHomeAvailable = !!r.lgHome; });
            shell.loadMode();
        }
    }
    onExitTargetChosen: http("/exit-target?id=" + encodeURIComponent(target))
    // Updates: update.sh, run by the helper.
    function updateRun(step, channel) {
        http("/update?step=" + step + "&channel=" + channel,
             function(r) { updateResult(step, r); }, function() { updateResult(step, null); });
    }
    // The backup file, kept by the helper next to the launcher: written
    // with a POST, read back (info and load) with a GET.
    function backupRun(step, data) {
        if (step === "save") http("/backup", function(r) { backupResult("save", r); }, function() { backupResult("save", null); }, data);
        else http("/restore", function(r) { backupResult(step, r.saved ? r : null); }, function() { backupResult(step, null); });
    }
    property string launchWarningLanguage: ""
    function loadMode() {
        http("/mode", function(r) {
            if (modeConfirm && r.inspection && modeConfirmFingerprint !== r.inspection.fingerprint) {
                modeConfirm = ""; modeError = "launch_changed";
            }
            modeInfo = r;
            if (!r.busy && r.inspection && (r.inspection.fingerprint !== launchLastWarning || launchWarningLanguage !== lang)) {
                launchLastWarning = r.inspection.fingerprint;
                launchWarningLanguage = lang;
                if (r.inspection.issues.length) message = t("launch_attention");
                else if (r.migrationAvailable) notice = t("launch_migrate");
            }
            if (r.busy) modePoll.restart();
            if (r.result && r.result.ok === false)
                modeError = r.result.error || "launch_failed";
            // One note per finished switch, until the user has seen it (or ten minutes passed).
            if (!r.busy && r.result && r.result.at > settings.modeAck && Date.now() - r.result.at < 600000 && modeConfirm === "") {
                modeDoneOk = r.result.ok === true;
                modeDoneAt = r.result.at;
            }
        });
    }
    onLaunchCheckRequested: loadMode()
    Timer { id: modePoll; interval: 1000; onTriggered: loadMode() }
    function modeRun(mode, fingerprint) {
        http("/mode", function(r) {
            if (!r.ok) { modeError = r.error || "launch_failed"; return; }
            message = r.pending ? t("mode_switching") : "";
            loadMode();
        }, function(status, answer) { modeError = answer && answer.error ? answer.error : "launch_failed"; loadMode(); }, {mode: mode, fingerprint: fingerprint});
    }
    // Settings → Remote button: the helper reads one press at a time and
    // writes the binding to the mapper (webos10/helper/button.js).
    function buttonLoadRun() { http("/button", function(r) { buttonInfo = r; }); }
    function buttonCaptureRun(id, fresh) {
        http("/button", function(r) { buttonCaptured(id, r); },
             function(status, answer) { buttonCaptured(id, answer && answer.error ? answer : null); }, {step: "capture", fresh: fresh});
    }
    function buttonBindRun(code) {
        http("/button", function(r) { buttonSaved(r); }, function(status, answer) { buttonSaved(answer); }, {step: "bind", code: code});
    }
    function buttonUnbindRun() {
        http("/button", function(r) { buttonSaved(r); }, function(status, answer) { buttonSaved(answer); }, {step: "unbind"});
    }
    // The helper closes and launches the overlay process after replying, so
    // this QML instance never has to restart itself while handling a click.
    function restartHomebar() {
        http("/restart", function() { closeHome(); }, function() { message = t("err_restart"); }, {});
    }
    // What stays visible under the overlay: the first card that is not us.
    QtObject {
        id: foregroundInfo
        function callService(p) {
            shell.http("/foreground", function(r) {
                nowTitle = "";
                var list = r.foregroundAppInfo || [];
                for (var i=0; i<list.length; i++) {
                    if (list[i].appId.indexOf("org.rawin.launcher") === 0 || list[i].windowType === "_WEBOS_WINDOW_TYPE_OVERLAY") continue;
                    if (describe(list[i].windowGroupOwnerId || list[i].appId)) return;
                }
            });
        }
    }
