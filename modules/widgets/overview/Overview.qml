import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.globals
import qs.modules.theme
import qs.modules.components
import qs.modules.bar.workspaces
import qs.modules.services
import qs.config

Item {
    id: overviewRoot
    anchors.fill: parent

    // Direct hyprctl for workspace switching
    Process {
        id: wsSwitchProcess
    }

    // Fetch all workspace states via hyprctl -j (includes empty/off-screen)
    property var workspaceStates: []
    Process {
        id: wsStateProcess
        command: ["hyprctl", "workspaces", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var raw = JSON.parse(text);
                    if (Array.isArray(raw))
                        overviewRoot.workspaceStates = raw;
                } catch (e) {}
            }
        }
    }
    // Refresh workspace states when overview opens + periodically
    Timer {
        id: wsStateTimer
        interval: 800
        running: GlobalStates.overviewOpen
        repeat: true
        onTriggered: { if (!wsStateProcess.running) wsStateProcess.running = true; }
    }

    // Config
    readonly property real scale: Config.overview.scale
    readonly property int rows: Config.overview.rows
    readonly property int columns: Config.overview.columns
    readonly property int workspacesShown: rows * columns
    readonly property real workspaceSpacing: Config.overview.workspaceSpacing
    readonly property real workspacePadding: 8
    readonly property color activeBorderColor: Styling.srItem("overprimary")

    property var currentScreen: null
    readonly property var monitor: currentScreen ? AxctlService.monitorFor(currentScreen) : AxctlService.focusedMonitor
    readonly property var windowList: CompositorData.windowList
    readonly property var allMonitors: CompositorData.monitors
    readonly property int monitorId: monitor?.id ?? -1
    readonly property var monitorData: allMonitors.find(m => m.id === monitorId) ?? null
    readonly property string barPosition: Config.bar.position
    readonly property var barPanel: monitor ? Visibilities.getBarPanelForScreen(monitor.name) : null
    readonly property bool isBarPinned: barPanel ? barPanel.pinned : (Config.bar.pinnedOnStartup ?? true)
    readonly property int barReserved: isBarPinned ? (Config.showBackground ? 44 : 40) : 0

    // Workspace cell size — fills available space manteniendo 16:9
    readonly property real _spacingW: (columns - 1) * workspaceSpacing + workspacePadding * 2
    readonly property real _spacingH: (rows - 1) * workspaceSpacing + workspacePadding * 2
    readonly property real _cellWfromW: Math.max(80, Math.round((width - _spacingW) / columns))
    readonly property real _cellHfromW: Math.max(60, Math.round(_cellWfromW * 9 / 16))
    readonly property real _cellHfromH: Math.max(60, Math.round((height - _spacingH) / rows))
    readonly property real _cellWfromH: Math.max(80, Math.round(_cellHfromH * 16 / 9))
    // Prefer width-based calc if total height fits, else use height-based
    readonly property bool _useWbase: (rows * _cellHfromW + _spacingH) <= height
    readonly property real wsCellW: _useWbase ? _cellWfromW : _cellWfromH
    readonly property real wsCellH: _useWbase ? _cellHfromW : _cellHfromH
    readonly property real gridTotalW: columns * wsCellW + _spacingW
    readonly property real gridTotalH: rows * wsCellH + _spacingH

    // Drag state
    property int draggingFromWorkspace: -1
    property int draggingTargetWorkspace: -1

    // Search
    property string searchQuery: ""
    property var matchingWindows: []
    property int selectedMatchIndex: 0
    function resetSearch() { searchQuery = ""; matchingWindows = []; selectedMatchIndex = 0; }
    onSearchQueryChanged: updateMatchingWindows()
    onWindowListChanged: {
        updateMatchingWindows();
        Qt.callLater(_updateFilteredWindows);
    }
    onAllMonitorsChanged: Qt.callLater(_updateFilteredWindows)

    // Force refresh after user actions (drag, click)
    function refreshOverview() {
        if (typeof CompositorData !== "undefined" && CompositorData.refreshFromHyprctl)
            CompositorData.refreshFromHyprctl();
        Qt.callLater(_updateFilteredWindows);
    }

    // Poll for position/size updates while overview is visible.
    Timer {
        id: positionPollTimer
        interval: 300
        running: GlobalStates.overviewOpen
        repeat: true
        onTriggered: overviewRoot._updateFilteredWindows()
    }

    // Force refresh from hyprctl when overview opens so window list is current
    property int _openRefreshCount: 0

    // Rapid-fire refreshes when overview opens to catch async compositor data
    Timer {
        id: openRefreshTimer
        interval: 250
        running: GlobalStates.overviewOpen && overviewRoot._openRefreshCount < 6
        repeat: true
        onTriggered: {
            if (typeof CompositorData !== "undefined" && CompositorData.refreshFromHyprctl) {
                CompositorData.refreshFromHyprctl();
            }
            overviewRoot._updateFilteredWindows();
            overviewRoot._openRefreshCount++;
        }
    }

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen) {
                overviewRoot._openRefreshCount = 0;
                if (typeof CompositorData !== "undefined" && CompositorData.refreshFromHyprctl) {
                    CompositorData.refreshFromHyprctl();
                }
                overviewRoot._updateFilteredWindows();
            }
        }
    }

    property var _filteredWindowsCache: []

    Component.onCompleted: {
        _updateFilteredWindows();
        wsStateProcess.running = true;
    }

    function _updateFilteredWindows() {
        var list = overviewRoot.windowList;
        var result = [];
        for (var i = 0; i < list.length; i++) {
            var w = list[i];
            if (!w || !w.workspace || !w.workspace.id || w.workspace.id <= 0 || w.workspace.id > workspacesShown)
                continue;
            var winMon = overviewRoot.allMonitors.find(function(m) { return m.id === w.monitor; });
            result.push({
                windowData: w,
                winMonData: winMon
            });
        }
        _filteredWindowsCache = _computeFillSizes(result);
    }

    function _computeFillSizes(items) {
        var i, j, a, b;
        var bp = overviewRoot.barPosition;
        var br = overviewRoot.barReserved;
        for (i = 0; i < items.length; i++) {
            a = items[i];
            var wd = a.windowData;
            var wsId = wd.workspace?.id ?? 0;
            var md = a.winMonData;
            var ro = md && (md.transform % 2 === 1);
            var monW = md ? (ro ? (md.height || 1080) : (md.width || 1920)) : 1920;
            var monH = md ? (ro ? (md.width || 1920) : (md.height || 1080)) : 1080;
            monW = monW > 0 ? monW : 1920;
            monH = monH > 0 ? monH : 1080;

            var ax = (wd.at?.[0] ?? 0) - (md?.x ?? 0);
            var ay = (wd.at?.[1] ?? 0) - (md?.y ?? 0);
            if (bp === "left") ax -= br;
            if (bp === "top") ay -= br;
            ax = Math.max(0, ax);
            ay = Math.max(0, ay);
            var aw = wd.size?.[0] ?? monW;
            var ah = wd.size?.[1] ?? monH;
            var effW = monW - (bp === "left" || bp === "right" ? br : 0);
            var effH = monH - (bp === "top" || bp === "bottom" ? br : 0);

            var rightLimit = effW;
            var bottomLimit = effH;

            for (j = 0; j < items.length; j++) {
                if (i === j) continue;
                b = items[j];
                if ((b.windowData.workspace?.id ?? 0) !== wsId) continue;
                if ((b.winMonData?.id ?? -1) !== (md?.id ?? -1)) continue;

                var bx = (b.windowData.at?.[0] ?? 0) - (b.winMonData?.x ?? 0);
                var by = (b.windowData.at?.[1] ?? 0) - (b.winMonData?.y ?? 0);
                if (bp === "left") bx -= br;
                if (bp === "top") by -= br;
                var bw = b.windowData.size?.[0] ?? monW;
                var bh = b.windowData.size?.[1] ?? monH;

                var bContainedInA = (bx >= ax && by >= ay && bx + bw <= ax + aw && by + bh <= ay + ah);
                if (!bContainedInA && bx > ax && by < ay + ah && by + bh > ay)
                    rightLimit = Math.min(rightLimit, bx);
                if (!bContainedInA && by > ay && bx < ax + aw && bx + bw > ax)
                    bottomLimit = Math.min(bottomLimit, by);
            }

            var relW = aw > 200 ? Math.max(0.05, Math.min(1, aw / effW)) : 0.85;
            var relH = ah > 200 ? Math.max(0.05, Math.min(1, ah / effH)) : 0.85;
            a.fillW = effW > 0 ? Math.max(relW, Math.min(1, (rightLimit - ax) / effW)) : 0.85;
            a.fillH = effH > 0 ? Math.max(relH, Math.min(1, (bottomLimit - ay) / effH)) : 0.85;
        }
        return items;
    }

    function fuzzyMatch(q, t) {
        if (q.length === 0) return true;
        if (t.length === 0) return false;
        var qi = 0;
        for (var i = 0; i < t.length && qi < q.length; i++) { if (t[i] === q[qi]) qi++; }
        return qi === q.length;
    }
    function fuzzyScore(q, t) {
        if (q.length === 0) return 0;
        if (t.length === 0) return -1;
        if (t.includes(q)) return 1000 + (100 - t.length);
        var qi = 0, cons = 0, maxc = 0, score = 0;
        for (var i = 0; i < t.length && qi < q.length; i++) {
            if (t[i] === q[qi]) { qi++; cons++; maxc = Math.max(maxc, cons);
                if (i === 0 || t[i-1] === ' ' || t[i-1] === '-' || t[i-1] === '_') score += 10; }
            else cons = 0;
        }
        if (qi !== q.length) return -1;
        return score + maxc * 5;
    }
    function updateMatchingWindows() {
        if (searchQuery.length === 0) { matchingWindows = []; selectedMatchIndex = 0; return; }
        var q = searchQuery.toLowerCase();
        var m = windowList.filter(function(w) {
            if (!w) return false;
            return fuzzyMatch(q, (w.title || "").toLowerCase()) || fuzzyMatch(q, (w.class || "").toLowerCase());
        }).map(function(w) {
            return { window: w, score: Math.max(fuzzyScore(q, (w.title || "").toLowerCase()), fuzzyScore(q, (w.class || "").toLowerCase())) };
        }).sort(function(a,b) { return b.score - a.score; }).map(function(i) { return i.window; });
        matchingWindows = m; selectedMatchIndex = m.length > 0 ? 0 : -1;
    }
    function isWindowMatched(addr) { return searchQuery.length > 0 && matchingWindows.some(function(w) { return w?.address === addr; }); }
    function isWindowSelected(addr) { return matchingWindows.length > 0 && selectedMatchIndex >= 0 && matchingWindows[selectedMatchIndex]?.address === addr; }

    readonly property var filteredWindows: _filteredWindowsCache

    // ═══════════════════════════════════════════════════════════════
    // FULL-SCREEN GRID
    // ═══════════════════════════════════════════════════════════════
    Item {
        id: gridContainer
        anchors.centerIn: parent
        width: gridTotalW
        height: gridTotalH

        // Workspace cells — drawn first so window cards overlay on top
        Repeater {
            model: workspacesShown

            Rectangle {
                id: cell
                required property int index
                readonly property int wsNum: index + 1
                readonly property int col: index % columns
                readonly property int row: Math.floor(index / columns)
                readonly property bool isDropTarget: overviewRoot.draggingTargetWorkspace === wsNum
                readonly property int staggerDelay: (row * columns + col) * 40

                x: col * (wsCellW + workspaceSpacing) + workspacePadding
                y: row * (wsCellH + workspaceSpacing) + workspacePadding
                width: wsCellW
                height: wsCellH
                color: "transparent"
                radius: Styling.radius(2)
                border.width: 2
                border.color: isDropTarget ? Colors.outline : "transparent"
                clip: true

                // Staggered entrance animation
                opacity: 0
                scale: 0.85
                Component.onCompleted: {
                    opacity = 1;
                    scale = 1;
                }
                Behavior on opacity {
                    enabled: Anim.animationsEnabled
                    SequentialAnimation {
                        PauseAnimation { duration: cell.staggerDelay }
                        NumberAnimation {
                            duration: Anim.emphasizedNormal
                            easing.type: Anim.easing("decelerate").type
                            easing.bezierCurve: Anim.easing("decelerate").bezierCurve
                        }
                    }
                }
                Behavior on scale {
                    enabled: Anim.animationsEnabled
                    SequentialAnimation {
                        PauseAnimation { duration: cell.staggerDelay }
                        NumberAnimation {
                            duration: Anim.emphasizedNormal
                            easing.type: Anim.springSnappy().type
                            easing.bezierCurve: Anim.springSnappy().bezierCurve
                        }
                    }
                }

                // Wallpaper thumbnail
                TintedWallpaper {
                    anchors.fill: parent
                    radius: Styling.radius(2)
                    tintEnabled: GlobalStates.wallpaperManager ? GlobalStates.wallpaperManager.tintEnabled : false
                    property string lfp: GlobalStates.wallpaperManager ? GlobalStates.wallpaperManager.getLockscreenFramePath(GlobalStates.wallpaperManager.currentWallpaper) : ""
                    source: lfp ? "file://" + lfp : ""
                }

                // Workspace number
                Text {
                    anchors.centerIn: parent
                    text: String(wsNum)
                    font.family: Config.theme.font
                    font.pixelSize: Math.max(20, Math.round(wsCellH * 0.12))
                    font.bold: true
                    color: Colors.onSurface
                    opacity: 0.3
                    z: 5
                }

                // Click cell to switch workspace
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onClicked: {
                        wsSwitchProcess.command = ["hyprctl", "dispatch", "workspace", String(wsNum)];
                        wsSwitchProcess.running = true;
                    }
                    onDoubleClicked: {
                        Visibilities.setActiveModule("");
                        wsSwitchProcess.command = ["hyprctl", "dispatch", "workspace", String(wsNum)];
                        wsSwitchProcess.running = true;
                    }
                }

                // Drop target for dragged windows
                DropArea {
                    anchors.fill: parent
                    onEntered: overviewRoot.draggingTargetWorkspace = wsNum
                    onExited: { if (overviewRoot.draggingTargetWorkspace === wsNum) overviewRoot.draggingTargetWorkspace = -1; }
                }
            }
        }

        // Window overlay — on top of workspace cells
        Item {
            id: winLayer
            anchors.fill: parent

            // Fallback click on empty space (when no window cards cover the cell)
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onClicked: mouse => {
                    var cw = wsCellW + workspaceSpacing;
                    var ch = wsCellH + workspaceSpacing;
                    var col = Math.floor((mouse.x - workspacePadding) / cw);
                    var row = Math.floor((mouse.y - workspacePadding) / ch);
                    if (col >= 0 && col < columns && row >= 0 && row < rows) {
                        wsSwitchProcess.command = ["hyprctl", "dispatch", "workspace",
                            String(row * columns + col + 1)];
                        wsSwitchProcess.running = true;
                        Qt.callLater(refreshOverview);
                    }
                }
            }

            // Window cards
            Repeater {
                model: filteredWindows

                delegate: OverviewWindow {
                    id: win
                    required property var modelData
                    windowData: modelData.windowData
                    availableWorkspaceWidth: wsCellW
                    availableWorkspaceHeight: wsCellH
                    monitorData: modelData.winMonData || overviewRoot.monitorData
                    barPosition: overviewRoot.barPosition
                    barReserved: overviewRoot.barReserved

                    overviewRootRef: overviewRoot
                    isSearchMatch: overviewRoot.isWindowMatched(windowData?.address)
                    isSearchSelected: overviewRoot.isWindowSelected(windowData?.address)

                    // Grid cell offset based on workspace ID
                    property int wCol: (windowData?.workspace.id - 1) % columns
                    property int wRow: Math.floor((windowData?.workspace.id - 1) / columns)
                    xOffset: Math.round(wCol * (wsCellW + workspaceSpacing) + workspacePadding)
                    yOffset: Math.round(wRow * (wsCellH + workspaceSpacing) + workspacePadding)

                    onDragStarted: overviewRoot.draggingFromWorkspace = windowData?.workspace.id || -1
                    onDragFinished: function(targetWs) {
                        overviewRoot.draggingFromWorkspace = -1;
                        if (targetWs > 0 && targetWs !== windowData?.workspace.id) {
                            AxctlService.dispatch("movetoworkspacesilent " + targetWs + ",address:" + (windowData?.address || ""));
                            Qt.callLater(function() { CompositorData.refreshFromHyprctl(); });
                        }
                    }
                    onWindowClicked: {
                        Visibilities.setActiveModule("", true);
                        Qt.callLater(function() { AxctlService.dispatch("focuswindow address:" + windowData.address); });
                    }
                    onWindowClosed: { AxctlService.dispatch("closewindow address:" + windowData.address); }
                }
            }
        }
    }
}
