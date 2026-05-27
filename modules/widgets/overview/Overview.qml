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
            }
        }
    }

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
                        readonly property real monW: mon ? (mon.width || 1920) : 1920
                        readonly property real monH: mon ? (mon.height || 1080) : 1080
                        readonly property real relX: monW > 0 ? ((win.at?.[0] || 0) - (mon?.x || 0)) / monW : 0
                        readonly property real relY: monH > 0 ? ((win.at?.[1] || 0) - (mon?.y || 0)) / monH : 0
                        readonly property real relW: monW > 0 ? Math.max(0.05, Math.min(1, (win.size?.[0] || 100) / monW)) : 0.85
                        readonly property real relH: monH > 0 ? Math.max(0.05, Math.min(1, (win.size?.[1] || 100) / monH)) : 0.85

                        // Fill to neighbor algorithm: expand until hitting another window edge
                        readonly property real fillW: {
                            var base = relW;
                            var r = relX + relW;
                            var others = cellWindows;
                            for (var i = 0; i < others.length; i++) {
                                if (others[i].address === win.address) continue;
                                var ox = ((others[i].at?.[0] || 0) - (mon?.x || 0)) / monW;
                                var oy = ((others[i].at?.[1] || 0) - (mon?.y || 0)) / monH;
                                var ow = (others[i].size?.[0] || 100) / monW;
                                var oh = (others[i].size?.[1] || 100) / monH;
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
                                var ow = (others[i].size?.[0] || 100) / monW;
                                var oh = (others[i].size?.[1] || 100) / monH;
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

                        // ── App icon (shown when no live preview) ──
                        Image {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: Math.round(-parent.height * 0.02)
                            width: Math.round(Math.min(parent.width, parent.height) * 0.30)
                            height: width
                            source: Quickshell.iconPath(overviewRoot.iconForClass(cls), "image-missing")
                            sourceSize: Qt.size(width, height)
                            asynchronous: true
                            opacity: 0.6
                            visible: !Config.performance.windowPreview || toplevel == null
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

                        // ── Address debug (small) ──
                        // Uncomment for debugging
                        // Text {
                        //     anchors.top: parent.top; anchors.right: parent.right
                        //     anchors.margins: 2
                        //     text: addr.substring(addr.length-8)
                        //     font.pixelSize: 6; color: Colors.onSurface; opacity: 0.3
                        // }

                        // ── Interaction ──
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

                            onClicked: mouse => {
                                if (mouse.button === Qt.LeftButton) {
                                    Visibilities.setActiveModule("", true);
                                    Qt.callLater(function() {
                                        AxctlService.dispatch("focuswindow address:" + addr);
                                        wsSwitchProcess.command = ["hyprctl", "dispatch", "workspace", String(wsNum)];
                                        wsSwitchProcess.running = true;
                                    });
                                } else if (mouse.button === Qt.MiddleButton) {
                                    AxctlService.dispatch("closewindow address:" + addr);
                                }
                            }
                        }
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

                // ── Click cell (empty space) ──
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
            }
        }
    }
}
