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
                // Exposed for dragTracker.findCardAt()
                property var windowCards: []

                x: col * (wsCellW + workspaceSpacing) + workspacePadding
                y: row * (wsCellH + workspaceSpacing) + workspacePadding
                width: wsCellW
                height: wsCellH
                color: Qt.rgba(Colors.surfaceContainer.r, Colors.surfaceContainer.g, Colors.surfaceContainer.b, 0.12)
                radius: Styling.radius(2)
                clip: !overviewRoot.isDragging

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
                            var r = 1.0; // stretch to right edge of monitor
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
                            var b = 1.0; // stretch to bottom edge of monitor
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

                        // Expose card info for the root dragTracker
                        property bool _isCard: true
                        property var _cardData: ({ wsNum: wsNum, addr: addr, cls: cls, title: title, cardW: cardW, cardH: cardH, cardX: cardX, cardY: cardY, cellX: cell.x, cellY: cell.y })
                        // Register with parent cell for dragTracker lookup
                        Component.onCompleted: {
                            var arr = cell.windowCards;
                            if (arr.indexOf) {
                                arr.push(root);
                                cell.windowCards = arr;
                            }
                        }

                        // Drag override: when active, x/y follow mouse instead of grid
                        property bool _dragActive: false
                        property real _dragOverrideX: 0
                        property real _dragOverrideY: 0
                        x: _dragActive ? _dragOverrideX : cardX
                        y: _dragActive ? _dragOverrideY : cardY
                        z: _dragActive ? 9999 : 1
                        scale: _dragActive ? 1.04 : 1.0

                        Behavior on scale {
                            enabled: Anim.animationsEnabled
                            SpringAnimation { spring: 4.0; damping: 0.35; mass: 0.3 }
                        }
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

            }
        }

    }

    // ── Drag overlay (inactivo: la card se mueve por si misma) ──
    Item {
        id: dragOverlay
        visible: false
        z: 9999
    }

    // ── SINGLE MouseArea: handles ALL interactions ──
    // Finds cards via childAt + _isCard property walk.
    // No mouse event conflicts because this is the only MouseArea.
    MouseArea {
        id: dragTracker
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        hoverEnabled: true
        z: 9998
        cursorShape: overviewRoot.isDragging ? Qt.ClosedHandCursor : Qt.ArrowCursor

        // Find card at mouse position by iterating visible cards in the grid
        function findCardAt(mx, my) {
            // Convert root coords to grid-relative
            var gx = mx - gridContainer.x;
            var gy = my - gridContainer.y;

            // Iterate all workspaces to find cards
            for (var ws = 1; ws <= overviewRoot.workspacesShown; ws++) {
                var cellEl = gridContainer.children.find(function(c) {
                    return c.wsNum === ws;
                });
                if (!cellEl) continue;

                // Convert grid coords to cell-relative
                var cx = gx - cellEl.x;
                var cy = gy - cellEl.y;

                // Iterate card children of this cell
                var cardItems = cellEl.windowCards;
                if (!cardItems) continue;
                for (var ci = 0; ci < cardItems.length; ci++) {
                    var card = cardItems[ci];
                    if (!card._isCard) continue;
                    // Check if mouse is within this card's bounds
                    if (cx >= card.x && cx <= card.x + card.width &&
                        cy >= card.y && cy <= card.y + card.height) {
                        return card;
                    }
                }
            }
            return null;
        }

        // ── Press: detect card, start hold timer ──
        property var _pendingCard: null
        property var _pendingData: null
        property bool _holding: false
        property bool _dragging: false

        Timer {
            id: holdTimer
            interval: 120
            onTriggered: {
                if (dragTracker._holding && !dragTracker._dragging) {
                    dragTracker._dragging = true;
                    var d = dragTracker._pendingData;
                    var card = dragTracker._pendingCard;
                    if (!d || !card) return;

                    // Activate card override: card moves freely
                    card._dragActive = true;
                    card._dragOverrideX = d.cardX;
                    card._dragOverrideY = d.cardY;

                    overviewRoot.isDragging = true;
                    overviewRoot.dragFromWorkspace = d.wsNum;
                    overviewRoot.dragWindowAddr = d.addr;
                    overviewRoot.dragGhostCls = d.cls;
                    overviewRoot.dragGhostTitle = d.title;
                    overviewRoot.dragGhostAddr = d.addr;
                    overviewRoot.dragGhostW = d.cardW;
                    overviewRoot.dragGhostH = d.cardH;
                    overviewRoot.dragGhostX = d.cardX;
                    overviewRoot.dragGhostY = d.cardY;
                }
            }
        }

        // Helper: find workspace number from root-level coordinates
        function wsAt(mx, my) {
            var gx = mx - gridContainer.x;
            var gy = my - gridContainer.y;
            var cw = overviewRoot.wsCellW + overviewRoot.workspaceSpacing;
            var ch = overviewRoot.wsCellH + overviewRoot.workspaceSpacing;
            var col = Math.floor((gx - overviewRoot.workspacePadding) / cw);
            var row = Math.floor((gy - overviewRoot.workspacePadding) / ch);
            if (col >= 0 && col < overviewRoot.columns && row >= 0 && row < overviewRoot.rows) {
                return row * overviewRoot.columns + col + 1;
            }
            return -1;
        }

        onPressed: mouse => {
            var card = findCardAt(mouse.x, mouse.y);

            if (card) {
                dragTracker._pendingCard = card;
                dragTracker._pendingData = card._cardData;
                dragTracker._holding = true;
                dragTracker._startX = mouse.x;
                dragTracker._startY = mouse.y;
                holdTimer.restart();
            } else {
                dragTracker._holding = false;
                dragTracker._pendingCard = null;
                dragTracker._pendingData = null;
            }
        }

        onReleased: mouse => {
            holdTimer.stop();

            if (dragTracker._dragging) {
                var targetWs = overviewRoot.dragToWorkspace;
                var origWs = overviewRoot.dragFromWorkspace;
                var dragAddr = overviewRoot.dragWindowAddr;
                var card = dragTracker._pendingCard;

                // Reset card override
                if (card) {
                    card._dragActive = false;
                }

                dragTracker._dragging = false;
                dragTracker._holding = false;
                dragTracker._pendingCard = null;
                dragTracker._pendingData = null;
                overviewRoot.isDragging = false;
                overviewRoot.dragToWorkspace = -1;
                overviewRoot.dragFromWorkspace = -1;
                overviewRoot.dragWindowAddr = "";

                if (targetWs > 0 && targetWs !== origWs && dragAddr) {
                    AxctlService.dispatch("movetoworkspacesilent " + targetWs + ",address:" + dragAddr);
                }

                Qt.callLater(function() {
                    if (!clientProcess.running) clientProcess.running = true;
                    if (!monProcess.running) monProcess.running = true;
                });

            } else if (dragTracker._holding && mouse.button === Qt.LeftButton) {
                var d = dragTracker._pendingData;
                if (d && d.addr) {
                    Visibilities.setActiveModule("", true);
                    Qt.callLater(function() {
                        AxctlService.dispatch("focuswindow address:" + d.addr);
                        wsSwitchProcess.command = ["hyprctl", "dispatch", "workspace", String(d.wsNum)];
                        wsSwitchProcess.running = true;
                    });
                }

            } else if (mouse.button === Qt.MiddleButton || mouse.button === Qt.RightButton) {
                var card = findCardAt(mouse.x, mouse.y);
                if (card && card._cardData && card._cardData.addr) {
                    AxctlService.dispatch("closewindow address:" + card._cardData.addr);
                }

            } else if (mouse.button === Qt.LeftButton && !dragTracker._holding) {
                var ws = dragTracker.wsAt(mouse.x, mouse.y);
                if (ws > 0) {
                    wsSwitchProcess.command = ["hyprctl", "dispatch", "workspace", String(ws)];
                    wsSwitchProcess.running = true;
                }
            }

            dragTracker._holding = false;
            dragTracker._pendingCard = null;
            dragTracker._pendingData = null;
        }

        // Cancel hold on significant movement
        property real _startX: 0
        property real _startY: 0

        onPositionChanged: mouse => {
            if (dragTracker._dragging) {
                var card = dragTracker._pendingCard;
                var d = dragTracker._pendingData;
                if (card && d) {
                    // Card override position: mouse relative to cell, centered
                    var mx = mouse.x - gridContainer.x - d.cellX;
                    var my = mouse.y - gridContainer.y - d.cellY;
                    card._dragOverrideX = mx - d.cardW / 2;
                    card._dragOverrideY = my - d.cardH / 2;
                }

                // Ghost position for overlay (if used as fallback)
                overviewRoot.dragGhostX = mouse.x - overviewRoot.dragGhostW / 2;
                overviewRoot.dragGhostY = mouse.y - overviewRoot.dragGhostH / 2;

                // Target cell
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
            } else if (dragTracker._holding && !dragTracker._dragging) {
                var dx = mouse.x - dragTracker._startX;
                var dy = mouse.y - dragTracker._startY;
                if (Math.sqrt(dx*dx + dy*dy) > 15) {
                    holdTimer.stop();
                    dragTracker._holding = false;
                    dragTracker._pendingCard = null;
                    dragTracker._pendingData = null;
                }
            }
        }
    }
}
