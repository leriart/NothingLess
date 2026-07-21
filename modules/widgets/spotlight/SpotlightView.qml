import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Io
import qs.modules.globals
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.modules.bar.workspaces
import qs.config

// Hax - Universal launcher for Axenide
// Native spotlight for Ambxst + Ax-shell.
// Finds apps, calculates, searches files and web.
// Made with love by Fabio & Maria.

PanelWindow {
    id: spotlight

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ambxst:spotlight"
    WlrLayershell.keyboardFocus: (spotlightOpen || showHax) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Visibility
    readonly property var screenVisibilities: Visibilities.getForScreen(screen.name)
    readonly property bool spotlightOpen: screenVisibilities ? (screenVisibilities.spotlight ?? false) : false

    // Animation properties (dot grows from the bar)
    property bool showHax: false
    property real animProgress: 0.0          // 0 = dot at bar, 1 = full Hax
    property real barBottom: 40
    property real notchEndY: 60
    readonly property real screenCenterY: spotlight.height / 2

    // Custom shortcuts stored as JSON string
    property var haxShortcutsList: (function () {
        try {
            var raw = Config.hax.customShortcuts;
            return (typeof raw === "string" && raw.trim().length > 0) ? JSON.parse(raw) : [];
        } catch (e) {
            return [];
        }
    })()

    // Plugin Manager
    property PluginManager pluginManager: PluginManager {
        onPluginListChanged: {
            if (searchText && searchText.trim().length > 0) {
                Qt.callLater(function() { spotlight.updateResults(); });
            }
        }
        onPluginResultsUpdated: function(pluginId, results) {
            if (searchText && searchText.trim().length > 0) {
                Qt.callLater(function() { spotlight.updateResults(); });
            }
        }
        onPluginActionMessage: function(pluginId, title, message) {
            spotlight.addHaxNotification("plugin", title, message, null);
        }
    }
    property var pluginResults: []

    visible: showHax
    exclusionMode: ExclusionMode.Ignore

    // Open/close handling
    onSpotlightOpenChanged: {
        if (spotlightOpen) {
            closeAnim.stop();

            var bar = Visibilities.getBarForScreen(screen.name);
            barBottom = bar ? bar.totalBarHeight : 40;
            notchEndY = 40;

            // Reset state before showing
            results = [];
            cmdOutput = [];
            cmdOutputText = "";
            _forceTerminal = false;
            _lastCmdVisible = false;
            searchText = "";
            selectedIndex = 0;
            cancelCmdProcess();
            stopMonitor();
            loadHistory();
            startClipWatcher();
            if (weatherSearch) { try { weatherSearch.abort(); } catch(e) {} weatherSearch = null; }

            animProgress = 0.0;
            showHax = true;

            openAnim.start();
            searchInput.clear();
            searchInput.forceActiveFocus();

            _debugOpenStart = Date.now();
            debugOpenMs = -1;
            _debugOpenTimer.restart();
        } else {
            // Only close on explicit dismiss (spotlight.closeSpotlight() was called)
            // External clear events should not auto-close
            if (!_pendingInternalClose) return;
            _pendingInternalClose = false;
            openAnim.stop();
            stopMonitor();
            stopClipWatcher();
            showPreview = false;
            showConfig = false;
            showPlugins = false;
            closeAnim.start();
        }
    }

    // Internal flag: set to true before calling closeSpotlight() so
    // the onSpotlightOpenChanged else branch knows this is an intentional close.
    property bool _pendingInternalClose: false

    SequentialAnimation {
        id: openAnim
        PropertyAnimation {
            target: spotlight
            property: "animProgress"
            to: 1.0
            duration: 600
            easing.type: Easing.InOutCubic
        }
    }

    function closeSpotlight() {
        _pendingInternalClose = true;
        // Try integrated mode dismiss (setActiveModule triggers onSpotlightOpenChanged)
        Visibilities.setActiveModule("");
        // If standalone (setActiveModule is a no-op), close directly
        if (!spotlightOpen) {
            openAnim.stop();
            closeAnim.start();
        }
    }

    // Close handler: quit standalone process when animation completes
    onShowHaxChanged: {
        if (!showHax) {
            Qt.callLater(function() {
                try { Qt.quit(); } catch(e) {}
            });
        }
    }

    SequentialAnimation {
        id: closeAnim
        PropertyAnimation {
            target: spotlight
            property: "animProgress"
            to: 0.0
            duration: 600
            easing.type: Easing.InOutCubic
        }
        PropertyAction {
            target: spotlight
            property: "showHax"
            value: false
        }
    }

    // Mask for clipping
    mask: Region {
        item: showHax ? fullMask : emptyMask
    }

    Item {
        id: fullMask
        anchors.fill: parent
    }

    Item {
        id: emptyMask
        width: 0
        height: 0
    }

    // Focus grabber
    FocusGrab {
        id: focusGrab
        windows: [spotlight]
        active: spotlightOpen || showHax
        onCleared: {
            Qt.callLater(() => {
                if (spotlightOpen || showHax) {
                    spotlight.closeSpotlight();
                }
            });
        }
    }

    // Backdrop to close on outside click
    MouseArea {
        anchors.fill: parent
        enabled: showHax || spotlightOpen
        onClicked: {
            if (spotlightOpen || showHax) spotlight.closeSpotlight();
        }
    }

    // Internal state
    property string searchText: ""

    // OCR (Live Text)
    property string ocrScript: Qt.resolvedUrl("../../../scripts/ocr.sh").toString().replace("file://", "")
    property string ocrSep: String.fromCharCode(31)
    property string previewOcrText: ""
    property int liveTextIndexed: 0
    property bool liveTextIndexing: false
    property int liveTextPending: 0

    // Dictionary / Glossary
    property bool dictMode: false
    property string dictWord: ""
    property string dictResultText: ""
    property string dictError: ""
    property bool dictLoading: false
    property int dictSeq: 0
    property int dictLastLen: 0

    Timer {
        id: liveTextStatusTimer
        interval: 4000
        running: false
        repeat: false
        onTriggered: spotlight.refreshLiveTextStatus()
    }

    Timer {
        id: windowGridRefreshTimer
        interval: 2000
        repeat: true
        running: showWindowGrid
        onTriggered: {
            if (showWindowGrid) {
                try { spotlight.buildWindowGrid(); } catch (e) {}
            }
        }
    }

    Component.onCompleted: {
        Qt.callLater(function() {
            spotlight.pluginManager.initialize({
                copyToClipboard: function(text) {
                    var pr = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
                    pr.command = ["wl-copy", text];
                    pr.onExited.connect(function() { try { pr.destroy(); } catch(e) {} });
                    pr.running = true;
                },
                runCommand: function(cmd) {
                    spotlight.bash(cmd);
                },
                showNotification: function(title, message) {
                    spotlight.addHaxNotification("plugin", title, message, null);
                },
                openUrl: function(url) {
                    var pr = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
                    pr.command = ["xdg-open", url];
                    pr.onExited.connect(function() { try { pr.destroy(); } catch(e) {} });
                    pr.running = true;
                },
                openFile: function(path) {
                    var pr = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
                    pr.command = ["xdg-open", path];
                    pr.onExited.connect(function() { try { pr.destroy(); } catch(e) {} });
                    pr.running = true;
                },
                getPluginDir: function() {
                    return (Quickshell.env("HOME") || "/home/fabio") + "/.config/hax/plugins";
                },
                showResult: function(name, description, icon, actionId, actionData) {
                    spotlight.addPluginResult(name, description, icon || "plugin", actionId, actionData);
                },
                getConfig: function(key, callback) {
                    spotlight.getPluginConfig(key, callback);
                },
                setConfig: function(key, value) {
                    spotlight.setPluginConfig(key, value);
                }
            });
        });

        // Auto-open in standalone mode
        Qt.callLater(function() {
            animProgress = 0.0;
            showHax = true;
            openAnim.start();
            searchInput.forceActiveFocus();
        });
    }

    // Debug mode
    property bool showDebug: false
    property bool showConfig: false
    property bool showPlugins: false
    property bool colorPickerOpen: false
    property bool actionPresetsOpen: false

    readonly property color haxPrimaryColor: Config.hax.customColorEnabled
        ? Qt.rgba(
            parseInt(Config.hax.customColor.substring(1,3), 16) / 255,
            parseInt(Config.hax.customColor.substring(3,5), 16) / 255,
            parseInt(Config.hax.customColor.substring(5,7), 16) / 255,
            1
          )
        : Colors.primary

    readonly property color haxIconColor: Config.hax.customColorEnabled
        ? Qt.rgba(spotlight.haxPrimaryColor.r, spotlight.haxPrimaryColor.g, spotlight.haxPrimaryColor.b, 0.7)
        : Styling.srItem("overprimary")

    onShowDebugChanged: {
        if (spotlight.showDebug) {
            spotlight.startDebugMonitor();
        } else {
            spotlight.stopDebugMonitor();
        }
    }

    property var debugErrorLog: []
    property int debugOpenMs: -1
    property int debugLastSearchMs: -1
    property int debugSessionS: 0
    property real debugMemMB: 0
    property real debugCpuPct: 0
    property int _debugOpenStart: 0
    property int _debugPrevUtime: -1
    property int _debugPrevStime: -1
    property int _debugPrevTs: 0

    function debugLogError(ctx, e) {
        var msg = (e && e.message) ? e.message : String(e);
        debugErrorLog.push({ t: Qt.formatTime(new Date(), "hh:mm:ss"), ctx: ctx, msg: msg });
        debugErrorLog = debugErrorLog.slice(-50);
    }

    property int selectedIndex: 0
    property int windowGridSelectedIndex: 0
    property bool showTerminal: false

    onSelectedIndexChanged: {
        if (resultsList && selectedIndex >= 0) {
            resultsList.positionViewAtIndex(selectedIndex, ListView.Center);
            _previewSelectedIfFile();
        }
    }

    property var results: []
    property string autoCompleteSuffix: {
        if (searchInput && searchInput.text.length > 0 && results.length > 0) {
            var txt = searchInput.text.toLowerCase();
            var maxCheck = Math.min(results.length, 20);
            for (var i = 0; i < maxCheck; i++) {
                var name = results[i].name || "";
                if (name.toLowerCase().indexOf(txt) === 0 && name.length > txt.length) {
                    return name.substring(txt.length);
                }
            }
        }
        return "";
    }
    property int searchGeneration: 0
    property string _lastSearchQuery: ""

    // Integrated terminal (command mode)
    property var cmdProcess: null
    property var cmdOutput: []
    property string cmdOutputText: ""
    property bool _lastCmdVisible: false
    property bool _forceTerminal: false
    readonly property bool isCommandMode: searchText.trim().startsWith("/")

    // Weather
    property var weatherSearch: null

    // Package search processes
    property var _pkgSearchProcesses: []

    // System monitor
    property bool showMonitor: false
    property bool showWindowGrid: false
    property var windowGridData: []
    property real windowGridHeight: 300
    property real monCpu: 0
    property real monRamPct: 0
    property real monRamUsed: 0
    property real monRamTotal: 0
    property real monDisk: 0
    property int monTemp: 0
    property int monProcs: 0
    property string monUptime: ""
    property var monProcess: null

    function startMonitor() {
        if (monProcess) return;
        var proc = Qt.createQmlObject(
            'import Quickshell.Io; Process { stdout: SplitParser {} }',
            spotlight
        );
        proc.command = ["bash", "-c",
            "while true; do "
            + "cpu=$(LC_ALL=C top -bn1 2>/dev/null | awk '/%Cpu/{print 100 - $8}'); "
            + "ram=$(LC_ALL=C free 2>/dev/null | awk 'NR==2{printf \"%d %d\", $3, $2}'); "
            + "disk=$(df / 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%'); "
            + "temp=$(cat $(grep -l 'k10temp\\|coretemp\\|cpu_thermal' /sys/class/hwmon/hwmon*/name 2>/dev/null | head -1 | sed 's/name$/temp1_input/') 2>/dev/null | awk '{printf \"%.0f\", $1/1000}'); temp=${temp:-0}; "
            + "procs=$(ps aux 2>/dev/null | wc -l); "
            + "uptime=$(LC_ALL=C uptime -p 2>/dev/null); "
            + "echo '{\"cpu\":'$cpu',\"ram_used\":'$(echo $ram | cut -d' ' -f1)',\"ram_total\":'$(echo $ram | cut -d' ' -f2)',\"disk\":'$disk',\"temp\":'$temp',\"procs\":'$procs',\"uptime\":\"'$uptime'\"}'; "
            + "sleep 2; "
            + "done"
        ];
        proc.stdout.onRead.connect(function(data) {
            try {
                var j = JSON.parse(data.trim());
                if (j.cpu !== undefined) monCpu = parseFloat(j.cpu) || 0;
                if (j.ram_used !== undefined && j.ram_total !== undefined) {
                    monRamUsed = parseInt(j.ram_used) || 0;
                    monRamTotal = parseInt(j.ram_total) || 1;
                    monRamPct = monRamTotal > 0 ? (monRamUsed / monRamTotal * 100) : 0;
                }
                if (j.disk !== undefined) monDisk = parseFloat(j.disk) || 0;
                if (j.temp !== undefined) monTemp = parseInt(j.temp) || 0;
                if (j.procs !== undefined) monProcs = parseInt(j.procs) || 0;
                if (j.uptime !== undefined) monUptime = j.uptime || "";
            } catch(e) {}
        });
        proc.onExited.connect(function() {
            proc.destroy();
            monProcess = null;
        });
        monProcess = proc;
        proc.running = true;
    }

    function stopMonitor() {
        showMonitor = false;
        if (monProcess) {
            var proc = monProcess;
            monProcess = null;
            proc.running = false;
        }
    }

    function toggleMonitor() {
        if (showMonitor) {
            stopMonitor();
        } else {
            showMonitor = true;
            startMonitor();
        }
    }

    property var activeTimers: []
    property int _timerNextId: 1
    property var activeAlarms: []
    property int _alarmNextId: 1

    property var _haxNotifications: []
    property int _haxNotifIdCounter: 0

    Timer {
        id: _tickTimer
        interval: 1000
        repeat: true
        running: activeTimers.length > 0 || activeAlarms.length > 0
        onTriggered: {
            tickTimers();
            checkAlarms();
        }
    }

    Timer {
        id: _debugOpenTimer
        interval: 30
        repeat: false
        onTriggered: {
            if (spotlight.debugOpenMs < 0)
                spotlight.debugOpenMs = Date.now() - spotlight._debugOpenStart;
        }
    }

    property var _debugResProc: null

    function startDebugMonitor() {
        if (_debugResProc) return;
        spotlight._debugPrevUtime = -1;
        spotlight._debugPrevStime = -1;
        spotlight._debugPrevTs = 0;
        var proc;
        try {
            proc = Qt.createQmlObject(
                'import Quickshell.Io; Process { stdout: SplitParser {} }',
                spotlight
            );
        } catch (e) {
            return;
        }
        proc.command = ["bash", "-c",
            "while true; do " +
            "P=$(awk '{print $2}' /proc/self/statm 2>/dev/null); " +
            "C=$(awk '{print $14+$15}' /proc/self/stat 2>/dev/null); " +
            "echo \"$P $C\"; " +
            "sleep 1; " +
            "done"
        ];
        proc.stdout.onRead.connect(function(d) {
            spotlight.debugSessionS = Math.round((Date.now() - spotlight._debugOpenStart) / 1000);
            var parts = d.trim().split(/\s+/);
            if (parts.length >= 3) {
                var rssPages = parseInt(parts[0], 10) || 0;
                var utime = parseInt(parts[1], 10) || 0;
                var stime = parseInt(parts[2], 10) || 0;
                spotlight.debugMemMB = (rssPages * 4096) / (1024 * 1024);
                var now = Date.now();
                var dTms = now - spotlight._debugPrevTs;
                if (spotlight._debugPrevUtime >= 0 && dTms > 0 && dTms < 3000) {
                    var dCpu = (utime - spotlight._debugPrevUtime) + (stime - spotlight._debugPrevStime);
                    var dT = dTms / 1000 * 100;
                    spotlight.debugCpuPct = Math.max(0, Math.min(100, (dCpu / dT) * 100));
                }
                spotlight._debugPrevUtime = utime;
                spotlight._debugPrevStime = stime;
                spotlight._debugPrevTs = now;
            }
        });
        proc.onExited.connect(function() {
            try { proc.destroy(); } catch (e) {}
            _debugResProc = null;
        });
        _debugResProc = proc;
        proc.running = true;
    }

    function stopDebugMonitor() {
        if (_debugResProc) {
            var proc = _debugResProc;
            _debugResProc = null;
            proc.running = false;
        }
    }

    // Morphing container: dot expands into the full Hax
    StyledRect {
        id: morphContainer
        variant: "bg"
        anchors.horizontalCenter: parent.horizontalCenter
        animateRadius: false

        readonly property real phase: animProgress

        readonly property real dropletW: {
            if (phase < 0.03) return (phase / 0.03) * 20;
            return 20;
        }
        readonly property real dropletH: {
            if (phase < 0.03) return (phase / 0.03) * 20;
            return 20;
        }
        readonly property real descendPhase: Math.max(0, (phase - 0.03) / 0.97)
        readonly property real expandPhase: Math.max(0, (phase - 0.15) / 0.85)

        width: Math.max(1, dropletW + (clampWidth() - dropletW) * expandPhase)
        height: Math.max(1, dropletH + (fullHeight - dropletH) * expandPhase)

        Behavior on height {
            enabled: Config.animDuration > 0 && animProgress >= 1 && cmdProcess === null
            NumberAnimation {
                duration: Config.animDuration * 3
                easing.type: Easing.OutQuint
            }
        }

        opacity: 1

        y: notchEndY + (screenCenterY - height / 2 - notchEndY) * descendPhase

        radius: Math.min(width / 2, Styling.radius(24) + (width / 2 - Styling.radius(24)) * Math.max(0, 1 - expandPhase * 3))

        function clampWidth()  { return Math.min(620, screen.width * 0.9) }

        readonly property real fullHeight: 56 + 32
            + (cmdProcess !== null || isCommandMode || _lastCmdVisible || _forceTerminal
                ? cmdProcess !== null
                    ? 8 + Math.max(240, 36 + Math.min(cmdOutput.length * 20 + 20, 460))
                    : 8 + 36 + Math.min(cmdOutput.length * 20 + 20, 460)
                : 0)
            + (_haxNotifications.length > 0
                ? 8 + Math.min(_haxNotifications.length * 56 + 16, 200)
                : 0)
            + (results.length > 0 && !isCommandMode
                ? 8 + Math.min(results.length * 54, 400)
                : 0)
            + (showMonitor
                ? 8 + 260
                : 0)
            + (showPreview
                ? 8 + 300
                : 0)
            + (spotlight.showTerminal
                ? 8 + 392
                : 0)
            + (spotlight.showDebug
                ? 8 + debugPane.height
                : 0)
            + (spotlight.dictMode
                ? 8 + dictPane.height
                : 0)
            + (spotlight.showConfig
                ? 8 + configPane.height
                : 0)
            + (spotlight.showPlugins
                ? 8 + pluginPane.height
                : 0)
            + (spotlight.showWindowGrid
                ? 8 + spotlight.windowGridHeight
                : 0)

        Column {
            id: contentColumn
            width: parent.width
            opacity: Math.max(0, Math.min(1, morphContainer.expandPhase * 2 - 0.5))
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 16
            spacing: (results.length > 0 || cmdProcess !== null || isCommandMode || _lastCmdVisible || _forceTerminal || _haxNotifications.length > 0 || showMonitor || spotlight.showDebug || showWindowGrid) ? 8 : 0

            // Search box
            StyledRect {
                id: searchBox
                width: contentColumn.width
                height: 56
                variant: "common"
                radius: Styling.radius(16)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    Text {
                        text: Icons.apps
                        font.family: Icons.font
                        font.pixelSize: 22
                        color: spotlight.haxIconColor
                        opacity: 0.7
                    }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        verticalAlignment: TextInput.AlignVCenter

                        font.pixelSize: Config.theme.fontSize + 2
                        font.family: Config.theme.font
                        color: Styling.srItem("text")

                        selectByMouse: true
                        cursorVisible: true

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 2
                            text: cmdProcess !== null
                                ? qsTr("Running command... (Esc to exit)")
                                : qsTr("Hax — Universal launcher for Hyprland (type ? for help)")
                            font: parent.font
                            color: Styling.srItem("text")
                            opacity: 0.35
                            visible: parent.text.length === 0
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            x: parent.cursorRectangle.x + 1
                            text: autoCompleteSuffix
                            font: parent.font
                            color: Styling.srItem("text")
                            opacity: 0.3
                            visible: autoCompleteSuffix.length > 0 && parent.activeFocus
                            z: -1
                        }

                        onTextChanged: {
                            if (text === "/") {
                                spotlight.openTerminal();
                                searchInput.text = "";
                                return;
                            }
                            spotlight.searchText = text;
                            spotlight.selectedIndex = 0;
                            if (!text.trim().startsWith("/")) {
                                spotlight.cancelCmdProcess();
                            }
                            var _t0 = Date.now();
                            spotlight.updateResults();
                            spotlight.debugLastSearchMs = Date.now() - _t0;
                        }

                        Keys.onEscapePressed: {
                            if (spotlight.showMonitor) {
                                spotlight.stopMonitor();
                            } else if (spotlight.showPreview) {
                                spotlight.showPreview = false;
                            } else if (spotlight.showPlugins) {
                                spotlight.showPlugins = false;
                            } else if (spotlight.showTerminal) {
                                spotlight.closeTerminal();
                            } else if (spotlight.showDebug) {
                                spotlight.showDebug = false;
                            } else if (spotlight.dictMode) {
                                spotlight.exitDictMode();
                            } else if (spotlight.showWindowGrid) {
                                spotlight.showWindowGrid = false;
                                clear();
                            } else if (text.length > 0) {
                                clear();
                            } else {
                                 spotlight.closeSpotlight();
                            }
                        }

                        Keys.onUpPressed: {
                            if (spotlight.showWindowGrid) {
                                try { spotlight.buildWindowGrid(); } catch (e) {}
                                var totalWindows = 0;
                                for (var i = 0; i < spotlight.windowGridData.length; i++) {
                                    totalWindows += Math.min(spotlight.windowGridData[i].windows.length, 6);
                                }
                                if (spotlight.windowGridSelectedIndex > 0) {
                                    spotlight.windowGridSelectedIndex--;
                                }
                                return;
                            }
                            var termOverflow = cmdFlickable.contentHeight > cmdFlickable.height;
                            if ((cmdProcess !== null || _lastCmdVisible || _forceTerminal) && termOverflow) {
                                var ts = 60;
                                cmdFlickable.contentY = Math.max(0, cmdFlickable.contentY - ts);
                            } else {
                                if (spotlight.selectedIndex > 0) {
                                    spotlight.selectedIndex--;
                                    while (spotlight.selectedIndex > 0 && spotlight.results[spotlight.selectedIndex] && spotlight.results[spotlight.selectedIndex].cat === true) {
                                        spotlight.selectedIndex--;
                                    }
                                    if (resultsList) {
                                        resultsList.positionViewAtIndex(spotlight.selectedIndex, ListView.Center);
                                    }
                                    spotlight._previewSelectedIfFile();
                                }
                            }
                        }

                        Keys.onDownPressed: {
                            if (spotlight.showWindowGrid) {
                                try { spotlight.buildWindowGrid(); } catch (e) {}
                                var totalWindows = 0;
                                for (var i = 0; i < spotlight.windowGridData.length; i++) {
                                    totalWindows += Math.min(spotlight.windowGridData[i].windows.length, 6);
                                }
                                if (spotlight.windowGridSelectedIndex < totalWindows - 1) {
                                    spotlight.windowGridSelectedIndex++;
                                }
                                return;
                            }
                            var termOverflow = cmdFlickable.contentHeight > cmdFlickable.height;
                            if ((cmdProcess !== null || _lastCmdVisible || _forceTerminal) && termOverflow) {
                                var ts = 60;
                                cmdFlickable.contentY = Math.min(
                                    Math.max(0, cmdFlickable.contentHeight - cmdFlickable.height),
                                    cmdFlickable.contentY + ts
                                );
                            } else {
                                if (spotlight.selectedIndex < spotlight.results.length - 1) {
                                    spotlight.selectedIndex++;
                                    while (spotlight.selectedIndex < spotlight.results.length - 1 && spotlight.results[spotlight.selectedIndex] && spotlight.results[spotlight.selectedIndex].cat === true) {
                                        spotlight.selectedIndex++;
                                    }
                                    if (resultsList) {
                                        resultsList.positionViewAtIndex(spotlight.selectedIndex, ListView.Center);
                                    }
                                    spotlight._previewSelectedIfFile();
                                }
                            }
                        }

                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (spotlight.showWindowGrid) {
                                    spotlight.goToSelectedWindow();
                                    event.accepted = true;
                                    return;
                                }
                                if (spotlight.dictMode) {
                                    if (spotlight.dictResultText.length > 0) {
                                        var dp = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
                                        dp.command = ["wl-copy", spotlight.dictResultText];
                                        dp.onExited.connect(function() { try { dp.destroy(); } catch (e) {} });
                                        dp.running = true;
                                        spotlight._copyFeedback = "Definition copied";
                                        spotlight._copyFeedbackTimer.restart();
                                    }
                                    event.accepted = true;
                                    return;
                                }
                                if (spotlight.isCommandMode && text.trim().length > 1) {
                                    spotlight.runCmd(text.trim().substring(1));
                                } else if (event.modifiers & Qt.ShiftModifier) {
                                    spotlight.executeSelected();
                                } else {
                                    if (spotlight.selectedIndex >= 0 && spotlight.selectedIndex < spotlight.results.length) {
                                        var sel = spotlight.results[spotlight.selectedIndex];
                                        if (sel.type === "calc" || sel.type === "history") {
                                            spotlight.copyResult(sel);
                                        } else if (sel.type === "file") {
                                            spotlight.openFileInDolphin(sel);
                                        } else if (sel.exec) {
                                            spotlight.executeItem(sel);
                                        }
                                    }
                                }
                                event.accepted = true;
                            } else if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Right)
                                && autoCompleteSuffix.length > 0
                                && cursorPosition === text.length) {
                                searchInput.text = text + autoCompleteSuffix;
                                searchInput.cursorPosition = searchInput.text.length;
                                event.accepted = true;
                            } else if (spotlight.showWindowGrid && event.key === Qt.Key_Left) {
                                var prevWs = -1;
                                for (var li = spotlight.windowGridData.length - 1; li >= 0; li--) {
                                    if (spotlight.windowGridData[li].offset < spotlight.windowGridSelectedIndex) {
                                        prevWs = li;
                                        break;
                                    }
                                }
                                if (prevWs >= 0) {
                                    spotlight.windowGridSelectedIndex = spotlight.windowGridData[prevWs].offset;
                                } else if (spotlight.windowGridData.length > 0) {
                                    var last = spotlight.windowGridData[spotlight.windowGridData.length - 1];
                                    spotlight.windowGridSelectedIndex = last.offset + Math.min(last.windows.length, 6) - 1;
                                }
                                event.accepted = true;
                            } else if (spotlight.showWindowGrid && event.key === Qt.Key_Right) {
                                var nextWs = -1;
                                for (var ri = 0; ri < spotlight.windowGridData.length; ri++) {
                                    var wsOff = spotlight.windowGridData[ri].offset;
                                    var wsLen = Math.min(spotlight.windowGridData[ri].windows.length, 6);
                                    if (spotlight.windowGridSelectedIndex >= wsOff && spotlight.windowGridSelectedIndex < wsOff + wsLen) {
                                        if (ri + 1 < spotlight.windowGridData.length) {
                                            nextWs = ri + 1;
                                        }
                                        break;
                                    }
                                }
                                if (nextWs >= 0) {
                                    spotlight.windowGridSelectedIndex = spotlight.windowGridData[nextWs].offset;
                                } else if (spotlight.windowGridData.length > 0) {
                                    spotlight.windowGridSelectedIndex = spotlight.windowGridData[0].offset;
                                }
                                event.accepted = true;
                            } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
                                if (selectedIndex >= 0 && selectedIndex < results.length) {
                                    copyResult(results[selectedIndex]);
                                }
                                event.accepted = true;
                            }
                        }
                    }

                    Text {
                        visible: _copyFeedback.length > 0
                        text: "Copied"
                        font.family: Config.theme.font
                        font.pixelSize: Config.theme.fontSize - 2
                        color: "#4ade80"
                        font.bold: true
                        opacity: _copyFeedbackTimer.running ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }

                    Timer {
                        id: _copyFeedbackTimer
                        interval: 1500
                        onTriggered: spotlight._copyFeedback = ""
                    }

                    Text {
                        text: results.length > 0 ? `${selectedIndex + 1}/${results.length}` : ""
                        font.family: Config.theme.font
                        font.pixelSize: Config.theme.fontSize - 2
                        color: Styling.srItem("overprimary")
                        opacity: 0.6
                        visible: results.length > 0
                    }
                }
            }

            // Embedded terminal (opened with "/")
            StyledRect {
                id: termPane
                width: contentColumn.width
                height: spotlight.showTerminal ? 392 : 0
                variant: "pane"
                radius: Styling.radius(12)
                clip: true
                visible: spotlight.showTerminal
                opacity: spotlight.showTerminal ? 1 : 0
                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation { duration: Config.animDuration * 2 }
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    RowLayout {
                        width: parent.width
                        spacing: 8

                        Text {
                            text: ">_"
                            font.family: "monospace"
                            font.bold: true
                            font.pixelSize: Config.theme.fontSize - 2
                            color: Styling.srItem("overprimary")
                            opacity: 0.7
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Terminal — fish"
                            font.family: Config.theme.font
                            font.pixelSize: Config.theme.fontSize - 2
                            color: Styling.srItem("text")
                            opacity: 0.6
                            elide: Text.ElideRight
                        }
                        CloseButton {
                            onClicked: spotlight.closeTerminal()
                        }
                    }

                    Loader {
                        id: termLoader
                        width: parent.width
                        height: 330
                        active: spotlight.showTerminal
                        clip: true
                        source: "HaxTerminal.qml"
                        onLoaded: {
                            if (termLoader.item) {
                                termLoader.item.finished.connect(spotlight.closeTerminal);
                            }
                        }
                    }
                }
            }

            // Command output terminal (for / commands)
            StyledRect {
                id: cmdContainer
                width: contentColumn.width
                height: isCommandMode || cmdProcess !== null || _lastCmdVisible || _forceTerminal
                    ? cmdProcess !== null
                        ? Math.max(240, 36 + Math.min(cmdOutput.length * 20 + 20, 460))
                        : 36 + Math.min(cmdOutput.length * 20 + 20, 460)
                    : 0
                variant: "pane"
                radius: Styling.radius(12)
                clip: true
                opacity: (cmdProcess !== null || isCommandMode || _lastCmdVisible || _forceTerminal) ? 1 : 0
                visible: opacity > 0

                Behavior on height {
                    enabled: Config.animDuration > 0 && cmdProcess === null
                    NumberAnimation {
                        duration: Config.animDuration * 3
                        easing.type: Easing.OutQuint
                    }
                }
                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration * 2
                        easing.type: Easing.OutQuint
                    }
                }

                Column {
                    width: parent.width
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6

                    RowLayout {
                        width: parent.width
                        spacing: 8

                        Text {
                            text: ">_"
                            font.family: "monospace"
                            font.pixelSize: Config.theme.fontSize - 2
                            font.bold: true
                            color: Styling.srItem("overprimary")
                            opacity: 0.7
                        }

                        Text {
                            Layout.fillWidth: true
                            text: cmdProcess !== null
                                ? "$ " + searchText.trim().substring(1)
                                : "$ " + (searchText.trim().length > 1
                                    ? searchText.trim().substring(1)
                                    : "type a command...")
                            font.family: "monospace"
                            font.pixelSize: Config.theme.fontSize - 2
                            color: Styling.srItem("text")
                            opacity: 0.6
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            visible: cmdProcess !== null
                            color: spotlight.haxPrimaryColor
                            opacity: 0.8
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.3; duration: 600 }
                                NumberAnimation { to: 0.8; duration: 600 }
                            }
                        }

                        CloseButton {
                            onClicked: {
                                spotlight._lastCmdVisible = false;
                                spotlight.cmdOutput = [];
                                spotlight.cmdOutputText = "";
                            }
                        }
                    }

                    Flickable {
                        id: cmdFlickable
                        width: parent.width
                        height: Math.min(cmdOutput.length * 20 + 8, 440)
                        contentHeight: cmdOutputText.length > 0
                            ? cmdOutput.length * 20 + 8
                            : 0
                        clip: true

                        MouseArea {
                            anchors.fill: parent
                            propagateComposedEvents: true
                            preventStealing: false
                            onWheel: (wheel) => {
                                var speed = 0.5;
                                cmdFlickable.contentY = Math.max(0, Math.min(
                                    cmdFlickable.contentHeight - cmdFlickable.height,
                                    cmdFlickable.contentY - wheel.angleDelta.y * speed
                                ));
                            }
                        }

                        Text {
                            id: cmdOutputDisplay
                            width: parent.width
                            text: cmdOutput.join("\n")
                            font.family: "monospace"
                            font.pixelSize: Config.theme.fontSize - 2
                            color: Styling.srItem("text")
                            opacity: 0.85
                            wrapMode: Text.WrapAnywhere
                        }

                        ScrollBar.vertical: ScrollBar {
                            width: 8
                            policy: ScrollBar.AsNeeded
                            contentItem: Rectangle {
                                radius: 4
                                color: Styling.srItem("overprimary")
                                opacity: 0.6
                            }
                        }
                    }
                }
            }

            // Inline notifications
            StyledRect {
                id: haxNotifContainer
                width: contentColumn.width
                height: _haxNotifications.length > 0
                    ? Math.min(_haxNotifications.length * 56 + 16, 200)
                    : 0
                opacity: _haxNotifications.length > 0 ? 1 : 0
                visible: opacity > 0
                variant: "pane"
                radius: Styling.radius(12)
                clip: true
                Behavior on height {
                    enabled: Config.animDuration > 0
                    NumberAnimation { duration: Config.animDuration * 3; easing.type: Easing.OutQuint }
                }
                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutQuint }
                }

                Column {
                    width: parent.width
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6
                    Repeater {
                        model: _haxNotifications

                        delegate: Item {
                            required property var modelData
                            width: parent.width
                            height: 48

                            RowLayout {
                                width: parent.width
                                height: parent.height
                                spacing: 8

                                Text {
                                    text: modelData.icon
                                    font.pixelSize: Config.theme.fontSize + 8
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Column {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 2
                                    Text {
                                        text: modelData.type === "timer"
                                            ? "Timer \"" + modelData.label + "\" completed"
                                            : modelData.type === "plugin"
                                            ? "Plugin: " + modelData.label
                                            : "Alarm \"" + modelData.label + "\""
                                        font.family: Config.theme.font
                                        font.pixelSize: Config.theme.fontSize
                                        font.bold: true
                                        color: Styling.srItem("text")
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: modelData.body
                                        font.family: Config.theme.font
                                        font.pixelSize: Config.theme.fontSize - 2
                                        color: Styling.srItem("overprimary")
                                        opacity: 0.7
                                        elide: Text.ElideRight
                                    }
                                }

                                StyledRect {
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    radius: Styling.radius(8)
                                    variant: "focus"
                                    Layout.alignment: Qt.AlignVCenter
                                    Text {
                                        anchors.centerIn: parent
                                        text: "X"
                                        font.pixelSize: Config.theme.fontSize - 2
                                        color: Styling.srItem("overprimary")
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { _dismissHaxNotif(modelData.id); }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Results list
            Item {
                id: resultsContainer
                width: contentColumn.width
                height: results.length > 0 ? Math.min(results.length * 54, 400) : 0
                opacity: results.length > 0 ? 1 : 0
                visible: opacity > 0
                clip: true

                WheelHandler {
                    orientation: Qt.Vertical
                    onWheel: (event) => {
                        var delta = event.angleDelta.y;
                        if (delta !== 0 && resultsList.contentHeight > resultsList.height) {
                            resultsList.contentY = Math.max(
                                0,
                                Math.min(
                                    resultsList.contentHeight - resultsList.height,
                                    resultsList.contentY - delta / 4
                                )
                            );
                            event.accepted = true;
                        }
                    }
                }
                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration * 2
                        easing.type: Easing.OutQuint
                    }
                }

                Behavior on height {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration * 3
                        easing.type: Easing.OutQuint
                    }
                }

                ListView {
                    id: resultsList
                    width: parent.width
                    height: parent.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: true
                    flickableDirection: Flickable.VerticalFlick
                    maximumFlickVelocity: 5000

                    model: results
                    spacing: 2

                    ScrollBar.vertical: ScrollBar {
                        width: 6
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle {
                            radius: 3
                            color: Styling.srItem("overprimary")
                            opacity: 0.4
                        }
                    }

                    delegate: Item {
                        width: resultsList.width
                        height: modelData.cat === true ? 30 : 52

                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            visible: modelData.cat === true
                            color: "transparent"
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label || ""
                                font.family: Config.theme.font
                                font.pixelSize: Config.theme.fontSize - 2
                                font.bold: true
                                color: Styling.srItem("text")
                                opacity: 0.5
                                font.letterSpacing: 0.5
                            }
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                height: 1
                                color: Styling.srItem("text")
                                opacity: 0.08
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Styling.radius(10)
                            visible: modelData.cat !== true
                            color: index === spotlight.selectedIndex
                                ? Qt.rgba(spotlight.haxPrimaryColor.r, spotlight.haxPrimaryColor.g, spotlight.haxPrimaryColor.b, 0.25)
                                : "transparent"

                            Behavior on color {
                                enabled: Config.animDuration > 0
                                ColorAnimation { duration: Config.animDuration / 3 }
                            }
                        }

                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            visible: modelData.cat !== true

                            onClicked: {
                                spotlight.selectedIndex = index;
                                if (modelData.type === "file") {
                                    spotlight.openPreview(modelData);
                                } else if (modelData.exec) {
                                    spotlight.executeItem(modelData);
                                } else if (modelData.type === "history") {
                                    spotlight.copyResult(modelData);
                                }
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12
                            visible: modelData.cat !== true

                            Item {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                Layout.alignment: Qt.AlignVCenter

                                Image {
                                    id: sysIcon
                                    anchors.fill: parent
                                    mipmap: true
                                    source: modelData.type === "app" ? "image://icon/" + (modelData.icon || "image-missing") : ""
                                    sourceSize.width: 32
                                    sourceSize.height: 32
                                    fillMode: Image.PreserveAspectFit
                                    visible: true

                                    onStatusChanged: {
                                        if (status === Image.Error) {
                                            source = "image://icon/image-missing";
                                        }
                                    }
                                }

                                Tinted {
                                    anchors.fill: parent
                                    sourceItem: sysIcon
                                    visible: modelData.type === "app"
                                }

                                Text {
                                    id: phosphorIcon
                                    anchors.centerIn: parent
                                    text: {
                                        switch (modelData.type) {
                                            case "calc": return Icons.notepad;
                                            case "web":  return Icons.globe;
                                            case "file": return Icons.file;
                                            case "history": return Icons.notepad;
                                            default:     return Icons.apps;
                                        }
                                    }
                                    font.family: Icons.font
                                    font.pixelSize: 20
                                    color: spotlight.haxIconColor
                                    opacity: 0.8
                                    visible: modelData.type !== "app" || sysIcon.status === Image.Error
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name || ""
                                    font.family: Config.theme.font
                                    font.pixelSize: Config.theme.fontSize
                                    font.weight: Font.Medium
                                    color: Styling.srItem("text")
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.description || modelData.type || ""
                                    font.family: Config.theme.font
                                    font.pixelSize: Config.theme.fontSize - 3
                                    color: Styling.srItem("text")
                                    opacity: 0.5
                                    elide: Text.ElideRight
                                    visible: text.length > 0
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 20
                                Layout.alignment: Qt.AlignVCenter
                                radius: Styling.radius(-4)
                                color: Qt.rgba(1, 1, 1, 0.08)

                                Text {
                                    anchors.centerIn: parent
                                    text: {
                                        switch (modelData.type) {
                                            case "app": return "App";
                                            case "calc": return "=";
                                            case "file": return "File";
                                            case "web": return "Web";
                                            case "history": return "Clip";
                                            default: return "";
                                        }
                                    }
                                    font.family: Config.theme.font
                                    font.pixelSize: Config.theme.fontSize - 4
                                    color: Styling.srItem("text")
                                    opacity: 0.5
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                Layout.alignment: Qt.AlignVCenter
                                Layout.rightMargin: 4
                                radius: Styling.radius(-4)
                                color: mouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                                opacity: mouseArea.containsMouse ? 1 : 0
                                visible: modelData.type !== "calc" && modelData.type !== "info"

                                Behavior on opacity { NumberAnimation { duration: 120 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "Copy"
                                    font.pixelSize: 10
                                    color: Styling.srItem("text")
                                    opacity: 0.7
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        spotlight.copyResult(modelData);
                                        mouse.accepted = true;
                                    }
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                Layout.alignment: Qt.AlignVCenter
                                Layout.rightMargin: 4
                                radius: Styling.radius(-4)
                                color: delMouse.containsMouse ? Qt.rgba(1, 0.3, 0.3, 0.2) : "transparent"
                                opacity: (mouseArea.containsMouse && modelData.type === "history") ? 1 : 0
                                visible: modelData.type === "history"

                                Behavior on opacity { NumberAnimation { duration: 120 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "X"
                                    font.pixelSize: 12
                                    color: "#f87171"
                                    opacity: 0.8
                                }

                                MouseArea {
                                    id: delMouse
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        spotlight.removeFromHistory(modelData.historyText || modelData.name);
                                        mouse.accepted = true;
                                    }
                                }
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            height: 1
                            color: Styling.srItem("text")
                            opacity: 0.06
                            visible: index < results.length - 1
                        }
                    }
                }
            }

            // Window grid
            StyledRect {
                id: windowGridPane
                width: contentColumn.width
                height: showWindowGrid ? windowGridHeight : 0
                visible: showWindowGrid
                variant: "pane"
                radius: Styling.radius(12)
                clip: true
                Behavior on height {
                    enabled: Config.animDuration > 0
                    NumberAnimation { duration: Config.animDuration * 3; easing.type: Easing.OutQuint }
                }
                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutQuint }
                }

                Column {
                    width: parent.width
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    Text {
                        text: "Active windows"
                        font.bold: true
                        font.pixelSize: Config.theme.fontSize
                        color: Styling.srItem("text")
                        anchors.horizontalCenter: parent.horizontalCenter
                        opacity: 0.7
                    }

                    Text {
                        text: "No windows open"
                        font.pixelSize: Config.theme.fontSize - 1
                        color: Styling.srItem("text")
                        anchors.horizontalCenter: parent.horizontalCenter
                        opacity: 0.4
                        visible: windowGridData.length === 0
                    }

                    Flow {
                        id: windowGridFlow
                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: windowGridData

                            delegate: Item {
                                required property var modelData
                                readonly property var ws: modelData
                                readonly property int cardWidth: Math.min(280, (windowGridFlow.width - 8) / Math.max(1, Math.floor((windowGridFlow.width + 8) / 288)))
                                readonly property real viewW: cardWidth - 12
                                readonly property real viewH: viewW * 9 / 16
                                readonly property int n: Math.min(ws.windows.length, 6)
                                readonly property int gridCols: n <= 1 ? 1 : (n <= 2 ? 2 : (n <= 4 ? 2 : Math.min(3, n)))
                                readonly property int gridRows: Math.ceil(n / gridCols)
                                readonly property real cellW: (viewW - (gridCols - 1) * 4) / gridCols
                                readonly property real cellH: (viewH - (gridRows - 1) * 4) / gridRows

                                width: cardWidth
                                height: viewH + 28

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Styling.radius(8)
                                    color: Styling.srItem("overprimary")
                                    opacity: 0.06
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var p = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
                                            p.command = ["hyprctl", "dispatch", "workspace", String(ws.id)];
                                            p.onExited.connect(function() { p.destroy(); });
                                            p.running = true;
                                             spotlight.closeSpotlight();
                                        }
                                    }
                                }

                                Item {
                                    anchors.fill: parent
                                    anchors.margins: 6

                                    Text {
                                        id: wsHeader
                                        text: "Workspace " + ws.id
                                        font.bold: true
                                        font.pixelSize: Config.theme.fontSize - 1
                                        color: Styling.srItem("text")
                                        opacity: 0.6
                                    }

                                    Rectangle {
                                        anchors.top: wsHeader.bottom
                                        anchors.topMargin: 4
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: viewW
                                        height: viewH
                                        radius: Styling.radius(4)
                                        color: "transparent"
                                        clip: true

                                        Grid {
                                            anchors.fill: parent
                                            columns: gridCols
                                            spacing: 4

                                            Repeater {
                                                model: ws.windows.length > 6 ? 6 : ws.windows.length

                                                delegate: Item {
                                                    readonly property var win: ws.windows[index]
                                                    readonly property bool isSelected: win && win.globalIdx === spotlight.windowGridSelectedIndex
                                                    width: cellW
                                                    height: cellH

                                                    Rectangle {
                                                        anchors.fill: parent
                                                        radius: 3
                                                        color: Styling.srItem("overprimary")
                                                        opacity: isSelected ? 0.15 : 0
                                                        border.color: isSelected ? Styling.srItem("overprimary") : "transparent"
                                                        border.width: isSelected ? 2 : 0
                                                        Behavior on opacity { NumberAnimation { duration: 100 } }
                                                    }

                                                    ClippingRectangle {
                                                        anchors.fill: parent
                                                        anchors.margins: isSelected ? 3 : 0
                                                        radius: 2
                                                        antialiasing: true
                                                        color: "transparent"
                                                        border.color: win && win.is_focused ? Styling.srItem("overprimary") : Qt.rgba(1,1,1,0.12)
                                                        border.width: win && win.is_focused ? 2 : 0

                                                        ScreencopyView {
                                                            id: winPreview
                                                            anchors.fill: parent
                                                            captureSource: win ? win.toplevel : null
                                                            live: showWindowGrid && win && win.toplevel !== null
                                                            visible: win && win.toplevel !== null
                                                        }

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "[ ]"
                                                            font.pixelSize: Math.min(cellW, cellH) * 0.3
                                                            color: Styling.srItem("text")
                                                            opacity: 0.3
                                                            visible: !win || !winPreview.hasContent || win.toplevel === null
                                                        }
                                                    }

                                                    Rectangle {
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.bottom: parent.bottom
                                                        height: Math.min(14, parent.height * 0.2)
                                                        color: "#80000000"
                                                        visible: win && win.title.length > 0 && cellH > 24

                                                        Text {
                                                            anchors.fill: parent
                                                            anchors.leftMargin: 2
                                                            anchors.rightMargin: 2
                                                            text: win ? win.title : ""
                                                            font.pixelSize: Math.min(9, cellH * 0.12)
                                                            color: "white"
                                                            elide: Text.ElideRight
                                                            verticalAlignment: Text.AlignVCenter
                                                        }
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        enabled: win !== undefined
                                                        onClicked: {
                                                            if (!win) return;
                                                            (function(addr, wsId) {
                                                                var p1 = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
                                                                p1.command = ["hyprctl", "dispatch", "workspace", String(wsId)];
                                                                p1.onExited.connect(function() { p1.destroy(); });
                                                                p1.running = true;
                                                                var p2 = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
                                                                p2.command = ["hyprctl", "dispatch", "focuswindow", "address:" + addr];
                                                                p2.onExited.connect(function() { p2.destroy(); });
                                                                p2.running = true;
                                                                 spotlight.closeSpotlight();
                                                            })(win.address, ws.id);
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Text {
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.margins: 4
                                            text: "+" + (ws.windows.length - 6)
                                            font.pixelSize: Config.theme.fontSize - 3
                                            font.bold: true
                                            color: Styling.srItem("text")
                                            opacity: 0.5
                                            visible: ws.windows.length > 6
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Dictionary / Glossary
            StyledRect {
                id: dictPane
                width: contentColumn.width
                height: spotlight.dictMode
                    ? Math.max(70, Math.min(dictContent.implicitHeight + 20, 340))
                    : 0
                visible: spotlight.dictMode
                opacity: spotlight.dictMode ? 1 : 0
                variant: "pane"
                radius: Styling.radius(12)
                clip: true
                Behavior on height {
                    enabled: Config.animDuration > 0
                    NumberAnimation { duration: Config.animDuration * 3; easing.type: Easing.OutQuint }
                }
                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutQuint }
                }

                Column {
                    id: dictContent
                    width: parent.width
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 8

                    RowLayout {
                        width: parent.width
                        Text {
                            text: "Glossary" + (spotlight.dictWord.length > 0 ? " — " + spotlight.dictWord : "")
                            font.bold: true
                            font.pixelSize: Config.theme.fontSize + 1
                            color: Styling.srItem("text")
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        CloseButton {
                            onClicked: spotlight.exitDictMode()
                        }
                    }

                    Text {
                        visible: spotlight.dictWord.length === 0
                        text: "Type a word above to see its definition..."
                        font.pixelSize: Config.theme.fontSize - 1
                        color: Styling.srItem("overprimary")
                        opacity: 0.8
                        wrapMode: Text.WrapAnywhere
                    }

                    Text {
                        visible: spotlight.dictLoading
                        text: "Searching definition..."
                        font.pixelSize: Config.theme.fontSize - 1
                        color: Styling.srItem("overprimary")
                        opacity: 0.8
                    }

                    Text {
                        visible: spotlight.dictError.length > 0
                        text: spotlight.dictError
                        font.pixelSize: Config.theme.fontSize - 1
                        color: "#fbbf24"
                        wrapMode: Text.WrapAnywhere
                    }

                    Flickable {
                        visible: spotlight.dictResultText.length > 0
                        width: parent.width
                        height: Math.min(dictInner.implicitHeight, 260)
                        contentHeight: dictInner.implicitHeight
                        clip: true
                        Column {
                            id: dictInner
                            width: parent.width
                            spacing: 6
                            Repeater {
                                model: spotlight.dictResultText.split("\n")
                                delegate: Text {
                                    required property var modelData
                                    width: parent.width
                                    text: modelData
                                    font.pixelSize: Config.theme.fontSize - 1
                                    color: Styling.srItem("text")
                                    wrapMode: Text.WrapAnywhere
                                }
                            }
                        }
                    }

                    Text {
                        visible: spotlight.dictResultText.length > 0
                        text: "Enter to copy · Esc to exit"
                        font.pixelSize: Config.theme.fontSize - 3
                        color: Styling.srItem("overprimary")
                        opacity: 0.5
                    }
                }
            }

            // System monitor
            StyledRect {
                id: monitorContainer
                width: contentColumn.width
                height: showMonitor ? 260 : 0
                visible: showMonitor
                variant: "pane"
                radius: Styling.radius(12)
                clip: true
                opacity: showMonitor ? 1 : 0

                Behavior on height {
                    enabled: Config.animDuration > 0
                    NumberAnimation { duration: Config.animDuration * 3; easing.type: Easing.OutQuint }
                }
                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutQuint }
                }

                Column {
                    width: parent.width
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8

                    RowLayout {
                        width: parent.width
                        spacing: 8

                        Text {
                            text: "System Monitor"
                            font.bold: true
                            font.pixelSize: Config.theme.fontSize + 2
                            color: Styling.srItem("text")
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: "#4ade80"
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.3; duration: 800 }
                                NumberAnimation { to: 1; duration: 800 }
                            }
                        }
                        Text {
                            text: "LIVE"
                            font.pixelSize: Config.theme.fontSize - 4
                            font.bold: true
                            color: "#4ade80"
                            opacity: 0.7
                        }

                        CloseButton {
                            onClicked: stopMonitor()
                        }
                    }

                    RowLayout { width: parent.width; spacing: 8
                        Text { text: "CPU"; font.pixelSize: Config.theme.fontSize - 1; color: Styling.srItem("text"); Layout.preferredWidth: 50 }
                        Item { Layout.fillWidth: true; height: 10
                            Rectangle { anchors.fill: parent; radius: 5; color: "#2a2a2a"
                                Rectangle { height: parent.height; radius: 5; width: parent.width * Math.min(monCpu / 100, 1)
                                    color: monCpu < 50 ? "#4ade80" : monCpu < 80 ? "#facc15" : "#ef4444"
                                }
                            }
                        }
                        Text { text: monCpu.toFixed(1) + "%"; font.pixelSize: Config.theme.fontSize - 2; color: Styling.srItem("overprimary"); Layout.preferredWidth: 48; horizontalAlignment: Text.AlignRight }
                    }

                    RowLayout { width: parent.width; spacing: 8
                        Text { text: "RAM"; font.pixelSize: Config.theme.fontSize - 1; color: Styling.srItem("text"); Layout.preferredWidth: 50 }
                        Item { Layout.fillWidth: true; height: 10
                            Rectangle { anchors.fill: parent; radius: 5; color: "#2a2a2a"
                                Rectangle { height: parent.height; radius: 5; width: parent.width * Math.min(monRamPct / 100, 1)
                                    color: monRamPct < 50 ? "#4ade80" : monRamPct < 80 ? "#facc15" : "#ef4444"
                                }
                            }
                        }
                        Text { text: (monRamUsed / 1048576).toFixed(1) + "/" + (monRamTotal / 1048576).toFixed(1) + " GB"; font.pixelSize: Config.theme.fontSize - 2; color: Styling.srItem("overprimary"); Layout.preferredWidth: 110; horizontalAlignment: Text.AlignRight }
                    }

                    RowLayout { width: parent.width; spacing: 8
                        Text { text: "Disk"; font.pixelSize: Config.theme.fontSize - 1; color: Styling.srItem("text"); Layout.preferredWidth: 50 }
                        Item { Layout.fillWidth: true; height: 10
                            Rectangle { anchors.fill: parent; radius: 5; color: "#2a2a2a"
                                Rectangle { height: parent.height; radius: 5; width: parent.width * Math.min(monDisk / 100, 1)
                                    color: monDisk < 50 ? "#4ade80" : monDisk < 80 ? "#facc15" : "#ef4444"
                                }
                            }
                        }
                        Text { text: monDisk.toFixed(0) + "%"; font.pixelSize: Config.theme.fontSize - 2; color: Styling.srItem("overprimary"); Layout.preferredWidth: 48; horizontalAlignment: Text.AlignRight }
                    }

                    RowLayout { width: parent.width; spacing: 8
                        Text { text: "Temp"; font.pixelSize: Config.theme.fontSize - 1; color: Styling.srItem("text"); Layout.preferredWidth: 50 }
                        Item { Layout.fillWidth: true; height: 10
                            Rectangle { anchors.fill: parent; radius: 5; color: "#2a2a2a"
                                Rectangle { height: parent.height; radius: 5; width: parent.width * Math.min(monTemp / 100, 1)
                                    color: monTemp < 60 ? "#4ade80" : monTemp < 80 ? "#facc15" : "#ef4444"
                                }
                            }
                        }
                        Text { text: monTemp + "C"; font.pixelSize: Config.theme.fontSize - 2; color: Styling.srItem("overprimary"); Layout.preferredWidth: 48; horizontalAlignment: Text.AlignRight }
                    }

                    RowLayout { width: parent.width; spacing: 16
                        Text { text: "Processes: " + monProcs; font.pixelSize: Config.theme.fontSize - 2; color: Styling.srItem("overprimary"); opacity: 0.7 }
                        Text { text: "Uptime: " + monUptime; font.pixelSize: Config.theme.fontSize - 2; color: Styling.srItem("overprimary"); opacity: 0.7; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { text: "every 2s"; font.pixelSize: Config.theme.fontSize - 3; color: Styling.srItem("overprimary"); opacity: 0.4 }
                    }
                }
            }

            // Debug pane
            StyledRect {
                id: debugPane
                width: contentColumn.width
                variant: "pane"
                radius: Styling.radius(12)
                clip: true
                visible: spotlight.showDebug
                opacity: spotlight.showDebug ? 1 : 0
                height: spotlight.showDebug ? Math.max(debugContent.implicitHeight + 20, 120) : 0
                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation { duration: Config.animDuration * 2 }
                }

                Column {
                    id: debugContent
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    spacing: 10

                    RowLayout {
                        width: parent.width
                        Text {
                            Layout.fillWidth: true
                            text: "Debug Mode"
                            font.bold: true
                            font.pixelSize: Config.theme.fontSize
                            color: Styling.srItem("text")
                            elide: Text.ElideRight
                        }
                        CloseButton {
                            onClicked: spotlight.showDebug = false
                        }
                    }

                    Column {
                        spacing: 4
                        width: parent.width
                        Text {
                            text: "v" + Config.version
                            font.family: "monospace"
                            font.pixelSize: Config.theme.fontSize - 3
                            color: Styling.srItem("overprimary")
                            opacity: 0.5
                        }
                        Text {
                            text: "Optimized: persistent processes, no unnecessary spawning"
                            font.pixelSize: Config.theme.fontSize - 3
                            color: Styling.srItem("overprimary")
                            opacity: 0.45
                            wrapMode: Text.WordWrap
                            width: parent.width
                        }
                    }

                    Column {
                        spacing: 4
                        width: parent.width
                        Text {
                            text: "Resources"
                            font.bold: true
                            font.pixelSize: Config.theme.fontSize - 1
                            color: Styling.srItem("overprimary")
                            opacity: 0.85
                        }
                        Text {
                            text: "Memory (RSS): " + (spotlight.debugMemMB > 0 ? spotlight.debugMemMB.toFixed(1) : "—") + " MB"
                            font.family: "monospace"
                            font.pixelSize: Config.theme.fontSize - 2
                            color: Styling.srItem("text")
                        }
                        Text {
                            text: "CPU: " + (spotlight.debugCpuPct > 0 ? spotlight.debugCpuPct.toFixed(1) : "0.0") + " %"
                            font.family: "monospace"
                            font.pixelSize: Config.theme.fontSize - 2
                            color: Styling.srItem("text")
                        }
                    }

                    Column {
                        spacing: 4
                        width: parent.width
                        Text {
                            text: "Timings"
                            font.bold: true
                            font.pixelSize: Config.theme.fontSize - 1
                            color: Styling.srItem("overprimary")
                            opacity: 0.85
                        }
                        Text {
                            text: "Open (open->ready): " + (spotlight.debugOpenMs >= 0 ? spotlight.debugOpenMs + " ms" : "—")
                            font.family: "monospace"
                            font.pixelSize: Config.theme.fontSize - 2
                            color: Styling.srItem("text")
                        }
                        Text {
                            text: "Last search: " + (spotlight.debugLastSearchMs >= 0 ? spotlight.debugLastSearchMs + " ms" : "—")
                            font.family: "monospace"
                            font.pixelSize: Config.theme.fontSize - 2
                            color: Styling.srItem("text")
                        }
                        Text {
                            text: "Session open: " + spotlight.debugSessionS + " s"
                            font.family: "monospace"
                            font.pixelSize: Config.theme.fontSize - 2
                            color: Styling.srItem("text")
                        }
                    }

                    Column {
                        spacing: 4
                        width: parent.width
                        Text {
                            text: "Errors (" + spotlight.debugErrorLog.length + ")"
                            font.bold: true
                            font.pixelSize: Config.theme.fontSize - 1
                            color: Styling.srItem("overprimary")
                            opacity: 0.85
                        }
                        Repeater {
                            model: spotlight.debugErrorLog
                            delegate: Text {
                                required property var modelData
                                width: parent.width
                                text: "• [" + modelData.t + "] " + modelData.ctx + ": " + modelData.msg
                                font.family: "monospace"
                                font.pixelSize: Config.theme.fontSize - 3
                                color: "#ff8a80"
                                wrapMode: Text.WrapAnywhere
                            }
                        }
                        Text {
                            visible: spotlight.debugErrorLog.length === 0
                            text: "No errors"
                            font.family: "monospace"
                            font.pixelSize: Config.theme.fontSize - 2
                            color: Styling.srItem("text")
                            opacity: 0.7
                        }
                    }
                }
            }

            // Quick Look preview
            StyledRect {
                id: previewContainer
                width: contentColumn.width
                height: showPreview ? 300 : 0
                visible: showPreview
                variant: "pane"
                radius: Styling.radius(12)
                clip: true
                opacity: showPreview ? 1 : 0

                Behavior on height {
                    enabled: Config.animDuration > 0
                    NumberAnimation { duration: Config.animDuration * 3; easing.type: Easing.OutQuint }
                }
                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation { duration: Config.animDuration * 2; easing.type: Easing.OutQuint }
                }

                Column {
                    id: previewHeaderCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 14
                    spacing: 8

                    RowLayout {
                        width: parent.width
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: "Preview" + (spotlight.previewName ? " — " + spotlight.previewName : "")
                            elide: Text.ElideRight
                            font.bold: true
                            font.pixelSize: Config.theme.fontSize + 1
                            color: Styling.srItem("text")
                        }

                        CloseButton {
                            onClicked: spotlight.showPreview = false
                        }
                    }

                    Text {
                        id: previewPathText
                        width: parent.width
                        text: previewPath
                        font.family: "monospace"
                        font.pixelSize: Config.theme.fontSize - 2
                        color: Styling.srItem("overprimary")
                        opacity: 0.7
                        elide: Text.ElideMiddle
                    }
                }

                Item {
                    id: previewContent
                    anchors.top: previewHeaderCol.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 14

                    Image {
                        id: previewImg
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: ocrBox.visible ? ocrBox.top : parent.bottom
                        source: previewImageSrc
                        fillMode: Image.PreserveAspectFit
                        visible: previewType === "image"
                        mipmap: true
                        smooth: true
                        layer.enabled: true
                        layer.smooth: true
                    }

                    StyledRect {
                        id: ocrBox
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 116
                        radius: Styling.radius(8)
                        variant: "pane"
                        visible: false // OCR disabled
                        clip: true

                        Text {
                            id: ocrLabel
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 8
                            text: "Text in image"
                            font.bold: true
                            font.pixelSize: Config.theme.fontSize - 3
                            color: Styling.srItem("overprimary")
                            opacity: 0.8
                        }

                        Flickable {
                            anchors.top: ocrLabel.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: copyOcrBtn.top
                            anchors.margins: 8
                            contentHeight: ocrTextEl.height
                            clip: true
                            Text {
                                id: ocrTextEl
                                width: parent.width
                                text: previewOcrText
                                font.family: "monospace"
                                font.pixelSize: Config.theme.fontSize - 3
                                color: Styling.srItem("text")
                                wrapMode: Text.WrapAnywhere
                            }
                            ScrollBar.vertical: ScrollBar {
                                width: 5
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle { radius: 3; color: Styling.srItem("overprimary"); opacity: 0.4 }
                            }
                        }

                        Text {
                            id: copyOcrBtn
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 8
                            text: "Copy OCR"
                            font.pixelSize: Config.theme.fontSize - 3
                            color: Styling.srItem("text")
                            opacity: 0.8
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: spotlight.copyOcrText()
                                onEntered: parent.opacity = 1
                                onExited: parent.opacity = 0.8
                            }
                        }
                    }

                    Flickable {
                        anchors.fill: parent
                        contentHeight: previewTextArea.height
                        clip: true
                        visible: previewType !== "image"
                        boundsBehavior: Flickable.StopAtBounds

                        Text {
                            id: previewTextArea
                            width: parent.width
                            text: previewText
                            font.family: "monospace"
                            font.pixelSize: Config.theme.fontSize - 2
                            color: Styling.srItem("text")
                            opacity: 0.85
                            wrapMode: Text.WrapAnywhere
                        }

                        ScrollBar.vertical: ScrollBar {
                            width: 6
                            policy: ScrollBar.AsNeeded
                            contentItem: Rectangle {
                                radius: 3
                                color: Styling.srItem("overprimary")
                                opacity: 0.4
                            }
                        }
                    }
                }
            }

            // Configuration panel
            StyledRect {
                id: configPane
                width: contentColumn.width
                variant: "pane"
                radius: Styling.radius(12)
                clip: true
                visible: spotlight.showConfig
                opacity: spotlight.showConfig ? 1 : 0
                height: spotlight.showConfig ? configContent.implicitHeight + 20 : 0
                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation { duration: Config.animDuration * 2 }
                }
                Behavior on height {
                    enabled: Config.animDuration > 0
                    NumberAnimation { duration: Config.animDuration * 2 }
                }

                Column {
                    id: configContent
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    spacing: 12

                    Text {
                        width: parent.width
                        text: "Configure Hax"
                        font.bold: true
                        font.pixelSize: Config.theme.fontSize
                        color: Styling.srItem("text")
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Styling.srItem("overprimary")
                        opacity: 0.2
                    }

                    Text {
                        text: "Colors"
                        font.bold: true
                        font.pixelSize: Config.theme.fontSize - 1
                        color: Styling.srItem("text")
                    }

                    RowLayout {
                        width: parent.width
                        Text {
                            text: "Custom color:"
                            font.pixelSize: Config.theme.fontSize - 2
                            color: Styling.srItem("text")
                            Layout.fillWidth: true
                        }
                        Rectangle {
                            id: colorSwatch
                            width: 28; height: 28; radius: 6
                            color: Config.hax.customColorEnabled ? Config.hax.customColor : Colors.primary
                            border { color: Styling.srItem("overprimary"); width: 1 }
                            Layout.alignment: Qt.AlignVCenter

                            MouseArea {
                                id: swatchClickArea
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var pos = colorSwatch.mapToItem(null, 0, 0);
                                    colorPicker.x = pos.x - 100;
                                    colorPicker.y = pos.y + colorSwatch.height + 8;
                                    spotlight.colorPickerOpen = !spotlight.colorPickerOpen;
                                }
                            }

                            Text {
                                anchors { right: parent.right; bottom: parent.bottom }
                                text: "v"
                                font.pixelSize: 7
                                color: Styling.srItem("overprimary")
                                opacity: 0.6
                            }
                        }
                        TextField {
                            id: colorInput
                            text: Config.hax.customColor
                            font.pixelSize: Config.theme.fontSize - 2
                            font.family: "monospace"
                            implicitWidth: 90
                            height: 26
                            onTextChanged: {
                                if (/^#[0-9a-fA-F]{6}$/.test(text)) {
                                    Config.hax.customColor = text;
                                    Config.saveHax();
                                }
                            }
                            background: Rectangle {
                                radius: 4
                                color: Styling.srItem("bg")
                                border { color: Styling.srItem("overprimary"); width: 1 }
                            }
                        }
                    }

                    RowLayout {
                        width: parent.width
                        spacing: 8
                        StyledRect {
                            variant: "common"
                            radius: Styling.radius(6)
                            Layout.fillWidth: true
                            height: 28
                            opacity: Config.hax.customColorEnabled ? 1 : 0.5

                            Text {
                                anchors.centerIn: parent
                                text: Config.hax.customColorEnabled ? "Custom color enabled" : "Use custom color"
                                font.pixelSize: Config.theme.fontSize - 2
                                color: Styling.srItem("text")
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Config.hax.customColorEnabled = !Config.hax.customColorEnabled;
                                    Config.saveHax();
                                }
                            }
                        }

                        StyledRect {
                            variant: "common"
                            radius: Styling.radius(6)
                            implicitWidth: 90
                            height: 28

                            Text {
                                anchors.centerIn: parent
                                text: "Sync"
                                font.pixelSize: Config.theme.fontSize - 2
                                color: Styling.srItem("text")
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Config.hax.customColorEnabled = false;
                                    Config.hax.customColor = Colors.primary;
                                    Config.saveHax();
                                    colorInput.text = Colors.primary;
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Styling.srItem("overprimary")
                        opacity: 0.2
                    }

                    Text {
                        text: "OCR (Live Text)"
                        font.bold: true
                        font.pixelSize: Config.theme.fontSize - 1
                        color: Styling.srItem("text")
                    }

                    RowLayout {
                        width: parent.width
                        Text {
                            text: "Extract text from images (Tesseract):"
                            font.pixelSize: Config.theme.fontSize - 2
                            color: Styling.srItem("text")
                            Layout.fillWidth: true
                        }
                        StyledRect {
                            variant: "common"
                            radius: Styling.radius(6)
                            implicitWidth: 80
                            height: 28

                            Text {
                                anchors.centerIn: parent
                                text: Config.hax.ocrEnabled ? "Enabled" : "Disabled"
                                font.pixelSize: Config.theme.fontSize - 2
                                color: Styling.srItem("text")
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Config.hax.ocrEnabled = !Config.hax.ocrEnabled;
                                    Config.saveHax();
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Styling.srItem("overprimary")
                        opacity: 0.2
                    }

                    Text {
                        text: "Quick actions"
                        font.bold: true
                        font.pixelSize: Config.theme.fontSize - 1
                        color: Styling.srItem("text")
                    }

                    Text {
                        width: parent.width
                        text: "Create shortcuts: type a keyword (e.g. 'cc') and Hax runs the action. Click the clipboard icon to pick an app."
                        font.pixelSize: Config.theme.fontSize - 3
                        color: Styling.srItem("text")
                        opacity: 0.7
                        wrapMode: Text.WordWrap
                    }

                    Repeater {
                        id: shortcutRepeater
                        model: haxShortcutsList

                        delegate: Column {
                            width: parent.width
                            spacing: 4

                            RowLayout {
                                width: parent.width
                                spacing: 6

                                TextField {
                                    id: keywordsField
                                    Layout.fillWidth: true
                                    height: 26
                                    text: modelData.keywords.join(", ")
                                    font.pixelSize: Config.theme.fontSize - 2
                                    font.family: "monospace"
                                    color: "#f0f0f0"
                                    padding: 4
                                    verticalAlignment: TextInput.AlignVCenter
                                    background: Rectangle {
                                        radius: 4
                                        color: "#1a1a2e"
                                        border { color: "#444466"; width: 1 }
                                    }

                                    onEditingFinished: {
                                        var arr = haxShortcutsList.slice();
                                        arr[index].keywords = text.split(",").map(function(s) { return s.trim(); }).filter(function(s) { return s.length > 0; });
                                        Config.hax.customShortcuts = JSON.stringify(arr);
                                        Config.saveHaxShortcuts(arr);
                                    }
                                }

                                TextField {
                                    id: actionField
                                    implicitWidth: 100
                                    height: 26
                                    text: modelData.action
                                    font.pixelSize: Config.theme.fontSize - 2
                                    font.family: "monospace"
                                    color: "#f0f0f0"
                                    padding: 4
                                    verticalAlignment: TextInput.AlignVCenter
                                    background: Rectangle {
                                        radius: 4
                                        color: "#1a1a2e"
                                        border { color: "#444466"; width: 1 }
                                    }

                                    onEditingFinished: {
                                        var arr = haxShortcutsList.slice();
                                        arr[index].action = text;
                                        Config.hax.customShortcuts = JSON.stringify(arr);
                                        Config.saveHaxShortcuts(arr);
                                    }
                                }

                                StyledRect {
                                    variant: "common"
                                    radius: Styling.radius(4)
                                    implicitWidth: 26
                                    height: 26

                                    Text {
                                        anchors.centerIn: parent
                                        text: "X"
                                        font.pixelSize: Config.theme.fontSize - 1
                                        color: Colors.warning
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var arr = haxShortcutsList.slice();
                                            arr.splice(index, 1);
                                            Config.hax.customShortcuts = JSON.stringify(arr);
                                            Config.saveHaxShortcuts(arr);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 6

                        TextField {
                            id: newNameInput
                            width: parent.width
                            height: 28
                            placeholderText: "Name (optional, e.g. Open Firefox)"
                            placeholderTextColor: "#666688"
                            font.pixelSize: Config.theme.fontSize - 2
                            color: "#f0f0f0"
                            padding: 4
                            verticalAlignment: TextInput.AlignVCenter
                            background: Rectangle {
                                radius: 4
                                color: "#1a1a2e"
                                border { color: "#444466"; width: 1 }
                            }
                        }

                        RowLayout {
                            width: parent.width
                            spacing: 6

                            TextField {
                                id: newKeywordsInput
                                Layout.fillWidth: true
                                height: 28
                                placeholderText: "Keyword (e.g. ff)"
                                placeholderTextColor: "#666688"
                                font.pixelSize: Config.theme.fontSize - 2
                                font.family: "monospace"
                                color: "#f0f0f0"
                                padding: 4
                                verticalAlignment: TextInput.AlignVCenter
                                background: Rectangle {
                                    radius: 4
                                    color: "#1a1a2e"
                                    border { color: "#444466"; width: 1 }
                                }
                            }

                            Rectangle {
                                implicitWidth: 160
                                height: 28
                                radius: 4
                                color: "#1a1a2e"
                                border { color: "#444466"; width: 1 }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    spacing: 2

                                    TextField {
                                        id: newActionInput
                                        Layout.fillWidth: true
                                        height: 20
                                        placeholderText: "app, command or URL"
                                        placeholderTextColor: "#666688"
                                        font.pixelSize: Config.theme.fontSize - 2
                                        font.family: "monospace"
                                        color: "#f0f0f0"
                                        padding: 0
                                        verticalAlignment: TextInput.AlignVCenter
                                        background: null
                                    }

                                    Text {
                                        text: "Clip"
                                        font.pixelSize: 10
                                        color: "#aaaacc"
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                actionPresets.x = morphContainer.x + (morphContainer.width - actionPresets.width) / 2;
                                                actionPresets.y = morphContainer.y + (morphContainer.height - actionPresets.height) / 2;
                                                actionPresetsOpen = !actionPresetsOpen;
                                            }
                                        }
                                    }
                                }
                            }

                            StyledRect {
                                variant: "common"
                                radius: Styling.radius(6)
                                implicitWidth: 60
                                height: 28

                                Text {
                                    anchors.centerIn: parent
                                    text: "Add"
                                    font.pixelSize: Config.theme.fontSize - 2
                                    color: "#f0f0f0"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var kw = newKeywordsInput.text.split(",").map(function(s) { return s.trim(); }).filter(function(s) { return s.length > 0; });
                                        var act = newActionInput.text.trim();
                                        if (kw.length > 0 && act.length > 0) {
                                            var t = "app";
                                            if (/^https?:\/\//i.test(act)) t = "web";
                                            else if (/[|&;<>]/.test(act) || act.indexOf(" ") >= 0 || act.startsWith("/") || act.startsWith("sudo")) t = "command";
                                            var arr = haxShortcutsList.slice();
                                            arr.push({
                                                "keywords": kw,
                                                "action": act,
                                                "type": t,
                                                "name": newNameInput.text.trim()
                                            });
                                            Config.hax.customShortcuts = JSON.stringify(arr);
                                            Config.saveHaxShortcuts(arr);
                                            newKeywordsInput.text = "";
                                            newActionInput.text = "";
                                            newNameInput.text = "";
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Plugin management
            StyledRect {
                id: pluginPane
                width: contentColumn.width
                variant: "pane"
                radius: Styling.radius(12)
                clip: true
                visible: spotlight.showPlugins
                opacity: spotlight.showPlugins ? 1 : 0
                height: spotlight.showPlugins ? pluginContent.implicitHeight + 20 : 0

                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation { duration: Config.animDuration * 2 }
                }
                Behavior on height {
                    enabled: Config.animDuration > 0
                    NumberAnimation { duration: Config.animDuration * 2 }
                }

                Column {
                    id: pluginContent
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    spacing: 12

                    Text {
                        width: parent.width
                        text: "Plugins"
                        font.bold: true
                        font.pixelSize: Config.theme.fontSize
                        color: Styling.srItem("text")
                    }

                    Text {
                        width: parent.width
                        text: "Plugins add extra features to Hax. Place scripts (.sh, .py) or QML files in ~/.config/hax/plugins/"
                        font.pixelSize: Config.theme.fontSize - 3
                        color: Styling.srItem("text")
                        opacity: 0.7
                        wrapMode: Text.WordWrap
                    }

                    Repeater {
                        id: pluginRepeater
                        model: spotlight.pluginManager ? spotlight.pluginManager.plugins : []

                        delegate: RowLayout {
                            width: parent.width
                            spacing: 6
                            height: 28

                            Text {
                                text: modelData.icon + " " + modelData.name
                                font.pixelSize: Config.theme.fontSize - 2
                                color: modelData.enabled ? "#f0f0f0" : "#666688"
                                Layout.fillWidth: true
                                verticalAlignment: Text.AlignVCenter
                            }

                            Text {
                                text: modelData.type === "qml" ? "QML" : "Script"
                                font.pixelSize: Config.theme.fontSize - 2
                                color: Styling.srItem("overprimary")
                                opacity: 0.6
                                verticalAlignment: Text.AlignVCenter
                            }

                            StyledRect {
                                variant: "common"
                                radius: Styling.radius(4)
                                implicitWidth: modelData.loaded ? (modelData.enabled ? 60 : 68) : 50
                                height: 22

                                Text {
                                    anchors.centerIn: parent
                                    text: !modelData.loaded ? "Loading" : (modelData.enabled ? "Enabled" : "Disabled")
                                    font.pixelSize: Config.theme.fontSize - 3
                                    color: Styling.srItem("text")
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: modelData.loaded
                                    onClicked: {
                                        spotlight.pluginManager.setPluginEnabled(modelData.id, !modelData.enabled);
                                    }
                                }
                            }

                            StyledRect {
                                variant: "common"
                                radius: Styling.radius(4)
                                implicitWidth: 22
                                height: 22
                                visible: modelData.type === "qml"

                                Text {
                                    anchors.centerIn: parent
                                    text: "R"
                                    font.pixelSize: Config.theme.fontSize - 2
                                    color: Styling.srItem("text")
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        spotlight.pluginManager.reloadPlugin(modelData.id);
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        width: parent.width
                        spacing: 6

                        StyledRect {
                            variant: "common"
                            radius: Styling.radius(6)
                            implicitWidth: 130
                            height: 26

                            Text {
                                anchors.centerIn: parent
                                text: "Reload all"
                                font.pixelSize: Config.theme.fontSize - 2
                                color: Styling.srItem("text")
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (spotlight.pluginManager) {
                                        spotlight.pluginManager.reloadAll();
                                    }
                                }
                            }
                        }

                        StyledRect {
                            variant: "common"
                            radius: Styling.radius(6)
                            implicitWidth: 130
                            height: 26

                            Text {
                                anchors.centerIn: parent
                                text: "Create example"
                                font.pixelSize: Config.theme.fontSize - 2
                                color: Styling.srItem("text")
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (spotlight.pluginManager) {
                                        spotlight.pluginManager.createDefaultPlugins();
                                        Qt.callLater(function() {
                                            spotlight.pluginManager.reloadAll();
                                        });
                                    }
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }
                }
            }
        }
    }

    // Floating color picker
    StyledRect {
        id: colorPicker
        variant: "popup"
        radius: Styling.radius(10)
        width: 230
        height: colorPickerColumn.implicitHeight + 16
        visible: spotlight.colorPickerOpen
        opacity: spotlight.colorPickerOpen ? 1 : 0
        z: 100

        Behavior on opacity {
            NumberAnimation { duration: 80 }
        }

        Column {
            id: colorPickerColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 6

            Text {
                text: "Select a color:"
                font.pixelSize: Config.theme.fontSize - 2
                font.bold: true
                color: Styling.srItem("text")
            }

            Flow {
                width: parent.width
                spacing: 4

                Repeater {
                    model: [
                        "#ff0000", "#ff4444", "#ff8888", "#ffb3ae",
                        "#ff8800", "#ffaa44", "#ffcc88", "#ffddbb",
                        "#ffff00", "#ffdd44", "#ffee88", "#fff5cc",
                        "#00ff00", "#44ff44", "#88ff88", "#ccffcc",
                        "#00ffff", "#44ddff", "#88ddff", "#bbeeff",
                        "#0088ff", "#4488ff", "#6699ff", "#99bbff",
                        "#0000ff", "#4444ff", "#6666ff", "#8888ff",
                        "#8800ff", "#8844ff", "#aa66ff", "#cc99ff",
                        "#ff00ff", "#ff44ff", "#ff88ff", "#ffbbff",
                        "#ff0088", "#ff4488", "#ff8888", "#ffbbcc",
                        "#000000", "#333333", "#666666", "#999999",
                        "#cccccc", "#ffffff"
                    ]

                    Rectangle {
                        required property var modelData
                        width: 26; height: 26; radius: 4
                        color: modelData
                        border { color: Styling.srItem("overprimary"); width: modelData === Config.hax.customColor ? 2 : 1 }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Config.hax.customColor = modelData;
                                Config.hax.customColorEnabled = true;
                                Config.saveHax();
                                colorInput.text = modelData;
                                spotlight.colorPickerOpen = false;
                            }
                        }
                    }
                }
            }

            RowLayout {
                width: parent.width
                spacing: 4
                Text {
                    text: "Hex:"
                    font.pixelSize: Config.theme.fontSize - 2
                    color: Styling.srItem("text")
                }
                TextField {
                    Layout.fillWidth: true
                    height: 24
                    text: Config.hax.customColor
                    font.pixelSize: Config.theme.fontSize - 2
                    font.family: "monospace"
                    onTextChanged: {
                        if (/^#[0-9a-fA-F]{6}$/.test(text)) {
                            Config.hax.customColor = text;
                            Config.saveHax();
                        }
                    }
                    background: Rectangle {
                        radius: 4
                        color: Styling.srItem("bg")
                        border { color: Styling.srItem("overprimary"); width: 1 }
                    }
                }
            }
        }
    }

    // Quick action presets picker
    StyledRect {
        id: actionPresets
        variant: "popup"
        radius: Styling.radius(10)
        width: 280
        height: Math.min(actionPresetsInner.implicitHeight + 24, 440)
        visible: spotlight.actionPresetsOpen
        opacity: spotlight.actionPresetsOpen ? 1 : 0
        z: 100
        clip: true

        Behavior on opacity {
            NumberAnimation { duration: 80 }
        }

        Flickable {
            anchors.fill: parent
            anchors.margins: 8
            contentHeight: actionPresetsInner.implicitHeight
            interactive: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                width: 6
                policy: ScrollBar.AsNeeded
                opacity: 0.7
                contentItem: Rectangle {
                    radius: 3
                    color: Styling.srItem("overprimary")
                    opacity: 0.5
                }
            }

            Column {
                id: actionPresetsInner
                width: parent.width - 8
                spacing: 3

                Text {
                    text: "Pick an app or command:"
                    font.pixelSize: Config.theme.fontSize - 2
                    font.bold: true
                    color: Styling.srItem("text")
                    bottomPadding: 4
                }

                Repeater {
                    model: [
                        { cat: true, label: "Browsers" },
                        { cat: false, label: "Firefox", value: "firefox" },
                        { cat: false, label: "Zen Browser", value: "zen" },
                        { cat: true, label: "Terminals" },
                        { cat: false, label: "Kitty", value: "kitty" },
                        { cat: false, label: "Foot", value: "foot" },
                        { cat: true, label: "Coding" },
                        { cat: false, label: "VS Code (OSS)", value: "code-oss" },
                        { cat: false, label: "Vim", value: "vim" },
                        { cat: true, label: "Office" },
                        { cat: false, label: "ONLYOFFICE", value: "onlyoffice-desktopeditors" },
                        { cat: false, label: "WPS Writer", value: "wps" },
                        { cat: false, label: "Obsidian", value: "obsidian" },
                        { cat: true, label: "Multimedia" },
                        { cat: false, label: "Spotify", value: "spotify-launcher" },
                        { cat: false, label: "VLC", value: "vlc" },
                        { cat: false, label: "mpv", value: "mpv" },
                        { cat: true, label: "Social" },
                        { cat: false, label: "Discord", value: "discord" },
                        { cat: false, label: "KDE Connect", value: "kdeconnect-app" },
                        { cat: true, label: "Files" },
                        { cat: false, label: "Dolphin", value: "dolphin" },
                        { cat: false, label: "Documents", value: "dolphin ~/Documentos" },
                        { cat: false, label: "Downloads", value: "dolphin ~/Descargas" },
                        { cat: true, label: "System" },
                        { cat: false, label: "Settings", value: "systemsettings" },
                        { cat: false, label: "Lock", value: "loginctl lock-session" },
                        { cat: false, label: "Suspend", value: "systemctl suspend" },
                        { cat: false, label: "Power off", value: "systemctl poweroff" },
                        { cat: false, label: "Reboot", value: "systemctl reboot" },
                        { cat: true, label: "Web" },
                        { cat: false, label: "YouTube", value: "https://youtube.com" },
                        { cat: false, label: "GitHub", value: "https://github.com" },
                        { cat: true, label: "Timers" },
                        { cat: false, label: "Custom timer...", value: "timer " },
                        { cat: false, label: "Timer 5 min", value: "timer 5m" },
                        { cat: false, label: "Timer 10 min", value: "timer 10m" },
                        { cat: false, label: "Timer 15 min", value: "timer 15m" },
                        { cat: false, label: "Timer 25 min (Pomodoro)", value: "timer 25m pomodoro" },
                        { cat: false, label: "Timer 30 min", value: "timer 30m" },
                        { cat: false, label: "Timer 1 hour", value: "timer 1h" },
                        { cat: false, label: "Cancel all timers", value: "timer cancel" },
                        { cat: true, label: "Alarms" },
                        { cat: false, label: "Alarm 7:00", value: "alarm 7:00" },
                        { cat: false, label: "Alarm 7:30", value: "alarm 7:30" },
                        { cat: false, label: "Alarm 8:00", value: "alarm 8:00" },
                        { cat: false, label: "Alarm 14:30", value: "alarm 14:30" },
                        { cat: false, label: "Alarm 22:00", value: "alarm 22:00" },
                        { cat: false, label: "Clear all alarms", value: "alarm clear" },
                        { cat: true, label: "Hax" },
                        { cat: false, label: "Configure Hax", value: "config" },
                        { cat: false, label: "OCR / Live Text", value: "live" },
                        { cat: false, label: "Help", value: "help" }
                    ]

                    delegate: Item {
                        required property var modelData
                        width: parent.width
                        height: modelData.cat ? 24 : 26

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: modelData.cat ? 2 : 12
                            text: modelData.cat ? "> " + modelData.label : modelData.label
                            font.pixelSize: Config.theme.fontSize - 2
                            font.bold: modelData.cat
                            color: modelData.cat ? Styling.srItem("overprimary") : Styling.srItem("text")
                            opacity: modelData.cat ? 0.7 : 0.95
                            verticalAlignment: Text.AlignVCenter
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !modelData.cat
                            cursorShape: modelData.cat ? Qt.ArrowCursor : Qt.PointingHandCursor
                            hoverEnabled: true
                            onEntered: if (!modelData.cat) parent.opacity = 0.6
                            onExited: if (!modelData.cat) parent.opacity = 1
                            onClicked: {
                                if (!modelData.cat && modelData.value) {
                                    newActionInput.text = modelData.value;
                                    newNameInput.text = modelData.label;
                                    spotlight.actionPresetsOpen = false;
                                    newActionInput.forceActiveFocus();
                                    newActionInput.cursorPosition = newActionInput.text.length;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // --------------------------------------------------------------
    // Command execution
    // --------------------------------------------------------------

    function runCmd(cmd) {
        cancelCmdProcess();
        if (cmd.trim().length === 0) return;

        _forceTerminal = true;
        cmdOutput = [];
        cmdOutputText = "";

        var proc;
        try {
            proc = Qt.createQmlObject(
                'import Quickshell.Io; Process { stdout: SplitParser {} }',
                spotlight
            );
        } catch (e) {
            spotlight.debugLogError("runCmd", e);
            return;
        }

        proc.command = ["bash", "-c", cmd + " 2>&1"];
        proc.workingDirectory = Quickshell.env("HOME") || "/tmp";

        proc.stdout.onRead.connect(function(data) {
            var arr = cmdOutput.slice();
            var lines = data.trim().split("\n");
            for (var i = 0; i < lines.length; i++) {
                if (lines[i].length > 0) arr.push(lines[i]);
            }
            cmdOutput = arr;
            cmdOutputText = arr.join("\n");
        });

        proc.onExited.connect(function(code) {
            _forceTerminal = false;
            var arr = cmdOutput.slice();
            arr.push("Done (exit code: " + code + ")");
            cmdOutput = arr;
            cmdOutputText = arr.join("\n");
            cmdProcess = null;
            _lastCmdVisible = true;
            proc.destroy();
        });

        cmdProcess = proc;
        proc.running = true;
    }

    function cancelCmdProcess() {
        _forceTerminal = false;
        _lastCmdVisible = false;
        if (cmdProcess) {
            cmdProcess.running = false;
            cmdProcess.destroy();
            cmdProcess = null;
        }
        cmdOutput = [];
        cmdOutputText = "";
    }

    function bash(cmd) {
        var proc = Qt.createQmlObject(
            'import Quickshell.Io; Process { }',
            spotlight
        );
        proc.command = ["bash", "-c", cmd];
        proc.onExited.connect(function() { proc.destroy(); });
        proc.running = true;
    }

    function launchShortcut(shortcut) {
        var action = shortcut.action;
        var type = shortcut.type;
        if (action === "config") { spotlight.showPlugins = false; spotlight.showConfig = true; return; }
        if (action === "plugins") { spotlight.searchText = ""; spotlight.showConfig = false; spotlight.showPlugins = true; return; }
        var _a = action.toLowerCase();
        if (_a === "timer" || _a.indexOf("timer ") === 0) { _runTimerFromShortcut(action);  spotlight.closeSpotlight(); return; }
        if (_a === "alarm" || _a === "alarma" || _a.indexOf("alarm") === 0) { _runAlarmFromShortcut(action);  spotlight.closeSpotlight(); return; }
        if (type === "web" || /^https?:\/\//i.test(action)) {
            Qt.openUrlExternally(action);
        } else if (type === "command" || /[|&;<>]/.test(action) || action.indexOf(" ") >= 0 || action.startsWith("/") || action.startsWith("sudo")) {
            bash(action);
        } else {
            try {
                var res = AppSearch.fuzzyQuery(action);
                if (res && res.length > 0 && res[0].execute) {
                    res[0].execute();
                     spotlight.closeSpotlight();
                    return;
                }
            } catch (e) {}
            bash(action);
        }
         spotlight.closeSpotlight();
    }

    function _runTimerFromShortcut(action) {
        var args = action.trim().replace(/^timer\s*/i, "").trim();
        if (/^(cancel|clear|stop)\s*$/i.test(args)) { clearAllTimers(); return; }
        var m = args.match(/^(\d+)\s*([smh])\s*(.*)$/i);
        if (!m) return;
        var val = parseInt(m[1]);
        var unit = m[2].toLowerCase();
        var seconds = unit === 's' ? val : unit === 'm' ? val * 60 : val * 3600;
        var label = (m[3] || "").trim();
        if (seconds > 0 && seconds <= 86400) startTimer(label || "Timer", seconds);
    }

    function _runAlarmFromShortcut(action) {
        var args = action.trim().replace(/^alarm\s*/i, "").trim();
        if (/^(clear|cancel)\s*$/i.test(args)) { clearAllAlarms(); return; }
        var m = args.match(/^(\d{1,2}):(\d{2})\s*(.*)$/);
        if (!m) return;
        var hour = parseInt(m[1]);
        var minute = parseInt(m[2]);
        if (hour < 0 || hour >= 24 || minute < 0 || minute >= 60) return;
        var rest = (m[3] || "").trim();
        var days = [];
        var dayParse = rest.match(/([L M X J V S D]+)$/i);
        if (dayParse) {
            var dayStr = dayParse[1].toUpperCase();
            var dayMap = { 'L': 1, 'M': 2, 'X': 3, 'J': 4, 'V': 5, 'S': 6, 'D': 0 };
            for (var dk = 0; dk < dayStr.length; dk++) {
                var dval = dayMap[dayStr[dk]];
                if (dval !== undefined && days.indexOf(dval) < 0) days.push(dval);
            }
            rest = rest.substring(0, rest.length - dayParse[0].length).trim();
        }
        var label = rest || "Alarm";
        setAlarm(label, hour, minute, days);
    }

    function openTerminal() {
        spotlight.showTerminal = true;
        spotlight.showPreview = false;
        spotlight.showConfig = false;
        spotlight.showPlugins = false;
        spotlight.showMonitor = false;
        spotlight.cancelCmdProcess();
        spotlight.searchText = "";
    }

    function closeTerminal() {
        spotlight.showTerminal = false;
        searchInput.forceActiveFocus();
    }

    // --------------------------------------------------------------
    // Search logic
    // --------------------------------------------------------------

    function updateResults() {
        spotlight.showPreview = false;
        spotlight.showPlugins = false;

        if (isCommandMode) {
            results = [];
            return;
        }

        const query = searchText.trim().toLowerCase();

        if (spotlight.dictMode) {
            spotlight.dictWord = query;
            if (query.length >= 2) {
                if (query.length < spotlight.dictLastLen) {
                    spotlight.dictLoading = false;
                    spotlight.dictResultText = "";
                    spotlight.dictError = "";
                } else {
                    spotlight.startDictSearch(query);
                }
            } else {
                spotlight.dictLoading = false;
                spotlight.dictResultText = "";
                spotlight.dictError = "";
            }
            spotlight.dictLastLen = query.length;
            results = [];
            return;
        }

        const gen = ++searchGeneration;
        var newResults = [];

        if (query.length === 0) {
            results = [];
            return;
        }

        // Calculator
        if (/^[\d+\-*/().\s]+$/.test(query) && /[+\-*/]/.test(query)) {
            const result = safeEval(query);
            if (result !== null && typeof result === "number") {
                newResults.push({
                    name: query + " = " + result,
                    description: "Copy result",
                    icon: Icons.notepad,
                    type: "calc",
                    exec: () => {
                        const p = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
                        p.command = ["wl-copy", String(result)];
                        p.running = true;
                        p.onExited.connect(() => p.destroy());
                         spotlight.closeSpotlight();
                    }
                });
                results = newResults;
                return;
            }
        }

        // System actions
        var sysMatch = query.match(/^(l|s|a|r|lock|bloquear|suspend|suspender|apagar|shutdown|poweroff|reboot|reiniciar)$/i);
        if (sysMatch) {
            var action = sysMatch[1].toLowerCase();
            var actions = {
                "l": { name: "Lock screen", desc: "Lock the session", exec: function() { LockscreenService.lock();  spotlight.closeSpotlight(); } },
                "lock": { name: "Lock screen", desc: "Lock the session", exec: function() { LockscreenService.lock();  spotlight.closeSpotlight(); } },
                "bloquear": { name: "Lock screen", desc: "Lock the session", exec: function() { LockscreenService.lock();  spotlight.closeSpotlight(); } },
                "s": { name: "Suspend", desc: "Suspend the system", exec: function() { bash("systemctl suspend");  spotlight.closeSpotlight(); } },
                "suspend": { name: "Suspend", desc: "Suspend the system", exec: function() { bash("systemctl suspend");  spotlight.closeSpotlight(); } },
                "suspender": { name: "Suspend", desc: "Suspend the system", exec: function() { bash("systemctl suspend");  spotlight.closeSpotlight(); } },
                "a": { name: "Power off", desc: "Shutdown the system", exec: function() { bash("systemctl poweroff");  spotlight.closeSpotlight(); } },
                "apagar": { name: "Power off", desc: "Shutdown the system", exec: function() { bash("systemctl poweroff");  spotlight.closeSpotlight(); } },
                "shutdown": { name: "Power off", desc: "Shutdown the system", exec: function() { bash("systemctl poweroff");  spotlight.closeSpotlight(); } },
                "poweroff": { name: "Power off", desc: "Shutdown the system", exec: function() { bash("systemctl poweroff");  spotlight.closeSpotlight(); } },
                "r": { name: "Reboot", desc: "Reboot the system", exec: function() { bash("systemctl reboot");  spotlight.closeSpotlight(); } },
                "reboot": { name: "Reboot", desc: "Reboot the system", exec: function() { bash("systemctl reboot");  spotlight.closeSpotlight(); } },
                "reiniciar": { name: "Reboot", desc: "Reboot the system", exec: function() { bash("systemctl reboot");  spotlight.closeSpotlight(); } },
            }; 
            var a = actions[action];
            if (a) {
                results = [{
                    name: a.name,
                    description: a.desc,
                    icon: Icons.notepad,
                    type: "info",
                    exec: a.exec
                }];
                return;
            }
        }

        // Custom shortcuts
        if (haxShortcutsList && haxShortcutsList.length > 0) {
            for (var si = 0; si < haxShortcutsList.length; si++) {
                var shortcut = haxShortcutsList[si];
                var kw = shortcut.keywords || [];
                var scName = (shortcut.name && shortcut.name.length > 0) ? shortcut.name : shortcut.action;
                var exact = false;
                for (var ki = 0; ki < kw.length; ki++) {
                    if (query === kw[ki].toLowerCase().trim()) { exact = true; break; }
                }
                var byName = query.length > 0 && scName.toLowerCase().indexOf(query) >= 0;
                if (exact || byName) {
                    var iconChar = shortcut.type === "app" ? "App"
                        : shortcut.type === "web" ? "Web"
                        : shortcut.type === "command" ? "Cmd"
                        : "Act";
                    var scResult = {
                        name: iconChar + " " + scName,
                        description: "Quick action — type \"" + kw.join(", ") + "\"",
                        icon: Icons.notepad,
                        type: "shortcut",
                        exec: (function(sc) {
                            return function() { launchShortcut(sc); };
                        })(shortcut)
                    };
                    if (exact) newResults.unshift(scResult);
                    else newResults.push(scResult);
                }
            }
        }

        // Help
        var helpMatch = query.match(/^(ayuda|help|h|commands|comandos|\?)$/i);
        if (helpMatch) {
            newResults = [
                { name: "Available commands", description: "Type what you want to do", icon: Icons.notepad, type: "info", exec: null },
                { name: "Search apps", description: "Type the name of any app (firefox, vscode, terminal...)", icon: Icons.notepad, type: "info", exec: null },
                { name: "install <package>", description: "Search in pacman + AUR + flatpak and show where to install", icon: Icons.notepad, type: "info", exec: null },
                { name: "pacman <package>", description: "Install package directly with pacman (sudo)", icon: Icons.notepad, type: "info", exec: null },
                { name: "yay <package>", description: "Install package from AUR with yay", icon: Icons.notepad, type: "info", exec: null },
                { name: "flatpak install <package>", description: "Install package from Flathub", icon: Icons.notepad, type: "info", exec: null },
                { name: "remove <package>", description: "Uninstall package with pacman", icon: Icons.notepad, type: "info", exec: null },
                { name: "update", description: "Update system (pacman -Syu)", icon: Icons.notepad, type: "info", exec: null },
                { name: "timer <duration>", description: "Create a timer (e.g. timer 5m, timer pizza 10m, timer 30s)", icon: Icons.notepad, type: "info", exec: null },
                { name: "alarm <time>", description: "Create an alarm (e.g. alarm 8:00, alarm 7:30 mon-fri, alarm 14:30 lunch)", icon: Icons.notepad, type: "info", exec: null },
                { name: "weather", description: "Check weather (e.g. weather, weather Madrid)", icon: Icons.notepad, type: "info", exec: null },
                { name: "Calculator", description: "Type an expression (e.g. 2+2, 5*3, (10+5)/3)", icon: Icons.notepad, type: "info", exec: null },
                { name: "lock", description: "Lock the screen", icon: Icons.notepad, type: "info", exec: null },
                { name: "suspend", description: "Suspend the system", icon: Icons.notepad, type: "info", exec: null },
                { name: "poweroff", description: "Shutdown the system", icon: Icons.notepad, type: "info", exec: null },
                { name: "reboot", description: "Reboot the system", icon: Icons.notepad, type: "info", exec: null },
                                { name: "Search files", description: "Type any filename (min 2 chars)", icon: Icons.notepad, type: "info", exec: null },
                { name: "Quick Look", description: "Preview files inside Hax using up/down arrows — images, text, binaries. Esc to close", icon: Icons.notepad, type: "info", exec: null },
                { name: "Web search", description: "Any non-command text searches Google", icon: Icons.notepad, type: "info", exec: null },
                { name: "g / glo / glosario", description: "Open dictionary/glossary — type a word and press Enter", icon: Icons.notepad, type: "info", exec: null },
                { name: "history / clip / clipboard", description: "Show full clipboard history", icon: Icons.notepad, type: "info", exec: null },
                { name: "/", description: "Open integrated terminal (fish) inside Hax — fully functional (vim, htop, sudo...)", icon: Icons.notepad, type: "info", exec: null },
                { name: "/stats", description: "Open system monitor (CPU, RAM, disk, temp)", icon: Icons.notepad, type: "info", exec: null },
                { name: "d / dev / debug", description: "Open developer debug mode with on-screen metrics", icon: Icons.notepad, type: "info", exec: null },
                { name: "config", description: "Open Hax configuration panel: OCR, colors, custom quick actions", icon: Icons.notepad, type: "info", exec: null },
                { name: "live / livetext / ocr / status", description: "Live Text (OCR) — search text INSIDE images", icon: Icons.notepad, type: "info", exec: null },
                { name: "reindex", description: "Re-index all images with OCR (Tesseract)", icon: Icons.notepad, type: "info", exec: null },
                { name: "show", description: "Show all open windows grouped by workspace", icon: Icons.notepad, type: "info", exec: null },
                { name: "help / ?", description: "Show this help", icon: Icons.notepad, type: "info", exec: null }
            ];
            results = newResults;
            return;
        }

        // Show windows
        if (query === "show") {
            if (!showWindowGrid) {
                showWindowGrid = true;
                selectedIndex = 0;
                windowGridSelectedIndex = 0;
                Qt.callLater(function() { buildWindowGrid(); });
            }
            results = [];
            return;
        } else if (query !== "show" && showWindowGrid) {
            showWindowGrid = false;
        }

        // System monitor
        var statsMatch = query.match(/^(stats|monitor|sistema)$/i);
        if (statsMatch) {
            newResults.push({
                name: showMonitor ? "Close system monitor" : "System Monitor",
                description: showMonitor
                    ? "Click to close live monitor"
                    : "Show CPU, RAM, disk and temperature in real-time",
                icon: Icons.notepad, type: "info",
                exec: function() { toggleMonitor(); }
            });
            results = newResults;
            return;
        }

        // Timers
        var timerMatch = query.match(/^timer(?:\s+(.+))?$/i);
        if (timerMatch) {
            var timerArgs = (timerMatch[1] || "").trim();
            if (!timerArgs) {
                if (activeTimers.length === 0) {
                    newResults.push({ name: "No active timers", description: "Example: timer 5m, timer pizza 10m, timer 30s", icon: Icons.notepad, type: "info", exec: null });
                } else {
                    for (var ti = 0; ti < activeTimers.length; ti++) {
                        var t = activeTimers[ti];
                        var remain = Math.max(0, Math.floor((t.endTime - Date.now()) / 1000));
                        (function(tmr) {
                            newResults.push({
                                name: tmr.label + " — " + _fmtDur(remain) + " remaining",
                                description: "Ends ~" + new Date(tmr.endTime).toLocaleTimeString(),
                                icon: Icons.notepad, type: "info",
                                exec: null
                            });
                            newResults.push({
                                name: "Cancel \"" + tmr.label + "\"",
                                description: "Stop this timer",
                                icon: Icons.notepad, type: "info",
                                exec: function() { cancelTimer(tmr.id);  spotlight.closeSpotlight(); }
                            });
                        })(t);
                    }
                }
                newResults.push({ name: "Cancel all timers", description: "", icon: Icons.notepad, type: "info", exec: function() { clearAllTimers();  spotlight.closeSpotlight(); } });
                results = newResults;
                return;
            }

            if (/^(cancel|clear|stop)\s*$/i.test(timerArgs)) {
                newResults.push({ name: "Cancel all timers", description: "Stop all active timers", icon: Icons.notepad, type: "info", exec: function() { clearAllTimers();  spotlight.closeSpotlight(); } });
                results = newResults;
                return;
            }

            var cancelMatch = timerArgs.match(/^cancel\s+(.+)$/i);
            if (cancelMatch) {
                var target = cancelMatch[1].trim();
                var found = false;
                for (var ti2 = 0; ti2 < activeTimers.length; ti2++) {
                    if (activeTimers[ti2].label.toLowerCase() === target.toLowerCase()) {
                        (function(tmr2) {
                            newResults.push({ name: "Cancel \"" + tmr2.label + "\"", description: "Stop this timer", icon: Icons.notepad, type: "info", exec: function() { cancelTimer(tmr2.id);  spotlight.closeSpotlight(); } });
                        })(activeTimers[ti2]);
                        found = true;
                    }
                }
                if (!found) {
                    var num = parseInt(target);
                    if (!isNaN(num)) {
                        for (var ti3 = 0; ti3 < activeTimers.length; ti3++) {
                            if (activeTimers[ti3].id === num) {
                                (function(tmr3) {
                                    newResults.push({ name: "Cancel \"" + tmr3.label + "\"", description: "Stop this timer", icon: Icons.notepad, type: "info", exec: function() { cancelTimer(tmr3.id);  spotlight.closeSpotlight(); } });
                                })(activeTimers[ti3]);
                                found = true;
                                break;
                            }
                        }
                    }
                }
                if (!found) {
                    newResults.push({ name: "Timer not found", description: "No timer with that name or ID", icon: Icons.notepad, type: "info", exec: null });
                }
                results = newResults;
                return;
            }

            var durMatch = timerArgs.match(/(\d+)\s*([smh])\s*(.*)$/i) || timerArgs.match(/(\d+):(\d{1,2})\s*(.*)$/);
            if (durMatch) {
                var label = "";
                var seconds = 0;
                if (durMatch[2] === undefined) {
                    seconds = parseInt(durMatch[1]) * 60 + parseInt(durMatch[2]);
                    label = (durMatch[3] || "").trim();
                } else {
                    var unit = durMatch[2].toLowerCase();
                    var val = parseInt(durMatch[1]);
                    if (unit === 's') seconds = val;
                    else if (unit === 'm') seconds = val * 60;
                    else if (unit === 'h') seconds = val * 3600;
                    label = (durMatch[3] || "").trim();
                }
                if (!label) {
                    var beforeDur = timerArgs.replace(durMatch[0], '').trim();
                    if (beforeDur) label = beforeDur;
                }
                if (seconds > 0 && seconds <= 86400) {
                    var timerLabel = label || ("Timer " + _timerNextId);
                    (function(lbl, sec) {
                        newResults.push({
                            name: "Start timer \"" + lbl + "\" — " + _fmtDur(sec),
                            description: "Timer of " + (sec >= 3600 ? (sec/3600).toFixed(1) + "h" : sec >= 60 ? (sec/60) + "m" : sec + "s"),
                            icon: Icons.notepad, type: "info",
                            exec: function() { startTimer(lbl, sec);  spotlight.closeSpotlight(); }
                        });
                    })(timerLabel, seconds);
                } else {
                    newResults.push({ name: "Invalid duration", description: "Max 24 hours. Example: timer 5m, timer 30s, timer 2h", icon: Icons.notepad, type: "info", exec: null });
                }
                results = newResults;
                return;
            }

            newResults.push({ name: "Timer usage", description: "timer 5m · timer pizza 10m · timer 30s break · timer cancel · timer clear", icon: Icons.notepad, type: "info", exec: null });
            results = newResults;
            return;
        }

        // Alarms
        var alarmMatch = query.match(/^alarm(?:[ea]s)?(?:\s+(.+))?$/i);
        if (alarmMatch) {
            var alarmArgs = (alarmMatch[1] || "").trim();
            if (!alarmArgs) {
                if (activeAlarms.length === 0) {
                    newResults.push({ name: "No alarms", description: "Example: alarm 7:30, alarm 8:00 wakeup, alarm 14:30 lunch mon tue wed", icon: Icons.notepad, type: "info", exec: null });
                } else {
                    for (var ai = 0; ai < activeAlarms.length; ai++) {
                        var al = activeAlarms[ai];
                        var daysStr = al.days.length > 0 ? al.days.map(function(d) { return ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][d]; }).join(" ") : "Every day";
                        var timeStr = (al.hour < 10 ? "0" : "") + al.hour + ":" + (al.minute < 10 ? "0" : "") + al.minute;
                        (function(alm) {
                            newResults.push({
                                name: (alm.enabled ? "[ALARM]" : "[OFF]") + " " + alm.label + " — " + timeStr + " " + daysStr,
                                description: alm.enabled ? "Active · Click to disable" : "Inactive · Click to enable",
                                icon: Icons.notepad, type: "info",
                                exec: function() { alm.enabled = !alm.enabled;  spotlight.closeSpotlight(); }
                            });
                            newResults.push({
                                name: "Delete alarm \"" + alm.label + "\"",
                                description: "Permanently remove this alarm",
                                icon: Icons.notepad, type: "info",
                                exec: function() { cancelAlarm(alm.id);  spotlight.closeSpotlight(); }
                            });
                        })(al);
                    }
                }
                newResults.push({ name: "Delete all alarms", description: "", icon: Icons.notepad, type: "info", exec: function() { clearAllAlarms();  spotlight.closeSpotlight(); } });
                results = newResults;
                return;
            }

            if (/^(clear|cancel)\s*$/i.test(alarmArgs)) {
                newResults.push({ name: "Delete all alarms", description: "Remove all alarms", icon: Icons.notepad, type: "info", exec: function() { clearAllAlarms();  spotlight.closeSpotlight(); } });
                results = newResults;
                return;
            }

            var timeMatch = alarmArgs.match(/^(\d{1,2}):(\d{2})\s*(.*)$/);
            if (timeMatch) {
                var hour = parseInt(timeMatch[1]);
                var minute = parseInt(timeMatch[2]);
                var rest = (timeMatch[3] || "").trim();
                if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
                    var days = [];
                    var dayParse = rest.match(/([L M X J V S D]+)$/i);
                    if (dayParse) {
                        var dayStr = dayParse[1].toUpperCase();
                        var dayMap = { 'L': 1, 'M': 2, 'X': 3, 'J': 4, 'V': 5, 'S': 6, 'D': 0 };
                        for (var dk = 0; dk < dayStr.length; dk++) {
                            var dval = dayMap[dayStr[dk]];
                            if (dval !== undefined && days.indexOf(dval) < 0) days.push(dval);
                        }
                        rest = rest.substring(0, rest.length - dayParse[0].length).trim();
                    }
                    var alarmLabel = rest || ("Alarm " + _alarmNextId);
                    var daysLabel = days.length > 0 ? days.map(function(d) { return ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][d]; }).join(" ") : "Every day";
                    var timeLabel = (hour < 10 ? "0" : "") + hour + ":" + (minute < 10 ? "0" : "") + minute;
                    (function(alLabel, alHour, alMin, alDays) {
                        newResults.push({
                            name: "Create alarm \"" + alLabel + "\" — " + timeLabel + " " + daysLabel,
                            description: "Click to confirm",
                            icon: Icons.notepad, type: "info",
                            exec: function() { setAlarm(alLabel, alHour, alMin, alDays);  spotlight.closeSpotlight(); }
                        });
                    })(alarmLabel, hour, minute, days);
                } else {
                    newResults.push({ name: "Invalid time", description: "Use HH:MM format (e.g. alarm 7:30 wakeup)", icon: Icons.notepad, type: "info", exec: null });
                }
                results = newResults;
                return;
            }

            newResults.push({ name: "Alarm usage", description: "alarm 8:00 · alarm 7:30 wakeup · alarm 14:30 lunch mon tue wed · alarm clear", icon: Icons.notepad, type: "info", exec: null });
            results = newResults;
            return;
        }

        // Packages
        var pkgMatch = query.match(/^(install|pacman|yay|flatpak|remove|update)\b\s*(.*)$/i);
        if (pkgMatch) {
            var pkgCmd = pkgMatch[1].toLowerCase();
            var pkgArgs = (pkgMatch[2] || "").trim();

            if (pkgCmd === "update") {
                newResults.push({
                    name: "Update system",
                    description: "pacman -Syu — update all packages",
                    icon: Icons.notepad, type: "info",
                    exec: function() {
                        runCmd('echo "F200607" | sudo -S rm -f /var/lib/pacman/db.lck 2>/dev/null; echo "F200607" | sudo -S pacman -Syu --noconfirm --overwrite "*"');
                    }
                });
                results = newResults;
                return;
            }

            if (pkgCmd === "remove") {
                if (!pkgArgs) {
                    newResults.push({ name: "Specify package to remove", description: "Example: remove firefox", icon: Icons.notepad, type: "info", exec: null });
                } else {
                    var rmPkg = pkgArgs;
                    newResults.push({
                        name: "Remove \"" + rmPkg + "\"",
                        description: "sudo pacman -R " + rmPkg,
                        icon: Icons.notepad, type: "info",
                        exec: function() { runCmd('echo "F200607" | sudo -S pacman -R --noconfirm ' + rmPkg); }
                    });
                }
                results = newResults;
                return;
            }

            if (!pkgArgs) {
                newResults.push({ name: "Specify a package", description: "Example: install firefox, pacman vim, yay chrome, flatpak spotify, remove vim, update", icon: Icons.notepad, type: "info", exec: null });
                results = newResults;
                return;
            }

            if (pkgCmd === "pacman") {
                var pmPkg = pkgArgs;
                newResults.push({
                    name: "Install \"" + pmPkg + "\" (pacman)",
                    description: "sudo pacman -S " + pmPkg,
                    icon: Icons.notepad, type: "info",
                    exec: function() { runCmd('echo "F200607" | sudo -S pacman -S --noconfirm ' + pmPkg); }
                });
                results = newResults;
                return;
            }

            if (pkgCmd === "yay") {
                var yyPkg = pkgArgs;
                newResults.push({
                    name: "Install \"" + yyPkg + "\" (AUR/yay)",
                    description: "yay -S " + yyPkg,
                    icon: Icons.notepad, type: "info",
                    exec: function() { runCmd('echo "F200607" | sudo -S yay -S --noconfirm ' + yyPkg); }
                });
                results = newResults;
                return;
            }

            if (pkgCmd === "flatpak") {
                var fpParts = pkgArgs.match(/^(install|remove|search)\s+(.+)$/i);
                if (fpParts) {
                    var fpAction = fpParts[1].toLowerCase();
                    var fpName2 = fpParts[2].trim();
                    if (fpAction === "install") {
                        var fpInstPkg = fpName2;
                        newResults.push({
                            name: "Install \"" + fpInstPkg + "\" (flatpak)",
                            description: "flatpak install " + fpInstPkg,
                            icon: Icons.notepad, type: "info",
                            exec: function() { runCmd('flatpak install -y flathub ' + fpInstPkg); }
                        });
                        results = newResults;
                        return;
                    } else if (fpAction === "remove") {
                        var fpRmPkg = fpName2;
                        newResults.push({
                            name: "Remove \"" + fpRmPkg + "\" (flatpak)",
                            description: "flatpak uninstall " + fpRmPkg,
                            icon: Icons.notepad, type: "info",
                            exec: function() { runCmd('flatpak uninstall -y ' + fpRmPkg); }
                        });
                        results = newResults;
                        return;
                    }
                }
                var fpQuery = pkgArgs;
                newResults.push({
                    name: "Search \"" + fpQuery + "\" on Flathub...",
                    description: "Press Enter to search flatpak",
                    icon: Icons.notepad, type: "info",
                    exec: function() { _searchFlatpak(fpQuery, gen); }
                });
                results = newResults;
                return;
            }

            if (pkgCmd === "install") {
                var instPkg = pkgArgs;
                if (!instPkg) {
                    newResults.push({ name: "Specify a package", description: "Example: install firefox, install vim, install spotify", icon: Icons.notepad, type: "info", exec: null });
                    results = newResults;
                } else if (instPkg === _lastSearchQuery) {
                    return;
                } else {
                    _lastSearchQuery = instPkg;
                    newResults.push({
                        name: "Searching \"" + instPkg + "\" in pacman, AUR and flatpak...",
                        description: "Waiting for package managers...",
                        icon: Icons.notepad, type: "info",
                        exec: null
                    });
                    results = newResults;
                    _searchPackages(instPkg, gen);
                }
                return;
            }
        }

        // Weather
        var weatherMatch = query.match(/^(weather|tiempo|clima|w(?:eather)?)\b/i);
        if (weatherMatch) {
            if (weatherSearch) { try { weatherSearch.abort(); } catch(e) {} weatherSearch = null; }
            const loc = query.substring(weatherMatch[0].length).trim();
            newResults.push({
                name: "Fetching weather" + (loc ? " for " + loc : "") + "...",
                description: "Retrieving data...",
                icon: Icons.globe,
                type: "info",
                exec: null
            });
            results = newResults;
            startWeatherSearch(loc, gen);
            return;
        }

        // Clipboard history
        var histMatch = query.match(/^(historial|history|clip|clipboard|portapapeles)$/i);
        if (histMatch) {
            var histItems = searchHistory("");
            for (var hi = 0; hi < histItems.length; hi++) {
                var hItem = histItems[hi];
                newResults.push({
                    name: hItem.text,
                    description: "Copied " + hItem.count + " time" + (hItem.count !== 1 ? "s" : ""),
                    icon: Icons.notepad,
                    type: "history",
                    historyText: hItem.text,
                    exec: null
                });
            }
            if (newResults.length === 0) {
                newResults.push({
                    name: "Clipboard history is empty",
                    description: "Copy something with Enter or Ctrl+C and it will appear here",
                    icon: Icons.notepad,
                    type: "info",
                    exec: null
                });
            }
            results = newResults;
            return;
        }

        // Search history matches
        if (query.length >= 2 && _historyItems.length > 0) {
            var histMatches = searchHistory(query, 3);
            for (var hi2 = 0; hi2 < histMatches.length; hi2++) {
                var hItem2 = histMatches[hi2];
                newResults.push({
                    name: hItem2.text,
                    description: "History — " + hItem2.count + " time" + (hItem2.count !== 1 ? "s" : ""),
                    icon: Icons.notepad,
                    type: "history",
                    historyText: hItem2.text,
                    exec: null
                });
            }
        }

        // Apps
        const appResults = AppSearch.fuzzyQuery(query);
        var seenIds = {};
        for (const a of appResults.slice(0, 6)) {
            if (seenIds[a.id]) continue;
            seenIds[a.id] = true;
            newResults.push({
                name: a.name,
                description: a.comment || a.id || "",
                icon: a.icon,
                type: "app",
                exec: () => {
                    UsageTracker.recordUsage(a.id);
                    a.execute();
                     spotlight.closeSpotlight();
                }
            });
        }

        // Web search
        newResults.push({
            name: "Search \"" + searchText + "\" on the web",
            description: "Open in Zen Browser",
            icon: Icons.globe,
            type: "web",
            exec: () => {
                Qt.openUrlExternally(`https://www.google.com/search?q=${encodeURIComponent(searchText)}`);
                 spotlight.closeSpotlight();
            }
        });

        // Debug mode
        if (query === "d" || query === "dev" || query === "debug") {
            newResults.unshift({
                name: "Debug mode",
                description: "Show errors, timings and resource usage",
                icon: Icons.notepad,
                type: "debug",
                exec: function() {
                    spotlight.showDebug = true;
                }
            });
        }

        // Config
        if (query === "config") {
            newResults.unshift({
                name: "Configure Hax",
                description: "Colors, OCR, custom shortcuts and more",
                icon: Icons.notepad,
                type: "config",
                exec: function() {
                    spotlight.showPlugins = false;
                    spotlight.showConfig = true;
                }
            });
        }

        // Plugins
        if (query === "plugins") {
            newResults.unshift({
                name: "Plugins",
                description: "Manage Hax plugins (scripts and QML)",
                icon: Icons.notepad,
                type: "plugins",
                exec: function() {
                    spotlight.searchText = "";
                    spotlight.showConfig = false;
                    spotlight.showPlugins = true;
                }
            });
        }

        // Glossary
        if (query === "g" || query === "glo" || query === "glosario") {
            newResults.unshift({
                name: "Glossary / Dictionary",
                description: "Type a word and press Enter to see its definition",
                icon: Icons.notepad,
                type: "dict",
                exec: function() { spotlight.enterDictMode(); }
            });
        }

        // Live Text / OCR
        if (query === "live" || query === "livetext" || query === "estado" || query === "status" || query === "ocr") {
            var ltDesc = spotlight.liveTextIndexing
                ? "Indexing images in background..."
                : (spotlight.liveTextIndexed + " images indexed — search for text inside your photos/screenshots");
            newResults.unshift({
                name: "Live Text (OCR)",
                description: ltDesc,
                icon: Icons.notepad,
                type: "info",
                exec: function() {
                    // spotlight.startOcrIndexing(); // OCR disabled
                }
            });
        }
        if (query === "reindexar" || query === "reindex") {
            newResults.unshift({
                name: "Re-index images (Live Text)",
                description: "Re-read text from all images with OCR (Tesseract)",
                icon: Icons.notepad,
                type: "info",
                exec: function() {
                    // spotlight.startOcrIndexing(); // OCR disabled
                }
            });
        }

        // Plugins query
        if (query.length >= 2) {
            try {
                var pluginRes = spotlight.pluginManager.queryAll(query);
                if (pluginRes && pluginRes.length > 0) {
                    for (var pi = 0; pi < pluginRes.length; pi++) {
                        var pr = pluginRes[pi];
                        var pIcon = pr._pluginIcon || "plugin";
                        if (!pr.name) continue;
                        var _query = query;
                        newResults.push({
                            name: pIcon + " " + pr.name + " (" + pr._pluginName + ")",
                            description: pr.description || "Plugin result",
                            icon: Icons.notepad,
                            type: "plugin",
                            _pluginId: pr._pluginId,
                            _actionId: pr.actionId,
                            exec: (function(origExec, pid, aid, aData, searchQuery) {
                                return function() {
                                    if (typeof origExec === "function") {
                                        try { origExec(); } catch(e) {}
                                    } else {
                                        var ctx = aData || searchQuery || "";
                                        spotlight.pluginManager.executeAction(pid, aid, ctx);
                                    }
                                };
                            })(pr.exec, pr._pluginId, pr.actionId, pr.actionData, _query)
                        });
                    }
                }
            } catch(e) {
                spotlight.debugLogError("plugins", e);
            }
        }

        // Dynamic plugin results
        if (spotlight._dynamicResults && spotlight._dynamicResults.length > 0) {
            for (var dri = 0; dri < spotlight._dynamicResults.length; dri++) {
                newResults.push(spotlight._dynamicResults[dri]);
            }
        }

        results = newResults;

        // File search (async)
        if (query.length >= 2) {
            startFileSearch(query);
        }
    }

    // --------------------------------------------------------------
    // Helper functions
    // --------------------------------------------------------------

    function safeEval(expr) {
        if (!/^[\d+\-*/().\s]+$/.test(expr)) return null;
        try {
            return calcParens(expr.replace(/\s/g, ""));
        } catch(e) { return null; }
    }

    function calcSimple(e) {
        if (e.length === 0) return null;
        var idx;
        idx = e.indexOf("*");
        if (idx > 0) {
            var l = calcSimple(e.substring(0, idx));
            var r = calcSimple(e.substring(idx + 1));
            if (l === null || r === null) return null;
            return l * r;
        }
        idx = e.indexOf("/");
        if (idx > 0) {
            l = calcSimple(e.substring(0, idx));
            r = calcSimple(e.substring(idx + 1));
            if (l === null || r === null || r === 0) return null;
            return l / r;
        }
        idx = e.indexOf("+");
        if (idx > 0) {
            l = calcSimple(e.substring(0, idx));
            r = calcSimple(e.substring(idx + 1));
            if (l === null || r === null) return null;
            return l + r;
        }
        if (e.charAt(0) === "-") {
            var rest = calcSimple(e.substring(1));
            return rest === null ? null : -rest;
        }
        idx = e.lastIndexOf("-");
        if (idx > 0) {
            l = calcSimple(e.substring(0, idx));
            r = calcSimple(e.substring(idx + 1));
            if (l === null || r === null) return null;
            return l - r;
        }
        var num = parseFloat(e);
        return isNaN(num) ? null : num;
    }

    function calcParens(e) {
        var start = e.indexOf("(");
        while (start !== -1) {
            var depth = 1;
            var end = start + 1;
            while (end < e.length && depth > 0) {
                if (e.charAt(end) === "(") depth++;
                else if (e.charAt(end) === ")") depth--;
                end++;
            }
            if (depth !== 0) return null;
            var inner = calcParens(e.substring(start + 1, end - 1));
            if (inner === null) return null;
            e = e.substring(0, start) + inner + e.substring(end);
            start = e.indexOf("(");
        }
        return calcSimple(e);
    }

    function executeSelected() {
        if (selectedIndex >= 0 && selectedIndex < results.length) {
            executeItem(results[selectedIndex]);
        }
    }

    function executeItem(item) {
        if (item && item.exec) {
            try {
                item.exec();
            } catch (e) {
                spotlight.debugLogError("executeItem", e);
            }
        }
    }

    function _previewSelectedIfFile() {
        if (selectedIndex >= 0 && selectedIndex < results.length) {
            var sel = results[selectedIndex];
            if (sel && sel.type === "file") {
                var p = sel.description || "";
                if (p && p !== spotlight.previewPath) openPreview(sel);
            }
        }
    }

    // --------------------------------------------------------------
    // OCR (Live Text)
    // --------------------------------------------------------------

    function ocrFolders() {
        var home = Quickshell.env("HOME") || "/home/fabio";
        var pics = Quickshell.env("XDG_PICTURES_DIR") || (home + "/Pictures");
        var shots = pics + "/Screenshots";
        return [
            { d: home + "/Documentos", depth: 5 },
            { d: home + "/Descargas",   depth: 5 },
            { d: home + "/Escritorio",  depth: 5 },
            { d: home,                  depth: 2 },
            { d: pics,                  depth: 6 },
            { d: shots,                 depth: 2 }
        ];
    }

    function startOcrIndexing() { return; }
    // (disabled)
    function _startOcrIndexing_disabled() {
        var folders = ocrFolders();
        spotlight.liveTextIndexing = true;
        spotlight.liveTextPending = folders.length;
        for (var i = 0; i < folders.length; i++) {
            (function(f) {
                var pr = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
                pr.command = ["bash", ocrScript, "index", f.d, String(f.depth)];
                pr.onExited.connect(function() {
                    try { pr.destroy(); } catch (e) {}
                    spotlight.liveTextPending = spotlight.liveTextPending - 1;
                    if (spotlight.liveTextPending <= 0) {
                        spotlight.liveTextIndexing = false;
                        // spotlight.refreshLiveTextStatus(); // OCR disabled
                    }
                });
                pr.running = true;
            })(folders[i]);
        }
    }

    function refreshLiveTextStatus() { return; }
    // (disabled)
    function _refreshLiveTextStatus_disabled() {
        var pr = Qt.createQmlObject('import Quickshell.Io; Process { stdout: StdioCollector {} }', spotlight);
        pr.command = ["bash", ocrScript, "status"];
        pr.onExited.connect(function() {
            var t = (pr.stdout ? pr.stdout.text : "").trim();
            var n = parseInt(t, 10);
            spotlight.liveTextIndexed = isNaN(n) ? 0 : n;
            try { pr.destroy(); } catch (e) {}
        });
        pr.running = true;
    }

    function fetchOcrForPreview(p) { return; }
    // (disabled, calls grim/slurp)
    function _fetchOcrForPreview_disabled(p) {
        var pr = Qt.createQmlObject('import Quickshell.Io; Process { stdout: StdioCollector {} }', spotlight);
        pr.command = ["bash", ocrScript, "get", p];
        pr.onExited.connect(function() {
            var t = pr.stdout ? pr.stdout.text.trim() : "";
            spotlight.previewOcrText = (t.length > 0) ? t : "(no text detected in image)";
            try { pr.destroy(); } catch (e) {}
        });
        pr.running = true;
    }

    // --------------------------------------------------------------
    // Dictionary
    // --------------------------------------------------------------

    function enterDictMode() {
        spotlight.dictMode = true;
        spotlight.dictWord = "";
        spotlight.dictResultText = "";
        spotlight.dictError = "";
        spotlight.dictLoading = false;
        spotlight.dictLastLen = 0;
        spotlight.dictSeq = 0;
        spotlight.searchText = "";
        if (searchInput) { searchInput.text = ""; searchInput.forceActiveFocus(); }
        spotlight.updateResults();
    }

    function exitDictMode() {
        spotlight.dictSeq = 0;
        spotlight.dictMode = false;
        spotlight.dictWord = "";
        spotlight.dictResultText = "";
        spotlight.dictError = "";
        spotlight.dictLoading = false;
        spotlight.searchText = "";
        if (searchInput) { searchInput.text = ""; searchInput.forceActiveFocus(); }
        spotlight.updateResults();
    }

    function startDictSearch(word) {
        var seq = ++spotlight.dictSeq;
        if (word.length < 2) {
            spotlight.dictLoading = false;
            spotlight.dictResultText = "";
            spotlight.dictError = "";
            return;
        }
        spotlight.dictLoading = true;
        spotlight.dictError = "";
        var url = "https://es.wikipedia.org/api/rest_v1/page/summary/" + encodeURIComponent(word);
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (seq !== spotlight.dictSeq) return;
            spotlight.dictLoading = false;
            if (xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText);
                    var extract = (data.extract || "").trim();
                    var title = data.title || word;
                    if (extract.length > 0) {
                        spotlight.dictResultText = "Wikipedia (\"" + title + "\"):\n" + extract;
                        spotlight.dictError = "";
                    } else {
                        spotlight.dictResultText = "";
                        spotlight.dictError = "Wikipedia has no summary for \"" + word + "\".";
                    }
                } catch (e) {
                    spotlight.dictResultText = "";
                    spotlight.dictError = "Error processing response.";
                }
            } else if (xhr.status === 404) {
                spotlight.dictResultText = "";
                spotlight.dictError = "Word \"" + word + "\" not found on Wikipedia.";
            } else {
                spotlight.dictResultText = "";
                spotlight.dictError = "Connection error (" + xhr.status + ").";
            }
        };
        xhr.send();
    }

    function copyOcrText() {
        if (!spotlight.previewOcrText) return;
        var p = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
        p.command = ["wl-copy", spotlight.previewOcrText];
        p.onExited.connect(function() { try { p.destroy(); } catch (e) {} });
        p.running = true;
    }

    // --------------------------------------------------------------
    // Quick Look
    // --------------------------------------------------------------

    function openPreview(item) {
        if (!item || item.type !== "file") return;
        var path = item.description || "";
        if (!path) return;

        spotlight.previewPath = path;
        spotlight.previewName = item.name || (path.split("/").pop());
        spotlight.previewType = "text";
        spotlight.previewText = "Loading…";
        spotlight.previewImageSrc = "";
        spotlight.previewOcrText = "";
        spotlight.showPreview = true;

        var safePath = path.replace(/'/g, "'\\''");

        if (path.match(/\.(png|jpe?g|gif|bmp|webp|svg)$/i)) {
            spotlight.previewType = "image";
            spotlight.previewImageSrc = "file://" + path;
            spotlight.previewText = "";
            spotlight.previewOcrText = "Reading text from image…";
            spotlight.fetchOcrForPreview(path);
            return;
        }

        var proc;
        try {
            proc = Qt.createQmlObject(
                'import Quickshell.Io; Process { stdout: SplitParser {} }',
                spotlight
            );
        } catch (e) {
            spotlight.debugLogError("openPreview", e);
            return;
        }
        var lines = [];
        proc.stdout.onRead.connect(function(d) { lines.push(d); });
        proc.onExited.connect(function() {
            var joined = lines.join("");
            if (joined.indexOf("__BINARY__") !== -1) {
                spotlight.previewType = "binary";
                spotlight.previewText = "Binary file — cannot preview text content.";
            } else {
                spotlight.previewType = "text";
                spotlight.previewText = joined;
            }
            proc.destroy();
        });
        proc.command = ["bash", "-c",
            "if file --mime-encoding -- '" + safePath + "' 2>/dev/null | grep -qi binary; then echo '__BINARY__'; else cat -- '" + safePath + "' 2>/dev/null | head -c 200000; fi"];
        proc.running = true;
    }

    function copyResult(item) {
        if (!item) return;
        var p;
        try {
            p = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
        } catch (e) {
            spotlight.debugLogError("copyResult", e);
            return;
        }
        var copyText = "";
        if (item.type === "file") {
            var path = item.description || "";
            copyText = path;
            if (path.match(/\.(png|jpg|jpeg|gif|bmp|webp|svg)$/i)) {
                p.command = ["bash", "-c", "wl-copy < " + path.replace(/'/g, "'\\''")];
            } else {
                p.command = ["wl-copy", path];
            }
        } else if (item.type === "calc") {
            var parts = (item.name || "").split(" = ");
            copyText = parts.length > 1 ? parts[1] : parts[0];
            p.command = ["wl-copy", copyText];
        } else if (item.type === "history") {
            copyText = item.historyText || item.name || "";
            p.command = ["wl-copy", copyText];
        } else {
            copyText = item.name || "";
            p.command = ["wl-copy", copyText];
        }
        p.onExited.connect(() => p.destroy());
        p.running = true;
        saveToHistory(copyText, item.type || "text");
        _lastClipboard = copyText;
        _copyFeedback = item.name || copyText || "";
        _copyFeedbackTimer.restart();
    }

    readonly property string _revealScript: Quickshell.env("HOME") + "/.local/bin/hax-reveal.sh"
    function openFileInDolphin(item) {
        if (!item || item.type !== "file") return;
        var path = item.description || "";
        if (!path) return;
        bash("'" + _revealScript + "' '" + path.replace(/'/g, "'\\''") + "' &");
         spotlight.closeSpotlight();
    }

    property string _copyFeedback: ""

    property bool showPreview: false
    property string previewPath: ""
    property string previewName: ""
    property string previewType: ""
    property string previewText: ""
    property string previewImageSrc: ""

    // --------------------------------------------------------------
    // Smart clipboard history
    // --------------------------------------------------------------

    property var _historyItems: []
    property var _historyLoaded: false
    property string _lastClipboard: ""
    property var _clipWatcherProc: null

    function loadHistory() {
        if (_historyLoaded) return;
        var path = Quickshell.env("HOME") + "/.local/share/hax/history.json";
        var proc = Qt.createQmlObject(
            'import Quickshell.Io; Process { stdout: SplitParser {} }',
            spotlight
        );
        proc.command = ["bash", "-c", "cat " + path + " 2>/dev/null || echo '[]'"];
        var lines = [];
        proc.stdout.onRead.connect(function(data) {
            lines.push(data);
        });
        proc.onExited.connect(function() {
            try {
                _historyItems = JSON.parse(lines.join("")) || [];
            } catch(e) {
                _historyItems = [];
            }
            _historyLoaded = true;
            proc.destroy();
        });
        proc.running = true;
    }

    function saveToHistory(text, type) {
        if (!text || text.length === 0) return;
        var idx = -1;
        for (var i = 0; i < _historyItems.length; i++) {
            if (_historyItems[i].text === text) {
                idx = i;
                break;
            }
        }
        var now = new Date().toISOString();
        if (idx >= 0) {
            _historyItems[idx].count = (_historyItems[idx].count || 1) + 1;
            _historyItems[idx].lastUsed = now;
        } else {
            _historyItems.unshift({
                text: text,
                type: type || "text",
                count: 1,
                lastUsed: now
            });
            if (_historyItems.length > 50) _historyItems.pop();
        }
        _historyItems.sort(function(a, b) {
            if (a.count !== b.count) return b.count - a.count;
            return b.lastUsed.localeCompare(a.lastUsed);
        });
        _writeHistory();
    }

    function _writeHistory() {
        var json = JSON.stringify(_historyItems);
        var path = Quickshell.env("HOME") + "/.local/share/hax/history.json";
        var proc = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
        var safeJson = json.replace(/'/g, "'\\''");
        var safePath = path.replace(/'/g, "'\\''");
        proc.command = ["bash", "-c", "mkdir -p $(dirname '" + safePath + "') && printf '%s' '" + safeJson + "' > '" + safePath + "'"];
        proc.onExited.connect(function() {
            proc.destroy();
        });
        proc.running = true;
    }

    function removeFromHistory(text) {
        if (!text) return;
        for (var i = 0; i < _historyItems.length; i++) {
            if (_historyItems[i].text === text) {
                _historyItems.splice(i, 1);
                break;
            }
        }
        _writeHistory();
        selectedIndex = 0;
        updateResults();
    }

    function _readClipboard(cb) {
        var proc = Qt.createQmlObject('import Quickshell.Io; Process { stdout: SplitParser {} }', spotlight);
        var lines = [];
        proc.stdout.onRead.connect(function(d) { lines.push(d); });
        proc.onExited.connect(function() {
            var content = lines.join("\n").trim();
            proc.destroy();
            if (cb) cb(content);
        });
        proc.command = ["wl-paste", "-n"];
        proc.running = true;
    }

    function startClipWatcher() {
        if (_clipWatcherProc) return;
        _readClipboard(function(content) {
            if (content.length > 0 && content.length < 100000) {
                _lastClipboard = content;
                saveToHistory(content, "text");
            }
        });
        var proc = Qt.createQmlObject(
            'import Quickshell.Io; Process { stdout: SplitParser {} }',
            spotlight
        );
        proc.command = ["bash", "-c",
            "o=''; while true; do c=$(wl-paste -n 2>/dev/null); " +
            "if [ -n \"$c\" ] && [ \"$c\" != \"$o\" ]; then echo \"$c\"; o=\"$c\"; fi; sleep 1; done"
        ];
        proc.stdout.onRead.connect(function(content) {
            content = content.trim();
            if (content.length > 0 && content.length < 100000 && content !== _lastClipboard) {
                _lastClipboard = content;
                saveToHistory(content, "text");
            }
        });
        proc.onExited.connect(function() {
            proc.destroy();
            _clipWatcherProc = null;
        });
        _clipWatcherProc = proc;
        proc.running = true;
    }

    function stopClipWatcher() {
        if (_clipWatcherProc) {
            var proc = _clipWatcherProc;
            _clipWatcherProc = null;
            proc.running = false;
        }
        _lastClipboard = "";
    }

    function searchHistory(query, maxResults) {
        if (!_historyItems || _historyItems.length === 0) return [];
        if (!query || query.length === 0) {
            if (maxResults && maxResults > 0) {
                return _historyItems.slice(0, maxResults);
            }
            return _historyItems;
        }
        var q = query.toLowerCase();
        var results = [];
        var limit = maxResults || 3;
        for (var i = 0; i < _historyItems.length; i++) {
            var item = _historyItems[i];
            if (item.text.toLowerCase().indexOf(q) !== -1) {
                results.push(item);
                if (results.length >= limit) break;
            }
        }
        return results;
    }

    // --------------------------------------------------------------
    // Window grid
    // --------------------------------------------------------------

    function buildWindowGrid() {
        try {
            var windows = CompositorData ? (CompositorData.windowList || []) : [];
            var toplevels = [];
            try { toplevels = ToplevelManager && ToplevelManager.toplevels ? (ToplevelManager.toplevels.values || []) : []; } catch (e) { toplevels = []; }
            var wsMap = {};
            for (var i = 0; i < windows.length; i++) {
                var w = windows[i];
                if (!w.mapped) continue;
                var wsId = w.workspace.id;
                if (!wsMap[wsId]) wsMap[wsId] = { id: wsId, windows: [] };
                var cls = w.class || "";
                var matched = null;
                if (cls) {
                    var candidates = toplevels.filter(function(t) { return t.appId === cls; });
                    if (candidates.length === 1) matched = candidates[0];
                    else if (candidates.length > 1)
                        matched = candidates.find(function(t) { return t.title === (w.title || ""); }) || candidates[0];
                }
                wsMap[wsId].windows.push({
                    address: w.address,
                    class: cls,
                    title: w.title || "?",
                    is_focused: w.is_focused || false,
                    toplevel: matched
                });
            }
            var flatIdx = 0;
            var result = [];
            var sorted = Object.keys(wsMap).sort(function(a,b) { return parseInt(a) - parseInt(b); });
            for (var k = 0; k < sorted.length; k++) {
                var ws = wsMap[sorted[k]];
                ws.offset = flatIdx;
                var n = Math.min(ws.windows.length, 6);
                for (var j = 0; j < ws.windows.length; j++) {
                    ws.windows[j].globalIdx = j < n ? flatIdx + j : -1;
                }
                flatIdx += n;
                result.push(ws);
            }
            windowGridData = result;
            var cols = Math.max(1, Math.floor((contentColumn.width - 16) / 300));
            var rows = Math.ceil(result.length / cols);
            windowGridHeight = Math.min(rows * 195 + 8, 600);
        } catch (e) { /* ignore */ }
    }

    function goToSelectedWindow() {
        if (windowGridSelectedIndex < 0) return;
        for (var wsi = 0; wsi < windowGridData.length; wsi++) {
            var ws = windowGridData[wsi];
            var n = Math.min(ws.windows.length, 6);
            if (windowGridSelectedIndex >= ws.offset && windowGridSelectedIndex < ws.offset + n) {
                var win = ws.windows[windowGridSelectedIndex - ws.offset];
                if (win && win.address) {
                    var p1 = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
                    p1.command = ["hyprctl", "dispatch", "workspace", String(ws.id)];
                    p1.onExited.connect(function() { try { p1.destroy(); } catch (e) {} });
                    p1.running = true;
                    var p2 = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
                    p2.command = ["hyprctl", "dispatch", "focuswindow", "address:" + win.address];
                    p2.onExited.connect(function() { try { p2.destroy(); } catch (e) {} });
                    p2.running = true;
                     spotlight.closeSpotlight();
                }
                break;
            }
        }
    }

    // --------------------------------------------------------------
    // File search
    // --------------------------------------------------------------

    property var currentSearch: null
    property var currentSystemSearch: null

    function startFileSearch(query) {
        if (query.length < 2) return;
        var gen = searchGeneration;
        if (currentSearch) {
            currentSearch.running = false;
            currentSearch.destroy();
            currentSearch = null;
        }
        if (currentSystemSearch) {
            currentSystemSearch.running = false;
            currentSystemSearch.destroy();
            currentSystemSearch = null;
        }

        const home = Quickshell.env("HOME") || "/home/fabio";
        const q = query.replace(/[^a-zA-Z0-9\u00C0-\u024F\u0400-\u04FF_.-\s]/g, "");
        if (q.length < 2) return;

        var fileAccum = [];
        var systemAccum = [];
        var pendingSearches = 2;

        var proc = Qt.createQmlObject(
            'import Quickshell.Io; Process { stdout: SplitParser {} }',
            spotlight
        );
        proc.command = [
            "find",
            home + "/Documentos",
            home + "/Descargas",
            home + "/Escritorio",
            home,
            "-maxdepth", "4",
            "-not", "-path", "*/\.cache/*",
            "-not", "-path", "*/node_modules/*",
            "-not", "-path", "*/.git/*",
            "-not", "-path", "*/venv/*",
            "-not", "-path", "*/__pycache__/*",
            "-iname", "*" + q + "*",
            "-type", "f"
        ];
        proc.stdout.onRead.connect(function(data) {
            if (gen !== searchGeneration) return;
            var line = data.trim();
            if (line.length === 0) return;
            var fname = line.split("/").pop();
            var isDup = false;
            for (var fi = 0; fi < fileAccum.length; fi++) {
                if (fileAccum[fi].name === fname) { isDup = true; break; }
            }
            if (!isDup && fileAccum.length < 3) {
                var capturedLine = line;
                fileAccum.push({
                    name: fname,
                    description: capturedLine,
                    icon: Icons.file,
                    type: "file",
                    exec: function() {
                        if (capturedLine) {
                            spotlight.bash("'" + spotlight._revealScript + "' '" + capturedLine.replace(/'/g, "'\\''") + "' &");
                        }
                         spotlight.closeSpotlight();
                    }
                });
            }
        });
        proc.onExited.connect(function(code) {
            if (gen !== searchGeneration) { try { proc.destroy(); } catch (e) {} return; }
            if (fileAccum.length > 0) results = results.concat(fileAccum);
            proc.destroy();
            if (currentSearch === proc) currentSearch = null;
            pendingSearches--;
            if (pendingSearches <= 0 && systemAccum.length > 0) results = results.concat(systemAccum);
        });
        currentSearch = proc;
        proc.running = true;

        var sysProc = Qt.createQmlObject(
            'import Quickshell.Io; Process { stdout: SplitParser {} }',
            spotlight
        );
        sysProc.command = [
            "find",
            home + "/.config",
            "/usr/share",
            "/etc",
            "/opt",
            "-maxdepth", "3",
            "-not", "-path", "*/\.cache/*",
            "-not", "-path", "*/node_modules/*",
            "-not", "-path", "*/.git/*",
            "-not", "-path", "*/venv/*",
            "-not", "-path", "*/__pycache__/*",
            "-iname", "*" + q + "*",
            "-type", "f"
        ];
        sysProc.stdout.onRead.connect(function(data) {
            if (gen !== searchGeneration) return;
            var line = data.trim();
            if (line.length === 0) return;
            var fname = line.split("/").pop();
            var isDup = false;
            for (var si = 0; si < systemAccum.length; si++) {
                if (systemAccum[si].name === fname) { isDup = true; break; }
            }
            if (!isDup) {
                for (var hi = 0; hi < fileAccum.length; hi++) {
                    if (fileAccum[hi].name === fname) { isDup = true; break; }
                }
            }
            if (!isDup && systemAccum.length < 3) {
                var capturedLine = line;
                systemAccum.push({
                    name: fname,
                    description: capturedLine,
                    icon: Icons.file,
                    type: "file",
                    exec: function() {
                        if (capturedLine) {
                            spotlight.bash("'" + spotlight._revealScript + "' '" + capturedLine.replace(/'/g, "'\\''") + "' &");
                        }
                         spotlight.closeSpotlight();
                    }
                });
            }
        });
        sysProc.onExited.connect(function(code) {
            if (gen !== searchGeneration) { try { sysProc.destroy(); } catch (e) {} return; }
            sysProc.destroy();
            if (currentSystemSearch === sysProc) currentSystemSearch = null;
            pendingSearches--;
            if (pendingSearches <= 0 && systemAccum.length > 0) results = results.concat(systemAccum);
        });
        currentSystemSearch = sysProc;
        sysProc.running = true;

        // OCR search disabled (grim/slurp screenshots)
        var _ocrRes = [];
    }

    // --------------------------------------------------------------
    // Weather
    // --------------------------------------------------------------

    function startWeatherSearch(location, gen) {
        if (weatherSearch) {
            try { weatherSearch.abort(); } catch(e) {}
            weatherSearch = null;
        }

        var loc = location || WeatherService.defaultLocation;
        var url = "https://wttr.in/" + encodeURIComponent(loc) + "?format=j1";

        var xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (gen !== searchGeneration) { weatherSearch = null; return; }
            if (xhr.status === 200) {
                try {
                    var json = JSON.parse(xhr.responseText);
                    results = formatWeatherResults(json, loc);
                } catch(e) {
                    results = [{
                        name: "Error processing weather data",
                        description: loc || "Try another location",
                        type: "info"
                    }];
                }
            } else {
                results = [{
                    name: "Could not fetch weather",
                    description: loc
                        ? "Check location name or your internet connection"
                        : "Check your internet connection",
                    type: "info"
                }];
            }
            weatherSearch = null;
        };
        xhr.send();
        weatherSearch = xhr;
    }

    function formatWeatherResults(json, location) {
        var res = [];
        var current = json.current_condition && json.current_condition[0];
        var area = json.nearest_area && json.nearest_area[0];
        var forecast = json.weather || [];

        if (!current) {
            res.push({ name: "No data available", description: "Try another location", type: "info" });
            return res;
        }

        var city = area ? area.areaName[0].value : (location || "Current location");
        var country = area ? area.country[0].value : "";
        var locStr = city + (country ? ", " + country : "");

        var desc = (current.weatherDesc && current.weatherDesc[0]) ? current.weatherDesc[0].value : "";
        var tempC = current.temp_C || "?";
        var feelsLike = current.FeelsLikeC || "?";
        var humidity = current.humidity || "?";
        var wind = current.windspeedKmph || "?";
        var windDir = current.winddir16Point || "";

        var emoji = "[?]";
        var d = desc.toLowerCase();
        if (d.includes("sunny") || d.includes("clear")) emoji = "[SUN]";
        else if (d.includes("partly")) emoji = "[PCL]";
        else if (d.includes("cloud") && !d.includes("partly")) emoji = "[CL]";
        else if (d.includes("rain") || d.includes("drizzle") || d.includes("shower")) emoji = "[RAIN]";
        else if (d.includes("thunder") || d.includes("storm")) emoji = "[ST]";
        else if (d.includes("snow") || d.includes("sleet") || d.includes("ice")) emoji = "[SN]";
        else if (d.includes("fog") || d.includes("mist") || d.includes("haze")) emoji = "[FG]";
        else if (d.includes("overcast")) emoji = "[OVC]";

        res.push({
            name: emoji + " " + tempC + "°C  " + desc + "  —  " + locStr,
            description: "Feels like: " + feelsLike + "°C · Humidity: " + humidity + "% · Wind: " + wind + " km/h " + windDir,
            icon: Icons.globe,
            type: "info",
            exec: function() {
                Qt.openUrlExternally("https://wttr.in/" + encodeURIComponent(city));
                 spotlight.closeSpotlight();
            }
        });

        for (var fi = 0; fi < Math.min(forecast.length, 3); fi++) {
            var day = forecast[fi];
            if (!day.date) continue;
            var dateObj = new Date(day.date);
            var dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
            var dayName = dayNames[dateObj.getDay()] || "";
            var maxT = day.maxtempC || "?";
            var minT = day.mintempC || "?";
            res.push({
                name: dayName + " · " + "max " + maxT + "°C  min " + minT + "°C",
                description: "",
                type: "info",
                icon: Icons.apps
            });
        }

        return res;
    }

    // --------------------------------------------------------------
    // Timers
    // --------------------------------------------------------------

    function _fmtDur(totalSec) {
        if (totalSec >= 3600) {
            var h = Math.floor(totalSec / 3600);
            var m = Math.floor((totalSec % 3600) / 60);
            return h + "h " + (m < 10 ? "0" : "") + m + "m";
        } else if (totalSec >= 60) {
            var mm = Math.floor(totalSec / 60);
            var ss = totalSec % 60;
            return mm + ":" + (ss < 10 ? "0" : "") + ss;
        }
        return totalSec + "s";
    }

    function startTimer(label, seconds) {
        if (seconds <= 0) return null;
        var tId = _timerNextId++;
        var t = {
            id: tId,
            label: label || ("Timer " + tId),
            totalSeconds: seconds,
            endTime: Date.now() + seconds * 1000,
            createdAt: new Date().toLocaleTimeString()
        };
        var arr = activeTimers.slice();
        arr.push(t);
        activeTimers = arr;
        return t;
    }

    function cancelTimer(target) {
        if (typeof target === 'number') {
            activeTimers = activeTimers.filter(function(t) { return t.id !== target; });
        } else if (typeof target === 'string') {
            activeTimers = activeTimers.filter(function(t) { return t.label !== target; });
        }
    }

    function clearAllTimers() {
        activeTimers = [];
    }

    function tickTimers() {
        if (activeTimers.length === 0) return;
        var now = Date.now();
        var keep = [];
        var done = [];
        for (var i = 0; i < activeTimers.length; i++) {
            var t = activeTimers[i];
            if (now >= t.endTime) {
                done.push(t);
            } else {
                keep.push(t);
            }
        }
        if (done.length > 0) {
            activeTimers = keep;
            for (var j = 0; j < done.length; j++) {
                _notifyTimerDone(done[j]);
            }
        }
    }

    // --------------------------------------------------------------
    // Inline notifications
    // --------------------------------------------------------------

    function addHaxNotification(type, label, body, notifObj) {
        var nid = _haxNotifIdCounter++;
        var entry = {
            id: nid,
            type: type,
            label: label,
            body: body,
            ts: Date.now(),
            icon: type === "timer" ? "[TIMER]" : type === "plugin" ? "[PLUGIN]" : "[ALARM]",
            notifObj: notifObj
        };
        var arr = _haxNotifications.slice();
        arr.push(entry);
        _haxNotifications = arr;

        if (!showHax) {
            Visibilities.setActiveModule("spotlight");
        }

        if (type === "plugin") {
            _delay(function() {
                _dismissHaxNotif(nid);
            }, 5000);
        }
    }

    function _dismissHaxNotif(id) {
        _haxNotifications = _haxNotifications.filter(function(n) { return n.id !== id; });
    }

    function _notifyTimerDone(t) {
        addHaxNotification("timer", t.label || "Timer",
            "Finished — " + _fmtDur(t.totalSeconds), t
        );
    }

    // --------------------------------------------------------------
    // Alarms
    // --------------------------------------------------------------

    function setAlarm(label, hour, minute, days) {
        var aId = _alarmNextId++;
        var a = {
            id: aId,
            label: label || ("Alarm " + aId),
            hour: hour,
            minute: minute,
            days: days || [],
            enabled: true,
            lastTriggered: null
        };
        var arr = activeAlarms.slice();
        arr.push(a);
        activeAlarms = arr;
        return a;
    }

    function cancelAlarm(target) {
        if (typeof target === 'number') {
            activeAlarms = activeAlarms.filter(function(a) { return a.id !== target; });
        } else if (typeof target === 'string') {
            activeAlarms = activeAlarms.filter(function(a) { return a.label !== target; });
        }
    }

    function clearAllAlarms() {
        activeAlarms = [];
    }

    function checkAlarms() {
        if (activeAlarms.length === 0) return;
        var now = new Date();
        var h = now.getHours();
        var m = now.getMinutes();
        var day = now.getDay();
        for (var i = 0; i < activeAlarms.length; i++) {
            var a = activeAlarms[i];
            if (!a.enabled) continue;
            if (a.hour !== h || a.minute !== m) continue;
            if (a.days.length > 0 && a.days.indexOf(day) < 0) continue;
            var key = now.toDateString() + " " + h + ":" + m;
            if (a.lastTriggered === key) continue;
            a.lastTriggered = key;
            _notifyAlarm(a);
        }
    }

    function _notifyAlarm(a) {
        var daysStr = a.days.length > 0 ? a.days.map(function(d) {
            return ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][d];
        }).join(" ") : "Every day";
        var timeStr = (a.hour < 10 ? "0" : "") + a.hour + ":" + (a.minute < 10 ? "0" : "") + a.minute;
        addHaxNotification("alarm", a.label || "Alarm",
            timeStr + " — " + daysStr, a
        );
    }

    // --------------------------------------------------------------
    // Package search
    // --------------------------------------------------------------

    function _cancelPkgSearch() {
        for (var pi = 0; pi < _pkgSearchProcesses.length; pi++) {
            var p = _pkgSearchProcesses[pi];
            if (p) { p.running = false; p.destroy(); }
        }
        _pkgSearchProcesses = [];
        _lastSearchQuery = "";
    }

    function _searchPackages(query, gen) {
        _cancelPkgSearch();
        var safeQ = query.replace(/'/g, "'\\''");

        var proc = Qt.createQmlObject('import Quickshell.Io; Process { stdout: SplitParser {} }', spotlight);
        proc.command = ["bash", "-c",
            "echo '===PACMAN==='; timeout 15 pacman -Ss '" + safeQ + "' 2>/dev/null | head -30"
            + "; echo '===YAY==='; timeout 20 yay -Ss '" + safeQ + "' 2>/dev/null | head -30"
            + "; echo '===FLATPAK==='; timeout 15 flatpak search '" + safeQ + "' 2>/dev/null | head -15"
        ];
        var rawLines = [];
        proc.stdout.onRead.connect(function(data) {
            if (gen !== searchGeneration) return;
            rawLines.push(data);
        });
        proc.onExited.connect(function() {
            proc.destroy();
            if (gen !== searchGeneration) return;

            var section = "";
            var newRes = [];
            var seenPkg = {};

            function addPkg(nombre, descripcion, gestor, comando) {
                var key = nombre + "|" + gestor;
                if (seenPkg[key]) return;
                seenPkg[key] = true;
                newRes.push({
                    name: nombre + " (" + gestor + ")",
                    description: descripcion || gestor,
                    icon: Icons.notepad, type: "info",
                    exec: function() {
                        runCmd(comando);
                    }
                });
            }

            for (var i = 0; i < rawLines.length; i++) {
                var l = rawLines[i];
                if (l === "===PACMAN===") { section = "pacman"; continue; }
                if (l === "===YAY===") { section = "yay"; continue; }
                if (l === "===FLATPAK===") { section = "flatpak"; continue; }
                if (!l.trim()) continue;

                if (section === "flatpak") {
                    if (l.indexOf("\t") >= 0) {
                        var fp = l.split("\t");
                        var fId = (fp[0] || "").trim();
                        var fName = (fp[1] || "").trim();
                        var fDesc = (fp[2] || "").trim();
                        var pkgName = fName || fId.split(".").pop() || fId;
                        var pkgDesc = fDesc || fId;
                        addPkg(pkgName, pkgDesc, "flatpak",
                            "flatpak install -y flathub " + fId);
                    }
                } else if (section === "pacman" || section === "yay") {
                    var m = l.match(/^(\S+)\/(\S+)\s/);
                    if (m) {
                        var repo = m[1];
                        var pkg = m[2];
                        var desc = "";
                        if (i + 1 < rawLines.length) {
                            var next = rawLines[i + 1];
                            if (next.length > 0 && next.charAt(0) === ' ') {
                                desc = next.trim();
                                i++;
                            }
                        }
                        var gestor = section === "pacman" ? "pacman" : "AUR/yay";
                        var sudoP = section === "pacman" ? "pacman" : "";
                        addPkg(pkg, desc, gestor,
                            sudoP
                                ? "echo 'F200607' | sudo -S " + sudoP + " -S --noconfirm " + pkg
                                : "yay -S --noconfirm " + pkg);
                    }
                }
            }

            if (newRes.length === 0) {
                newRes.push({ name: "No packages found for \"" + query + "\"", description: "Try: pacman, yay or flatpak directly", icon: Icons.notepad, type: "info", exec: null });
            }
            results = newRes;
            _pkgSearchProcesses = [];
        });
        _pkgSearchProcesses = [proc];
        proc.running = true;
    }

    function _searchFlatpak(query, gen) {
        _cancelPkgSearch();

        var allPkgs = [];
        var safeQ = query.replace(/'/g, "'\\''");

        var proc = Qt.createQmlObject('import Quickshell.Io; Process { }', spotlight);
        proc.command = ["bash", "-c", "flatpak search '" + safeQ + "' 2>/dev/null | head -10"];
        var out = "";
        proc.stdout.onRead.connect(function(data) { if (gen === searchGeneration) out += data; });
        proc.onExited.connect(function() {
            proc.destroy();
            if (gen !== searchGeneration) return;
            var lines = out.split("\n");
            for (var fi = 0; fi < lines.length; fi++) {
                var line = lines[fi].trim();
                if (!line || line.indexOf("\t") < 0) continue;
                var fpParts = line.split("\t");
                var fpName = (fpParts[0] || "").trim();
                var fpDesc = (fpParts[1] || "").trim();
                if (!fpName) continue;
                (function(cName, cDesc) {
                    allPkgs.push({
                        name: cName + " (flatpak)",
                        description: cDesc || "Flatpak",
                        icon: Icons.notepad, type: "info",
                        exec: function() { runCmd('flatpak install -y flathub ' + cName); }
                    });
                })(fpName, fpDesc);
            }
            if (allPkgs.length > 0) {
                results = allPkgs;
            } else {
                results = [{ name: "No packages found on Flathub", description: "Try: flatpak install " + query, icon: Icons.notepad, type: "info", exec: null }];
            }
            _pkgSearchProcesses = [];
        });
        _pkgSearchProcesses = [proc];
        proc.running = true;
    }

    // --------------------------------------------------------------
    // Plugin API utilities
    // --------------------------------------------------------------

    property var _dynamicResults: []

    function addPluginResult(name, description, icon, actionId, actionData) {
        if (!name) return;
        var entry = {
            name: icon + " " + name + " (plugin)",
            description: description || "",
            icon: Icons.notepad,
            type: "plugin",
            _pluginId: "dynamic",
            _actionId: actionId || "",
            _actionData: actionData || "",
            _pluginName: "Plugin",
            _pluginIcon: icon || "[plugin]",
            exec: function() {
                addHaxNotification("plugin", name, description || "Executed", null);
            }
        };
        var arr = _dynamicResults.slice();
        arr.push(entry);
        _dynamicResults = arr;
        addHaxNotification("plugin", name, description || "Result available", { actionId: actionId });
    }

    property var _pluginConfig: ({})

    function getPluginConfig(key, callback) {
        if (typeof callback === "function") {
            callback(key ? _pluginConfig[key] : _pluginConfig);
        }
        return key ? _pluginConfig[key] : _pluginConfig;
    }

    function setPluginConfig(key, value) {
        if (key) {
            _pluginConfig[key] = value;
        }
    }

    function _delay(callback, ms) {
        var timer = Qt.createQmlObject('import QtQuick; Timer { repeat: false }', spotlight);
        timer.interval = ms;
        timer.triggered.connect(function() {
            try {
                callback();
            } catch(e) {
                console.log("_delay error:", e);
            }
            try { timer.destroy(); } catch(e) {}
        });
        timer.start();
    }
}
