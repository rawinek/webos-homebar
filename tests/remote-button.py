"""Settings → Remote button in Qt, with the helper's answers played in by hand:
the row only in the overlay modes, two presses of the same button to save,
reserved buttons and a different second press refused, change and unpin."""
import importlib.util, tempfile
from pathlib import Path
from PySide6.QtCore import QUrl, Qt
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('render',ROOT/'tools/render-panel.py');rp=importlib.util.module_from_spec(spec);spec.loader.exec_module(rp)
app=QGuiApplication([])
with tempfile.TemporaryDirectory() as tmp:
 d=Path(tmp);rp.panel(d)
 main=rp.MAIN % (1920,1080)
 main=main.replace('    function glow()', '''    property string result: ""
    function mode(current) {
        return {available:true,nativeSupported:true,current:current,busy:false,
            inspection:{issues:[],blockers:[],cleanup:0,owner:"lg",fingerprint:"qt",migrationAvailable:false}};
    }
    function check(ok, what) { if (!ok) throw Error(what + " | step=" + shell.buttonStep + " text=" + shell.buttonText); }
    function test() {
        shell.ready = true;
        shell.settings = shell.validSettings({lang:"pl"});
        check(shell.settingKeys.indexOf("button") < 0, "row on the Home panel");
        shell.modeInfo = mode("native");
        check(shell.settingKeys.indexOf("button") < 0, "row with System HOME");
        shell.modeInfo = mode("overlay");
        check(shell.settingKeys.indexOf("button") > shell.settingKeys.indexOf("mode"), "row in the overlay");
        shell.buttonInfo = {ok: true, mapper: "input", active: true, blocked: "", bound: []};
        shell.page = "settings"; shell.selected = shell.settingKeys.indexOf("button");
        check(shell.settingsItems[shell.selected].value === "Brak", "nothing bound");
        shell.activate(shell.settingsItems[shell.selected]);
        check(shell.buttonStep === "first", "first press asked for");
        var first = shell.buttonCapture;
        shell.buttonCaptured(first, {code: 28, name: ""});
        check(shell.buttonStep === "first" && shell.buttonText.indexOf("strzałki") >= 0 && shell.buttonCapture === first + 1, "OK refused, asked again");
        shell.buttonCaptured(first, {code: 399, name: "green"});
        check(shell.buttonStep === "first", "an abandoned answer is dropped");
        shell.buttonCaptured(shell.buttonCapture, {code: 399, name: "green"});
        check(shell.buttonStep === "second" && shell.buttonPopupText().indexOf("ZIELONY (399)") === 0, "second press asked for");
        shell.buttonCaptured(shell.buttonCapture, {code: 401, name: "blue"});
        check(shell.buttonStep === "second" && shell.buttonPopupText().indexOf("NIEBIESKI (401)") >= 0, "another button refused");
        shell.buttonCaptured(shell.buttonCapture, {code: 399, name: "green"});
        check(shell.buttonStep === "saving", "same button saves");
        shell.buttonSaved({ok: true, mapper: "input", blocked: "", bound: [{mapper: "input", key: "399", code: 399, name: "green"}]});
        check(shell.buttonStep === "done" && shell.buttonText.indexOf("ZIELONY (399)") === 0, "saved");
        check(shell.settingsItems[shell.selected].value === "ZIELONY (399)", "the row shows it");
        shell.closeButton();
        check(shell.buttonStep === "", "closed");
        shell.openButton();
        check(shell.buttonStep === "menu" && shell.buttonPopupText().indexOf("Input Hook") >= 0, "change or unpin");
        shell.buttonUnpin = true; shell.answerButtonMenu();
        check(shell.buttonStep === "unpinning", "unpinning");
        shell.buttonSaved({ok: true, mapper: "input", blocked: "", bound: []});
        check(shell.buttonStep === "done" && shell.buttonText === shell.t("button_unpinned"), "unpinned");
        shell.closeButton();
        shell.openButton(); shell.buttonCaptured(shell.buttonCapture, {code: 0, name: ""});
        check(shell.buttonStep === "done" && shell.buttonText === shell.t("button_none_seen"), "nothing pressed");
        shell.closeButton();
        shell.openButton(); shell.buttonCaptured(shell.buttonCapture, {code: 400, name: "yellow"}); shell.buttonCaptured(shell.buttonCapture, {code: 400, name: "yellow"});
        shell.buttonSaved({ok: false, error: "button_taken"});
        check(shell.buttonText === shell.t("button_taken"), "a taken button");
        shell.closeButton();
        shell.buttonInfo = {ok: true, mapper: "", blocked: "button_no_mapper", bound: []};
        shell.openButton();
        check(shell.buttonStep === "done" && shell.buttonText === shell.t("button_no_mapper"), "no mapper");
        shell.closeButton();
        shell.buttonInfo = {ok: true, mapper: "input", active: false, blocked: "", bound: []};
        shell.openButton(); shell.buttonCaptured(shell.buttonCapture, {code: 401, name: "blue"}); shell.buttonCaptured(shell.buttonCapture, {code: 401, name: "blue"});
        shell.buttonSaved({ok: true, mapper: "input", active: false, blocked: "", bound: [{mapper: "input", key: "401", code: 401, name: "blue"}]});
        check(shell.buttonText.indexOf("Input Hook nie działa") > 0, "a mapper that is not running is mentioned");
        shell.closeButton();
        shell.buttonInfo = {ok: true, mapper: "", active: false, blocked: "", bound: []};
        shell.openButton(); shell.buttonCaptured(shell.buttonCapture, {code: 1086, name: "Alexa"});
        check(shell.buttonStep === "done" && shell.buttonText.indexOf("Alexa (1086)") === 0 && shell.buttonText.indexOf("org.rawin.launcher") > 0, "no mapper: the code only");
        shell.closeButton();
        shell.buttonInfo = {ok: true, mapper: "input", active: true, blocked: "", bound: []};
        shell.foreground = true; shell.openButton(); shell.foreground = false;
        check(shell.buttonStep === "", "closing the panel ends the popup");
        shell.foreground = true;
        shell.page = "settings"; shell.selected = shell.settingKeys.indexOf("button");
        shell.openButton();
        shell.forceActiveFocus();
        result = "PASS";
    }
    function step() { return shell.buttonStep; }
    function glow()''')
 (d/'main.qml').write_text(main)
 view=QQuickView();view.setSource(QUrl.fromLocalFile(str(d/'main.qml')))
 assert view.status()==QQuickView.Ready,view.errors()
 view.show();rp.wait(250);root=view.rootObject();root.test();assert root.property('result')=='PASS'
 rp.wait(300)
 out=ROOT/'dist/render-modes';out.mkdir(parents=True,exist_ok=True)
 view.grabWindow().save(str(out/'remote-button-popup.png'))
 # A real BACK while it waits closes the popup; other keys stay inside it.
 QTest.keyClick(view,Qt.Key_Down);rp.wait(50);assert root.step()=='first'
 QTest.keyClick(view,Qt.Key_Escape);rp.wait(50);assert root.step()=='',root.step()
print('PASS remote button: overlay modes only, two presses of one button, reserved and other buttons refused, change, unpin, errors, mapper not running, code only without a mapper, panel close, BACK cancels')
