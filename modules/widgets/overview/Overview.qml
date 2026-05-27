import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
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

    Process { id: wsSwitchProcess }

    // ── Window data from hyprctl ──
    property var rawWindows: []
    property var rawMonitors: []

    Process {
        id: clientProcess
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var raw = JSON.parse(text);
                    if (Array.isArray(raw)) overviewRoot.rawWindows = raw;
                } catch (e) {}
            }
        }
    }

    Process {
        id: monProcess
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var raw = JSON.parse(text);
                    if (Array.isArray(raw)) overviewRoot.rawMonitors = raw;
                } catch (e) {}
            }
        }
    }

    // When rawWindows updates, tell the mapper to find unmatched windows
    onRawWindowsChanged: {
        if (GlobalStates.overviewOpen && WlrToplevelMapper) {
            WlrToplevelMapper.updateUnmatched(rawWindows);
            WlrToplevelMapper.captureAllUnmatched();
        }
    }

    Timer {
        id: refreshTimer
        interval: 600
        running: GlobalStates.overviewOpen
        repeat: true
        onTriggered: {
            if (!clientProcess.running) clientProcess.running = true;
            if (!monProcess.running) monProcess.running = true;
        }
    }

    // ── Config ──
    readonly property int rows: Config.overview.rows
    readonly property int columns: Config.overview.columns
    readonly property int workspacesShown: rows * columns
    readonly property real workspaceSpacing: Config.overview.workspaceSpacing
    readonly property real workspacePadding: 8
    readonly property color activeBorderColor: Styling.srItem("overprimary")
    property var currentScreen: null

    // Monitor lookup by ID
    readonly property var monMap: {
        var m = {};
        var list = overviewRoot.rawMonitors;
        for (var i = 0; i < list.length; i++) m[list[i].id] = list[i];
        return m;
    }

    // ── Cell size — 16:9 ──
    readonly property real _spacingW: (columns - 1) * workspaceSpacing + workspacePadding * 2
    readonly property real _spacingH: (rows - 1) * workspaceSpacing + workspacePadding * 2
    readonly property real _cellWfromW: Math.max(80, Math.round((width - _spacingW) / columns))
    readonly property real _cellHfromW: Math.max(60, Math.round(_cellWfromW * 9 / 16))
    readonly property real _cellHfromH: Math.max(60, Math.round((height - _spacingH) / rows))
    readonly property real _cellWfromH: Math.max(80, Math.round(_cellHfromH * 16 / 9))
    readonly property bool _useWbase: (rows * _cellHfromW + _spacingH) <= height
    readonly property real wsCellW: _useWbase ? _cellWfromW : _cellWfromH
    readonly property real wsCellH: _useWbase ? _cellHfromW : _cellHfromH
    readonly property real gridTotalW: columns * wsCellW + _spacingW
    readonly property real gridTotalH: rows * wsCellH + _spacingH

    // ── Windows grouped by workspace ──
    readonly property var windowsByWs: {
        var map = {};
        var list = overviewRoot.rawWindows;
        for (var i = 0; i < list.length; i++) {
            var w = list[i];
            var wsId = w.workspace && w.workspace.id ? w.workspace.id : 0;
            if (wsId < 1 || wsId > workspacesShown) continue;
            if (!map[wsId]) map[wsId] = [];
            map[wsId].push(w);
        }
        return map;
    }

    function winsForWs(wsNum) { return overviewRoot.windowsByWs[String(wsNum)] || []; }

    function iconForClass(cls) { return AppSearch.guessIcon(cls || ""); }

    function colorForClass(cls) {
        var c = (cls || "").toLowerCase();
        var hash = 0;
        for (var i = 0; i < c.length; i++) hash = ((hash << 5) - hash) + c.charCodeAt(i);
        var hue = ((hash % 360) + 360) % 360;
        return Qt.hsla(hue / 360, 0.5, 0.4, 1.0);
    }

    // ── Refresh when overview opens ──
    property int _refreshCount: 0

    Timer {
        id: openRefreshTimer
        interval: 200
        running: GlobalStates.overviewOpen && _refreshCount < 8
        repeat: true
        onTriggered: {
            if (!clientProcess.running) clientProcess.running = true;
            if (!monProcess.running) monProcess.running = true;
            _refreshCount++;
        }
    }

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen) {
                _refreshCount = 0;
                if (!clientProcess.running) clientProcess.running = true;
                if (!monProcess.running) monProcess.running = true;
                // Trigger grim fallback on next data refresh
                Qt.callLater(function() {
                    if (WlrToplevelMapper && rawWindows.length > 0) {
                        WlrToplevelMapper.updateUnmatched(rawWindows);
                        WlrToplevelMapper.captureAllUnmatched();
                    }
                });
            } else {
                // Reset drag state on close
                overviewRoot.isDragging = false;
                overviewRoot.dragToWorkspace = -1;
                overviewRoot.dragFromWorkspace = -1;
                overviewRoot.dragWindowAddr = "";
            }
        }
    }

    // ── Drag state ──
    property int dragFromWorkspace: -1
    property int dragToWorkspace: -1
    property string dragWindowAddr: ""
    property bool isDragging: false
    property real dragGhostX: 0
    property real dragGhostY: 0
    property real dragGhostW: 120
    property real dragGhostH: 80
    property string dragGhostCls: ""
    property string dragGhostTitle: ""
    property string dragGhostAddr: ""

    Component.onCompleted: {
        if (!clientProcess.running) clientProcess.running = true;
        if (!monProcess.running) monProcess.running = true;
    }

    // ── Grid layout ──
    Item {
        id: gridContainer
        anchors.centerIn: parent
        width: gridTotalW
        height: gridTotalH

        Repeater {
            model: workspacesShown

            Rectangle {
                id: cell
                required property int index
                readonly property int wsNum: index + 1
                readonly property int col: index % columns
                readonly property int row: Math.floor(index / columns)
                readonly property var cellWindows: overviewRoot.winsForWs(wsNum)
                readonly property int staggerDelay: (row * columns + col) * 40

                x: col * (wsCellW + workspaceSpacing) + workspacePadding
                y: row * (wsCellH + workspaceSpacing) + workspacePadding
                width: wsCellW
                height: wsCellH
                color: Qt.rgba(Colors.surfaceContainer.r, Colors.surfaceContainer.g, Colors.surfaceContainer.b, 0.12)
                radius: Styling.radius(2)
                clip: true

                // Staggered entrance
                opacity: 0; scale: 0.85
                Component.onCompleted: { opacity = 1; scale = 1; }
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

                // ── Live screen capture background ──
                ScreencopyView {
                    id: bgCap
                    anchors.fill: parent
                    captureSource: {
                        // Find the first window's monitor, or use current
                        var mons = overviewRoot.rawMonitors;
                        if (cellWindows.length > 0) {
                            var monId = cellWindows[0].monitor;
                            var target = mons.find(function(m) { return m.id === monId; });
                            if (target) return target;
                        }
                        return mons.length > 0 ? mons[0] : null;
                    }
                    live: GlobalStates.overviewOpen
                    visible: !GlobalStates.lockscreenVisible
                    opacity: 0.7
                }

                // ── Wallpaper fallback ──
                TintedWallpaper {
                    anchors.fill: parent; radius: Styling.radius(2)
                    tintEnabled: GlobalStates.wallpaperManager ? GlobalStates.wallpaperManager.tintEnabled : false
                    property string lfp: GlobalStates.wallpaperManager ? GlobalStates.wallpaperManager.getLockscreenFramePath(GlobalStates.wallpaperManager.currentWallpaper) : ""
                    source: lfp ? "file://" + lfp : ""
                    visible: !bgCap.hasContent || !GlobalStates.overviewOpen
                }

                // ── Window cards: positioned by % of monitor ──
                Repeater {
                    model: cellWindows

                    Item {
                        required property var modelData
                        readonly property var win: modelData
                        readonly property var mon: overviewRoot.monMap[String(win.monitor)]

                        // Window position & size as fraction of its monitor
                        // Note: hyprctl reports at[] in logical coords but size[]
                        // in physical coords when scale != 1.0. We multiply
                        // size by scale to normalize to logical coordinates.
                        readonly property real _monScale: mon ? (mon.scale || 1.0) : 1.0
                        readonly property real monW: mon ? (mon.width || 1920) : 1920
                        readonly property real monH: mon ? (mon.height || 1080) : 1080
                        readonly property real relX: monW > 0 ? ((win.at?.[0] || 0) - (mon?.x || 0)) / monW : 0
                        readonly property real relY: monH > 0 ? ((win.at?.[1] || 0) - (mon?.y || 0)) / monH : 0
                        readonly property real relW: monW > 0 ? Math.max(0.05, Math.min(1, ((win.size?.[0] || 100) * _monScale) / monW)) : 0.85
                        readonly property real relH: monH > 0 ? Math.max(0.05, Math.min(1, ((win.size?.[1] || 100) * _monScale) / monH)) : 0.85

                        // Fill to neighbor: expand until hitting another window edge
                        readonly property real fillW: {
                            var base = relW;
                            var r = relX + relW;
                            var others = cellWindows;
                            for (var i = 0; i < others.length; i++) {
                                if (others[i].address === win.address) continue;
                                var ox = ((others[i].at?.[0] || 0) - (mon?.x || 0)) / monW;
                                var oy = ((others[i].at?.[1] || 0) - (mon?.y || 0)) / monH;
                                var ow = Math.max(0.05, ((others[i].size?.[0] || 100) * _monScale) / monW);
                                var oh = Math.max(0.05, ((others[i].size?.[1] || 100) * _monScale) / monH);
                                if (ox > relX && oy < relY + relH && oy + oh > relY)
                                    r = Math.min(r, ox);
                            }
                            return Math.max(base, r - relX);
                        }
                        readonly property real fillH: {
                            var base = relH;
                            var b = relY + relH;
                            var others = cellWindows;
                            for (var i = 0; i < others.length; i++) {
                                if (others[i].address === win.address) continue;
                                var ox = ((others[i].at?.[0] || 0) - (mon?.x || 0)) / monW;
                                var oy = ((others[i].at?.[1] || 0) - (mon?.y || 0)) / monH;
                                var ow = Math.max(0.05, ((others[i].size?.[0] || 100) * _monScale) / monW);
                                var oh = Math.max(0.05, ((others[i].size?.[1] || 100) * _monScale) / monH);
                                if (oy > relY && ox < relX + relW && ox + ow > relX)
                                    b = Math.min(b, oy);
                            }
                            return Math.max(base, b - relY);
                        }

                        readonly property real cardX: Math.round(relX * wsCellW)
                        readonly property real cardY: Math.round(relY * wsCellH)
                        readonly property real cardW: Math.max(12, Math.round(fillW * wsCellW))
                        readonly property real cardH: Math.max(12, Math.round(fillH * wsCellH))

                        readonly property string cls: win.class || ""
                        readonly property string addr: win.address || ""
                        readonly property string title: win.title || cls

                        x: cardX; y: cardY
                        z: 1
                        width: cardW; height: cardH

                        // ── Live per-window preview via WlrToplevelMapper ──
                        readonly property var toplevel: WlrToplevelMapper ? WlrToplevelMapper.find(cls, title) : null

                        // Card background
                        Rectangle {
                            anchors.fill: parent
                            radius: Styling.radius(-2)
                            color: Qt.rgba(Colors.surfaceContainer.r, Colors.surfaceContainer.g, Colors.surfaceContainer.b, 0.45)
                            border.color: Qt.rgba(Colors.onSurface.r, Colors.onSurface.g, Colors.onSurface.b, 0.15)
                            border.width: 1

                            // Accent strip
                            Rectangle {
                                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                height: Math.max(2, Math.round(parent.height * 0.04))
                                color: overviewRoot.colorForClass(cls); radius: parent.radius
                            }

                            // Gradient overlay for depth
                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                gradient: Gradient {
                                    orientation: Gradient.Diagonal
                                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.03) }
                                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.12) }
                                }
                            }
                        }

                        // ── Live window preview (when Toplevel available) ──
                        Loader {
                            anchors.fill: parent
                            active: Config.performance.windowPreview && toplevel != null
                            visible: status === Loader.Ready
                            asynchronous: true

                            sourceComponent: ClippingRectangle {
                                anchors.fill: parent
                                radius: Styling.radius(-2)
                                antialiasing: true
                                color: "transparent"

                                ScreencopyView {
                                    id: winPreview
                                    width: Math.max(1, win.size?.[0] || 640)
                                    height: Math.max(1, win.size?.[1] || 480)
                                    captureSource: toplevel
                                    live: GlobalStates.overviewOpen

                                    transform: Scale {
                                        origin.x: 0; origin.y: 0
                                        xScale: parent.width / winPreview.width
                                        yScale: parent.height / winPreview.height
                                    }
                                }

                                // Dim overlay so text is readable
                                Rectangle {
                                    anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.15)
                                }
                            }
                        }

                        // ── Grim fallback screenshot (when no live preview) ──
                        Image {
                            id: grimShot
                            anchors.fill: parent
                            source: (Config.performance.windowPreview && toplevel == null)
                                ? WlrToplevelMapper.screenshotPath(addr) : ""
                            sourceSize: Qt.size(parent.width, parent.height)
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            visible: status === Image.Ready && toplevel == null
                            opacity: 0.5
                        }

                        // ── App icon (shown when no live preview AND no grim) ──
                        Image {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: Math.round(-parent.height * 0.02)
                            width: Math.round(Math.min(parent.width, parent.height) * 0.30)
                            height: width
                            source: Quickshell.iconPath(overviewRoot.iconForClass(cls), "image-missing")
                            sourceSize: Qt.size(width, height)
                            asynchronous: true
                            opacity: 0.6
                            visible: (!Config.performance.windowPreview || toplevel == null) && (!grimShot.visible || grimShot.status !== Image.Ready)
                        }

                        // ── Window title ──
                        Text {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Math.max(1, Math.round(parent.height * 0.02))
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.leftMargin: Math.max(1, Math.round(parent.width * 0.02))
                            anchors.rightMargin: Math.max(1, Math.round(parent.width * 0.02))
                            text: title
                            font.family: Config.theme.font
                            font.pixelSize: Math.max(5, Math.round(parent.height * 0.07))
                            color: Colors.onSurface
                            opacity: 0.5
                            elide: Text.ElideRight; maximumLineCount: 1
                            horizontalAlignment: Text.AlignHCenter
                            visible: parent.height > 35
                        }

                        // ── Dim original during drag ──
                        Rectangle {
                            anchors.fill: parent
                            radius: Styling.radius(-2)
                            color: overviewRoot.isDragging && overviewRoot.dragWindowAddr === addr
                                ? Qt.rgba(0, 0, 0, 0.4) : "transparent"
                            z: 5
                            Behavior on color {
                                enabled: Anim.animationsEnabled
                                ColorAnimation { duration: 120 }
                            }
                        }

                        // ── Interaction: click, drag, close ──
                        MouseArea {
                            id: cardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                            cursorShape: containsMouse ? Qt.PointingHandCursor : Qt.ArrowCursor

                            property bool _holding: false
                            property bool _dragging: false
                            property real _startX: 0
                            property real _startY: 0
                            property real _ghostOffX: 0
                            property real _ghostOffY: 0

                            Timer {
                                id: holdTimer
                                interval: 120
                                onTriggered: {
                                    if (cardMouse._holding && !cardMouse._dragging) {
                                        cardMouse._dragging = true;
                                        overviewRoot.isDragging = true;
                                        overviewRoot.dragFromWorkspace = wsNum;
                                        overviewRoot.dragWindowAddr = addr;
                                        overviewRoot.dragGhostCls = cls;
                                        overviewRoot.dragGhostTitle = title;
                                        overviewRoot.dragGhostAddr = addr;
                                        overviewRoot.dragGhostW = cardW;
                                        overviewRoot.dragGhostH = cardH;
                                        // Ghost initial position at card's location
                                        overviewRoot.dragGhostX = cell.x + cardX + gridContainer.x;
                                        overviewRoot.dragGhostY = cell.y + cardY + gridContainer.y;
                                    }
                                }
                            }

                            onPressed: mouse => {
                                if (mouse.button === Qt.LeftButton) {
                                    // Reset any stale drag state
                                    cardMouse._dragging = false;
                                    cardMouse._holding = true;
                                    cardMouse._startX = mouse.x;
                                    cardMouse._startY = mouse.y;
                                    holdTimer.restart();
                                } else if (mouse.button === Qt.RightButton) {
                                    AxctlService.dispatch("closewindow address:" + addr);
                                }
                            }

                            onMouseXChanged: {
                                if (cardMouse._holding && !cardMouse._dragging) {
                                    var dx = cardMouse.mouseX - cardMouse._startX;
                                    var dy = cardMouse.mouseY - cardMouse._startY;
                                    if (Math.sqrt(dx*dx + dy*dy) > 12) {
                                        holdTimer.stop();
                                        cardMouse._holding = false;
                                    }
                                }
                            }

                            onMouseYChanged: {
                                if (cardMouse._holding && !cardMouse._dragging) {
                                    var dx = cardMouse.mouseX - cardMouse._startX;
                                    var dy = cardMouse.mouseY - cardMouse._startY;
                                    if (Math.sqrt(dx*dx + dy*dy) > 12) {
                                        holdTimer.stop();
                                        cardMouse._holding = false;
                                    }
                                }
                            }

                            // Initial position capture when drag starts
                            onPositionChanged: {
                                if (cardMouse._dragging) {
                                    // Find target cell from mouse position
                                    var gridX = cardMouse.mouseX + cardX + cell.x;
                                    var gridY = cardMouse.mouseY + cardY + cell.y;
                                    var cw = wsCellW + workspaceSpacing;
                                    var ch = wsCellH + workspaceSpacing;
                                    var col = Math.floor((gridX - workspacePadding) / cw);
                                    var row = Math.floor((gridY - workspacePadding) / ch);
                                    if (col >= 0 && col < columns && row >= 0 && row < rows) {
                                        var target = row * columns + col + 1;
                                        if (target !== overviewRoot.dragToWorkspace) {
                                            overviewRoot.dragToWorkspace = target;
                                        }
                                    } else {
                                        overviewRoot.dragToWorkspace = -1;
                                    }
                                }
                            }

                            onReleased: mouse => {
                                if (mouse.button === Qt.LeftButton) {
                                    holdTimer.stop();
                                    if (cardMouse._dragging) {
                                        // Drop: dispatch move to target workspace
                                        var targetWs = overviewRoot.dragToWorkspace;
                                        var origWs = overviewRoot.dragFromWorkspace;
                                        var dragAddr = overviewRoot.dragWindowAddr;

                                        cardMouse._dragging = false;
                                        cardMouse._holding = false;
                                        overviewRoot.isDragging = false;
                                        overviewRoot.dragToWorkspace = -1;
                                        overviewRoot.dragFromWorkspace = -1;
                                        overviewRoot.dragWindowAddr = "";

                                        if (targetWs > 0 && targetWs !== origWs && dragAddr) {
                                            AxctlService.dispatch("movetoworkspacesilent " + targetWs + ",address:" + dragAddr);
                                            Qt.callLater(function() {
                                                if (!clientProcess.running) clientProcess.running = true;
                                                if (!monProcess.running) monProcess.running = true;
                                            });
                                        }
                                    } else if (cardMouse._holding) {
                                        // Quick click: focus + switch
                                        Visibilities.setActiveModule("", true);
                                        Qt.callLater(function() {
                                            AxctlService.dispatch("focuswindow address:" + addr);
                                            wsSwitchProcess.command = ["hyprctl", "dispatch", "workspace", String(wsNum)];
                                            wsSwitchProcess.running = true;
                                        });
                                        cardMouse._holding = false;
                                    }
                                } else if (mouse.button === Qt.MiddleButton || mouse.button === Qt.RightButton) {
                                    AxctlService.dispatch("closewindow address:" + addr);
                                }
                            }
                        }
                    }
                }

                // ── Drop target highlight ──
                Rectangle {
                    anchors.fill: parent
                    radius: Styling.radius(2)
                    color: "transparent"
                    border.color: overviewRoot.dragToWorkspace === wsNum ? Colors.primary : "transparent"
                    border.width: overviewRoot.dragToWorkspace === wsNum ? 3 : 0
                    opacity: overviewRoot.dragToWorkspace === wsNum ? 0.7 : 0
                    z: 10
                    Behavior on opacity {
                        enabled: Anim.animationsEnabled
                        NumberAnimation { duration: 100 }
                    }
                    Behavior on border.width {
                        enabled: Anim.animationsEnabled
                        NumberAnimation { duration: 100 }
                    }
                }

                // ── Workspace number ──
                Text {
                    anchors.right: parent.right; anchors.bottom: parent.bottom
                    anchors.margins: 4
                    text: String(wsNum)
                    font.family: Config.theme.font
                    font.pixelSize: Math.max(10, Math.round(wsCellH * 0.08))
                    font.bold: true; color: Colors.onSurface; opacity: 0.2; z: 5
                }

                // ── Cell click: empty space below window cards ──
                // Rendered last = highest visual stacking.
                // Window cards sit on top because they're in a Repeater child.
                // Clicks on empty space reach here since no card covers them.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    enabled: !overviewRoot.isDragging
                    z: -1
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
            }
        }

    }

    // ── Drag ghost card (outside gridContainer, at overviewRoot level) ──
    Item {
        id: dragGhost
        visible: overviewRoot.isDragging && overviewRoot.dragGhostAddr.length > 0
        z: 9999
        x: overviewRoot.dragGhostX
        y: overviewRoot.dragGhostY
        width: overviewRoot.dragGhostW
        height: overviewRoot.dragGhostH

        Behavior on x {
            enabled: Anim.animationsEnabled
            SpringAnimation { spring: 2.5; damping: 0.22; mass: 0.35 }
        }
        Behavior on y {
            enabled: Anim.animationsEnabled
            SpringAnimation { spring: 2.5; damping: 0.22; mass: 0.35 }
        }

        Rectangle {
            anchors.fill: parent
            radius: Styling.radius(-2)
            color: Qt.rgba(Colors.surfaceContainer.r, Colors.surfaceContainer.g, Colors.surfaceContainer.b, 0.7)
            border.color: Styling.srItem("overprimary")
            border.width: 2

            Rectangle {
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                height: Math.max(2, Math.round(parent.height * 0.04))
                color: overviewRoot.colorForClass(overviewRoot.dragGhostCls)
                radius: parent.radius
            }

            Image {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: Math.round(-parent.height * 0.02)
                width: Math.round(Math.min(parent.width, parent.height) * 0.30)
                height: width
                source: Quickshell.iconPath(overviewRoot.iconForClass(overviewRoot.dragGhostCls), "image-missing")
                sourceSize: Qt.size(width, height)
                asynchronous: true; opacity: 0.7
            }

            Text {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.max(1, Math.round(parent.height * 0.02))
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: 2; anchors.rightMargin: 2
                text: overviewRoot.dragGhostTitle
                font.family: Config.theme.font
                font.pixelSize: Math.max(5, Math.round(parent.height * 0.07))
                color: Colors.onSurface; opacity: 0.6
                elide: Text.ElideRight; maximumLineCount: 1
                horizontalAlignment: Text.AlignHCenter
                visible: parent.height > 35
            }
        }
    }

    // ── Global drag tracker at ROOT level (position tracking solo) ──
    // The release is handled by the card's onReleased (it has the press grab).
    MouseArea {
        id: dragTracker
        anchors.fill: parent
        enabled: overviewRoot.isDragging
        acceptedButtons: Qt.NoButton  // Don't grab, just track hover
        hoverEnabled: true
        z: 9998
        cursorShape: Qt.ClosedHandCursor

        onPositionChanged: mouse => {
            if (!overviewRoot.isDragging) return;
            // Ghost follows mouse
            overviewRoot.dragGhostX = mouse.x - overviewRoot.dragGhostW / 2;
            overviewRoot.dragGhostY = mouse.y - overviewRoot.dragGhostH / 2;

            // Target cell from grid-relative position
            var gx = mouse.x - gridContainer.x;
            var gy = mouse.y - gridContainer.y;
            var cw = overviewRoot.wsCellW + overviewRoot.workspaceSpacing;
            var ch = overviewRoot.wsCellH + overviewRoot.workspaceSpacing;
            var col = Math.floor((gx - overviewRoot.workspacePadding) / cw);
            var row = Math.floor((gy - overviewRoot.workspacePadding) / ch);
            if (col >= 0 && col < overviewRoot.columns && row >= 0 && row < overviewRoot.rows) {
                var target = row * overviewRoot.columns + col + 1;
                if (target !== overviewRoot.dragToWorkspace) {
                    overviewRoot.dragToWorkspace = target;
                }
            } else {
                overviewRoot.dragToWorkspace = -1;
            }
        }
    }
}
