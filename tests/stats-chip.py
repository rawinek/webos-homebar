"""The load of the TV in the status chip: the three optional parts, their texts and the boxes in the settings."""
import importlib.util, tempfile
from pathlib import Path
from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('render',ROOT/'tools/render-panel.py');rp=importlib.util.module_from_spec(spec);spec.loader.exec_module(rp)
app=QGuiApplication([])
with tempfile.TemporaryDirectory() as tmp:
 d=Path(tmp);rp.panel(d)
 main=rp.MAIN % (1920,1080)
 main=main.replace('    function glow()','''    property string result: ""
    function test() {
        shell.ready = true;
        shell.settings = shell.validSettings({lang:"en"});
        if (shell.settings.statCpu || shell.settings.statMem || shell.settings.statNet) throw Error("stats must be off by default");
        shell.stats = {ok:true, cpu:22, mem:{pct:60}, net:{down:35000, up:5089000}};
        if (shell.statsText.length !== 0) throw Error("nothing switched on, nothing shown");
        shell.settings = shell.validSettings({lang:"en", statCpu:true, statMem:true, statNet:true});
        var t = shell.statsText;
        if (t.length !== 3 || t[0] !== "CPU 22%" || t[1] !== "RAM 60%" || t[2] !== "↓ 35 kB/s  ↑ 5.1 MB/s") throw Error("texts: " + JSON.stringify(t));
        shell.settings = shell.validSettings({lang:"en", statMem:true});
        if (shell.statsText.length !== 1 || shell.statsText[0] !== "RAM 60%") throw Error("only memory");
        shell.stats = {ok:true, cpu:null, mem:{pct:60}, net:null};   // the first answer: memory only
        shell.settings = shell.validSettings({lang:"en", statCpu:true, statMem:true, statNet:true});
        if (shell.statsText.length !== 1) throw Error("rates wait for the second answer");
        shell.stats = {ok:false};
        if (shell.statsText.length !== 0) throw Error("an unreadable /proc shows nothing");
        var ids = shell.checkItems("topBar").map(function(i) { return i.id; });
        ["statCpu","statMem","statNet"].forEach(function(k) { if (ids.indexOf(k) < 0) throw Error("no box for " + k); });
        shell.settings = shell.validSettings({lang:"en"});
        shell.toggleCheck("topBar", "statCpu");
        if (shell.settings.statCpu !== true) throw Error("the box did not switch it on");
        shell.toggleCheck("topBar", "statCpu");
        if (shell.settings.statCpu !== false) throw Error("the box did not switch it off");
        shell.stats = {ok:true, cpu:22, mem:{pct:60}, net:{down:35000, up:5089000}};
        shell.settings = shell.validSettings({lang:"en", statCpu:true, statMem:true, statNet:true});
        shell.page = "home"; shell.selected = 0;
        result = "PASS";
    }
    function glow()''')
 (d/'main.qml').write_text(main)
 view=QQuickView();view.setSource(QUrl.fromLocalFile(str(d/'main.qml')))
 assert view.status()==QQuickView.Ready,view.errors()
 view.show();rp.wait(250);root=view.rootObject();root.test();assert root.property('result')=='PASS'
 rp.wait(500)
 out=ROOT/'dist/render-stats';out.mkdir(parents=True,exist_ok=True)
 view.grabWindow().save(str(out/'chip.png'))
print('PASS status chip: off by default, the three parts, memory-only first answer, boxes in the settings')
