import QtQuick 2.6
import QtGraphicalEffects 1.0
import WebOSServices 1.0
import WebOS.Global 1.0
import "Config.js" as Config
import "Strings.js" as Strings
import "Themes.js" as Themes
import "About.js" as About
import "DeviceIcons.js" as DeviceIcons

FocusScope {
    id: shell
    property var hostWindow
    property bool ready: false
    property bool foreground: false
    // home, apps, system, or settings: the launcher settings menu.
    property string page: "home"
    property int selected: 0
    property bool launching: false
    property bool pressing: false
    property string message: ""
    // Every launch point the TV lists (minus the build's excluded ones).
    property var applications: Config.apps
    // Favourites are app ids; edited on the TV (hold OK) and saved by FavouriteStore.qml.
    property var favouriteIds: Config.favourites.slice(0)
    readonly property var favourites: resolveFavourites(favouriteIds, applications)
    readonly property var favouriteKeys: favourites.map(function(f) { return f.id; })
    readonly property int favCount: favourites.length
    // Rail places for favourites: one "Add favourites" tile while there are
    // none, but only once the app list is known (not while it is still loading).
    readonly property bool showAddTile: favCount === 0 && applications.length > 0
    readonly property int favSlots: favCount > 0 ? favCount : (showAddTile ? 1 : 0)
    readonly property int maxFavourites: 7
    // Hidden on the TV: apps left out of Apps (RED, shown dimmed again with
    // "showHidden" so they can come back), and inputs left off the rail
    // (switched in Launcher settings or with DOWN in their edit mode). Saved
    // as "hidden" and "hiddenInputs".
    property var hiddenIds: []
    property var hiddenInputs: []
    // How often each app was opened from here ("usage"): the Apps order "most used".
    property var usage: ({})
    // The glow colour read from each app's icon ("colors": {id: {icon, accent}}),
    // for the apps the build has no colour for. See glowReader.
    property var iconColors: ({})
    // Apps as the Apps page shows them: without the hidden ones unless asked,
    // in the TV's order, A to Z or most used first.
    readonly property var apps: appsFor(applications, hiddenIds, settings.sort, settings.showHidden)
    property int editIndex: -1
    onEditIndexChanged: pendingRemoval = ""
    // The settings menu is a large subtree, built on its first use (or in the
    // first quiet moment) so the panel itself comes up at once.
    property bool menuLoaded: false
    // The rail's sources and shortcuts are edited like favourites: hold OK or
    // YELLOW, ← → moves, two ▼ presses take it off the row.
    property int editSourceIndex: -1
    property bool editInputIcon: false
    onEditSourceIndexChanged: { editInputIcon = false; pendingRemoval = ""; }
    readonly property var iconSource: editSourceIndex >= 0 ? sources[editSourceIndex] : null
    readonly property bool inputIconsVisible: ["icon", "iconHdmi", "iconLabel", "iconCec"].indexOf(settings.inputText) >= 0
    readonly property bool inputIconOnly: settings.inputText === "icon"
    readonly property var editIconChoices: sortedIconChoices(iconSource && iconSource.kind === "tv")
    function sortedIconChoices(tv) {
        var list = (tv ? DeviceIcons.tvCatalog : DeviceIcons.catalog).slice(0);
        list.sort(function(a, b) {
            var first = a.titleKey ? t(a.titleKey) : a.title;
            var second = b.titleKey ? t(b.titleKey) : b.title;
            return first.localeCompare(second);
        });
        return list;
    }
    function sourceIcon(source) {
        return source && source.kind === "tv" ? DeviceIcons.tvIcon(settings.tvIcon).id : DeviceIcons.icon(source && settings.inputIcons[source.id]).id;
    }
    function sourceIconIndex() { return DeviceIcons.index(sourceIcon(iconSource), editIconChoices); }
    function sourceIconTitle() {
        var choice = editIconChoices[sourceIconIndex()];
        return choice.titleKey ? t(choice.titleKey) : choice.title;
    }
    function cycleInputIcon(direction) {
        if (!iconSource) return;
        var icons = editIconChoices, next = {}, id = icons[(sourceIconIndex() + direction + icons.length) % icons.length].id;
        if (iconSource.kind === "tv") { setSetting("tvIcon", id); return; }
        for (var key in settings.inputIcons) next[key] = settings.inputIcons[key];
        next[iconSource.id] = id;
        setSetting("inputIcons", next);
    }
    function iconEditorCenter() {
        // Delegates disappear briefly when settings rebuild the input model.
        // Measure the rail instead, so the popup never caches a screen-centre
        // fallback and follows row layout changes and the rail's own scale.
        if (!iconSource) return margin;
        var currentWidth = iconSource.kind === "tv" ? sourceTileWidth : pillWidthFor(iconSource, titleTwins.rev);
        var prefixWidth = sourcesWidthFor(sources.slice(0, editSourceIndex+1), titleTwins.rev);
        return rail.x + (sourceRow.x + prefixWidth-currentWidth/2)*rail.scale;
    }
    // System can be moved among the shortcuts but never removed.
    property int editActionIndex: -1
    onEditActionIndexChanged: pendingRemoval = ""
    property string pendingRemoval: ""
    readonly property string removalKey: {
        if (page !== "home" || editInputIcon) return "";
        if (editIndex >= 0 && favourites[editIndex]) return "favourite:" + favourites[editIndex].id;
        if (editSourceIndex >= 0 && sources[editSourceIndex]) return "source:" + sources[editSourceIndex].id;
        if (editActionIndex >= 0 && homeActions[editActionIndex] && homeActions[editActionIndex].action !== "system")
            return "shortcut:" + homeActions[editActionIndex].action;
        return "";
    }
    onRemovalKeyChanged: pendingRemoval = ""
    onSelectedChanged: pendingRemoval = ""
    function requestRemoval() {
        if (!removalKey) return;
        if (pendingRemoval !== removalKey) { pendingRemoval = removalKey; return; }
        pendingRemoval = "";
        if (editIndex >= 0) removeFavourite(editIndex);
        else if (editSourceIndex >= 0) hideSource(editSourceIndex);
        else if (editActionIndex >= 0) removeHomeAction(editActionIndex);
    }
    function removalTarget() {
        var loader = editIndex >= 0 ? favouriteCells.itemAt(editIndex) : editSourceIndex >= 0 ? sourceCells.itemAt(editSourceIndex) : editActionIndex >= 0 ? shortcutCells.itemAt(editActionIndex) : null;
        return loader ? loader.item : null;
    }
    property string notice: ""
    property bool okHeld: false
    property bool longFired: false
    // The sources on the rail: Live TV and every input the TV has, in the
    // saved order and each with whether it is on the row. The rail, the
    // navigation and the settings menu's switches all follow these lists.
    // A hidden source keeps its place in sourceOrder, so switching it back on
    // puts it where it was. The inputs are the ones the TV listed.
    property var allInputs: Config.inputs
    readonly property var allSources: allSourcesFor(allInputs, hiddenInputs, settings)
    readonly property var sources: allSources.filter(function(s) { return !s.hidden; })
    readonly property int sourceCount: sources.length
    readonly property var inputs: allInputs.filter(function(d) { return hiddenInputs.indexOf(d.id) < 0; })
    // Preview a physical input, including a hidden one if none is on the row.
    // TV has its own appearance and its default text has no image asset.
    readonly property var previewSource: {
        var list = inputs.length ? inputs : allInputs;
        for (var i=0; i<list.length; i++) if (list[i].name) return list[i];
        return list.length ? list[0] : {title: "", name: ""};
    }
    // The moment the clock shows (tick() moves it on the minute) and the
    // clock itself, in the setting's format: 24-hour or 12-hour.
    property var nowTime: new Date()
    readonly property string clock: Qt.formatTime(nowTime, settings.hours === "12" ? "h:mm AP" : "hh:mm")
    property string nowTitle: ""
    // Launcher settings, saved with the favourites (key "settings").
    // lang: "system" or a code from Strings.languages; theme: an id from
    // Themes.ids; size: the text size; motion: animations; sort: the Apps
    // order; tv: Live TV on the rail; sourceOrder: the order of Live TV and
    // the inputs on the rail; inputText: what an input's pill shows ("hdmiLabel"
    // is "HDMI 2" over the label, "label", "hdmi" or "labelHdmi");
    // inputHeading: "hdmi", "label" or "cec" for the name above favourites;
    // inputOverflow: "ellipsis" or "scroll" for a name wider than the pill;
    // showHidden: hidden apps shown dimmed; exitTo
    // (overlay only, sent to the helper): "last"
    // or an input app id; clock, nowApp and weather: what the chip at the top
    // shows (the time, what is on screen, the weather); hours: the clock's
    // format, "24" or "12"; units: the temperature's, "auto" (by the TV's
    // region), "c" or "f"; title: the big name of the focused app on Home and
    // Apps; hints: the key hints on the bottom line; timeout: seconds without
    // input before closing (zero is off); beta: updates also offer test builds
    // (GitHub pre-releases).
    property var settings: validSettings({})
    property string systemLang: ""
    readonly property string units: settings.units === "auto" ? (/[-_]US$/i.test(systemLang) ? "f" : "c") : settings.units
    // The weather in the chip, from the setup server (shared/setup.js on port
    // 8898, the same in both variants): standard temp and apparent temp, WMO
    // code and day flag. Asked each time
    // Home opens and every quarter of an hour while it is open; the server
    // keeps an answer for a quarter of an hour too.
    property var weather: ({ok: false})
    // The load of the TV in the chip (Launcher settings → Top bar → Items), from
    // the setup server's /stats, asked every two seconds while Home is up. Each
    // part is off until switched on. The server sends the rates as bytes per second.
    property var stats: ({ok: false})
    readonly property bool anyStats: settings.statCpu === true || settings.statMem === true || settings.statNet === true
    function rateText(bytesPerSecond) {
        var k = bytesPerSecond / 1000;
        return k >= 1000 ? (k / 1000).toFixed(1) + " MB/s" : Math.round(k) + " kB/s";
    }
    function statsParts() {
        var parts = [];
        if (stats.ok !== true) return parts;
        if (settings.statCpu === true && typeof stats.cpu === "number") parts.push("CPU " + stats.cpu + "%");
        if (settings.statMem === true && stats.mem) parts.push("RAM " + stats.mem.pct + "%");
        if (settings.statNet === true && stats.net) parts.push("↓ " + rateText(stats.net.down) + "  ↑ " + rateText(stats.net.up));
        return parts;
    }
    readonly property var statsText: statsParts()
    readonly property bool weatherShown: settings.weather && weather.ok === true
    // Older cached answers have no apparent value; show the standard reading
    // until the next refresh rather than leaving the chip blank.
    readonly property int weatherTemp: settings.temperature === "apparent" && typeof weather.apparent === "number" ? weather.apparent : (typeof weather.temp === "number" ? weather.temp : 0)
    // The page to choose the weather's place on a phone: its address, the
    // same as a QR code (rows of "1" and "0"), the place now, and rev, which
    // the server counts up at each change of the place.
    property var setupInfo: ({url: "", qr: null, place: null, rev: -1})
    // The updater (Launcher settings → Updates): idle, checking, current,
    // available, downloading, ready, installing, done or failed; latest is the
    // version found, failed the text key of the failed step.
    property var updateInfo: ({state: "idle", latest: "", failed: ""})
    readonly property bool updateAvailable: updateInfo.state === "available"
    property real lastUpdateCheck: 0
    // The backup file next to the installed launcher: when it was saved.
    property var backupInfo: ({saved: ""})
    readonly property string lang: settings.lang && settings.lang !== "system" ? settings.lang : (Strings.supported(systemLang) || "en")
    // LG's own Home can be opened: always with the panel inside it; from the
    // overlay only when it was kept (the helper says so, see panel-bridge.qml).
    readonly property bool memoryOptimizerAvailable: Config.memoryOptimizer !== false
    property bool stockHomeAvailable: Config.stockHome !== false
    readonly property var tools: toolsFor(lang, applications, stockHomeAvailable)
    // Shortcuts after the inputs: the close-apps action, Apps and
    // System, in the saved order. System cannot be hidden, so the way into
    // the launcher's own settings and Apps is always on the row.
    readonly property var homeActions: homeActionsFor(settings)
    // The settings menu: the settings in groups, each a key; the rows the
    // menu shows (a group's name, then its settings); the focused one's
    // values. pane 0 is the list of settings, pane 1 their values. The
    // keys and the values do not depend on the settings themselves, so
    // choosing a value does not rebuild the menu around it.
    property var modeInfo: ({available: false, nativeSupported: false, current: "legacy", busy: false})
    property string modeConfirm: ""
    property string modeConfirmFingerprint: ""
    // The Yes/No popup of a mode change opens on No. modeDoneAt is the stamp of a
    // finished switch the user has not yet been told about (settings.modeAck).
    property bool modeConfirmYes: false
    property real modeDoneAt: 0
    property bool modeDoneOk: true
    property string modeError: ""
    property string launchLastWarning: ""
    property real modeDetailsOffset: 0
    signal modeDetailsScroll(int direction)
    signal launchCheckRequested()
    // Settings → Remote button (the overlay modes): what the helper says opens
    // Homebar besides HOME, and the popup's step: "menu" (change or unpin),
    // "first" and "second" (waiting for a press, read by the helper), "saving"
    // and "unpinning", then "done" with buttonText to read. buttonCapture
    // numbers the presses asked for: an answer to an abandoned one is dropped.
    property var buttonInfo: ({ok: false, bound: [], mapper: "", blocked: ""})
    property string buttonStep: ""
    property int buttonCode: 0
    property string buttonName: ""
    property string buttonText: ""
    property bool buttonUnpin: false
    property int buttonCapture: 0
    readonly property var settingGroups: groupsFor(Config.exitTarget, modeInfo.available, modeInfo.available && modeInfo.current !== "native")
    readonly property var settingKeys: keysOf(settingGroups)
    readonly property var menuRows: rowsOf(settingGroups, lang)
    readonly property var settingsItems: settingKeys.map(function(k) { return settingFor(k); })
    // Pointer preview is independent of the open section (selected). Crossing
    // another row on the way to its values must not replace the right pane.
    property int menuHover: -1
    // Unlike valueIndex, this visual preview must never call applyValue().
    property int valueHover: -1
    property int pane: 0
    property int valueIndex: 0
    readonly property string valueKey: page === "settings" && selected < settingKeys.length ? settingKeys[selected] : ""
    readonly property var valueOptions: valueKey ? (valueToggles ? checkItems(valueKey) : optionsFor(valueKey, lang, allInputs)) : []
    // Three rows are lists of switches, not one value: moving along one only
    // chooses, OK (or a click) switches that item. "sources": Live TV and
    // every input; "homeShortcuts": the tiles after them; "topBar": what the
    // chip in the corner shows.
    readonly property bool valueToggles: valueTogglesFor(valueKey)
    function valueTogglesFor(key) { return key === "sources" || key === "homeShortcuts" || key === "topBar"; }
    function valueOn(id) {
        if (valueKey === "mode") return modeInfo.current === id;
        if (!valueToggles) return settings[valueKey] === id;
        for (var i=0; i<valueOptions.length; i++) if (valueOptions[i].id === id) return valueOptions[i].on === true;
        return false;
    }
    // The switches of one such row, in the order the panel shows them.
    function checkItems(key) {
        var list = [], i;
        if (key === "sources") {
            for (i=0; i<allSources.length; i++)
                list.push({id: allSources[i].id, title: allSources[i].title + (allSources[i].detail ? " · " + allSources[i].detail : ""),
                           on: !allSources[i].hidden});
        } else if (key === "homeShortcuts") {
            list.push({id: "closeApps", title: t("close_apps_title"), on: settings.homeCloseApps === true});
            list.push({id: "apps", title: t("apps_title"), on: settings.homeApps !== false});
        } else if (key === "topBar") {
            list.push({id: "clock", title: t("set_clock"), on: settings.clock !== false});
            list.push({id: "nowApp", title: t("set_now_app"), on: settings.nowApp !== false});
            list.push({id: "weather", title: t("set_weather"), on: settings.weather !== false});
            list.push({id: "statCpu", title: t("set_stat_cpu"), on: settings.statCpu === true});
            list.push({id: "statMem", title: t("set_stat_mem"), on: settings.statMem === true});
            list.push({id: "statNet", title: t("set_stat_net"), on: settings.statNet === true});
        }
        return list;
    }
    function toggleCheck(key, id) {
        if (key === "sources") {
            if (id === "tv") setSetting("tv", settings.tv !== true);
            else toggleHiddenInput(id);
        } else if (key === "homeShortcuts") {
            if (id === "closeApps") setSetting("homeCloseApps", settings.homeCloseApps !== true);
            else setSetting("homeApps", settings.homeApps === false);
        } else if (key === "topBar") {
            setSetting(id, settings[id] === false);
        }
    }
    // In place of the favourites while there are none: OK opens Apps.
    readonly property var addFavouritesTile: ({title: t("add_favs_title"), action: "apps", symbol: "add"})
    signal stockRequested()
    signal closeRequested()
    // Unlike BACK, a timeout hides only the Homebar surface. Its host keeps
    // the Home card (and therefore the Magic Remote pointer) alive.
    signal timeoutRequested()
    signal exitTargetChosen(string target)

    // Spotlight B2: the focused item is named above a rail of rounded tiles,
    // its colour lights the bottom-left edge, the picture stays visible.
    // Colours come from the theme (Launcher settings → Theme, see Themes.js).
    readonly property var theme: Themes.palette(settings.theme)
    readonly property string ink: theme.ink
    readonly property string ink2: theme.ink2
    readonly property string ink3: theme.ink3
    readonly property string surface: theme.surface   // chips over the picture (status)
    readonly property string chip: theme.chip         // tiles and pills: solid, so nothing shows through
    readonly property string chipEdge: theme.chipEdge
    readonly property string neutral: theme.neutral
    readonly property string warning: theme.warning
    readonly property string fontName: inter.status === FontLoader.Ready ? inter.name : medium.name
    // The layout is drawn for 1920×1080 and scaled to the panel's real size:
    // the TV's UI runs at 1280×720 on HD sets and at 1920×1080 on FHD and UHD
    // ones (the TV scales it up to the panel). u is that scale; every length
    // below goes through px(). Positions hang from the bottom and the right
    // edge, so a wider screen simply gets a longer rail and more columns.
    // Text goes through pt(), which also takes the text size setting: the
    // tiles and pills keep their size (the rail is full with seven
    // favourites), the words on and around them grow.
    readonly property real u: width > 0 && height > 0 ? Math.min(width / 1920, height / 1080) : 1
    readonly property real textZoom: settings.size === "larger" ? 1.4 : settings.size === "large" ? 1.2 : 1
    function px(v) { return Math.round(v * u); }
    function pt(v) { return Math.round(v * u * textZoom); }
    // Animation lengths, or none with the setting "motion" off.
    function dur(ms) { return settings.motion === false ? 0 : ms; }
    readonly property int margin: px(96)
    readonly property int tile: px(120)
    readonly property int gap: px(24)
    readonly property int appColumns: Math.max(4, Math.floor((width - 2*margin + gap) / (tile + gap)))
    readonly property int railY: height - px(192)
    // The Home rail reserves room for inputs and shortcuts first. Every input
    // pill fits its own two lines up to 200 px; favourites then take what
    // is left, so seven favourites plus Live TV and every enabled shortcut
    // stay inside both screen margins. The widths come from hidden twins, not TextMetrics,
    // because the TV misses text-size changes (see the panel's rule).
    readonly property int railGroupGap: px(32)
    readonly property int sourceGap: px(12)
    readonly property int sourceMinWidth: px(64)
    // Live TV is a tile as big as a shortcut, not a pill: "TV" needs no width.
    readonly property int sourceTileWidth: px(64)
    readonly property int sourcePills: sources.filter(function(s) { return s.kind !== "tv"; }).length
    readonly property int sourcesWidth: sourcesWidthFor(sources, titleTwins.rev)
    readonly property int actionWidth: homeActions.length > 0 ? homeActions.length*px(64) + Math.max(0, homeActions.length-1)*sourceGap : 0
    readonly property int railGroups: (favSlots > 0 ? 1 : 0) + (sourceCount > 0 ? 1 : 0) + (homeActions.length > 0 ? 1 : 0)
    function pillWidthFor(source, rev) {
        // The hidden twins measure both lines independently of the pill's
        // width. rev keeps bindings alive when fonts or text sizes change.
        for (var i=0; i<sourceTwins.count; i++) {
            var twin = sourceTwins.itemAt(i);
            if (twin && source && twin.sourceId === source.id) return twin.pillWidth;
        }
        return sourceMinWidth;
    }
    function sourcesWidthFor(list, rev) {
        var total = Math.max(0, list.length-1)*sourceGap;
        for (var i=0; i<list.length; i++)
            total += list[i].kind === "tv" ? sourceTileWidth : pillWidthFor(list[i], rev);
        return total;
    }
    readonly property int favouriteRoom: width - 2*margin - actionWidth - sourcesWidth - Math.max(0, railGroups-1)*railGroupGap
    readonly property int favouriteTile: favSlots > 0 ? Math.max(px(48), Math.min(tile, Math.floor((favouriteRoom + gap) / favSlots) - gap)) : tile
    readonly property int favsWidth: favSlots > 0 ? favSlots*(favouriteTile + gap) - gap : 0
    // The name sits just above the tiles; a line under it (editing help, a
    // message) lifts it by one line. Without the name (setting "title",
    // Home and Apps only) a line under it still shows, just above the tiles.
    // On Home the favourite tiles are centred in a band as tall as a full
    // tile, so when the rail squeezes them (longer pills or more shortcuts on
    // the right) their top edge moves down: the name follows by that much and
    // keeps the same distance to the icons.
    readonly property bool showTitle: settings.title !== false || page === "system"
    readonly property int favouriteLift: page === "home" ? Math.round((tile - favouriteTile)/2) : 0
    readonly property int heroBaseline: height - (page === "apps" ? px(380) : px(238) - favouriteLift) - (showTitle ? (hero.sub ? pt(36) : 0) : px(20))
    readonly property var hero: heroFor(page, selected, apps, favourites, editIndex, launching, message, notice, tools, sources, iconColors)
    readonly property var hints: hintsFor(page, selected, favouriteKeys, editIndex, lang, updateInfo, pane, valueIndex, hiddenInputs)
    // The remote's colour keys, as the hints show them (the same in every theme).
    readonly property color keyRed: "#d83a3f"
    readonly property color keyYellow: "#f2c230"
    property color glowColor: hero.color
    Behavior on glowColor { ColorAnimation { duration: shell.dur(300) } }

    function closeHome() { closeRequested(); }
    // The timeout deliberately counts only actual input. Qt can send hover
    // events for a pointer that has not moved, so pointerMoved() calls this
    // only after its coordinate check; keys, clicks and wheel scrolls call it
    // directly. Zero keeps the feature off.
    function noteActivity() {
        if (settings.timeout > 0 && foreground && visible && page !== "settings") inactivityTimer.restart();
    }
    onSettingsChanged: noteActivity()
    Timer {
        id: inactivityTimer
        repeat: false
        interval: Math.max(1, settings.timeout) * 1000
        onTriggered: {
            if (settings.timeout > 0 && foreground && visible && page !== "settings" && !okHeld)
                timeoutRequested();
        }
    }
    // Qt sends hover when an item appears or moves under a resting pointer.
    // Compare window coordinates, so a tile's lift/scale cannot move focus.
    // The first event after opening only records where the pointer is.
    property point pointerAt: Qt.point(-1, -1)
    property real pointerBlockedUntil: 0
    function pointerMoved(item, mouse) {
        var p = item.mapToItem(null, mouse.x, mouse.y), first = pointerAt.x < 0;
        var moved = !first && (Math.abs(p.x - pointerAt.x) > 2 || Math.abs(p.y - pointerAt.y) > 2);
        pointerAt = Qt.point(p.x, p.y);
        if (moved) noteActivity();
        // Keys can hide the Magic Remote cursor. Keep their focus even if Qt
        // delivers hover during that transition; a held OK keeps its target.
        return moved && foreground && visible && Date.now() >= pointerBlockedUntil && !okHeld && editIndex < 0 && editSourceIndex < 0 && editActionIndex < 0;
    }

    FontLoader { id: inter; source: "file:///var/lib/webosbrew/rawin-launcher/current/fonts/Inter-Regular.ttf" }
    FontLoader { id: interBold; source: "file:///var/lib/webosbrew/rawin-launcher/current/fonts/Inter-Bold.ttf" }
    FontLoader { id: medium; source: "file:///usr/share/fonts/MuseoSans-Medium.ttf" }

    function t(key) { return Strings.get(lang, key); }
    // Whether two lists hold the same things: the app and input lists are read
    // again each time Home opens, and only a changed list replaces the old
    // one, so the tiles are not torn down and built again for nothing.
    function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
    function installed(id, apps) {
        for (var i=0; i<apps.length; i++) if (apps[i].id === id) return true;
        return false;
    }
    function appById(id) {
        for (var i=0; i<applications.length; i++) if (applications[i].id === id) return applications[i];
        return null;
    }
    function toolsFor(language, apps, stockHome) {
        var list = [
            {title: t("tv_settings"), id: "com.palm.app.settings", symbol: "settings"},
            {title: t("launcher_settings"), action: "launcherSettings", symbol: "tune"},
            {title: "PicCap", id: "org.webosbrew.piccap", symbol: "light", optional: true},
            {title: "Homebrew Channel", id: "org.webosbrew.hbchannel", symbol: "plus"},
            {title: "LG Content Store", id: "com.webos.app.discovery", symbol: "bag"},
            {title: t("stock_home"), action: "stock", symbol: "home", stock: true},
            {title: t("back_to_picture"), action: "close", symbol: "back"}
        ];
        // PicCap only where it is installed; LG's Home only where it is reachable.
        return list.filter(function(x) {
            return !(x.optional && !installed(x.id, apps)) && !(x.stock && !stockHome);
        });
    }
    // What a source's pill shows, independently of the heading above the row, in the
    // setting's arrangement: the port's title ("HDMI 2"), the label set on
    // the TV, or the HDMI-CEC name. The label modes fall back to the CEC name
    // when no label is set, the CEC modes to the label when the device is
    // silent; the port is always the last fallback. See Input appearance.
    function inputTexts(source) {
        var mode = settings.inputText || "hdmiLabel";
        var title = source ? source.title : "";
        var label = source ? (source.label || source.cec || "") : "";
        var cec = source ? (source.cec || source.label || "") : "";
        if (mode === "icon" || mode === "iconHdmi") return inputPair(title, "", title);
        if (mode === "iconLabel") return inputPair(label, "", title);
        if (mode === "iconCec") return inputPair(cec, "", title);
        if (mode === "hdmi") return inputPair(title, "", title);
        if (mode === "label") return inputPair(label, "", title);
        if (mode === "cec") return inputPair(cec, "", title);
        if (mode === "labelHdmi") return inputPair(label, title, title);
        if (mode === "cecHdmi") return inputPair(cec, title, title);
        if (mode === "hdmiCec") return inputPair(title, cec, title);
        return inputPair(title, label, title);   // hdmiLabel
    }
    // The large input heading has its own choice, even for icon-only tiles.
    function sourceHeading(source) {
        if (!source) return "";
        if (source.kind === "tv") return source.title;
        if (settings.inputHeading === "label") return source.label || source.cec || source.title;
        if (settings.inputHeading === "cec") return source.cec || source.label || source.title;
        return source.title;
    }
    function inputPair(first, second, title) {
        var primary = first || title;
        return {primary: primary, secondary: second && second !== primary ? second : ""};
    }
    function homeActionOrderFor(value) {
        // 0.16.1 stored the two optional shortcuts as a string. Keep that
        // preference, then save the editable form as an array of action ids:
        // the two optional ones and system, whose place can change too.
        if (value === "appsClose") value = ["apps", "closeApps"];
        else if (value === "closeApps") value = ["closeApps", "apps"];
        var out = [], allowed = ["closeApps", "apps", "system"], i;
        if (value && value.length !== undefined) for (i=0; i<value.length; i++)
            if (allowed.indexOf(value[i]) >= 0 && out.indexOf(value[i]) < 0) out.push(value[i]);
        for (i=0; i<allowed.length; i++) if (out.indexOf(allowed[i]) < 0) out.push(allowed[i]);
        return out;
    }
    // The saved order of the sources ("tv", then input ids), kept as given:
    // ids the TV no longer lists are ignored when the row is built, and new
    // ones go to the end.
    function sourceOrderFor(value) {
        if (!value || value.length === undefined) return [];
        var out = [];
        for (var i=0; i<value.length; i++)
            if (typeof value[i] === "string" && out.indexOf(value[i]) < 0) out.push(value[i]);
        return out;
    }
    function homeActionsFor(s) {
        var list = [], order = homeActionOrderFor(s.homeActionOrder);
        for (var i=0; i<order.length; i++) {
            if (order[i] === "apps" && s.homeApps !== false)
                list.push({title: t("apps_title"), action: "apps", symbol: "apps"});
            else if (order[i] === "closeApps" && s.homeCloseApps === true)
                list.push({title: t(memoryOptimizerAvailable && s.closeAppsMode === "memory" ? "val_close_memory" : "val_close_apps"), action: "closeApps", symbol: "clean"});
            else if (order[i] === "system")
                list.push({title: t("system_title"), action: "system", symbol: "settings"});
        }
        return list;
    }
    function homeActionIndex(action) {
        for (var i=0; i<homeActions.length; i++) if (homeActions[i].action === action) return i;
        return 0;
    }
    // The settings menu's groups: a name and the settings in it. About comes
    // first, so it is what the menu opens on. The BACK-hold target is the
    // overlay's alone, and so is the remote button, outside System HOME.
    function groupsFor(exitTarget, modes, button) {
        return [
            {title: "grp_about", keys: ["about"]},
            {title: "grp_look", keys: ["lang", "theme", "size", "motion"]},
            // Live TV is switched with the inputs, so the row stays one list.
            {title: "grp_home", keys: exitTarget ? ["sources", "inputText", "inputHeading", "inputOverflow", "homeShortcuts", "closeAppsMode", "exitTo"] : ["sources", "inputText", "inputHeading", "inputOverflow", "homeShortcuts", "closeAppsMode"]},
            {title: "grp_apps", keys: ["sort", "showHidden"]},
            {title: "grp_bar", keys: ["topBar", "hours", "place", "units", "temperature"]},
            {title: "grp_screen", keys: ["title", "hints", "timeout"]},
            {title: "grp_backup", keys: ["backup", "restore"]},
            {title: "grp_updates", keys: ["update", "beta"]},
            {title: "grp_support", keys: modes ? (button ? ["mode", "button", "restart"] : ["mode", "restart"]) : ["restart"]}
        ];
    }
    function keysOf(groups) {
        var out = [];
        for (var i=0; i<groups.length; i++) out = out.concat(groups[i].keys);
        return out;
    }
    // The menu's rows: {header: name} before each group, {key, index} for
    // each setting; index counts the settings alone, as selected does.
    function rowsOf(groups, language) {
        var out = [], n = 0;
        for (var i=0; i<groups.length; i++) {
            out.push({header: t(groups[i].title)});
            for (var j=0; j<groups[i].keys.length; j++) out.push({key: groups[i].keys[j], index: n++});
        }
        return out;
    }
    // One setting as the menu shows it: its name, its value's name (or an
    // action's status), and what OK does with it.
    function settingFor(key) {
        var names = {lang: "set_language", theme: "set_theme", size: "set_size", motion: "set_motion", sort: "set_sort",
                     showHidden: "set_hidden", exitTo: "set_exit", hours: "set_hours", title: "set_title", backup: "set_backup",
                     restore: "set_restore", update: "set_update", beta: "set_beta",
                     place: "set_place", units: "set_units", temperature: "set_temperature", about: "set_about", hints: "set_hints",
                     mode: "set_mode", timeout: "set_timeout", restart: "set_restart_homebar",
                     sources: "set_sources", inputText: "set_input_text", inputHeading: "set_input_heading", inputOverflow: "set_input_overflow", homeShortcuts: "set_home_shortcuts",
                     closeAppsMode: "set_close_apps_mode", button: "set_button",
                     topBar: "set_topbar"};
        var item = {key: key, title: t(names[key]), action: "setting", value: ""};
        if (key === "backup" || key === "restore") {
            item.action = key;
            // The day and the time, in the clock's format: short enough for the row.
            item.value = backupInfo.saved ? Strings.format(t("bak_saved"), {date: Qt.formatDateTime(new Date(backupInfo.saved), "d MMM " + (settings.hours === "12" ? "h:mm AP" : "hh:mm"))}) : t("bak_none");
        } else if (key === "update") {
            item.action = "update";
            item.value = updateText(updateInfo);
        } else if (key === "about") {
            item.action = "about";
            item.value = Strings.format(t("upd_idle"), {version: Config.version});
        } else if (key === "restart") {
            item.action = "restart";
            item.value = t("restart_sub");
        } else if (key === "button") {
            item.action = "button";
            item.value = buttonValue(buttonInfo);
        } else if (key === "place") {
            item.action = "place";
            item.value = placeText(setupInfo);
        } else item.value = valueTitle(key);
        return item;
    }
    function inputTitle(id) {
        for (var i=0; i<allInputs.length; i++) if (allInputs[i].id === id) return allInputs[i].title;
        return "HDMI " + id.slice(-1);
    }
    // The values of a setting, in the order the menu shows them. The BACK
    // target uses every physical input, including those hidden on the rail.
    function optionsFor(key, language, inputList) {
        var list = [], i;
        if (key === "mode") {
            if (modeInfo.nativeSupported) list.push({id: "native", title: t("val_mode_native")});
            list.push({id: "overlay", title: t("val_mode_overlay")});
        } else if (key === "lang") {
            list.push({id: "system", title: Strings.format(t("val_system"), {lang: Strings.names[Strings.supported(systemLang) || "en"]})});
            for (i=0; i<Strings.languages.length; i++) list.push({id: Strings.languages[i], title: Strings.names[Strings.languages[i]]});
        } else if (key === "theme") {
            for (i=0; i<Themes.ids.length; i++) list.push({id: Themes.ids[i], title: t("theme_" + Themes.ids[i])});
        } else if (key === "size") {
            list = [{id: "normal", title: t("val_size_normal")}, {id: "large", title: t("val_size_large")}, {id: "larger", title: t("val_size_larger")}];
        } else if (key === "sort") {
            list = [{id: "lg", title: t("val_sort_lg")}, {id: "az", title: t("val_sort_az")}, {id: "used", title: t("val_sort_used")}];
        } else if (key === "showHidden") {
            list = [{id: false, title: t("val_hidden_hide")}, {id: true, title: t("val_hidden_show")}];
        } else if (key === "closeAppsMode") {
            list = [{id: "apps", title: t("val_close_apps")}];
            if (memoryOptimizerAvailable) list.push({id: "memory", title: t("val_close_memory")});
        } else if (key === "exitTo") {
            list.push({id: "last", title: t("val_last_input")});
            list.push({id: "com.webos.app.livetv", title: t("live_tv")});
            for (i=0; i<inputList.length; i++) list.push({id: inputList[i].id, title: inputList[i].title});
            list.push({id: "none", title: t("val_exit_none")});
        } else if (key === "hints") {
            list = [{id: true, title: t("val_chip_on")}, {id: false, title: t("val_chip_off")}];
        } else if (key === "inputText") {
            // The three "only" values first, CEC straight under HDMI, then the
            // pairs. The default is "hdmiLabel": exactly what the panel did
            // before this choice existed, so an update changes nothing.
            list = [{id: "label", title: t("val_input_label")}, {id: "hdmi", title: t("val_input_hdmi")},
                    {id: "cec", title: t("val_input_cec")},
                    {id: "labelHdmi", title: t("val_input_label_hdmi")}, {id: "hdmiLabel", title: t("val_input_hdmi_label")},
                    {id: "cecHdmi", title: t("val_input_cec_hdmi")}, {id: "hdmiCec", title: t("val_input_hdmi_cec")},
                    {id: "icon", title: t("val_input_icon")}, {id: "iconHdmi", title: t("val_input_icon_hdmi")},
                    {id: "iconLabel", title: t("val_input_icon_label")}, {id: "iconCec", title: t("val_input_icon_cec")}];
        } else if (key === "inputHeading") {
            list = [{id: "hdmi", title: t("val_heading_hdmi")}, {id: "label", title: t("val_heading_label")},
                    {id: "cec", title: t("val_heading_cec")}];
        } else if (key === "inputOverflow") {
            list = [{id: "ellipsis", title: t("val_input_ellipsis")}, {id: "scroll", title: t("val_input_scroll")}];
        } else if (key === "units") {
            list = [{id: "auto", title: Strings.format(t("val_units_auto"), {unit: /[-_]US$/i.test(systemLang) ? "°F" : "°C"})},
                    {id: "c", title: t("val_units_c")}, {id: "f", title: t("val_units_f")}];
        } else if (key === "temperature") {
            list = [{id: "standard", title: t("val_temperature_standard")}, {id: "apparent", title: t("val_temperature_apparent")}];
        } else if (key === "timeout") {
            list = [{id: 0, title: t("val_timeout_off")}];
            for (i=0; i<[3, 5, 10, 15, 20, 30, 45, 60].length; i++) {
                var seconds = [3, 5, 10, 15, 20, 30, 45, 60][i];
                list.push({id: seconds, title: Strings.format(t("val_timeout_seconds"), {seconds: seconds})});
            }
        } else if (key === "hours") {
            list = [{id: "24", title: t("val_hours_24")}, {id: "12", title: t("val_hours_12")}];
        } else if (key === "title") {
            list = [{id: true, title: t("val_name_show")}, {id: false, title: t("val_name_hide")}];
        } else if (key === "motion" || key === "beta") {
            list = [{id: true, title: t("val_on")}, {id: false, title: t("val_off")}];
        }
        return list;
    }
    function valueTitle(key) {
        if (key === "mode") return t("val_mode_" + modeInfo.current);
        // A list of switches says how many of its items are on ("3/5").
        if (valueTogglesFor(key)) {
            var items = checkItems(key), on = items.filter(function(c) { return c.on === true; }).length;
            return on + "/" + items.length;
        }
        var o = optionsFor(key, lang, allInputs);
        for (var i=0; i<o.length; i++) if (o[i].id === settings[key]) return o[i].title;
        return "";
    }
    function updateText(u) {
        var v = {version: u.latest};
        if (u.state === "checking") return t("upd_checking");
        if (u.state === "current") return Strings.format(t("upd_current"), {version: Config.version});
        if (u.state === "available") return Strings.format(t("upd_available"), v);
        if (u.state === "downloading") return Strings.format(t("upd_downloading"), v);
        if (u.state === "ready") return Strings.format(t("upd_ready"), v);
        if (u.state === "installing") return Strings.format(t("upd_installing"), v);
        if (u.state === "done") return t("upd_done");
        if (u.state === "failed") return t(u.failed);
        return Strings.format(t("upd_idle"), {version: Config.version});
    }
    // The weather's place for its row: the one chosen on a phone, or the one
    // the TV's internet address points to.
    function placeText(info) {
        var p = info.place;
        if (!p || !p.name) return t("place_unknown");
        return p.auto ? Strings.format(t("place_auto"), {name: p.name}) : p.name;
    }
    // The release notes as the menu shows them: update.sh leaves plain text
    // with "### " before a heading, which is set in bold here.
    function notesText(notes) {
        return String(notes || "").split("\n").map(function(line) {
            var x = line.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
            return /^### /.test(x) ? "<b>" + x.slice(4) + "</b>" : x;
        }).join("<br>");
    }
    // What OK does on an action row: the verb for the hint, or nothing yet.
    function actionVerb(key) {
        if (key === "backup") return t("hint_backup");
        if (key === "restore") return backupInfo.saved ? t("hint_restore") : "";
        if (key === "restart") return t("hint_restart");
        if (key === "button") return t("hint_change");
        if (key === "update") {
            var s = updateInfo.state;
            return s === "available" ? t("hint_download") : s === "ready" ? t("hint_install")
                : ["idle", "current", "failed"].indexOf(s) >= 0 ? t("hint_check") : "";
        }
        return "";
    }
    // OK on Updates: check, download what was found, install what was downloaded.
    function updateAction() {
        var s = updateInfo.state;
        if (s === "available") updateStep("download");
        else if (s === "ready") updateStep("install");
        else if (s === "idle" || s === "current" || s === "failed") updateStep("check");
    }
    function isUpdateIdle() {
        return ["checking", "downloading", "installing", "done"].indexOf(updateInfo.state) < 0;
    }
    function updateStep(step) {
        var busy = {check: "checking", download: "downloading", install: "installing"}[step];
        if (busy) setUpdate({state: busy});
        updateRun(step, settings.beta ? "test" : "stable");
    }
    function setUpdate(change) {
        var next = {}, k;
        for (k in updateInfo) next[k] = updateInfo[k];
        for (k in change) next[k] = change[k];
        updateInfo = next;
    }
    // The answer of one update.sh step (null: no answer).
    function updateResult(step, r) {
        var ok = !!(r && r.ok);
        if (step === "check") setUpdate(ok ? {state: r.newer ? "available" : "current", latest: r.latest, notes: r.notes || ""} : {state: "failed", failed: "upd_err_check"});
        else if (step === "download") setUpdate(ok ? {state: "ready"} : {state: "failed", failed: "upd_err_download"});
        else if (step === "install") {
            if (ok) installPoll.restart();
            else setUpdate({state: "failed", failed: "upd_err_install"});
        } else if (step === "status" && ok) {
            // On success the installer restarts the launcher, which ends this
            // panel; "done" shows only if it is still here.
            if (r.state === "failed") { installPoll.stop(); setUpdate({state: "failed", failed: "upd_err_install"}); }
            else if (r.state === "done") { installPoll.stop(); setUpdate({state: "done"}); }
        }
    }
    Timer { id: installPoll; interval: 2000; repeat: true; onTriggered: updateRun("status", "stable") }
    // Once a day, the first time Home opens: is there a new version? A dot
    // on System and on Launcher settings says so (updateAvailable).
    function dailyUpdateCheck() {
        if (!isUpdateIdle() || Date.now() - lastUpdateCheck < 86400000) return;
        lastUpdateCheck = Date.now();
        updateStep("check");
    }
    // One setting to a value; the change applies at once.
    function setSetting(key, value) {
        if (settings[key] === value) return;
        var next = {};
        for (var k in settings) next[k] = settings[k];
        next[key] = value;
        settings = next;
        saveSettings();
        if (key === "exitTo") exitTargetChosen(value);
        if (key === "beta" && isUpdateIdle()) updateStep("check");
        if (key === "weather" && value) loadWeather();
        if ((key === "statCpu" || key === "statMem" || key === "statNet") && value) loadStats();
        if (key === "timeout") noteActivity();
    }
    // The settings as saved, each checked, with the defaults for the rest.
    function validSettings(s) {
        s = s && typeof s === "object" ? s : {};
        return {
            lang: s.lang === "system" || Strings.languages.indexOf(s.lang) >= 0 ? s.lang : "system",
            theme: Themes.ids.indexOf(s.theme) >= 0 ? s.theme : "default",
            size: ["normal", "large", "larger"].indexOf(s.size) >= 0 ? s.size : "normal",
            motion: s.motion !== false,
            sort: ["lg", "az", "used"].indexOf(s.sort) >= 0 ? s.sort : "lg",
            tv: s.tv === true,
            sourceOrder: sourceOrderFor(s.sourceOrder),
            // What an input's pill shows: the port, its label, or both.
            // No key (an install from before the setting) keeps the old
            // look: "HDMI 2" big, the label or CEC name under it.
            inputHeading: ["hdmi", "label", "cec"].indexOf(s.inputHeading) >= 0 ? s.inputHeading : "hdmi",
            inputText: ["label", "hdmi", "cec", "labelHdmi", "hdmiLabel", "cecHdmi", "hdmiCec", "icon", "iconHdmi", "iconLabel", "iconCec"].indexOf(s.inputText) >= 0 ? s.inputText : "hdmiLabel",
            // A name longer than a pill: end it with an ellipsis (as before)
            // or scroll it while the tile is focused.
            inputOverflow: s.inputOverflow === "scroll" ? "scroll" : "ellipsis",
            inputIcons: DeviceIcons.assignments(s.inputIcons),
            tvIcon: DeviceIcons.tvIcon(s.tvIcon).id,
            homeCloseApps: s.homeCloseApps === true,
            // The stamp of the last finished mode switch the user was told about.
            modeAck: typeof s.modeAck === "number" && s.modeAck > 0 ? s.modeAck : 0,
            // Older TVs may lack LG's optimiser screen. Keep a saved memory
            // action from opening unrelated Settings there; old combined mode
            // also falls back to closing background apps.
            closeAppsMode: memoryOptimizerAvailable && s.closeAppsMode === "memory" ? "memory" : "apps",
            homeApps: s.homeApps !== false,
            homeActionOrder: homeActionOrderFor(s.homeActionOrder),
            showHidden: s.showHidden === true,
            exitTo: /^(last|none|com\.webos\.app\.(livetv|(hdmi|dp|usbc)\d))$/.test(s.exitTo) ? s.exitTo : "last",
            clock: s.clock !== false,
            // Up to 0.14 "clock" showed or hid the whole chip: what is on
            // screen and the weather follow it until they are set themselves.
            nowApp: s.nowApp === undefined ? s.clock !== false : s.nowApp !== false,
            weather: s.weather === undefined ? s.clock !== false : s.weather !== false,
            // The load of the TV in the chip: each off until switched on.
            statCpu: s.statCpu === true,
            statMem: s.statMem === true,
            statNet: s.statNet === true,
            units: s.units === "c" || s.units === "f" ? s.units : "auto",
            temperature: s.temperature === "apparent" ? "apparent" : "standard",
            hours: s.hours === "12" ? "12" : "24",
            title: s.title !== false,
            hints: s.hints !== false,
            timeout: [3, 5, 10, 15, 20, 30, 45, 60].indexOf(s.timeout) >= 0 ? s.timeout : 0,
            beta: s.beta === true
        };
    }
    function saveSettings() { save(settings, "settings"); }
    function loadSettings() {
        try { settings = validSettings(store.item.load("settings")); } catch (e) {}
        if (Config.exitTarget) exitTargetChosen(settings.exitTo);
    }
    // One saved slot: a list or an object, or null when nothing is there.
    function save(value, key) {
        try { if (store.item) store.item.save(value, key); } catch (e) {}
    }
    function loaded(key, fallback) {
        try { var v = store.item.load(key); if (v !== null && v !== undefined) return v; } catch (e) {}
        return fallback;
    }
    function loadExtras() {
        var h = loaded("hidden", []), hi = loaded("hiddenInputs", []);
        hiddenIds = h.length !== undefined ? h : [];
        hiddenInputs = hi.length !== undefined ? hi : [];
        var u = loaded("usage", {}), c = loaded("colors", {});
        usage = typeof u === "object" && u.length === undefined ? u : {};
        iconColors = typeof c === "object" && c.length === undefined ? c : {};
    }
    // The glow colour of an app: from the build, else from its icon, else neutral.
    function styleFor(id) {
        var s = Config.styles ? Config.styles[id] : null;
        if (s && s.accent) return {accent: s.accent};
        var c = iconColors[id];
        return {accent: c && c.accent ? c.accent : neutral};
    }
    // Installed apps only, in the saved order; an uninstalled favourite simply disappears.
    function resolveFavourites(ids, apps) {
        var out = [];
        for (var i=0; i<ids.length && out.length < maxFavourites; i++) {
            for (var j=0; j<apps.length; j++) {
                if (apps[j].id !== ids[i]) continue;
                out.push({id: apps[j].id, title: apps[j].title, icon: apps[j].icon});
                break;
            }
        }
        return out;
    }
    function appsFor(all, hidden, sort, showHidden) {
        var list = all.filter(function(a) { return showHidden || hidden.indexOf(a.id) < 0; });
        if (sort === "az") list.sort(function(a, b) { return a.title.localeCompare(b.title); });
        else if (sort === "used") {
            // usage is read here, and only here, so the list follows the
            // counts only in this order.
            var counts = shell.usage;
            list.sort(function(a, b) { return (counts[b.id] || 0) - (counts[a.id] || 0) || a.title.localeCompare(b.title); });
        }
        return list;
    }
    // Live TV (always known, "tv") and the inputs from the TV, in the saved
    // order: the ids in sourceOrder first, then anything listed since, so a
    // new input appears after the arranged ones.
    function allSourcesFor(list, hiddenList, s) {
        var all = [{id: "tv", title: t("live_tv"), label: "", cec: "", name: "", present: true, kind: "tv", hidden: s.tv !== true}], i, j;
        for (i=0; i<list.length; i++)
            all.push({id: list[i].id, title: list[i].title, label: list[i].label || "", cec: list[i].cec || "",
                      name: list[i].name || "", present: list[i].present !== false, kind: "input",
                      hidden: hiddenList.indexOf(list[i].id) >= 0});
        var order = s.sourceOrder || [], out = [];
        for (i=0; i<order.length; i++)
            for (j=0; j<all.length; j++)
                if (all[j].id === order[i] && out.indexOf(all[j]) < 0) out.push(all[j]);
        for (j=0; j<all.length; j++) if (out.indexOf(all[j]) < 0) out.push(all[j]);
        return out;
    }
    // Opened from here: counts for the "most used" order.
    function noteLaunch(id) {
        if (!appById(id)) return;
        var u = {}, k;
        for (k in usage) u[k] = usage[k];
        u[id] = (u[id] || 0) + 1;
        usage = u;
        save(usage, "usage");
    }
    function heroFor(currentPage, index, appList, favs, editing, busy, error, note, toolList, sourceList, colors) {
        var h, n = favs.length;
        if (currentPage === "apps") {
            var app = appList[index] || {title: ""};
            h = {title: app.title, sub: hiddenIds.indexOf(app.id) >= 0 ? t("hidden_sub") : "", color: styleFor(app.id).accent};
        } else if (currentPage === "system") {
            var tool = toolList[index] || {title: ""};
            h = {title: tool.title, sub: "", color: neutral};
        } else if (currentPage === "settings") {
            h = {title: "", sub: "", color: neutral};
        } else if (showAddTile && index === 0) {
            h = {title: t("add_favs_title"), sub: t("add_favs_sub"), color: neutral};
        } else if (index < n) {
            var f = favs[index];
            h = {title: f.title, sub: editing >= 0 ? t("edit_sub") : "", color: styleFor(f.id).accent};
        } else if (index < favSlots + sourceList.length) {
            var source = sourceList[index - favSlots];
            // The heading is independent of the tile, including icon-only inputs.
            h = {title: sourceHeading(source), sub: editSourceIndex >= 0 ? (editInputIcon ? "← → " + t("hint_input_icon") : t("edit_inputs_sub") + "   ▲ " + t("hint_input_icon")) : "", color: neutral};
        } else {
            var action = homeActions[index - favSlots - sourceList.length] || {title: ""};
            // Under the name the same line as a favourite's while editing;
            // System only moves, so its line has no ▼.
            h = {title: action.title, sub: editActionIndex >= 0 ? (action.action === "system" ? t("edit_shortcuts_sub") : t("edit_shortcuts_remove_sub")) : "", color: neutral};
        }
        if (error) h.sub = error;
        else if (busy) h.sub = t("opening");
        else if (note) h.sub = note;
        return h;
    }
    // The hints on the bottom line: each a text and the keys that do it, a
    // colour key in its own colour ("hold OK" and YELLOW do the same thing).
    function hintKey(label, colour) { return {label: label, colour: colour || ""}; }
    function hint(keyList, text) { return {keys: keyList, text: text}; }
    function hintsFor(currentPage, index, keys, editing, language, upd, currentPane) {
        var ok = hintKey("OK"), back = hintKey(t("hint_back")), hold = hintKey(t("hint_hold_ok"));
        var red = hintKey(t("key_red"), "red"), yellow = hintKey(t("key_yellow"), "yellow");
        if (modeConfirm !== "") return [hint([hintKey("◀ ▶")], t("hint_choose")), hint([ok], t("hint_confirm")), hint([back], t("mode_no"))];
        if (modeDoneAt > 0) return [hint([ok], t("mode_ok"))];
        if (buttonStep === "menu") return [hint([hintKey("◀ ▶")], t("hint_choose")), hint([ok], t("hint_confirm")), hint([back], t("button_cancel"))];
        if (buttonStep === "done") return [hint([ok], t("mode_ok"))];
        if (buttonStep !== "") return buttonStep === "first" || buttonStep === "second" ? [hint([back], t("button_cancel"))] : [];
        if (currentPage === "apps") {
            var app = apps[index];
            var fav = app && keys.indexOf(app.id) >= 0, hid = app && hiddenIds.indexOf(app.id) >= 0;
            return [hint([ok], t("hint_open")), hint([hold, yellow], fav ? t("hint_remove_fav") : t("hint_add_fav")),
                    hint([red], hid ? t("hint_unhide") : t("hint_hide")), hint([back], t("hint_favourites"))];
        }
        if (currentPage === "system") return [hint([ok], t("hint_open")), hint([back], t("hint_favourites"))];
        if (currentPage === "settings") {
            if (currentPane === 1 && valueToggles) {
                var o = valueOptions[valueIndex], on = o && valueOn(o.id);
                return [hint([hintKey("▲ ▼")], t("hint_choose")), hint([ok], on ? t("hint_hide") : t("hint_unhide")), hint([back], t("hint_done"))];
            }
            if (currentPane === 1 && valueKey === "mode") return modeInfo.busy ? [hint([back], t("hint_done"))] : [hint([hintKey("▲ ▼")], t("hint_choose")), hint([ok], t("hint_choose")), hint([back], t("hint_done"))];
            if (currentPane === 1) return [hint([hintKey("▲ ▼")], t("hint_choose")), hint([ok], t("hint_done"))];
            var key = settingKeys[index], verb = actionVerb(key);
            if (key === "backup" || key === "restore" || key === "update" || key === "place" || key === "about" || key === "restart")
                return verb ? [hint([ok], verb), hint([back], t("hint_system"))] : [hint([back], t("hint_system"))];
            return [hint([ok], t("hint_change")), hint([back], t("hint_system"))];
        }
        // Editing a favourite, a source or a shortcut: the same keys for all.
        // Two DOWN presses take it off the row; System only moves.
        if (editing >= 0 || editSourceIndex >= 0 || editActionIndex >= 0) {
            if (editInputIcon) return [hint([hintKey("← →")], t("hint_input_icon")), hint([ok, back], t("hint_done"))];
            var editingSystem = editActionIndex >= 0 && homeActions[editActionIndex] !== undefined && homeActions[editActionIndex].action === "system";
            var editHints = [hint([hintKey("← →")], t("hint_move"))];
            if (editSourceIndex >= 0 && iconSource) editHints.push(hint([hintKey("▲")], t("hint_input_icon")));
            if (!editingSystem) editHints.push(hint([hintKey("▼")], t("hint_remove")));
            editHints.push(hint([ok], t("hint_done")));
            return editHints;
        }
        if (index < keys.length) return [hint([ok], t("hint_open")), hint([hold, yellow], t("hint_edit_favs"))];
        if (index < favSlots) return [hint([ok], t("hint_open"))];   // the "Add favourites" tile
        // A source (Live TV, an input): opened with OK, edited exactly like a
        // favourite with hold OK or YELLOW.
        if (index < favSlots + sourceCount)
            return [hint([ok], t("hint_open")), hint([hold, yellow], t("hint_edit_inputs"))];
        // A shortcut (Apps, System, the close-apps action), edited the same way.
        var homeAction = homeActions[index - favSlots - sourceCount];
        var actionHints = homeAction && homeAction.action === "closeApps" && settings.closeAppsMode !== "memory" ? [hint([ok], t("hint_close"))] : [hint([ok], t("hint_open"))];
        actionHints.push(hint([hold, yellow], t("hint_edit_shortcuts")));
        return actionHints;
    }

    function saveFavourites() {
        if (!store.item) { message = t("err_store_unavailable"); return; }
        try { store.item.save(favouriteIds, "favourites"); }
        catch (e) { message = t("err_save"); }
    }
    // The list saved on the TV wins over the build's defaults. With nothing
    // saved yet, the build's preset becomes the TV's own list at once, so a
    // later version with other defaults (an update) never changes it.
    function loadFavourites() {
        try {
            var ids = store.item.load("favourites");
            if (ids && ids.length !== undefined) favouriteIds = ids;
            else if (favouriteIds.length) store.item.save(favouriteIds, "favourites");
        } catch (e) {}
    }
    function setFavourites(ids) { favouriteIds = ids; saveFavourites(); }
    function toggleFavourite(app) {
        var ids = favouriteKeys.slice(0), at = ids.indexOf(app.id);
        if (at >= 0) { ids.splice(at, 1); notice = t("removed_fav"); }
        else if (ids.length >= maxFavourites) { notice = Strings.format(t("max_favs"), {n: maxFavourites}); return; }
        else { ids.push(app.id); notice = t("added_fav"); }
        setFavourites(ids);
    }
    // The edit handles a tile shows: a direction only while it can still move
    // that way, so at either end one arrow goes away.
    function moveHandles(index, count) {
        var out = [];
        if (index > 0) out.push("‹");
        if (index < count-1) out.push("›");
        return out;
    }
    function moveFavourite(from, to) {
        pendingRemoval = "";
        var ids = favouriteKeys.slice(0), id = ids[from];
        ids[from] = ids[to]; ids[to] = id;
        setFavourites(ids);
        editIndex = to; selected = to;
    }
    function moveSource(from, to) {
        pendingRemoval = "";
        var moving = sources[from], target = sources[to];
        if (!moving || !target) return;
        // The whole order, hidden sources included, so their places stay.
        var order = allSources.map(function(s) { return s.id; });
        var a = order.indexOf(moving.id), b = order.indexOf(target.id);
        if (a < 0 || b < 0) return;
        order[a] = target.id; order[b] = moving.id;
        setSetting("sourceOrder", order);
        editSourceIndex = to; selected = favSlots + to;
    }
    // DOWN on a source takes it off the row, as with a favourite and a
    // shortcut; the Inputs switches in Launcher settings turn it back on.
    function hideSource(index) {
        var source = sources[index];
        if (!source) return;
        editSourceIndex = -1;
        if (source.kind === "tv") setSetting("tv", false);
        else toggleHiddenInput(source.id);
        notice = t("removed_input");
        selected = Math.max(0, Math.min(selected, favSlots + sourceCount + homeActions.length - 1));
    }
    function moveHomeAction(from, to) {
        pendingRemoval = "";
        var moving = homeActions[from], target = homeActions[to];
        if (!moving || !target) return;
        var order = homeActionOrderFor(settings.homeActionOrder), a = order.indexOf(moving.action), b = order.indexOf(target.action);
        if (a < 0 || b < 0) return;
        order[a] = target.action; order[b] = moving.action;
        setSetting("homeActionOrder", order);
        editActionIndex = to; selected = favSlots + sourceCount + to;
    }
    // DOWN on a shortcut hides it, as DOWN does with a favourite; Launcher
    // settings turns the optional ones back on. System is only ever moved.
    function removeHomeAction(index) {
        var action = homeActions[index];
        if (!action || action.action === "system") return;
        if (action.action === "apps") setSetting("homeApps", false);
        else if (action.action === "closeApps") setSetting("homeCloseApps", false);
        editActionIndex = -1;
        notice = t("removed_shortcut");
        selected = Math.max(0, Math.min(selected, favSlots + sourceCount + homeActions.length - 1));
    }
    function removeFavourite(index) {
        var ids = favouriteKeys.slice(0);
        ids.splice(index, 1);
        editIndex = -1;
        setFavourites(ids);
        selected = Math.max(0, Math.min(index, ids.length-1));
        notice = t("removed_fav");
    }
    // RED: hide an app from Apps (and drop it from the favourites), or show
    // it again. An input is switched in Launcher settings' Inputs list, or
    // with DOWN in its own edit mode.
    function toggleHidden(app) {
        var ids = hiddenIds.slice(0), at = ids.indexOf(app.id);
        if (at >= 0) { ids.splice(at, 1); notice = t("unhidden_app"); }
        else {
            ids.push(app.id); notice = t("hidden_app");
            var favs = favouriteKeys.slice(0), f = favs.indexOf(app.id);
            if (f >= 0) { favs.splice(f, 1); setFavourites(favs); }
        }
        hiddenIds = ids;
        save(hiddenIds, "hidden");
        selected = Math.max(0, Math.min(selected, apps.length-1));
    }
    function toggleHiddenInput(id) {
        var ids = hiddenInputs.slice(0), at = ids.indexOf(id);
        if (at >= 0) { ids.splice(at, 1); notice = t("unhidden_input"); }
        else { ids.push(id); notice = t("hidden_input"); }
        hiddenInputs = ids;
        save(hiddenInputs, "hiddenInputs");
        // On Home the row got shorter; in the settings menu the row stays.
        if (page === "home") selected = Math.max(0, Math.min(selected, favSlots + sourceCount + homeActions.length - 1));
    }
    function hideAction() {
        // RED no longer hides inputs: they are taken off the row with DOWN in
        // their edit mode, and the Inputs switches bring them back.
        if (!ready || launching) return;
        if (page === "apps") { if (apps[selected]) toggleHidden(apps[selected]); }
    }
    // Hold OK (or the yellow key): edit a favourite, a source or a shortcut
    // on Home; toggle a favourite in Apps.
    function secondaryAction() {
        pendingRemoval = "";
        if (!ready || launching) return;
        if (page === "apps") { if (apps[selected]) toggleFavourite(apps[selected]); }
        else if (page !== "home") return;
        else if (selected < favCount) { editIndex = editIndex === selected ? -1 : selected; notice = ""; }
        else if (selected >= favSlots && selected < favSlots + sourceCount) {
            editSourceIndex = selected - favSlots; notice = "";
        } else if (selected >= favSlots + sourceCount && selected < favSlots + sourceCount + homeActions.length) {
            editActionIndex = selected - favSlots - sourceCount; notice = "";
        }
    }
    // The TV's inputs from eim getAllInputStatus: HDMI, and DisplayPort or
    // USB-C where a set has them. title is the port's own name ("HDMI 2");
    // name is the one the pill can show under or instead of it: the label set
    // on the TV when it is not just the port, else the HDMI-CEC name (subList
    // SIMPLINK), else nothing. The owner asked for the label to win.
    function inputsFrom(devices) {
        var next = [];
        for (var i=0; i<devices.length; i++) {
            var d = devices[i];
            var kind = !d.appId ? "" : d.appId.indexOf("com.webos.app.hdmi") === 0 ? "HDMI"
                : d.appId.indexOf("com.webos.app.dp") === 0 ? "DP" : d.appId.indexOf("com.webos.app.usbc") === 0 ? "USB-C" : "";
            if (!kind) continue;
            var port = kind + " " + d.port;
            var label = d.label && d.label !== port ? d.label : "";
            var cec = "", subs = d.subList || [];
            for (var j=0; j<subs.length; j++) if (subs[j].id === "SIMPLINK" && subs[j].osdName) { cec = subs[j].osdName; break; }
            var name = label || cec;
            // Something is plugged in: the TV says so (webOS 4: hdmiPlugIn,
            // webOS 10: activate) or a device answers over HDMI-CEC.
            var present = !!(d.hdmiPlugIn || d.activate || cec);
            next.push({id: d.appId, title: kind === "HDMI" ? port : (d.label || port), label: label, cec: cec,
                       name: name, present: present});
        }
        return next;
    }
    function setInputs(next) {
        if (next.length && !same(next, allInputs)) allInputs = next;
    }
    function describe(appId) {
        if (!appId || appId === "com.webos.app.home") return false;
        for (var i=0; i<allInputs.length; i++) if (allInputs[i].id === appId) { nowTitle = inputTexts(allInputs[i]).primary; return true; }
        for (var j=0; j<applications.length; j++) if (applications[j].id === appId) { nowTitle = applications[j].title; return true; }
        nowTitle = appId === "com.webos.app.livetv" ? t("live_tv") : appId;
        return true;
    }
    // Into the values of the focused setting, on its current value (a list of
    // switches opens on its first item).
    function enterValues() {
        var options = valueOptions, at = 0;
        if (!valueKey || settingFor(valueKey).action !== "setting") return;
        if (!valueToggles)
            for (var i=0; i<options.length; i++) if (options[i].id === (valueKey === "mode" ? modeInfo.current : settings[valueKey])) at = i;
        valueIndex = at;
        pane = 1;
    }
    // In the values the focused one is the chosen one: moving along them is
    // the preview, OK and left keep it.
    function applyValue() {
        var o = valueOptions[valueIndex];
        if (page === "settings" && pane === 1 && o && !valueToggles && valueKey !== "mode") setSetting(valueKey, o.id);
    }
    // What the focused launch method does, then where things stand now.
    function modeDescription(id) { return id === "native" || id === "overlay" ? t("mode_desc_" + id) : ""; }
    function modePopupText(id) {
        var r = modeInfo.inspection, text = t("mode_do_" + id);
        if (id === "native" && r && r.cleanup) {
            // Only the mappers that really hold a Homebar mapping are named.
            var names = [], magic = false, m = r.mapped || [];
            for (var i=0; i<m.length; i++) {
                if (names.indexOf(m[i].source) < 0) names.push(m[i].source);
                if (m[i].source === "Magic Mapper") magic = true;
            }
            text += "\n\n" + Strings.format(t("launch_cleanup"), {count: r.cleanup, sources: names.length ? names.join(", ") : "Input Hook / Magic Mapper"});
            if (magic) text += " " + t("launch_cleanup_restart");
        }
        return text;
    }
    function launchDetails(info, failure, language) {
        var r = info.inspection, lines = [];
        if (failure) lines.push(t(failure));
        if (!r) return lines.length ? lines.join("\n\n") : t("launch_checking");
        lines.push(t("set_mode") + ": " + t("val_mode_" + info.current));
        if (r.trial) lines.push(t("launch_trial"));
        if (info.recoveryNeeded) lines.push(t("launch_failed"));
        else if (info.busy) lines.push(t("mode_switching"));
        if (r.migrationAvailable) lines.push(t("launch_migrate"));
        for (var i=0; i<r.issues.length; i++) {
            var line = t(r.issues[i].code);
            if (r.issues[i].source) line = r.issues[i].source + ": " + line;
            if (lines.indexOf(line) < 0) lines.push(line);
        }
        if (!failure && !info.busy && !r.issues.length && !r.migrationAvailable) lines.push(t("launch_ready"));
        return lines.join("\n\n");
    }
    // OK or a click on a method opens the popup that says what will happen;
    // nothing changes until Yes. A changed configuration cancels it (loadMode).
    function chooseMode() {
        var o = valueOptions[valueIndex], r = modeInfo.inspection;
        if (!o || !r || modeInfo.busy) return;
        modeError = "";
        if (o.id === "native" && r.blockers.length) { modeError = r.blockers[0].code; return; }
        if (o.id === modeInfo.current && !(o.id === "native" && (r.cleanup || r.owner === "lg"))) return;
        modeConfirm = o.id; modeConfirmFingerprint = r.fingerprint; modeConfirmYes = false;
    }
    function answerMode(yes) {
        var id = modeConfirm;
        modeConfirm = ""; modeConfirmYes = false;
        if (yes && id) modeRun(id, modeConfirmFingerprint);
    }
    // A button as people know it: the coloured ones by colour, in the panel's
    // language, the others by their label; always with the code.
    function buttonLabel(code, name) {
        var colour = ["red", "green", "yellow", "blue"].indexOf(name) >= 0;
        return (colour ? t("key_" + name) : name || t("button_unnamed")) + " (" + code + ")";
    }
    function buttonValue(info) {
        var b = info.bound && info.bound.length ? info.bound[0] : null;
        return b ? buttonLabel(b.code, b.name) : t("val_button_none");
    }
    function mapperName(id) { return id === "magic" ? "Magic Mapper" : "Input Hook"; }
    function buttonPopupText() {
        var b = buttonInfo.bound && buttonInfo.bound.length ? buttonInfo.bound[0] : null;
        if (buttonStep === "menu" && b) return Strings.format(t("button_current"), {button: buttonLabel(b.code, b.name), mapper: mapperName(b.mapper)});
        var lead = buttonText ? buttonText + "\n\n" : "";
        if (buttonStep === "first") return lead + t("button_press") + "\n\n" + t("button_note");
        if (buttonStep === "second") return lead + Strings.format(t("button_again"), {button: buttonLabel(buttonCode, buttonName)});
        if (buttonStep === "done") return buttonText;
        return t("button_saving");
    }
    // OK on the row: the bound button can be changed or unpinned; without one,
    // the popup asks for a press straight away.
    function openButton() {
        buttonText = ""; buttonUnpin = false;
        // The helper has not answered (yet): nothing to go on.
        if (!buttonInfo.ok) { buttonStep = "done"; buttonText = t("button_failed"); return; }
        if (buttonInfo.blocked) { buttonStep = "done"; buttonText = buttonError({error: buttonInfo.blocked}); return; }
        if (buttonInfo.bound && buttonInfo.bound.length) buttonStep = "menu";
        else captureButton("first");
    }
    // The first press counts only from now on; the second may already have
    // come while the panel asked for it (the helper keeps reading meanwhile).
    function captureButton(step) {
        buttonStep = step; buttonCapture++;
        buttonCaptureRun(buttonCapture, step === "first" && buttonText === "");
    }
    // The same list as webos10/integration.js: OK, the arrows, BACK and HOME
    // drive the panel, and power stays the TV's.
    readonly property var reservedButtons: [28, 103, 105, 106, 108, 116, 412, 773]
    // One press read by the helper (code 0: none came in time). The first is
    // the button; the second has to be the same one before it is saved.
    function buttonCaptured(id, r) {
        if (id !== buttonCapture || (buttonStep !== "first" && buttonStep !== "second")) return;
        if (!r || r.error) { buttonStep = "done"; buttonText = buttonError(r); return; }
        if (!r.code) { buttonStep = "done"; buttonText = t("button_none_seen"); return; }
        if (buttonStep === "first") {
            if (reservedButtons.indexOf(r.code) >= 0) { buttonText = t("button_reserved"); captureButton("first"); return; }
            // No mapper Homebar can write to: the code is all it can give.
            if (!buttonInfo.mapper) { buttonStep = "done"; buttonText = Strings.format(t("button_code_only"), {button: buttonLabel(r.code, r.name)}); return; }
            buttonCode = r.code; buttonName = r.name || ""; buttonText = "";
            captureButton("second");
        } else if (r.code !== buttonCode) {
            buttonText = Strings.format(t("button_other"), {other: buttonLabel(r.code, r.name)});
            captureButton("second");
        } else {
            buttonStep = "saving";
            buttonBindRun(buttonCode);
        }
    }
    // The helper's answer to saving or unpinning: its new state, or an error.
    function buttonSaved(r) {
        var ok = r && r.ok;
        if (ok) buttonInfo = r;
        if (buttonStep === "saving") {
            buttonStep = "done";
            buttonText = !ok ? buttonError(r) : Strings.format(t("button_saved"), {button: buttonLabel(buttonCode, buttonName)})
                + (r.active ? "" : "\n\n" + Strings.format(t("button_inactive"), {mapper: mapperName(r.mapper)}));
        }
        else if (buttonStep === "unpinning") { buttonStep = "done"; buttonText = ok ? t("button_unpinned") : buttonError(r); }
    }
    function buttonError(r) {
        var code = r && r.error ? r.error : "button_failed", text = t(code);
        return text === code ? t("button_failed") : text;
    }
    function answerButtonMenu() {
        if (buttonUnpin) { buttonStep = "unpinning"; buttonUnbindRun(); }
        else captureButton("first");
    }
    function closeButton() {
        buttonStep = ""; buttonText = ""; buttonCapture++;
        buttonLoadRun();
    }
    // The "switch finished" popup: acknowledged once, per switch.
    function ackModeDone() {
        if (modeDoneAt > 0) setSetting("modeAck", modeDoneAt);
        modeDoneAt = 0;
    }
    function toggleValue() {
        var o = valueOptions[valueIndex];
        if (page === "settings" && pane === 1 && o && valueToggles) toggleCheck(valueKey, o.id);
    }
    onValueIndexChanged: { modeConfirm = ""; modeError = ""; applyValue(); }
    function activate(item) {
        pendingRemoval = "";
        if (!ready || launching || !item) return;
        if (editInputIcon) { editInputIcon = false; return; }
        message = "";
        if (item.action === "stock") { stockRequested(); return; }
        if (item.action === "close") { closeHome(); return; }
        if (item.action === "setting") {
            if (pane === 1 && valueKey === "mode") { chooseMode(); return; }
            if (pane === 1) pane = 0; else enterValues(); return; }
        if (item.action === "update") { updateAction(); return; }
        if (item.action === "place") { loadSetupInfo(); return; }
        if (item.action === "about") return;
        if (item.action === "restart") { restartHomebar(); return; }
        if (item.action === "button") { openButton(); return; }
        if (item.action === "backup") { backupRun("save", backupData()); return; }
        if (item.action === "restore") { if (backupInfo.saved) backupRun("load", null); return; }
        if (item.action === "launcherSettings") {
            page = "settings"; selected = 0; pane = 0;
            // Look for a new version each time the settings open, unless one
            // is already found; and whether there is a backup to restore.
            var s = updateInfo.state;
            if (s === "idle" || s === "current" || s === "failed") updateStep("check");
            backupRun("info", null);
            loadSetupInfo();
            buttonLoadRun();
            return;
        }
        if (item.action === "closeApps") { runCloseApps(); return; }
        if (item.action === "apps" || item.action === "system") {
            page = item.action; selected = 0; return;
        }
        // "tv" is the saved rail identity, not LG's application id. Resolve
        // it here so both the Home panel and overlay launch the real app.
        var launchId = item.kind === "tv" ? "com.webos.app.livetv" : item.id;
        noteLaunch(launchId);
        launching = true;
        launchTimeout.restart();
        launchService.callService({id: launchId, params: {}, reason: "launcher"});
    }
    function itemAt(index) {
        if (page === "apps") return apps[index];
        if (page === "system") return tools[index];
        if (page === "settings") return settingsItems[index];
        if (showAddTile && index === 0) return addFavouritesTile;
        if (index < favCount) return favourites[index];
        if (index < favSlots + sourceCount) return sources[index - favSlots];
        return homeActions[index - favSlots - sourceCount] || homeActions[homeActions.length-1];
    }
    // Favourites and settings, in one file next to the launcher on the TV.
    function backupData() {
        return {saved: new Date().toISOString(), version: Config.version, favourites: favouriteIds, settings: settings,
                hidden: hiddenIds, hiddenInputs: hiddenInputs, usage: usage};
    }
    function applyBackup(b) {
        if (!b || typeof b !== "object" || !b.saved) return false;
        if (b.favourites && b.favourites.length !== undefined) setFavourites(b.favourites.slice(0, maxFavourites));
        settings = validSettings(b.settings); saveSettings();
        if (Config.exitTarget) exitTargetChosen(settings.exitTo);
        hiddenIds = b.hidden && b.hidden.length !== undefined ? b.hidden : []; save(hiddenIds, "hidden");
        hiddenInputs = b.hiddenInputs && b.hiddenInputs.length !== undefined ? b.hiddenInputs : []; save(hiddenInputs, "hiddenInputs");
        usage = b.usage && typeof b.usage === "object" ? b.usage : {}; save(usage, "usage");
        return true;
    }
    // The answer of one backup step: info and load bring the file's
    // contents (null: no file or no answer), save says whether it was written.
    function backupResult(step, r) {
        if (step === "save") {
            if (r && r.ok) { notice = t("bak_done"); backupRun("info", null); }
            else message = t("bak_err");
        } else if (step === "info") {
            backupInfo = {saved: r && r.saved ? String(r.saved) : ""};
        } else if (step === "load") {
            if (applyBackup(r)) notice = t("bak_restored");
            else message = t("bak_err_read");
        }
    }
    // Home and System are one rail; All applications is a grid of appColumns;
    // the settings are a menu of rows with the values of one beside them.
    function isOk(key) { return key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Select; }
    function isBack(key) { return key === WebOS.Key_webOS_Back || key === Qt.Key_Escape || key === Qt.Key_Back || key === Qt.Key_Backspace || key === 461; }
    function isYellow(key) { return key === WebOS.Key_webOS_Yellow || key === 405; }
    function isRed(key) { return key === WebOS.Key_webOS_Red || key === 403; }
    function navigateMenu(key) {
        if (pane === 1) {
            if (valueKey === "mode" && ((key === Qt.Key_Down && valueIndex === valueOptions.length-1) || (key === Qt.Key_Up && modeDetailsOffset > 0))) {
                modeDetailsScroll(key === Qt.Key_Down ? 1 : -1); return true;
            }
            if (key === Qt.Key_Up) { if (valueIndex > 0) valueIndex--; }
            else if (key === Qt.Key_Down) { if (valueIndex < valueOptions.length-1) valueIndex++; }
            else if (isOk(key) && valueKey === "mode") chooseMode();
            else if (isOk(key) && valueToggles) toggleValue();
            else if (key === Qt.Key_Left || isOk(key) || isBack(key)) { modeConfirm = ""; pane = 0; }
            else return false;
            return true;
        }
        if (key === Qt.Key_Up) { if (selected > 0) selected--; }
        else if (key === Qt.Key_Down) { if (selected < settingKeys.length-1) selected++; }
        else if (key === Qt.Key_Right) enterValues();
        else if (isOk(key)) activate(itemAt(selected));
        else if (isBack(key)) { page = "system"; selected = toolIndex("launcherSettings"); }
        else return false;
        return true;
    }
    function navigate(key) {
        notice = "";
        if (key !== Qt.Key_Down) pendingRemoval = "";
        if (page === "settings") return navigateMenu(key);
        // Editing a favourite: arrows move it, two DOWN presses remove it; OK/BACK/UP finish.
        if (page === "home" && editIndex >= 0) {
            if (key === Qt.Key_Left) { if (editIndex > 0) moveFavourite(editIndex, editIndex-1); }
            else if (key === Qt.Key_Right) { if (editIndex < favCount-1) moveFavourite(editIndex, editIndex+1); }
            else if (key === Qt.Key_Down) requestRemoval();
            else if (isOk(key) || isBack(key) || key === Qt.Key_Up) editIndex = -1;
            else return false;
            return true;
        }
        if (page === "home" && editSourceIndex >= 0) {
            if (editInputIcon) {
                if (key === Qt.Key_Left || key === Qt.Key_Right) cycleInputIcon(key === Qt.Key_Left ? -1 : 1);
                else if (isOk(key) || isBack(key) || key === Qt.Key_Down || key === Qt.Key_Up) editInputIcon = false;
                else return false;
                return true;
            }
            if (key === Qt.Key_Up && iconSource) { editInputIcon = true; return true; }
            if (key === Qt.Key_Left) { if (editSourceIndex > 0) moveSource(editSourceIndex, editSourceIndex-1); }
            else if (key === Qt.Key_Right) { if (editSourceIndex < sourceCount-1) moveSource(editSourceIndex, editSourceIndex+1); }
            else if (key === Qt.Key_Down) requestRemoval();
            else if (isOk(key) || isBack(key) || key === Qt.Key_Up) editSourceIndex = -1;
            else return false;
            return true;
        }
        if (page === "home" && editActionIndex >= 0) {
            if (key === Qt.Key_Left) { if (editActionIndex > 0) moveHomeAction(editActionIndex, editActionIndex-1); }
            else if (key === Qt.Key_Right) { if (editActionIndex < homeActions.length-1) moveHomeAction(editActionIndex, editActionIndex+1); }
            else if (key === Qt.Key_Down) requestRemoval();
            else if (isOk(key) || isBack(key) || key === Qt.Key_Up) editActionIndex = -1;
            else return false;
            return true;
        }
        var count = page === "home" ? favSlots+sourceCount+homeActions.length : page === "apps" ? apps.length : tools.length;
        var columns = page === "apps" ? appColumns : count;
        if (key === Qt.Key_Left) { if (selected % columns > 0) selected--; }
        else if (key === Qt.Key_Right) { if (selected % columns < columns-1 && selected+1 < count) selected++; }
        else if (key === Qt.Key_Up) { if (selected-columns >= 0) selected -= columns; }
        else if (key === Qt.Key_Down) {
            if (selected+columns < count) selected += columns;
            else if (Math.floor(selected/columns) < Math.floor((count-1)/columns)) selected = count-1;
        } else if (isOk(key)) activate(itemAt(selected));
        else if (isBack(key)) {
            if (page === "home") closeHome();
            else { selected = favSlots + sourceCount + homeActionIndex(page === "apps" ? "apps" : "system"); page = "home"; }
        } else return false;
        return true;
    }
    function toolIndex(action) {
        for (var i=0; i<tools.length; i++) if (tools[i].action === action) return i;
        return 0;
    }
    function actionKey(key) { return isOk(key) || isBack(key); }
    // Activate on release: switching focus on press would deliver the same
    // OK release to LG's ribbon and accidentally launch a second application.
    // Holding OK past holdTimer runs secondaryAction instead of activating.
    // A remote that works by infrared (a Magic Remote without its radio, a
    // plain IR remote) sends a held key as quick presses and releases, not one
    // long press: so where holding OK does something, a release waits a moment
    // (okRelease) for the next press of the same hold before it counts.
    property real okSince: 0
    property int okKey: 0
    function holdable() {
        if (page === "apps") return true;
        if (page !== "home" || editIndex >= 0 || editSourceIndex >= 0 || editActionIndex >= 0) return false;
        if (selected < favCount) return true;
        return selected >= favSlots && selected < favSlots + sourceCount + homeActions.length;
    }
    // The HOME button, pressed again while the panel is up, reaches it as
    // Qt.Key_Super_L (the first press only opens it: LG's Home is launched, no
    // key arrives). Like BACK it closes the panel; the moment after the panel
    // opened is ignored, in case the opening press is still being released.
    property real foregroundSince: 0
    function isHomeKey(key) { return key === Qt.Key_Super_L; }
    Keys.onPressed: {
        noteActivity();
        if (isHomeKey(event.key)) {
            event.accepted = true;
            if (!event.isAutoRepeat && editIndex < 0 && Date.now() - foregroundSince > 600) closeHome();
            return;
        }
        // The mode popups take every key while they are up; BACK answers No.
        if (modeConfirm !== "" || modeDoneAt > 0) {
            event.accepted = true;
            if (event.isAutoRepeat) return;
            modeKeyHeld = event.key;
            if (modeConfirm === "") { if (isOk(event.key) || isBack(event.key)) ackModeDone(); return; }
            if (isBack(event.key)) answerMode(false);
            else if (isOk(event.key)) answerMode(modeConfirmYes);
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Up || event.key === Qt.Key_Down)
                modeConfirmYes = event.key === Qt.Key_Left || event.key === Qt.Key_Up;
            return;
        }
        // The remote-button popup takes every key too. While it waits, the press
        // is the helper's to read (BACK cancels); the menu is Change / Unpin.
        if (buttonStep !== "") {
            event.accepted = true;
            if (event.isAutoRepeat) return;
            modeKeyHeld = event.key;
            if (buttonStep === "menu") {
                if (isBack(event.key)) closeButton();
                else if (isOk(event.key)) answerButtonMenu();
                else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Up || event.key === Qt.Key_Down)
                    buttonUnpin = event.key === Qt.Key_Right || event.key === Qt.Key_Down;
            } else if (buttonStep === "done") {
                if (isOk(event.key) || isBack(event.key)) closeButton();
            } else if ((buttonStep === "first" || buttonStep === "second") && isBack(event.key)) closeButton();
            return;
        }
        if (page === "settings" && menuHover >= 0 && isOk(event.key) && !event.isAutoRepeat) {
            pane = 0; selected = menuHover;
        }
        menuHover = -1; valueHover = -1;
        pointerBlockedUntil = Date.now() + 1000;
        if (event.key !== Qt.Key_Down) pendingRemoval = "";
        // A held DOWN must never confirm its own warning through auto-repeat.
        if (event.key === Qt.Key_Down && event.isAutoRepeat && (editIndex >= 0 || editSourceIndex >= 0 || editActionIndex >= 0)) { event.accepted = true; return; }
        if (isYellow(event.key) || isRed(event.key)) { event.accepted=true; return; }
        if (actionKey(event.key)) {
            event.accepted=true;
            if (!isOk(event.key) || event.isAutoRepeat) return;
            if (okRelease.running) {
                // The same hold, from an infrared remote: on with the time it has.
                okRelease.stop();
                if (!longFired) { holdTimer.interval = Math.max(1, 700 - (Date.now() - okSince)); holdTimer.restart(); }
            } else if (!okHeld) {
                okHeld=true; longFired=false; pressing=true; okSince=Date.now(); holdTimer.interval=700; holdTimer.restart();
            }
        }
        else if (navigate(event.key)) event.accepted=true;
    }
    // The key a popup answered: its release must not act on the page beneath.
    property int modeKeyHeld: 0
    Keys.onReleased: {
        if (modeKeyHeld === event.key) { event.accepted = true; if (!event.isAutoRepeat) modeKeyHeld = 0; return; }
        if (isHomeKey(event.key)) { event.accepted = true; return; }
        if (isYellow(event.key)) { event.accepted=true; if (!event.isAutoRepeat) secondaryAction(); return; }
        if (isRed(event.key)) { event.accepted=true; if (!event.isAutoRepeat) hideAction(); return; }
        if (!actionKey(event.key)) return;
        event.accepted=true;
        if (event.isAutoRepeat) return;
        if (isOk(event.key)) {
            holdTimer.stop();
            if (longFired || holdable()) { okKey = event.key; okRelease.restart(); return; }
            okHeld=false; pressing=false;
        }
        navigate(event.key);
    }
    Timer { id: holdTimer; interval: 700; onTriggered: { if (okHeld) { longFired=true; pressing=false; secondaryAction(); } } }
    // The release of OK, once no press of the same hold followed it.
    Timer {
        id: okRelease; interval: 200
        onTriggered: {
            okHeld=false; pressing=false;
            if (longFired) { longFired=false; return; }
            navigate(okKey);
        }
    }
    Loader { id: store; source: "FavouriteStore.qml"; onLoaded: { shell.loadFavourites(); shell.loadSettings(); shell.loadExtras(); } }
    // Build the settings menu quietly a moment after the panel appears, so
    // opening Launcher settings the first time is as quick as later ones.
    Timer {
        interval: 2500; running: shell.foreground && !shell.menuLoaded
        onTriggered: shell.menuLoaded = true
    }
    onPageChanged: {
        pendingRemoval = "";
        if (page === "settings") { menuLoaded = true; inactivityTimer.stop(); } else noteActivity();
    }
    onForegroundChanged: {
        if (foreground) noteActivity();
        menuHover = -1; valueHover = -1;
        pointerAt = Qt.point(-1, -1);
        pressing = false; okHeld = false; longFired = false; holdTimer.stop(); okRelease.stop();
        editIndex = -1; editSourceIndex = -1; editActionIndex = -1; notice = ""; modeConfirm = "";
        // A remote-button popup does not outlive the panel; an answer still on
        // its way is dropped (buttonCapture).
        if (buttonStep !== "") { buttonStep = ""; buttonText = ""; buttonCapture++; }
        if (foreground) {
            foregroundSince = Date.now();
            launching = false; message = ""; page="home"; selected=0; pane=0; forceActiveFocus();
            tick();
            if (ready) { launchCheckRequested(); catalog.callService({}); foregroundInfo.callService({extraInfo: true}); loadInputs(); dailyUpdateCheck(); }
            loadWeather();
            loadStats();
        }
    }
    onLangChanged: if (ready) launchCheckRequested()
    onReadyChanged: {
        if (!ready) return;
        loadWeather();
        localeService.callService({keys: ["localeInfo"]});
        catalog.callService({});
        loadInputs();
        if (foreground) { foregroundInfo.callService({extraInfo: true}); dailyUpdateCheck(); }
    }
    onVisibleChanged: { pointerAt = Qt.point(-1, -1); if (visible && foreground) { forceActiveFocus(); noteActivity(); } }
    Component.onCompleted: tick()
    // The clock changes on the minute: each tick sets the next one for when
    // the minute turns, so the bar is never half a minute behind.
    function tick() {
        var now = new Date();
        nowTime = now;
        clockTimer.interval = 60000 - (now.getSeconds()*1000 + now.getMilliseconds()) + 50;
    }
    Timer { id: clockTimer; interval: 60000; repeat: true; running: shell.foreground; onTriggered: tick() }

    // The setup server, on 127.0.0.1 in both variants: GET, the JSON answer
    // to done (null: no answer).
    function setupGet(pathname, done) {
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            var r = null;
            if (xhr.status === 200) { try { r = JSON.parse(xhr.responseText); } catch (e) {} }
            done(r);
        };
        xhr.open("GET", "http://127.0.0.1:8898" + pathname);
        xhr.send();
    }
    // A failed answer keeps the last weather: the chip shows it until a new one comes.
    function loadWeather() {
        if (!settings.weather) return;
        setupGet("/weather?units=" + units, function(r) { if (r && r.ok) weather = r; });
    }
    onUnitsChanged: loadWeather()
    // A failed answer keeps the last numbers; the next one replaces them.
    function loadStats() {
        if (!anyStats) return;
        setupGet("/stats", function(r) { if (r && r.ok) stats = r; });
    }
    Timer { interval: 2000; repeat: true; running: shell.foreground && shell.anyStats; onTriggered: loadStats() }
    Timer { interval: 900000; repeat: true; running: shell.foreground && shell.settings.weather; onTriggered: loadWeather() }
    // The place page's address and the place now; the weather again when
    // the place was changed on a phone.
    function loadSetupInfo() {
        setupGet("/info", function(r) {
            if (!r || !r.ok) return;
            var moved = setupInfo.rev >= 0 && r.rev !== setupInfo.rev;
            setupInfo = r;
            if (moved) loadWeather();
        });
    }
    // While the Weather place row is focused, a place chosen on the phone
    // shows within a few seconds.
    Timer { interval: 3000; repeat: true; running: shell.foreground && shell.valueKey === "place"; onTriggered: loadSetupInfo() }
    onValueKeyChanged: { modeConfirm = ""; modeError = ""; if (valueKey === "place") loadSetupInfo(); if (valueKey === "mode") launchCheckRequested(); }

    // A QR code (rows of "1" and "0") on a Canvas, cell pixels a module.
    function drawQr(c, m, cell) {
        c.reset(); c.fillStyle = "#000000";
        if (!m) return;
        for (var y=0; y<m.length; y++) for (var x=0; x<m[y].length; x++) if (m[y].charAt(x) === "1") c.fillRect(x*cell, y*cell, cell, cell);
    }

    // The weather's symbol from its WMO code (Open-Meteo's weather_code).
    function weatherKind(w) {
        var c = w.code;
        if (c === 0 || c === 1) return w.day ? "sun" : "moon";
        if (c === 2) return w.day ? "partly" : "partlyNight";
        if (c === 45 || c === 48) return "fog";
        if (c >= 95) return "storm";
        if ((c >= 71 && c <= 77) || c === 85 || c === 86) return "snow";
        if (c >= 51) return "rain";
        return "cloud";
    }
    // A cloud on the 40-unit grid of the glyphs: three bumps on a flat base,
    // drawn as one outline (where two bumps meet is worked out here).
    function cloudPath(c, base) {
        var b = [[12, base - 6, 6], [21, base - 12, 9], [30, base - 6, 6]];
        function meet(p, q) {
            var dx = q[0]-p[0], dy = q[1]-p[1], d = Math.sqrt(dx*dx + dy*dy);
            var a = (p[2]*p[2] - q[2]*q[2] + d*d) / (2*d), h = Math.sqrt(Math.max(0, p[2]*p[2] - a*a));
            var mx = p[0] + a*dx/d, my = p[1] + a*dy/d;
            var x1 = mx + h*dy/d, y1 = my - h*dx/d, x2 = mx - h*dy/d, y2 = my + h*dx/d;
            return y1 < y2 ? [x1, y1] : [x2, y2];
        }
        function angle(circle, point) { return Math.atan2(point[1]-circle[1], point[0]-circle[0]); }
        var right = meet(b[1], b[2]), left = meet(b[0], b[1]);
        c.moveTo(12, base); c.lineTo(30, base);
        c.arc(30, base - 6, 6, Math.PI/2, angle(b[2], right), true);
        c.arc(21, base - 12, 9, angle(b[1], right), angle(b[1], left), true);
        c.arc(12, base - 6, 6, angle(b[0], left), Math.PI/2 - 2*Math.PI, true);
        c.closePath();
    }
    function sunPath(c, x, y, r, rays) {
        c.moveTo(x + r, y); c.arc(x, y, r, 0, Math.PI*2);
        for (var i=0; i<8; i++) {
            var a = i*Math.PI/4;
            c.moveTo(x + Math.cos(a)*(r + 4), y + Math.sin(a)*(r + 4));
            c.lineTo(x + Math.cos(a)*(r + 4 + rays), y + Math.sin(a)*(r + 4 + rays));
        }
    }
    // A crescent: the part of one circle outside a smaller one at its upper right.
    function moonPath(c, x, y, r) {
        var k = r/12;
        c.moveTo(x + 11.87*k, y + 1.73*k);
        c.arc(x, y, r, 0.145, 4.567, false);
        c.arc(x + 7*k, y - 7*k, 10*k, 3.650, 1.062, true);
        c.closePath();
    }
    function drawWeather(c, kind) {
        c.beginPath();
        if (kind === "sun") sunPath(c, 20, 20, 7, 4);
        else if (kind === "moon") moonPath(c, 20, 21, 12);
        else if (kind === "partly" || kind === "partlyNight") {
            if (kind === "partly") sunPath(c, 14, 14, 5, 3); else moonPath(c, 14, 14, 8);
            c.stroke();
            // The cloud in front: what of the sun is behind it is wiped first.
            c.beginPath(); c.save(); c.translate(4, 4); c.scale(0.85, 0.85); cloudPath(c, 34); c.restore();
            c.globalCompositeOperation = "destination-out"; c.fill();
            c.globalCompositeOperation = "source-over";
        } else if (kind === "fog") {
            c.moveTo(10,13); c.lineTo(30,13); c.moveTo(6,20); c.lineTo(34,20); c.moveTo(10,27); c.lineTo(30,27); c.moveTo(15,34); c.lineTo(25,34);
        } else if (kind === "cloud") cloudPath(c, 30);
        else {
            cloudPath(c, 26);
            if (kind === "rain") { c.moveTo(14,31); c.lineTo(12,37); c.moveTo(21,31); c.lineTo(19,37); c.moveTo(28,31); c.lineTo(26,37); }
            else if (kind === "storm") { c.moveTo(23,29); c.lineTo(18,34); c.lineTo(23,34); c.lineTo(19,39); }
            else if (kind === "snow") {
                c.stroke(); c.beginPath();
                c.arc(13,33,1.8,0,Math.PI*2); c.moveTo(22.8,36); c.arc(21,36,1.8,0,Math.PI*2); c.moveTo(30.8,33); c.arc(29,33,1.8,0,Math.PI*2);
                c.fillStyle = c.strokeStyle; c.fill();
                return;
            }
        }
        c.stroke();
    }

    // The glow colour of an app from its icon, for the apps the build has
    // no colour for: the icon is drawn small and its vivid pixels averaged
    // (grey, white and black count for little), once per icon, and kept in
    // "colors" with the icon's path, so a changed icon is read again.
    onApplicationsChanged: glowReader.queueAll()
    Canvas {
        id: glowReader
        // Off screen and see-through, not invisible: an invisible Canvas
        // may never get to paint.
        x: -100; y: -100; opacity: 0
        width: 24; height: 24
        renderStrategy: Canvas.Immediate
        renderTarget: Canvas.Image
        property var queue: []
        property string current: ""
        property var pending: ({})
        function queueAll() {
            var next = [];
            for (var i=0; i<shell.applications.length; i++) {
                var a = shell.applications[i], known = shell.iconColors[a.id];
                if (!a.icon || (Config.styles && Config.styles[a.id] && Config.styles[a.id].accent)) continue;
                if (known && known.icon === a.icon) continue;
                next.push(a);
            }
            queue = next;
            if (!current) step();
        }
        function step() {
            if (!queue.length) { current = ""; return; }
            var a = queue.shift();
            current = a.id;
            if (isImageLoaded(a.icon)) requestPaint();
            else loadImage(a.icon);
        }
        onImageLoaded: {
            var a = shell.appById(current);
            if (a && isImageLoaded(a.icon)) requestPaint();
            else step();
        }
        onPaint: {
            var a = shell.appById(current);
            if (!a) return;
            var c = getContext("2d");
            c.clearRect(0, 0, width, height);
            var accent = "";
            try {
                c.drawImage(a.icon, 0, 0, width, height);
                accent = shell.vividColor(c.getImageData(0, 0, width, height).data);
            } catch (e) {}
            unloadImage(a.icon);
            if (accent) {
                pending[a.id] = {icon: a.icon, accent: accent};
                flush.restart();
            }
            step();
        }
        // Several icons in one go: one new iconColors object (one glow
        // update) and one save for the batch.
        Timer {
            id: flush
            interval: 400
            onTriggered: {
                var next = {}, k;
                for (k in shell.iconColors) next[k] = shell.iconColors[k];
                for (k in glowReader.pending) next[k] = glowReader.pending[k];
                glowReader.pending = {};
                shell.iconColors = next;
                shell.save(next, "colors");
            }
        }
    }
    // The colour of an icon's vivid pixels, lifted to glow strength.
    function vividColor(data) {
        var r = 0, g = 0, b = 0, w = 0, ar = 0, ag = 0, ab = 0, n = 0;
        for (var i=0; i<data.length; i+=4) {
            var R = data[i], G = data[i+1], B = data[i+2], A = data[i+3];
            if (A < 128) continue;
            var max = Math.max(R, G, B), min = Math.min(R, G, B);
            var s = max ? (max - min) / max : 0, v = max / 255;
            var weight = s * s * v;
            r += R * weight; g += G * weight; b += B * weight; w += weight;
            ar += R; ag += G; ab += B; n++;
        }
        if (!n) return "";
        var out = w > n * 0.02 ? [r / w, g / w, b / w] : [ar / n, ag / n, ab / n];
        // Too dark to glow: brighten, keeping the hue.
        var top = Math.max(out[0], out[1], out[2]);
        if (top < 140 && top > 0) out = out.map(function(v) { return v * 140 / top; });
        return "#" + out.map(function(v) { var s = Math.round(Math.min(255, v)).toString(16); return s.length < 2 ? "0" + s : s; }).join("");
    }

    Service {
        id: launchService
        appId: "com.webos.app.home"
        service: "com.webos.applicationManager"
        method: "launch"
        onCallSuccess: {
            launching = false; launchTimeout.stop();
            if (hostWindow && hostWindow.interfaces.application) hostWindow.interfaces.application.hideApp();
        }
        onCallFailure: { launching = false; launchTimeout.stop(); message = t("err_launch"); }
        onError: { launching = false; launchTimeout.stop(); message = t("err_unavailable"); }
    }
    // LG may also close the process hosting Homebar, in either variant.
    // The next HOME opens it again with the saved settings.
    Service {
        id: closeAppsService
        appId: "com.webos.app.home"
        service: "com.webos.applicationManager"
        method: "closeAllApps"
        onCallSuccess: {
            notice = t("close_apps_done"); catalog.callService({});
        }
        onCallFailure: { notice = t("close_apps_failed"); }
        onError: { notice = t("err_unavailable"); }
    }
    Service {
        id: catalog
        appId: "com.webos.app.home"
        service: "com.webos.applicationManager"
        method: "listLaunchPoints"
        onCallSuccess: {
            if (!response.launchPoints) return;
            var next = [], seen = {};
            for (var i=0; i<response.launchPoints.length; i++) {
                var entry=response.launchPoints[i];
                if (seen[entry.id] || Config.excluded.indexOf(entry.id)>=0) continue;
                seen[entry.id]=true;
                var icon = entry.largeIcon || entry.icon;
                next.push({id: entry.id, title: entry.title || entry.id, icon: icon ? "file://"+icon : ""});
            }
            if (same(next, applications)) return;
            applications=next;
            if (page === "apps") selected=Math.max(0, Math.min(selected, apps.length-1));
        }
    }
    // What stays visible under the transparent top: the card behind Home.
    Service {
        id: foregroundInfo
        appId: "com.webos.app.home"
        service: "com.webos.applicationManager"
        method: "getForegroundAppInfo"
        onCallSuccess: {
            nowTitle = "";
            var list = response.foregroundAppInfo || [];
            for (var i=0; i<list.length; i++) if (describe(list[i].appId)) return;
            describe(response.appId);
        }
    }
    // The TV's language, used while the launcher language is "system".
    Service {
        id: localeService
        appId: "com.webos.app.home"
        service: "com.webos.settingsservice"
        method: "getSystemSettings"
        onCallSuccess: {
            var info = response.settings ? response.settings.localeInfo : null;
            if (info && info.locales && info.locales.UI) systemLang = info.locales.UI;
        }
    }
    // Inputs and the devices on them, read again each time Home opens.
    function loadInputs() { inputService.callService({}); }
    Service {
        id: inputService
        appId: "com.webos.app.home"
        service: "com.webos.service.eim"
        method: "getAllInputStatus"
        onCallSuccess: setInputs(response.devices ? inputsFrom(response.devices) : [])
    }
    // Updates: update.sh, run as root through the Homebrew Channel's exec.
    function updateRun(step, channel) {
        updateService.step = step;
        updateService.callService({command: "sh /var/lib/webosbrew/rawin-launcher/update.sh " + step + " " + channel});
    }
    Service {
        id: updateService
        property string step: ""
        appId: "com.webos.app.home"
        service: "org.webosbrew.hbchannel.service"
        method: "exec"
        onCallSuccess: {
            var r = null;
            try { r = JSON.parse(String(response.stdoutString || "").trim().split("\n").pop()); } catch (e) {}
            updateResult(step, r);
        }
        onCallFailure: updateResult(step, null)
        onError: updateResult(step, null)
    }
    // The backup file, through the same exec: written with printf (the JSON
    // in single quotes, its own quotes escaped), read back with cat.
    readonly property string backupFile: "/var/lib/webosbrew/rawin-launcher/backup.json"
    function backupRun(step, data) {
        backupService.step = step;
        var command = step === "save"
            ? "printf '%s' '" + JSON.stringify(data).replace(/'/g, "'\\''") + "' > " + backupFile + " && echo '{\"ok\":true}'"
            : "cat " + backupFile + " 2>/dev/null || echo null";
        backupService.callService({command: command});
    }
    Service {
        id: backupService
        property string step: ""
        appId: "com.webos.app.home"
        service: "org.webosbrew.hbchannel.service"
        method: "exec"
        onCallSuccess: {
            var r = null;
            try { r = JSON.parse(String(response.stdoutString || "").trim()); } catch (e) {}
            backupResult(step, r);
        }
        onCallFailure: backupResult(step, null)
        onError: backupResult(step, null)
    }
    // Only the overlay bridge implements runtime mode changes.
    function modeRun(mode, fingerprint) { message = t("err_mode"); }
    // Nor does the Home panel read the remote: the row is not shown there.
    function buttonLoadRun() {}
    function buttonCaptureRun(id, fresh) {}
    function buttonBindRun(code) {}
    function buttonUnbindRun() {}
    // Home-panel variant: apply.sh restarts only LG Home, which hosts the
    // panel. The launch after it brings the freshly loaded Homebar back.
    function restartHomebar() {
        restartService.callService({command: "sh /var/lib/webosbrew/rawin-launcher/apply.sh --restart"});
    }
    Service {
        id: restartService
        appId: "com.webos.app.home"
        service: "org.webosbrew.hbchannel.service"
        method: "exec"
        onCallFailure: message = t("err_restart")
        onError: message = t("err_restart")
    }
    Timer { id: launchTimeout; interval: 8000; onTriggered: { launching=false; message=t("err_slow"); } }

    // These are alternative actions: close apps now, or open LG's screen.
    // Opening the optimiser does not press its Start button.
    function runCloseApps() {
        if (memoryOptimizerAvailable && settings.closeAppsMode === "memory") {
            launching = true; launchTimeout.restart();
            launchService.callService({id: "com.palm.app.settings", params: {target: "MemoryOptimizer"}, reason: "launcher"});
        } else closeAppsService.callService({});
    }

    function drawGlyph(c, symbol) {
        c.beginPath();
        if (symbol === "settings") {
            c.moveTo(6,12); c.lineTo(23,12); c.moveTo(31,12); c.lineTo(34,12);
            c.moveTo(6,28); c.lineTo(9,28); c.moveTo(17,28); c.lineTo(34,28); c.stroke();
            c.beginPath(); c.arc(27,12,4,0,Math.PI*2); c.stroke();
            c.beginPath(); c.arc(13,28,4,0,Math.PI*2);
        } else if (symbol === "light") {
            c.roundedRect(9,11,22,16,3,3); c.moveTo(4,8); c.lineTo(4,32); c.moveTo(36,8); c.lineTo(36,32); c.moveTo(14,33); c.lineTo(26,33);
        } else if (symbol === "plus") {
            c.moveTo(8,14); c.lineTo(20,7); c.lineTo(32,14); c.lineTo(32,26); c.lineTo(20,33); c.lineTo(8,26); c.closePath();
            c.moveTo(20,15); c.lineTo(20,25); c.moveTo(15,20); c.lineTo(25,20);
        } else if (symbol === "bag") {
            c.moveTo(9,14); c.lineTo(31,14); c.lineTo(29,33); c.lineTo(11,33); c.closePath();
            c.moveTo(15,14); c.lineTo(15,12); c.arc(20,12,5,Math.PI,0,false); c.lineTo(25,14);
        } else if (symbol === "home") {
            c.moveTo(6,19); c.lineTo(20,8); c.lineTo(34,19); c.moveTo(10,16); c.lineTo(10,33); c.lineTo(30,33); c.lineTo(30,16);
            c.moveTo(17,33); c.lineTo(17,25); c.lineTo(23,25); c.lineTo(23,33);
        } else if (symbol === "back") {
            c.moveTo(16,10); c.lineTo(6,20); c.lineTo(16,30); c.moveTo(6,20); c.lineTo(34,20);
        } else if (symbol === "add") {
            c.moveTo(20,9); c.lineTo(20,31); c.moveTo(9,20); c.lineTo(31,20);
        } else if (symbol === "tune") {
            c.moveTo(10,6); c.lineTo(10,34); c.moveTo(20,6); c.lineTo(20,34); c.moveTo(30,6); c.lineTo(30,34); c.stroke();
            c.beginPath(); c.roundedRect(6,22,8,6,2,2); c.roundedRect(16,10,8,6,2,2); c.roundedRect(26,18,8,6,2,2);
            c.fillStyle = c.strokeStyle; c.fill();
        } else if (symbol === "apps") {
            c.roundedRect(7,7,11,11,3,3); c.roundedRect(22,7,11,11,3,3); c.roundedRect(7,22,11,11,3,3); c.roundedRect(22,22,11,11,3,3);
        } else if (symbol === "clean") {
            c.roundedRect(8,12,24,20,3,3); c.moveTo(6,12); c.lineTo(34,12); c.moveTo(16,7); c.lineTo(24,7); c.moveTo(15,18); c.lineTo(15,27); c.moveTo(20,18); c.lineTo(20,27); c.moveTo(25,18); c.lineTo(25,27);
        }
        c.stroke();
    }

    // Transparent native HOME surface: keep the current card/video underneath.
    Item {
        id: panel
        anchors.fill: parent
        opacity: shell.foreground ? 1 : 0
        property real lift: shell.foreground ? 0 : shell.px(24)
        transform: Translate { y: panel.lift }
        Behavior on opacity { NumberAnimation { duration: shell.dur(180); easing.type: Easing.OutCubic } }
        Behavior on lift { NumberAnimation { duration: shell.dur(180); easing.type: Easing.OutCubic } }

        // Shade only under the name and the rail, in the lower part of the
        // screen; the rest of the picture stays as it is. Under the settings
        // menu the whole screen is shaded.
        Rectangle {
            id: scrim
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: shell.page === "settings" ? parent.height : shell.page === "apps" ? shell.px(660) : shell.px(540)
            Behavior on height { NumberAnimation { duration: shell.dur(180); easing.type: Easing.OutCubic } }
            property color tint: shell.theme.scrim
            function a(v) { return Qt.rgba(tint.r, tint.g, tint.b, v); }
            gradient: Gradient {
                GradientStop { position: 0.00; color: scrim.a(shell.page === "settings" ? 0.55 : 0) }
                GradientStop { position: 0.22; color: scrim.a(shell.page === "settings" ? 0.65 : 0.30) }
                GradientStop { position: 0.45; color: scrim.a(shell.page === "settings" ? 0.75 : 0.66) }
                GradientStop { position: 0.68; color: scrim.a(0.86) }
                GradientStop { position: 1.00; color: scrim.a(0.93) }
            }
        }
        // The glow in the bottom-left corner, in the colour of what is
        // focused. A shader, so it covers only the part of the screen it
        // reaches: a full-screen one is the costliest thing a TV's GPU is
        // asked for here, and it is redrawn while the colour fades.
        RadialGradient {
            x: 0; y: parent.height - shell.px(455); width: shell.px(1400); height: shell.px(455)
            horizontalOffset: shell.px(192) - width/2; verticalOffset: shell.px(520) - height/2
            horizontalRadius: shell.px(1200); verticalRadius: shell.px(520)
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(shell.glowColor.r, shell.glowColor.g, shell.glowColor.b, 0.34) }
                GradientStop { position: 0.72; color: Qt.rgba(shell.glowColor.r, shell.glowColor.g, shell.glowColor.b, 0) }
            }
        }

        // Status: what is underneath, the weather, then the clock (each can be
        // hidden), on a chip like the input pills, so it reads over any
        // picture without shading the screen.
        Rectangle {
            id: status
            readonly property bool showApp: shell.settings.nowApp && nowTitle !== ""
            visible: showApp || shell.weatherShown || shell.settings.clock || shell.statsText.length > 0
            anchors.right: parent.right; anchors.rightMargin: shell.margin; y: shell.px(32)
            width: statusRow.width + shell.px(48); height: Math.max(shell.px(56), statusRow.height + shell.px(22)); radius: shell.px(18)
            color: shell.surface; border.width: 1; border.color: shell.theme.surfaceEdge
            Row {
                id: statusRow
                anchors.centerIn: parent; spacing: shell.px(18)
                // The load of the TV, small and plain, before the rest of the chip.
                Row {
                    visible: shell.statsText.length > 0; spacing: shell.px(16); anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: shell.statsText
                        Text { text: modelData; font.family: shell.fontName; font.pixelSize: shell.pt(17); color: shell.theme.hint; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                Rectangle { visible: shell.statsText.length > 0 && (status.showApp || shell.weatherShown || shell.settings.clock); width: 1; height: shell.pt(20); color: shell.theme.divider; anchors.verticalCenter: parent.verticalCenter }
                Row {
                    visible: status.showApp; spacing: shell.px(10); anchors.verticalCenter: parent.verticalCenter
                    Rectangle { width: shell.px(7); height: width; radius: width/2; color: shell.theme.focus; anchors.verticalCenter: parent.verticalCenter }
                    // A long app name is cut, not the chip pushed off the screen. Its
                    // width is measured by a hidden twin: an elided Text whose width
                    // hangs on its own implicitWidth keeps an old text's width on the
                    // TV, and a metrics object there misses a change of the text size.
                    Text { id: nowTwin; visible: false; text: nowTitle; font.family: shell.fontName; font.pixelSize: shell.pt(19) }
                    Text {
                        text: nowTitle; font.family: shell.fontName; font.pixelSize: shell.pt(19); color: shell.theme.text; anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(Math.ceil(nowTwin.implicitWidth) + 1, shell.px(480)); elide: Text.ElideRight
                    }
                }
                Rectangle { visible: status.showApp && (shell.weatherShown || shell.settings.clock); width: 1; height: shell.pt(20); color: shell.theme.divider; anchors.verticalCenter: parent.verticalCenter }
                Row {
                    visible: shell.weatherShown; spacing: shell.px(8); anchors.verticalCenter: parent.verticalCenter
                    Canvas {
                        property int box: shell.pt(30)
                        property string kind: shell.weatherKind(shell.weather)
                        property string stroke: shell.theme.text
                        width: box; height: box; anchors.verticalCenter: parent.verticalCenter
                        onKindChanged: requestPaint()
                        onStrokeChanged: requestPaint()
                        onBoxChanged: requestPaint()
                        onVisibleChanged: if (visible) requestPaint()
                        onPaint: {
                            var c=getContext("2d"); c.reset(); c.scale(box/40, box/40);
                            c.strokeStyle = stroke; c.lineWidth = Math.max(1.5, 2.2*shell.u)*40/box; c.lineCap="round"; c.lineJoin="round";
                            shell.drawWeather(c, kind);
                        }
                    }
                    Text { text: shell.weatherTemp + "°"; font.family: shell.fontName; font.pixelSize: shell.pt(21); color: shell.theme.text; anchors.verticalCenter: parent.verticalCenter }
                }
                Rectangle { visible: shell.weatherShown && shell.settings.clock; width: 1; height: shell.pt(20); color: shell.theme.divider; anchors.verticalCenter: parent.verticalCenter }
                Text { visible: shell.settings.clock; text: clock; font.family: shell.fontName; font.bold: true; font.pixelSize: shell.pt(26); font.letterSpacing: -0.4*shell.u; color: shell.theme.heading; anchors.verticalCenter: parent.verticalCenter }
            }
        }

        // Hero: the focused name and one line of context under it.
        Item {
            id: heroGroup
            visible: shell.page !== "settings"
            x: shell.margin; y: shell.heroBaseline - shell.px(160)
            width: shell.width - 2*shell.margin; height: shell.px(220)
            Item { id: heroBase; y: shell.px(160); width: 1; height: 1 }
            Text {
                width: parent.width; anchors.baseline: heroBase.top
                visible: shell.showTitle
                text: shell.hero.title; elide: Text.ElideRight
                font.family: shell.fontName; font.bold: true; font.pixelSize: shell.pt(60); font.letterSpacing: -1.8*shell.u; color: shell.theme.heading; style: Text.Raised; styleColor: shell.theme.headingShadow
            }
            Text {
                y: shell.px(174); width: parent.width; elide: Text.ElideRight
                text: shell.hero.sub; font.family: shell.fontName; font.pixelSize: shell.pt(22)
                color: message ? shell.warning : notice ? shell.theme.heading : shell.theme.text
            }
        }

        // Controls for what is focused, on the bottom line with the version:
        // a key outlined, a colour key filled with the remote's colour. The
        // setting "hints" hides them on Home, Apps and System; the settings
        // menu and editing favourites or shortcuts keep theirs.
        Row {
            visible: shell.pendingRemoval === "" && (shell.settings.hints || shell.page === "settings" || shell.editIndex >= 0 || shell.editSourceIndex >= 0 || shell.editActionIndex >= 0)
            x: shell.margin; y: shell.height - shell.px(47); spacing: shell.px(24)
            Repeater {
                model: shell.hints
                Row {
                    spacing: shell.px(9)
                    Row {
                        spacing: shell.px(6); anchors.verticalCenter: parent.verticalCenter
                        Repeater {
                            model: modelData.keys
                            // Two keys that do the same thing read "hold OK or YELLOW".
                            Row {
                                spacing: shell.px(6); anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    visible: index > 0; text: shell.t("hint_or"); anchors.verticalCenter: parent.verticalCenter
                                    font.family: shell.fontName; font.pixelSize: shell.pt(15); color: shell.theme.hint
                                }
                                Rectangle {
                                    readonly property string colour: modelData.colour
                                    width: keyLabel.implicitWidth+shell.px(14); height: shell.pt(24); radius: shell.px(7)
                                    color: colour === "red" ? shell.keyRed : colour === "yellow" ? shell.keyYellow : "transparent"
                                    border.width: colour ? 0 : Math.max(1, 1.5*shell.u); border.color: shell.theme.keyEdge
                                    Text {
                                        id: keyLabel; anchors.centerIn: parent; text: modelData.label
                                        font.family: shell.fontName; font.bold: true; font.pixelSize: shell.pt(12)
                                        color: parent.colour === "red" ? "#ffffff" : parent.colour === "yellow" ? "#1d1a12" : shell.theme.keyLabel
                                    }
                                }
                            }
                        }
                    }
                    Text { text: modelData.text; font.family: shell.fontName; font.pixelSize: shell.pt(15); color: shell.theme.hint; anchors.verticalCenter: parent.verticalCenter }
                }
            }
        }

        // Rounded app tile with the double focus ring.
        Component {
            id: appTile
            Item {
                id: cell
                property var entry
                property int navIndex: 0
                readonly property int size: parent && parent.tileSize ? parent.tileSize : shell.tile
                readonly property int corner: shell.px(30)
                property bool chosen: shell.selected === navIndex
                readonly property bool editing: shell.page === "home" && shell.editIndex === navIndex
                readonly property bool starred: shell.page === "apps" && entry !== undefined && shell.favouriteKeys.indexOf(entry.id) >= 0
                readonly property bool hidden: shell.page === "apps" && entry !== undefined && shell.hiddenIds.indexOf(entry.id) >= 0
                width: size; height: size
                z: chosen ? 2 : 0
                opacity: hidden ? 0.45 : 1
                scale: chosen ? (shell.pressing ? 1.03 : 1.1) : 1
                property real lift: chosen ? -6*shell.u : 0
                Behavior on lift { NumberAnimation { duration: shell.dur(180); easing.type: Easing.OutCubic } }
                transform: Translate { y: cell.lift }
                Behavior on scale { NumberAnimation { duration: shell.dur(180); easing.type: Easing.OutCubic } }
                Rectangle { visible: cell.chosen; anchors.centerIn: parent; width: cell.size+shell.px(14); height: width; radius: cell.corner+shell.px(7); color: cell.editing ? shell.warning : shell.theme.ring }
                Rectangle { visible: cell.chosen; anchors.centerIn: parent; width: cell.size+shell.px(8); height: width; radius: cell.corner+shell.px(4); color: shell.theme.gap }
                Rectangle { anchors.fill: parent; radius: cell.corner; color: shell.theme.tile }
                Text {
                    visible: icon.status !== Image.Ready
                    anchors.centerIn: parent; text: cell.entry && cell.entry.title ? cell.entry.title.charAt(0) : ""
                    font.family: shell.fontName; font.bold: true; font.pixelSize: shell.px(40); color: shell.ink2
                }
                Image {
                    id: icon; anchors.fill: parent; visible: false
                    source: cell.entry && cell.entry.icon ? cell.entry.icon : ""
                    fillMode: Image.PreserveAspectCrop; asynchronous: true; smooth: true
                    // Decoded at twice the tile, for the focus zoom; no larger.
                    sourceSize.width: 2*cell.size; sourceSize.height: 2*cell.size
                }
                Rectangle { id: corners; anchors.fill: parent; radius: cell.corner; visible: false }
                OpacityMask { anchors.fill: parent; source: icon; maskSource: corners; visible: icon.status === Image.Ready }
                // Edit handles sit on the tile edges, inside the gap to the neighbours.
                Repeater {
                    model: cell.editing ? shell.moveHandles(shell.editIndex, shell.favCount) : []
                    Rectangle {
                        x: modelData === "‹" ? -shell.px(14) : cell.size-shell.px(14); anchors.verticalCenter: parent.verticalCenter
                        width: shell.px(28); height: shell.px(44); radius: shell.px(14); color: shell.theme.handle; border.width: Math.max(1, 2*shell.u); border.color: shell.warning
                        Text { anchors.centerIn: parent; anchors.verticalCenterOffset: -2*shell.u; text: modelData; font.family: shell.fontName; font.bold: true; font.pixelSize: shell.px(30); color: shell.warning }
                    }
                }
                // Favourite marker in All applications.
                Rectangle {
                    visible: cell.starred; x: cell.size-shell.px(20); y: -shell.px(6); width: shell.px(26); height: width; radius: width/2
                    color: shell.theme.focus; border.width: shell.px(3); border.color: shell.theme.gap
                }
                // The pointer: a click focuses and opens; held, it does what
                // holding OK does (a Magic Remote's OK is a click while its
                // pointer shows). Movement only changes the highlighted item.
                MouseArea {
                    id: cellPointer
                    enabled: !shell.editInputIcon
                    anchors.fill: parent; hoverEnabled: true
                    onEntered: { if (shell.pointerMoved(cellPointer, {x: mouseX, y: mouseY})) shell.selected=cell.navIndex; }
                    onPositionChanged: { if (shell.pointerMoved(cellPointer, mouse)) shell.selected=cell.navIndex; }
                    property bool held: false
                    onPressed: { held = false; shell.noteActivity(); }
                    onPressAndHold: { held = true; shell.selected=cell.navIndex; shell.secondaryAction(); }
                    onClicked: { if (held) return; shell.selected=cell.navIndex; shell.activate(shell.itemAt(cell.navIndex)); }
                }
            }
        }
        // Rounded line-icon tile: All applications, System and its tools.
        Component {
            id: glyphTile
            Item {
                id: glyphCell
                property var entry
                property int navIndex: 0
                // Size comes from the Loader so the Canvas paints once at the right scale.
                readonly property int size: parent && parent.glyphSize ? parent.glyphSize : shell.px(88)
                readonly property bool big: size > 100*shell.u
                readonly property bool mid: size > 70*shell.u
                readonly property int corner: big ? shell.px(30) : mid ? shell.px(24) : shell.px(18)
                property bool chosen: shell.selected === navIndex
                readonly property bool editing: shell.page === "home" && navIndex >= shell.favSlots + shell.sourceCount && shell.editActionIndex === navIndex - shell.favSlots - shell.sourceCount
                // A new version is there: a dot on the way to the updater.
                readonly property bool badge: shell.updateAvailable && entry !== undefined && entry !== null &&
                    (entry.action === "system" || entry.action === "launcherSettings")
                width: size; height: size
                z: chosen ? 2 : 0
                scale: chosen ? (shell.pressing ? 1.03 : 1.1) : 1
                property real lift: chosen ? -6*shell.u : 0
                Behavior on lift { NumberAnimation { duration: shell.dur(180); easing.type: Easing.OutCubic } }
                transform: Translate { y: glyphCell.lift }
                Behavior on scale { NumberAnimation { duration: shell.dur(180); easing.type: Easing.OutCubic } }
                Rectangle { visible: glyphCell.chosen; anchors.centerIn: parent; width: glyphCell.size+shell.px(14); height: width; radius: glyphCell.corner+shell.px(7); color: glyphCell.editing ? shell.warning : shell.theme.ring }
                Rectangle { visible: glyphCell.chosen; anchors.centerIn: parent; width: glyphCell.size+shell.px(8); height: width; radius: glyphCell.corner+shell.px(4); color: shell.theme.gap }
                Rectangle {
                    anchors.fill: parent; radius: glyphCell.corner
                    color: glyphCell.chosen ? shell.theme.focus : shell.chip
                    border.width: glyphCell.chosen ? 0 : 1; border.color: shell.chipEdge
                    Behavior on color { ColorAnimation { duration: shell.dur(180) } }
                }
                Canvas {
                    property int box: glyphCell.big ? shell.px(44) : glyphCell.mid ? shell.px(32) : shell.px(28)
                    anchors.centerIn: parent; width: box; height: box
                    property string symbol: glyphCell.entry && glyphCell.entry.symbol ? glyphCell.entry.symbol : ""
                    property string stroke: glyphCell.chosen ? shell.theme.onFocus : shell.ink
                    onSymbolChanged: requestPaint()
                    onStrokeChanged: requestPaint()
                    onBoxChanged: requestPaint()
                    onPaint: {
                        var c=getContext("2d"); c.reset(); c.scale(box/40, box/40);
                        c.strokeStyle = stroke; c.lineWidth = Math.max(1.5, 2.2*shell.u)*40/box; c.lineCap="round"; c.lineJoin="round";
                        shell.drawGlyph(c, symbol);
                    }
                }
                Rectangle {
                    visible: glyphCell.badge; x: glyphCell.size-shell.px(16); y: -shell.px(4)
                    width: shell.px(20); height: width; radius: width/2
                    color: shell.warning; border.width: shell.px(3); border.color: shell.theme.gap
                }
                Loader {
                    visible: glyphCell.editing; active: visible; sourceComponent: sourceEditControls
                    width: shell.px(68); height: shell.px(28)
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.top; anchors.bottomMargin: shell.px(12)
                    onLoaded: item.forShortcut = true
                }
                MouseArea {
                    id: glyphPointer
                    enabled: !shell.editInputIcon
                    anchors.fill: parent; hoverEnabled: true
                    onEntered: { if (shell.pointerMoved(glyphPointer, {x: mouseX, y: mouseY})) shell.selected=glyphCell.navIndex; }
                    onPositionChanged: { if (shell.pointerMoved(glyphPointer, mouse)) shell.selected=glyphCell.navIndex; }
                    property bool held: false
                    onPressed: { held = false; shell.noteActivity(); }
                    onPressAndHold: { held = true; shell.selected=glyphCell.navIndex; shell.secondaryAction(); }
                    onClicked: { if (held) return; shell.selected=glyphCell.navIndex; shell.activate(shell.itemAt(glyphCell.navIndex)); }
                }
            }
        }
        // A source pill on the Home rail: HDMI n with the device under it, or Live TV.
        Component {
            id: pillTile
            Rectangle {
                id: pill
                property var entry
                property int navIndex: 0
                property bool chosen: shell.selected === navIndex
                readonly property bool editing: shell.page === "home" && shell.editSourceIndex === navIndex - shell.favSlots
                property real lift: chosen ? -4*shell.u : 0
                width: shell.pillWidthFor(pill.entry, titleTwins.rev)
                readonly property int textCap: Math.max(shell.px(20), width - shell.px(44) - (shell.inputIconsVisible ? shell.px(44) : 0))
                height: shell.inputIconOnly ? shell.sourceTileWidth : Math.max(shell.px(64), pillText.height + shell.px(20)); radius: shell.px(18)
                color: chosen ? shell.theme.focus : shell.chip
                border.width: chosen ? 0 : 1; border.color: shell.chipEdge
                // Nothing plugged in: the pill stays solid, its text dimmed.
                readonly property bool dim: !chosen && entry !== undefined && entry.present === false
                // Editing keeps an amber outline, with the controls above the tile;
                // the Loader raises the chosen pill over its neighbours.
                Rectangle {
                    visible: pill.editing; anchors.fill: parent; anchors.margins: -shell.px(5)
                    radius: pill.radius + shell.px(5); color: "transparent"
                    border.width: Math.max(1, 2*shell.u); border.color: shell.warning
                }

                scale: chosen ? (shell.pressing ? 1.02 : 1.06) : 1
                transform: Translate { y: pill.lift }
                Behavior on lift { NumberAnimation { duration: shell.dur(180); easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: shell.dur(180); easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: shell.dur(180) } }
                DeviceIcon {
                    visible: shell.inputIconsVisible
                    iconId: shell.sourceIcon(pill.entry)
                    objectName: "deviceGlyph"
                    width: shell.px(48); height: width
                    x: shell.inputIconOnly ? (parent.width-width)/2 : shell.px(12); anchors.verticalCenter: parent.verticalCenter
                    ink: pill.chosen ? shell.theme.onFocus : pill.dim ? shell.theme.dim : shell.ink
                }
                // UP opens the icon picker without changing the input's order.
                Loader {
                    visible: pill.editing && !shell.editInputIcon
                    active: visible; sourceComponent: sourceEditControls
                    width: shell.px(104); height: shell.px(28)
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.top; anchors.bottomMargin: shell.px(12)
                }
                Column {
                    id: pillText
                    visible: !shell.inputIconOnly
                    // What the setting "Input text" makes of this source: the
                    // port, its label, or both in the chosen order.
                    readonly property var texts: shell.inputTexts(pill.entry)
                    readonly property bool scrolls: shell.settings.inputOverflow === "scroll"
                    anchors.centerIn: parent; anchors.horizontalCenterOffset: shell.inputIconsVisible ? shell.px(28) : 0; spacing: 1
                    // A line wider than the pill ends with an ellipsis, or
                    // scrolls slowly to its end and back while the tile is
                    // focused (the setting "Long input names").
                    Item {
                        id: firstBox
                        objectName: "inputPrimaryBox"
                        readonly property real full: firstTwin.implicitWidth
                        readonly property bool over: full > pill.textCap + 0.5
                        readonly property bool marquee: pillText.scrolls && over && pill.chosen
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(pill.textCap, Math.max(1, full)); height: firstTwin.implicitHeight
                        clip: true
                        onMarqueeChanged: if (!marquee) firstText.x = 0
                        Text {
                            id: firstTwin; visible: false; text: pillText.texts.primary
                            font.family: shell.fontName; font.bold: true
                            font.pixelSize: pillText.texts.secondary ? shell.pt(19) : shell.pt(21); font.letterSpacing: -0.2*shell.u
                        }
                        Text {
                            id: firstText; objectName: "inputPrimaryText"; text: pillText.texts.primary
                            width: firstBox.marquee ? firstBox.full : firstBox.width
                            horizontalAlignment: Text.AlignHCenter; elide: firstBox.marquee ? Text.ElideNone : Text.ElideRight
                            font.family: shell.fontName; font.bold: true
                            font.pixelSize: pillText.texts.secondary ? shell.pt(19) : shell.pt(21); font.letterSpacing: -0.2*shell.u
                            color: pill.chosen ? shell.theme.onFocus : pill.dim ? shell.theme.dim : shell.theme.label
                        }
                        SequentialAnimation {
                            running: firstBox.marquee; loops: Animation.Infinite
                            PauseAnimation { duration: 1200 }
                            NumberAnimation {
                                target: firstText; property: "x"; from: 0; to: -(firstBox.full - firstBox.width)
                                duration: Math.max(700, Math.round((firstBox.full - firstBox.width) * 22)); easing.type: Easing.InOutQuad
                            }
                            PauseAnimation { duration: 1000 }
                            NumberAnimation { target: firstText; property: "x"; to: 0; duration: 700; easing.type: Easing.InOutQuad }
                        }
                    }
                    Item {
                        id: secondBox
                        readonly property real full: secondTwin.implicitWidth
                        readonly property bool over: full > pill.textCap + 0.5
                        readonly property bool marquee: pillText.scrolls && over && pill.chosen
                        visible: pillText.texts.secondary !== ""
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(pill.textCap, Math.max(1, full)); height: secondTwin.implicitHeight
                        clip: true
                        onMarqueeChanged: if (!marquee) secondText.x = 0
                        Text { id: secondTwin; visible: false; text: pillText.texts.secondary; font.family: shell.fontName; font.pixelSize: shell.pt(13) }
                        Text {
                            id: secondText; text: pillText.texts.secondary
                            width: secondBox.marquee ? secondBox.full : secondBox.width
                            horizontalAlignment: Text.AlignHCenter; elide: secondBox.marquee ? Text.ElideNone : Text.ElideRight
                            font.family: shell.fontName; font.pixelSize: shell.pt(13)
                            color: pill.chosen ? shell.theme.onFocus2 : pill.dim ? shell.theme.dim2 : shell.ink3
                        }
                        SequentialAnimation {
                            running: secondBox.marquee; loops: Animation.Infinite
                            PauseAnimation { duration: 1200 }
                            NumberAnimation {
                                target: secondText; property: "x"; from: 0; to: -(secondBox.full - secondBox.width)
                                duration: Math.max(700, Math.round((secondBox.full - secondBox.width) * 22)); easing.type: Easing.InOutQuad
                            }
                            PauseAnimation { duration: 1000 }
                            NumberAnimation { target: secondText; property: "x"; to: 0; duration: 700; easing.type: Easing.InOutQuad }
                        }
                    }
                }
                MouseArea {
                    id: pillPointer
                    enabled: !shell.editInputIcon
                    anchors.fill: parent; hoverEnabled: true
                    onEntered: { if (shell.pointerMoved(pillPointer, {x: mouseX, y: mouseY})) shell.selected=pill.navIndex; }
                    onPositionChanged: { if (shell.pointerMoved(pillPointer, mouse)) shell.selected=pill.navIndex; }
                    property bool held: false
                    onPressed: { held = false; shell.noteActivity(); }
                    onPressAndHold: { held = true; shell.selected=pill.navIndex; shell.secondaryAction(); }
                    onClicked: { if (held) return; shell.selected=pill.navIndex; shell.activate(shell.itemAt(pill.navIndex)); }
                }
            }
        }

        // Live TV: a tile as big as a shortcut instead of a pill, since "TV"
        // needs no room for a name; it is edited the same way.
        Component {
            id: tvTile
            Item {
                id: tvCell
                property var entry
                property int navIndex: 0
                readonly property int size: shell.sourceTileWidth
                readonly property bool chosen: shell.selected === navIndex
                readonly property bool editing: shell.page === "home" && shell.editSourceIndex === navIndex - shell.favSlots
                width: size; height: size
                scale: chosen ? (shell.pressing ? 1.03 : 1.1) : 1
                property real lift: chosen ? -6*shell.u : 0
                Behavior on lift { NumberAnimation { duration: shell.dur(180); easing.type: Easing.OutCubic } }
                transform: Translate { y: tvCell.lift }
                Behavior on scale { NumberAnimation { duration: shell.dur(180); easing.type: Easing.OutCubic } }
                Rectangle { visible: tvCell.chosen; anchors.centerIn: parent; width: tvCell.size+shell.px(14); height: width; radius: shell.px(18)+shell.px(7); color: tvCell.editing ? shell.warning : shell.theme.ring }
                Rectangle { visible: tvCell.chosen; anchors.centerIn: parent; width: tvCell.size+shell.px(8); height: width; radius: shell.px(18)+shell.px(4); color: shell.theme.gap }
                Rectangle {
                    anchors.fill: parent; radius: shell.px(18)
                    color: tvCell.chosen ? shell.theme.focus : shell.chip
                    border.width: tvCell.chosen ? 0 : 1; border.color: shell.chipEdge
                    Behavior on color { ColorAnimation { duration: shell.dur(180) } }
                }
                DeviceIcon {
                    objectName: "tvDeviceGlyph"
                    visible: shell.settings.tvIcon !== "tv"
                    anchors.centerIn: parent; width: shell.px(48); height: width
                    iconId: shell.settings.tvIcon === "tv" ? "tv-screen" : shell.settings.tvIcon
                    ink: tvCell.chosen ? shell.theme.onFocus : shell.ink
                }
                Loader {
                    visible: tvCell.editing && !shell.editInputIcon
                    active: visible; sourceComponent: sourceEditControls
                    width: shell.px(104); height: shell.px(28)
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.top; anchors.bottomMargin: shell.px(12)
                }
                Text {
                    visible: shell.settings.tvIcon === "tv"
                    anchors.centerIn: parent; text: tvCell.entry ? tvCell.entry.title : ""
                    font.family: shell.fontName; font.bold: true; font.pixelSize: shell.pt(19)
                    color: tvCell.chosen ? shell.theme.onFocus : shell.ink
                }
                Rectangle {
                    visible: tvCell.editing; anchors.fill: parent; anchors.margins: -shell.px(5)
                    radius: shell.px(18) + shell.px(5); color: "transparent"
                    border.width: Math.max(1, 2*shell.u); border.color: shell.warning
                }

                MouseArea {
                    id: tvPointer
                    enabled: !shell.editInputIcon
                    anchors.fill: parent; hoverEnabled: true
                    onEntered: { if (shell.pointerMoved(tvPointer, {x: mouseX, y: mouseY})) shell.selected = tvCell.navIndex; }
                    onPositionChanged: { if (shell.pointerMoved(tvPointer, mouse)) shell.selected = tvCell.navIndex; }
                    property bool held: false
                    onPressed: { held = false; shell.noteActivity(); }
                    onPressAndHold: { held = true; shell.selected = tvCell.navIndex; shell.secondaryAction(); }
                    onClicked: { if (held) return; shell.selected = tvCell.navIndex; shell.activate(shell.itemAt(tvCell.navIndex)); }
                }
            }
        }

        // Each input measures its own two lines without a width constraint.
        // The rail reserves their sum, so short names leave room for favourites.
        Item {
            id: titleTwins
            visible: false
            property int rev: 0
            Repeater {
                id: sourceTwins
                model: sources
                onItemAdded: titleTwins.rev++
                onItemRemoved: titleTwins.rev++
                Item {
                    readonly property string sourceId: modelData.id
                    readonly property var texts: shell.inputTexts(modelData)
                    readonly property int pillWidth: shell.inputIconOnly ? shell.px(72) : Math.max(shell.sourceMinWidth,
                        Math.min(shell.px(200), Math.ceil(Math.max(primaryTwin.implicitWidth, secondaryTwin.implicitWidth)) + shell.px(shell.inputIconsVisible ? 88 : 44)))
                    onPillWidthChanged: titleTwins.rev++
                    Text {
                        id: primaryTwin; text: parent.texts.primary
                        font.family: shell.fontName; font.bold: true
                        font.pixelSize: shell.pt(parent.texts.secondary ? 19 : 21)
                        font.letterSpacing: -0.2*shell.u
                    }
                    Text {
                        id: secondaryTwin; text: parent.texts.secondary
                        font.family: shell.fontName; font.pixelSize: shell.pt(13)
                    }
                }
            }
        }

        // Home rail: favourites, sources, the shortcuts (System among them).
        Row {
            id: rail
            visible: page === "home"
            x: shell.margin; y: shell.railY; height: shell.tile; spacing: shell.railGroupGap
            // Should the rail still be wider than the screen allows (a set
            // with many inputs), it is drawn a little smaller rather than cut.
            transformOrigin: Item.Left
            scale: Math.min(1, (shell.width - 2*shell.margin) / Math.max(1, width))
            Row {
                spacing: shell.gap; anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    id: favouriteCells
                    model: favourites
                    Loader {
                        property int tileSize: shell.favouriteTile
                        sourceComponent: appTile; z: item && item.chosen ? 2 : 0
                        onLoaded: { item.entry=modelData; item.navIndex=index; }
                    }
                }
                Loader {
                    active: shell.showAddTile
                    visible: active
                    property int glyphSize: shell.favouriteTile
                    sourceComponent: glyphTile
                    onLoaded: { item.entry = Qt.binding(function() { return shell.addFavouritesTile; }); item.navIndex = 0; }
                }
            }
            Row {
                id: sourceRow
                spacing: shell.px(12); anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    id: sourceCells
                    model: sources
                    Loader {
                        sourceComponent: modelData.kind === "tv" ? tvTile : pillTile
                        z: item && item.chosen ? 2 : 0
                        onLoaded: { item.entry=modelData; item.navIndex=Qt.binding(function() { return shell.favSlots+index; }); }
                    }
                }
            }
            Row {
                spacing: shell.px(12); anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    id: shortcutCells
                    model: shell.homeActions
                    Loader {
                        property int glyphSize: shell.px(64)
                        sourceComponent: glyphTile
                        // Like the other groups: the chosen tile (and its edit
                        // handles) paints over the tiles after it, not under.
                        z: item && item.chosen ? 2 : 0
                        onLoaded: {
                            item.entry = Qt.binding(function() { return modelData; });
                            item.navIndex = Qt.binding(function() { return shell.favSlots+shell.sourceCount+index; });
                        }
                    }
                }
            }
        }

        // Keep all edit directions above the artwork, in a single row.
        // Empty end directions retain their space so UP always stays centred.
        Component {
            id: sourceEditControls
            Row {
                property bool forShortcut: false
                readonly property int editAt: forShortcut ? shell.editActionIndex : shell.editSourceIndex
                readonly property int editCount: forShortcut ? shell.homeActions.length : shell.sourceCount
                id: editControls
                objectName: forShortcut ? "shortcutEditControls" : "sourceEditControls"
                spacing: shell.px(4)
                Repeater {
                    model: editControls.forShortcut ? ["‹", "›"] : ["‹", "▲", "›"]
                    Rectangle {
                        readonly property bool available: modelData === "▲" || (modelData === "‹" ? editControls.editAt > 0 : editControls.editAt < editControls.editCount-1)
                        width: shell.px(32); height: shell.px(28); radius: shell.px(8)
                        color: shell.theme.handle; border.color: shell.warning
                        opacity: available ? 1 : 0
                        Text {
                            anchors.centerIn: parent; anchors.verticalCenterOffset: modelData === "▲" ? 0 : -shell.u
                            text: modelData; color: shell.warning; font.family: shell.fontName
                            font.bold: true; font.pixelSize: shell.px(modelData === "▲" ? 16 : 26)
                        }
                        MouseArea {
                            anchors.fill: parent; enabled: parent.available
                            onClicked: {
                                shell.noteActivity();
                                if (modelData === "▲") shell.editInputIcon = true;
                                else if (editControls.forShortcut) shell.moveHomeAction(shell.editActionIndex, shell.editActionIndex + (modelData === "‹" ? -1 : 1));
                                else shell.moveSource(shell.editSourceIndex, shell.editSourceIndex + (modelData === "‹" ? -1 : 1));
                            }
                        }
                    }
                }
            }
        }

        // One warning follows the edited tile in panel coordinates, so it
        // stays inside the screen even at either end of a scaled rail.
        Rectangle {
            id: removalWarning
            objectName: "removalWarning"
            readonly property var targetTile: shell.removalTarget()
            readonly property point below: {
                if (!targetTile) return Qt.point(0, 0);
                // Track the focus animation as well as the item's geometry.
                var focusScale = targetTile.scale, lift = targetTile.lift;
                return targetTile.mapToItem(removalWarning.parent, targetTile.width/2, targetTile.height);
            }
            visible: shell.pendingRemoval !== "" && shell.pendingRemoval === shell.removalKey && targetTile !== null
            z: 40; width: Math.min(shell.width-2*shell.margin, removeLabel.implicitWidth+shell.px(52)); height: shell.px(38)
            x: Math.max(shell.margin, Math.min(shell.width-shell.margin-width, below.x-width/2))
            y: Math.min(below.y+shell.px(12), shell.height-height-shell.px(14))
            radius: shell.px(12); color: "#451d27"; border.color: "#ff7187"; border.width: Math.max(1, shell.u)
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: shell.dur(100) } }
            Rectangle {
                anchors.left: parent.left; anchors.leftMargin: shell.px(12); anchors.verticalCenter: parent.verticalCenter
                width: shell.px(18); height: width; radius: width/2; color: "#ff8da0"
                Text { anchors.centerIn: parent; text: "!"; color: "#451d27"; font.family: shell.fontName; font.bold: true; font.pixelSize: shell.px(13) }
            }
            Text {
                id: removeLabel; anchors.centerIn: parent; anchors.horizontalCenterOffset: shell.px(10)
                text: shell.t("confirm_remove_down"); color: "#fff0f3"; font.family: shell.fontName; font.pixelSize: shell.pt(14)
            }
        }

        Rectangle {
            id: iconPicker
            objectName: "inputIconPicker"
            visible: shell.page === "home" && shell.editSourceIndex >= 0 && shell.editInputIcon
            z: 30; width: shell.px(480); height: shell.px(264); radius: shell.px(22)
            x: Math.max(shell.margin, Math.min(shell.width-shell.margin-width, shell.iconEditorCenter()-width/2))
            y: shell.railY-height-shell.px(28)
            color: shell.chip; border.color: shell.warning; border.width: Math.max(1, 2*shell.u)
            MouseArea { anchors.fill: parent; onClicked: {} }

            Text {
                anchors.top: parent.top; anchors.topMargin: shell.px(18); anchors.horizontalCenter: parent.horizontalCenter
                text: shell.t("hint_input_icon"); color: shell.ink2; font.family: shell.fontName; font.pixelSize: shell.pt(16)
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter; y: shell.px(52); spacing: shell.px(12)
                Repeater {
                    model: [-2, -1, 0, 1, 2]
                    Rectangle {
                        width: shell.px(64); height: width; radius: shell.px(16)
                        readonly property var choice: shell.editIconChoices[(shell.sourceIconIndex() + modelData + shell.editIconChoices.length) % shell.editIconChoices.length]
                        color: modelData === 0 ? shell.theme.focus : "transparent"
                        opacity: Math.abs(modelData) === 2 ? 0.45 : 1
                        DeviceIcon { visible: parent.choice.id !== "tv"; anchors.centerIn: parent; width: shell.px(48); height: width; iconId: parent.choice.id === "tv" ? "tv-screen" : parent.choice.id; ink: modelData === 0 ? shell.theme.onFocus : shell.ink }
                        Text { visible: parent.choice.id === "tv"; anchors.centerIn: parent; text: "TV"; font.family: shell.fontName; font.bold: true; font.pixelSize: shell.pt(21); color: modelData === 0 ? shell.theme.onFocus : shell.ink }
                        MouseArea { anchors.fill: parent; onClicked: { shell.noteActivity(); shell.cycleInputIcon(modelData); } }
                    }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter; y: shell.px(132)
                text: shell.sourceIconTitle() + "  ·  " + (shell.sourceIconIndex()+1) + " / " + shell.editIconChoices.length
                color: shell.ink; font.family: shell.fontName; font.bold: true; font.pixelSize: shell.pt(21)
            }
            Text {
                x: shell.px(22); width: parent.width-2*x; y: shell.px(170); horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                text: shell.iconSource && shell.iconSource.kind === "tv" ? shell.t("tv_icon_help") : shell.t("input_icon_help"); color: shell.ink3; font.family: shell.fontName; font.pixelSize: shell.pt(14)
            }
            Rectangle {
                objectName: "closeIconPicker"
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: shell.px(12)
                width: closeIconLabel.implicitWidth+shell.px(28); height: shell.px(30)
                radius: shell.px(8); color: shell.theme.handle
                Text {
                    id: closeIconLabel; anchors.centerIn: parent
                    text: "▼  " + shell.t("hint_close_icons"); color: shell.warning
                    font.family: shell.fontName; font.pixelSize: shell.pt(14)
                }
                MouseArea { anchors.fill: parent; onClicked: { shell.noteActivity(); shell.editInputIcon = false; } }
            }
            MouseArea {
                anchors.fill: parent; acceptedButtons: Qt.NoButton
                onWheel: { shell.noteActivity(); var delta = wheel.angleDelta.y || wheel.pixelDelta.y; if (delta) shell.cycleInputIcon(delta > 0 ? -1 : 1); }
            }
        }

        // All applications: as many columns as the width takes, two rows visible.
        Flickable {
            id: appGrid
            visible: page === "apps"
            // Two rows and the focus ring's room under them, short of the next
            // row's favourite markers.
            x: shell.margin-shell.px(20); y: shell.height-shell.px(360); width: shell.appColumns*(shell.tile+shell.gap)-shell.gap+shell.px(40); height: 2*shell.tile+shell.gap+shell.px(40)
            clip: true; interactive: false
            readonly property int step: shell.tile+shell.gap
            readonly property int firstRow: Math.round(contentY/step)
            contentWidth: width; contentHeight: Math.max(height, Math.ceil(apps.length/shell.appColumns)*step+shell.px(48)-shell.gap)
            Behavior on contentY { enabled: !appWheelPause.running; NumberAnimation { duration: shell.dur(180); easing.type: Easing.OutCubic } }
            Timer { id: appWheelPause; interval: 200 }
            function scrollWheel(wheel) {
                var delta = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 120 * step;
                if (delta === 0) { wheel.accepted = false; return; }
                appWheelPause.restart();
                shell.pointerBlockedUntil = Date.now() + 200;
                contentY = Math.max(0, Math.min(contentY - delta, contentHeight - height));
                // Keep keyboard/OK focus on a visible tile without launching anything.
                // Ignore focus-follow while scrolling so it cannot undo the wheel.
                if (shell.apps.length > 0) {
                    var first = Math.ceil(contentY / step);
                    var last = Math.max(first, Math.floor((contentY + height - shell.px(24) - shell.tile) / step));
                    var row = Math.floor(shell.selected / shell.appColumns);
                    row = Math.max(first, Math.min(row, last));
                    shell.selected = Math.min(shell.apps.length - 1, row * shell.appColumns + shell.selected % shell.appColumns);
                }
                wheel.accepted = true;
            }
            Repeater {
                model: apps
                Loader {
                    readonly property int row: Math.floor(index/shell.appColumns)
                    x: shell.px(20)+(index%shell.appColumns)*appGrid.step; y: shell.px(24)+row*appGrid.step
                    z: item && item.chosen ? 2 : 0
                    // Only the rows on screen and the next one are built; a long
                    // list is not a long wait, nor a hundred icons in memory.
                    active: row >= appGrid.firstRow-1 && row <= appGrid.firstRow+2
                    sourceComponent: appTile
                    onLoaded: { item.entry=modelData; item.navIndex=index; }
                }
            }
            Connections {
                target: shell
                onSelectedChanged: {
                    if (shell.page !== "apps" || appWheelPause.running) return;
                    var row=Math.floor(shell.selected/shell.appColumns), first=Math.round(appGrid.contentY/appGrid.step);
                    if (row < first) appGrid.contentY=row*appGrid.step;
                    else if (row > first+1) appGrid.contentY=(row-1)*appGrid.step;
                }
                onPageChanged: appGrid.contentY=0
            }
        }
        // Wheel events over tiles and gaps scroll the viewport; clicks pass through.
        MouseArea {
            visible: shell.page === "apps"
            x: appGrid.x; y: appGrid.y; width: appGrid.width; height: appGrid.height
            acceptedButtons: Qt.NoButton
            onWheel: { shell.noteActivity(); appGrid.scrollWheel(wheel); }
        }
        Rectangle {
            visible: page === "apps" && appGrid.contentHeight > appGrid.height
            x: shell.width-shell.margin+shell.px(20); y: shell.height-shell.px(336); width: shell.px(4); height: 2*shell.tile+shell.gap; radius: width/2; color: shell.theme.track
            Rectangle {
                width: parent.width; radius: width/2; color: shell.theme.focus
                height: parent.height*appGrid.height/appGrid.contentHeight
                y: (parent.height-height)*appGrid.contentY/Math.max(1, appGrid.contentHeight-appGrid.height)
            }
        }

        // System: the same rail, glyph tiles at full size.
        Row {
            visible: page === "system"
            x: shell.margin; y: shell.railY; spacing: shell.gap
            Repeater {
                model: shell.tools
                Loader {
                    property int glyphSize: shell.tile
                    sourceComponent: glyphTile; z: item && item.chosen ? 2 : 0
                    onLoaded: { item.entry=modelData; item.navIndex=index; }
                }
            }
        }

        // The version, the TV's webOS and the variant, bottom right.
        Text {
            visible: page === "system"
            anchors.right: parent.right; anchors.rightMargin: shell.margin; y: shell.height-shell.px(43)
            text: "Homebar " + Config.version + (Config.webos ? " · webOS " + Config.webos : "") + (Config.platform ? " · " + Config.platform : "")
            font.family: shell.fontName; font.pixelSize: shell.pt(14); color: shell.theme.version
        }

        // Launcher settings: a menu over most of the screen, in the panel's
        // own colours. On the left the settings in groups, each with its
        // value; on the right the values of the focused one, a dot on the
        // chosen value, or what an action has to say. Up and down move, OK
        // or right goes into the values, where up and down choose (each
        // applies at once: the menu itself is the preview) and OK or left
        // come back; BACK closes the menu.
        // Launcher settings is a large subtree: it is built when the menu is
        // first opened, or during the first quiet moment, so showing the panel
        // on HOME never waits for it.
        Loader {
            id: menuLoader
            active: shell.menuLoaded
            sourceComponent: menuComponent
        }
        Component {
            id: menuComponent
            Rectangle {
                id: menu
                visible: opacity > 0
                opacity: shell.page === "settings" ? 1 : 0
                property real lift: shell.page === "settings" ? 0 : shell.px(16)
                transform: Translate { y: menu.lift }
                Behavior on opacity { NumberAnimation { duration: shell.dur(180); easing.type: Easing.OutCubic } }
                Behavior on lift { NumberAnimation { duration: shell.dur(180); easing.type: Easing.OutCubic } }
                x: shell.margin; y: shell.px(110)
                width: shell.width - 2*shell.margin; height: shell.height - shell.px(110) - shell.px(96)
                radius: shell.px(30); color: shell.chip; border.width: 1; border.color: shell.chipEdge
                readonly property int pad: shell.px(40)
                readonly property int rowHeight: shell.pt(56)
                readonly property int headerHeight: shell.pt(44)
                // Under the title, whatever the text size.
                readonly property int listTop: shell.px(30) + Math.round(shell.pt(34)*1.3) + shell.px(26)
                readonly property int listWidth: shell.px(720)

                Text {
                    x: menu.pad; y: shell.px(30)
                    text: shell.t("launcher_settings"); font.family: shell.fontName; font.bold: true; font.pixelSize: shell.pt(34); font.letterSpacing: -0.8*shell.u; color: shell.ink
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: menu.pad; y: shell.px(30) + Math.round(shell.pt(34)*1.3) - shell.pt(14) - shell.px(6)
                    text: "Homebar " + Config.version + (Config.webos ? " · webOS " + Config.webos : "") + (Config.platform ? " · " + Config.platform : "")
                    font.family: shell.fontName; font.pixelSize: shell.pt(14); color: shell.ink3
                }
                Rectangle { x: menu.pad; y: menu.listTop - shell.px(14); width: parent.width - 2*menu.pad; height: 1; color: shell.chipEdge }

                // Where a row starts in the list, from the rows' heights (the
                // column places them only a frame later).
                function rowY(index) {
                    var y = 0;
                    for (var i=0; i<shell.menuRows.length; i++) {
                        var r = shell.menuRows[i];
                        if (r.index === index) return y;
                        y += r.header !== undefined ? menu.headerHeight + (i > 0 ? shell.px(12) : 0) : menu.rowHeight;
                    }
                    return y;
                }
                // The settings, in groups, scrolling so the focused one stays in view.
                Flickable {
                    id: menuList
                    x: menu.pad; y: menu.listTop; width: menu.listWidth; height: menu.height - menu.listTop - menu.pad
                    clip: true; interactive: false
                    // Room under the last row for the fade at the bottom edge.
                    readonly property int fade: shell.px(18)
                    contentWidth: width; contentHeight: Math.max(height, menuColumn.height + fade)
                    Behavior on contentY { enabled: !wheelPause.running; NumberAnimation { duration: shell.dur(180); easing.type: Easing.OutCubic } }
                    Timer { id: wheelPause; interval: 200 }
                    function scrollWheel(wheel) {
                        var delta = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 120 * menu.rowHeight * 3;
                        if (delta === 0) { wheel.accepted = false; return; }
                        wheelPause.restart();
                        shell.menuHover = -1;
                        shell.pointerBlockedUntil = Date.now() + 200;
                        contentY = Math.max(0, Math.min(contentY - delta, contentHeight - height));
                        wheel.accepted = true;
                    }
                    // The focused row in view, and clear of the fades at the edges.
                    function follow() {
                        if (shell.page !== "settings") return;
                        var top = menu.rowY(shell.selected), bottom = top + menu.rowHeight, at = contentY;
                        if (bottom + fade > at + height) at = bottom + fade - height;
                        else if (top < at + menu.headerHeight) at = Math.max(0, top - menu.headerHeight - shell.px(12));
                        contentY = Math.max(0, Math.min(at, contentHeight - height));
                    }
                    Column {
                        id: menuColumn
                        width: parent.width
                        Repeater {
                            model: shell.menuRows
                            Item {
                                readonly property bool isHeader: modelData.header !== undefined
                                readonly property var setting: isHeader ? null : shell.settingsItems[modelData.index]
                                readonly property bool chosen: !isHeader && shell.selected === modelData.index
                                readonly property bool hovered: !isHeader && shell.menuHover === modelData.index
                                width: menuColumn.width; height: isHeader ? menu.headerHeight + (index > 0 ? shell.px(12) : 0) : menu.rowHeight
                                // A group's name.
                                Text {
                                    visible: isHeader; x: shell.px(20); anchors.bottom: parent.bottom; anchors.bottomMargin: shell.px(10)
                                    text: isHeader ? modelData.header : ""; font.family: shell.fontName; font.bold: true; font.pixelSize: shell.pt(13); font.letterSpacing: 1.2*shell.u; font.capitalization: Font.AllUppercase
                                    color: shell.ink3
                                }
                                // A setting: its name, its value at the right.
                                Rectangle {
                                    visible: !isHeader
                                    anchors.fill: parent; anchors.topMargin: shell.px(3); anchors.bottomMargin: shell.px(3)
                                    radius: shell.px(14)
                                    // On the B4, repainting hover elsewhere can leave the open
                                    // row's background visible but its text missing until another
                                    // repaint. Composite this one row as a texture so its text
                                    // cannot share a scene-graph batch with the changing values.
                                    layer.enabled: chosen
                                    // Pointer feedback never inverts text. Animating the background
                                    // alone left dark text on a still-dark background during hover.
                                    color: chosen ? shell.theme.tile : hovered ? shell.theme.track : "transparent"
                                    border.width: chosen || hovered ? 1 : 0; border.color: shell.theme.focus
                                    // Both texts are measured by hidden twins (no elide, no width:
                                    // their implicitWidth is the text's own, at the text size of
                                    // the moment) and cut to what the row has: the value to half
                                    // of it, the name to the rest.
                                    Text { id: nameTwin; visible: false; text: setting ? setting.title : ""; font.family: shell.fontName; font.pixelSize: shell.pt(22) }
                                    Text { id: valueTwin; visible: false; text: setting ? setting.value : ""; font.family: shell.fontName; font.pixelSize: shell.pt(19) }
                                    Text {
                                        id: rowValue
                                        anchors.right: parent.right; anchors.rightMargin: shell.px(20); anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(Math.ceil(valueTwin.implicitWidth) + 1, parent.width*0.5); elide: Text.ElideRight; horizontalAlignment: Text.AlignRight
                                        text: setting ? setting.value : ""; font.family: shell.fontName; font.pixelSize: shell.pt(19)
                                        color: shell.ink3
                                    }
                                    Text {
                                        id: rowName
                                        x: shell.px(20); anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(Math.ceil(nameTwin.implicitWidth) + 1, parent.width - rowValue.width - shell.px(60))
                                        elide: Text.ElideRight
                                        text: setting ? setting.title : ""; font.family: shell.fontName; font.pixelSize: shell.pt(22)
                                        color: shell.ink
                                    }
                                    // The pointer: a click focuses the row and opens its values
                                    // (or does what an action does). Hover only previews a row.
                                    MouseArea {
                                        id: rowPointer
                                        anchors.fill: parent; hoverEnabled: true
                                        // By id: on the TV's Qt 5.6, `this` in a function called
                                        // by name is not this MouseArea.
                                        function hoverRow(mouse) {
                                            if (shell.pointerMoved(rowPointer, mouse)) shell.menuHover = modelData.index;
                                        }
                                        onEntered: hoverRow({x: mouseX, y: mouseY})
                                        onPositionChanged: hoverRow(mouse)
                                        onExited: { if (shell.menuHover === modelData.index) shell.menuHover = -1; }
                                        onPressed: shell.noteActivity()
                                        onClicked: { shell.menuHover = -1; shell.pane = 0; shell.selected = modelData.index; shell.activate(shell.itemAt(modelData.index)); }
                                    }
                                }
                            }
                        }
                    }
                    Connections {
                        target: shell
                        onSelectedChanged: menuList.follow()
                        onPageChanged: { shell.menuHover = -1; menuList.contentY = 0; menuList.follow(); }
                    }
                }
                // Wheel input covers the list viewport, including gaps and headers.
                // No mouse buttons are accepted, so row clicks still reach their areas.
                MouseArea {
                    x: menuList.x; y: menuList.y; width: menuList.width; height: menuList.height
                    acceptedButtons: Qt.NoButton
                    onWheel: { shell.noteActivity(); menuList.scrollWheel(wheel); }
                }
                // The list's edges fade into the card, so a row cut by the edge
                // does not look cut.
                Rectangle {
                    x: menuList.x; y: menuList.y; width: menuList.width; height: shell.px(18)
                    gradient: Gradient { GradientStop { position: 0; color: shell.chip } GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) } }
                }
                Rectangle {
                    x: menuList.x; y: menuList.y + menuList.height - shell.px(18); width: menuList.width; height: shell.px(18)
                    gradient: Gradient { GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0) } GradientStop { position: 1; color: shell.chip } }
                }
                Rectangle { x: menu.pad + menu.listWidth + shell.px(40); y: menu.listTop; width: 1; height: menuList.height; color: shell.chipEdge }

                // The focused setting: its values, or an action's status.
                Item {
                    id: valuesPane
                    x: menu.pad + menu.listWidth + shell.px(80); y: menu.listTop
                    width: menu.width - x - menu.pad; height: menuList.height
                    clip: true
                    readonly property var setting: shell.page === "settings" && shell.selected < shell.settingsItems.length ? shell.settingsItems[shell.selected] : null
                    readonly property bool actionRow: setting !== null && setting.action !== "setting"
                    readonly property string key: setting ? setting.key : ""
                    Text {
                        id: valuesTitle
                        x: shell.px(20); y: shell.px(6); width: parent.width - shell.px(40); elide: Text.ElideRight
                        text: valuesPane.setting ? valuesPane.setting.title : ""
                        font.family: shell.fontName; font.bold: true; font.pixelSize: shell.pt(28); font.letterSpacing: -0.6*shell.u; color: shell.ink
                    }
                    // An action's status, and what OK does with it.
                    Column {
                        visible: valuesPane.actionRow
                        x: shell.px(20); y: valuesTitle.y + valuesTitle.height + shell.px(18); width: parent.width - shell.px(40); spacing: shell.px(16)
                        Text {
                            width: parent.width; wrapMode: Text.WordWrap
                            text: valuesPane.setting ? valuesPane.setting.value : ""
                            font.family: shell.fontName; font.pixelSize: shell.pt(21); color: shell.ink2
                        }
                        Row {
                            spacing: shell.px(9); visible: valuesPane.setting !== null && shell.actionVerb(valuesPane.setting.key) !== ""
                            Rectangle {
                                width: okLabel.implicitWidth+shell.px(14); height: shell.pt(24); radius: shell.px(7); color: "transparent"; border.width: Math.max(1, 1.5*shell.u); border.color: shell.ink3
                                anchors.verticalCenter: parent.verticalCenter
                                Text { id: okLabel; anchors.centerIn: parent; text: "OK"; font.family: shell.fontName; font.bold: true; font.pixelSize: shell.pt(12); color: shell.ink2 }
                            }
                            Text { text: valuesPane.setting ? shell.actionVerb(valuesPane.setting.key) : ""; font.family: shell.fontName; font.pixelSize: shell.pt(17); color: shell.ink2; anchors.verticalCenter: parent.verticalCenter }
                        }
                        // Updates: what the version found changes, from its release notes.
                        Column {
                            width: parent.width; spacing: shell.px(8)
                            visible: valuesPane.key === "update" && !!shell.updateInfo.notes
                                     && ["available", "downloading", "ready", "installing"].indexOf(shell.updateInfo.state) >= 0
                            Text { text: shell.t("upd_notes"); font.family: shell.fontName; font.bold: true; font.pixelSize: shell.pt(19); color: shell.ink }
                            Text {
                                width: parent.width; wrapMode: Text.WordWrap; textFormat: Text.StyledText
                                text: shell.notesText(shell.updateInfo.notes); lineHeight: 1.1
                                font.family: shell.fontName; font.pixelSize: shell.pt(17); color: shell.ink2
                            }
                        }
                        // About: a few words, the code to support the project, and
                        // where its source is.
                        Column {
                            width: parent.width; spacing: shell.px(22)
                            visible: valuesPane.key === "about"
                            Text {
                                width: parent.width; wrapMode: Text.WordWrap; lineHeight: 1.1
                                text: shell.t("about_text")
                                font.family: shell.fontName; font.pixelSize: shell.pt(19); color: shell.ink2
                            }
                            Row {
                                spacing: shell.px(28)
                                Rectangle {
                                    id: supportCode
                                    // Whole pixels per module and a quiet zone of four.
                                    readonly property int modules: About.supportQr.length
                                    readonly property int cell: Math.max(2, Math.floor(shell.px(260) / (modules + 8)))
                                    width: cell*(modules + 8); height: width; radius: shell.px(12); color: "#ffffff"
                                    Canvas {
                                        x: 4*parent.cell; y: x; width: parent.cell*parent.modules; height: width
                                        onWidthChanged: requestPaint()
                                        onVisibleChanged: if (visible) requestPaint()
                                        onPaint: shell.drawQr(getContext("2d"), About.supportQr, parent.cell)
                                    }
                                }
                                Column {
                                    anchors.verticalCenter: supportCode.verticalCenter; spacing: shell.px(8)
                                    Text { text: shell.t("about_scan"); font.family: shell.fontName; font.bold: true; font.pixelSize: shell.pt(21); color: shell.ink }
                                    Text { text: About.support.replace(/^https:\/\//, ""); font.family: shell.fontName; font.pixelSize: shell.pt(18); color: shell.ink2 }
                                }
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: "GitHub · " + About.repo.replace(/^https:\/\//, "")
                                font.family: shell.fontName; font.pixelSize: shell.pt(18); color: shell.ink2
                            }
                        }
                        // Weather place: the code that opens the place page on a
                        // phone, what to do with it, and its address.
                        Column {
                            width: parent.width; spacing: shell.px(16)
                            visible: valuesPane.key === "place" && shell.setupInfo.rev >= 0
                            Rectangle {
                                visible: !!shell.setupInfo.qr
                                // Whole pixels per module and a quiet zone of four.
                                readonly property int modules: shell.setupInfo.qr ? shell.setupInfo.qr.length : 21
                                readonly property int cell: Math.max(2, Math.floor(shell.px(300) / (modules + 8)))
                                width: cell*(modules + 8); height: width; radius: shell.px(12); color: "#ffffff"
                                Canvas {
                                    x: 4*parent.cell; y: x; width: parent.cell*parent.modules; height: width
                                    property var matrix: shell.setupInfo.qr
                                    onMatrixChanged: requestPaint()
                                    onWidthChanged: requestPaint()
                                    onVisibleChanged: if (visible) requestPaint()
                                    onPaint: shell.drawQr(getContext("2d"), matrix, parent.cell)
                                }
                            }
                            Text {
                                width: parent.width; wrapMode: Text.WordWrap
                                text: shell.setupInfo.url ? shell.t("place_scan") : shell.t("place_noip")
                                font.family: shell.fontName; font.pixelSize: shell.pt(18); color: shell.ink2
                            }
                            Text {
                                visible: !!shell.setupInfo.url; width: parent.width; elide: Text.ElideRight
                                text: shell.setupInfo.url.replace(/^http:\/\//, "")
                                font.family: shell.fontName; font.pixelSize: shell.pt(16); color: shell.ink3
                            }
                        }
                    }
                    Flickable {
                        id: modeHelp
                        visible: shell.valueKey === "mode"
                        anchors.left: parent.left; anchors.right: parent.right
                        y: valueList.y + valueList.height + shell.px(22)
                        height: Math.min(modeDetailsColumn.height, Math.max(shell.px(100), parent.height - y))
                        clip: true; interactive: true
                        contentWidth: width; contentHeight: modeDetailsColumn.height
                        onContentYChanged: shell.modeDetailsOffset = Math.max(0, contentY)
                        // What the focused method does, then where things stand now.
                        Column {
                            id: modeDetailsColumn; width: parent.width; spacing: shell.px(18)
                            Text {
                                id: modeDescriptionText; width: parent.width
                                text: shell.modeDescription(shell.valueOptions[shell.valueIndex] ? shell.valueOptions[shell.valueIndex].id : "")
                                textFormat: Text.PlainText
                                wrapMode: Text.WordWrap; font.family: shell.fontName; font.pixelSize: shell.pt(19); color: shell.ink
                            }
                            Text {
                                id: modeDetailsText; width: parent.width
                                text: shell.launchDetails(shell.modeInfo, shell.modeError, shell.lang)
                                textFormat: Text.PlainText
                                wrapMode: Text.WordWrap; font.family: shell.fontName; font.pixelSize: shell.pt(17); color: shell.ink3
                                onTextChanged: modeHelp.contentY = 0
                            }
                        }
                        MouseArea {
                            anchors.fill: parent; acceptedButtons: Qt.NoButton
                            onWheel: {
                                shell.noteActivity();
                                var delta = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 120 * shell.px(90);
                                modeHelp.contentY = Math.max(0, Math.min(modeHelp.contentY - delta, modeHelp.contentHeight - modeHelp.height));
                            }
                        }
                        Connections {
                            target: shell
                            onModeDetailsScroll: modeHelp.contentY = Math.max(0, Math.min(modeHelp.contentY + direction*shell.px(90), modeHelp.contentHeight - modeHelp.height))
                        }
                    }
                    // "Input appearance": a pill below the choices, drawn as on Home with
                    // the value being tried, so the choice is clear in the menu.
                    Column {
                        id: inputPreview
                        objectName: "inputAppearancePreview"
                        visible: shell.valueKey === "inputText" && shell.pane === 1 && shell.previewSource.title !== ""
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        spacing: shell.px(10)
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: shell.t("preview"); font.family: shell.fontName; font.pixelSize: shell.pt(14); color: shell.ink3
                        }
                        Rectangle {
                            id: previewPill
                            anchors.horizontalCenter: parent.horizontalCenter
                            readonly property var texts: shell.inputTexts(shell.previewSource)
                            readonly property int textCap: Math.max(shell.px(20), width - shell.px(44) - (shell.inputIconsVisible ? shell.px(44) : 0))
                            width: shell.pillWidthFor(shell.previewSource, titleTwins.rev); height: shell.inputIconOnly ? shell.sourceTileWidth : Math.max(shell.px(64), previewText.height + shell.px(20)); radius: shell.px(18)
                            color: shell.theme.focus
                            DeviceIcon {
                                visible: shell.inputIconsVisible; iconId: shell.sourceIcon(shell.previewSource)
                                width: shell.px(48); height: width
                                x: shell.inputIconOnly ? (parent.width-width)/2 : shell.px(12); anchors.verticalCenter: parent.verticalCenter
                                ink: shell.theme.onFocus
                            }
                            Column {
                                id: previewText; visible: !shell.inputIconOnly
                                anchors.centerIn: parent; anchors.horizontalCenterOffset: shell.inputIconsVisible ? shell.px(28) : 0; spacing: 1
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: previewPill.texts.primary; width: previewPill.textCap; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                                    font.family: shell.fontName; font.bold: true; font.pixelSize: previewSecond.visible ? shell.pt(19) : shell.pt(21)
                                    font.letterSpacing: -0.2*shell.u; color: shell.theme.onFocus
                                }
                                Text { id: previewTwin; visible: false; text: previewPill.texts.secondary; font.family: shell.fontName; font.pixelSize: shell.pt(13) }
                                Text {
                                    id: previewSecond; visible: text !== ""; text: previewPill.texts.secondary
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Math.min(Math.ceil(previewTwin.implicitWidth) + 1, previewPill.textCap); elide: Text.ElideRight
                                    font.family: shell.fontName; font.pixelSize: shell.pt(13); color: shell.theme.onFocus2
                                }
                            }
                        }
                    }
                    // The values: a dot on the chosen one; the focused one lit
                    // while the values have the focus.
                    MouseArea {
                        x: valueList.x; y: valueList.y; width: valueList.width; height: valueList.height; z: 2
                        visible: valueList.visible; acceptedButtons: Qt.NoButton
                        onWheel: {
                            shell.noteActivity();
                            var delta = wheel.pixelDelta.y || wheel.angleDelta.y / 120 * menu.rowHeight * 2;
                            shell.pointerBlockedUntil = Date.now() + 200;
                            valueList.contentY = Math.max(0, Math.min(valueList.contentY-delta, valueList.contentHeight-valueList.height));
                        }
                    }
                    Flickable {
                        id: valueList
                        objectName: "inputValueList"
                        // Values can be longer than the viewport, especially with
                        // larger text. Follow after layout as well as key changes.
                        onHeightChanged: follow()
                        onContentHeightChanged: follow()
                        visible: !valuesPane.actionRow
                        x: 0; y: valuesTitle.y + valuesTitle.height + shell.px(14); width: parent.width
                        // The launch methods are only a few rows: the text about them sits right under.
                        height: modeHelp.visible ? Math.min(valueColumn.height, parent.height - y - shell.px(160)) : parent.height - y - (inputPreview.visible ? inputPreview.height + shell.px(18) : 0)
                        clip: true; interactive: false
                        contentWidth: width; contentHeight: Math.max(height, valueColumn.height)
                        Behavior on contentY { NumberAnimation { duration: shell.dur(180); easing.type: Easing.OutCubic } }
                        function follow() {
                            var top = shell.valueIndex*menu.rowHeight, bottom = top + menu.rowHeight, at = contentY;
                            if (bottom > at + height) at = bottom - height;
                            else if (top < at) at = top;
                            contentY = Math.max(0, Math.min(at, Math.max(height, valueColumn.height) - height));
                        }
                        Column {
                            id: valueColumn
                            width: parent.width
                            Repeater {
                                model: shell.valueOptions
                                Rectangle {
                                    readonly property bool current: shell.valueOn(modelData.id)
                                    readonly property bool lit: shell.pane === 1 && shell.valueIndex === index
                                    readonly property bool hovered: shell.valueHover === index
                                    width: valueColumn.width; height: menu.rowHeight; radius: shell.px(14)
                                    // Only keyboard focus uses inverted colors, switched together.
                                    // Hover is an outline and tint, independent of the chosen value.
                                    color: lit ? shell.theme.focus : hovered ? shell.theme.track : "transparent"
                                    border.width: hovered && !lit ? 1 : 0; border.color: shell.theme.focus
                                    // A dot on the chosen value; a box, ticked when on, for switches.
                                    Rectangle {
                                        x: shell.px(20); anchors.verticalCenter: parent.verticalCenter
                                        width: shell.px(22); height: width; radius: shell.valueToggles ? shell.px(5) : width/2; color: "transparent"
                                        border.width: Math.max(1, 2*shell.u); border.color: lit ? shell.theme.onFocus : current ? shell.theme.focus : shell.ink3
                                        Rectangle {
                                            anchors.centerIn: parent; width: shell.valueToggles ? shell.px(12) : shell.px(10); height: width
                                            radius: shell.valueToggles ? shell.px(2) : width/2
                                            visible: current; color: lit ? shell.theme.onFocus : shell.theme.focus
                                        }
                                    }
                                    Text {
                                        x: shell.px(58); anchors.verticalCenter: parent.verticalCenter; width: parent.width - shell.px(78); elide: Text.ElideRight
                                        text: modelData.title; font.family: shell.fontName; font.pixelSize: shell.pt(22)
                                        color: lit ? shell.theme.onFocus : shell.ink
                                    }
                                    MouseArea {
                                        id: valuePointer
                                        anchors.fill: parent; hoverEnabled: true
                                        function hoverValue(mouse) {
                                            if (shell.pointerMoved(valuePointer, mouse)) shell.valueHover = index;
                                        }
                                        onEntered: hoverValue({x: mouseX, y: mouseY})
                                        onPositionChanged: hoverValue(mouse)
                                        onExited: { if (shell.valueHover === index) shell.valueHover = -1; }
                                        onPressed: shell.noteActivity()
                                        onClicked: {
                                            shell.valueHover = -1; shell.pane = 1; shell.valueIndex = index;
                                            if (shell.valueKey === "mode") shell.chooseMode(); else if (shell.valueToggles) shell.toggleValue(); else shell.applyValue();
                                        }
                                    }
                                }
                            }
                        }
                        Connections {
                            target: shell
                            onValueIndexChanged: valueList.follow()
                            onPaneChanged: valueList.follow()
                            onSelectedChanged: { shell.valueHover = -1; valueList.contentY = 0; }
                            onPageChanged: shell.valueHover = -1
                        }
                    }
                }
            }
        }
    } // panel

    // Mode change: what is about to happen, with Yes / No (opens on No); and,
    // after a switch, one note that it finished. Above everything, it takes every key.
    Rectangle {
        id: modePopup
        objectName: "modePopup"
        visible: shell.modeConfirm !== "" || shell.modeDoneAt > 0
        z: 60; x: 0; y: 0; width: shell.width; height: shell.height
        color: Qt.rgba(0, 0, 0, 0.62)
        MouseArea {
            anchors.fill: parent
            onClicked: { shell.noteActivity(); if (shell.modeConfirm !== "") shell.answerMode(false); else shell.ackModeDone(); }
        }
        Rectangle {
            id: modeCard
            anchors.centerIn: parent
            width: Math.min(parent.width - 2*shell.margin, shell.px(860)); height: modeColumn.implicitHeight + shell.px(60)
            radius: shell.px(22); color: shell.chip; border.color: shell.warning; border.width: Math.max(1, 2*shell.u)
            MouseArea { anchors.fill: parent; onClicked: {} }
            Column {
                id: modeColumn
                x: shell.px(34); y: shell.px(30); width: parent.width - 2*x; spacing: shell.px(20)
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: shell.modeConfirm !== "" ? shell.t("mode_popup_" + shell.modeConfirm) : shell.t("set_mode")
                    font.family: shell.fontName; font.bold: true; font.pixelSize: shell.pt(26); color: shell.ink
                }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap; textFormat: Text.PlainText
                    text: shell.modeConfirm !== "" ? shell.modePopupText(shell.modeConfirm) : shell.t(shell.modeDoneOk ? "mode_done" : "mode_failed")
                    font.family: shell.fontName; font.pixelSize: shell.pt(20); color: shell.ink2
                }
                Row {
                    spacing: shell.px(16)
                    Repeater {
                        model: shell.modeConfirm !== "" ? [true, false] : [true]
                        Rectangle {
                            readonly property bool yes: modelData
                            readonly property bool lit: shell.modeConfirm === "" || shell.modeConfirmYes === yes
                            objectName: shell.modeConfirm === "" ? "modeOk" : yes ? "modeYes" : "modeNo"
                            width: shell.px(150); height: shell.px(52); radius: shell.px(12)
                            color: lit ? shell.theme.focus : shell.theme.track
                            Text {
                                anchors.centerIn: parent
                                text: shell.modeConfirm === "" ? shell.t("mode_ok") : shell.t(parent.yes ? "mode_yes" : "mode_no")
                                font.family: shell.fontName; font.bold: true; font.pixelSize: shell.pt(21)
                                color: parent.lit ? shell.theme.onFocus : shell.ink
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { shell.noteActivity(); if (shell.modeConfirm !== "") shell.answerMode(parent.yes); else shell.ackModeDone(); }
                            }
                        }
                    }
                }
            }
        }
    }

    // Settings → Remote button: change or unpin the bound button, the two
    // presses that choose one, and what came of it. Above everything.
    Rectangle {
        id: buttonPopup
        objectName: "buttonPopup"
        visible: shell.buttonStep !== ""
        z: 61; x: 0; y: 0; width: shell.width; height: shell.height
        color: Qt.rgba(0, 0, 0, 0.62)
        MouseArea {
            anchors.fill: parent
            onClicked: { shell.noteActivity(); if (shell.buttonStep !== "saving" && shell.buttonStep !== "unpinning") shell.closeButton(); }
        }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 2*shell.margin, shell.px(860)); height: buttonColumn.implicitHeight + shell.px(60)
            radius: shell.px(22); color: shell.chip; border.color: shell.theme.focus; border.width: Math.max(1, 2*shell.u)
            MouseArea { anchors.fill: parent; onClicked: {} }
            Column {
                id: buttonColumn
                x: shell.px(34); y: shell.px(30); width: parent.width - 2*x; spacing: shell.px(20)
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: shell.t("set_button")
                    font.family: shell.fontName; font.bold: true; font.pixelSize: shell.pt(26); color: shell.ink
                }
                Text {
                    objectName: "buttonText"
                    width: parent.width; wrapMode: Text.WordWrap; textFormat: Text.PlainText
                    text: shell.buttonStep !== "" ? shell.buttonPopupText() : ""
                    font.family: shell.fontName; font.pixelSize: shell.pt(20); color: shell.ink2
                }
                Row {
                    spacing: shell.px(16)
                    visible: shell.buttonStep === "menu" || shell.buttonStep === "done"
                    Repeater {
                        model: shell.buttonStep === "menu" ? [false, true] : [false]
                        Rectangle {
                            readonly property bool unpin: modelData
                            readonly property bool lit: shell.buttonStep === "done" || shell.buttonUnpin === unpin
                            objectName: shell.buttonStep === "done" ? "buttonOk" : unpin ? "buttonUnpin" : "buttonChange"
                            width: shell.px(170); height: shell.px(52); radius: shell.px(12)
                            color: lit ? shell.theme.focus : shell.theme.track
                            Text {
                                anchors.centerIn: parent
                                text: shell.buttonStep === "done" ? shell.t("mode_ok") : shell.t(parent.unpin ? "button_unpin" : "button_change")
                                font.family: shell.fontName; font.bold: true; font.pixelSize: shell.pt(21)
                                color: parent.lit ? shell.theme.onFocus : shell.ink
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    shell.noteActivity();
                                    if (shell.buttonStep === "done") shell.closeButton();
                                    else { shell.buttonUnpin = parent.unpin; shell.answerButtonMenu(); }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
