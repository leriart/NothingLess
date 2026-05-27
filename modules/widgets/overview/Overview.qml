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

    // ── Direct window data from hyprctl ──
    property var rawWindows: []

    Process {
        id: clientProcess
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var raw = JSON.parse(text);
                    if (Array.isArray(raw)) {
                        overviewRoot.rawWindows = raw;
                    }
                } catch (e) {}
            }
        }
    }

    // Refresh window list periodically while overview is open
    Timer {
        id: refreshTimer
        interval: 600
        running: GlobalStates.overviewOpen
        repeat: true
        onTriggered: {
            if (!clientProcess.running)
                clientProcess.running = true;
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

    // Workspace cell size — fills available space manteniendo 16:9
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

    function windowsForWs(wsNum) {
        var arr = overviewRoot.windowsByWs[String(wsNum)];
        return arr || [];
    }

    function iconForClass(cls) {
        return AppSearch.guessIcon(cls || "");
    }

    // Accent color from class
    function colorForClass(cls) {
        var c = (cls || "").toLowerCase();
        var hash = 0;
        for (var i = 0; i < c.length; i++) hash = ((hash << 5) - hash) + c.charCodeAt(i);
        var hue = ((hash % 360) + 360) % 360;
        return Qt.hsla(hue / 360, 0.5, 0.4, 1.0);
    }

    // ── Force refresh when overview opens ──
    property int _refreshCount: 0

    Timer {
        id: openRefreshTimer
        interval: 200
        running: GlobalStates.overviewOpen && _refreshCount < 8
        repeat: true
        onTriggered: {
            if (!clientProcess.running)
                clientProcess.running = true;
            _refreshCount++;
        }
    }

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen) {
                _refreshCount = 0;
                if (!clientProcess.running)
                    clientProcess.running = true;
            }
        }
    }

    // ── LAYOUT ──
    Component.onCompleted: {
        if (!clientProcess.running)
            clientProcess.running = true;
    }

    Item {
        id: gridContainer
        anchors.centerIn: parent
        width: gridTotalW
        height: gridTotalH

        // Workspace cells
        Repeater {
            model: workspacesShown

            Rectangle {
                id: cell
                required property int index
                readonly property int wsNum: index + 1
                readonly property int col: index % columns
                readonly property int row: Math.floor(index / columns)
                readonly property var cellWindows: overviewRoot.windowsForWs(wsNum)
                readonly property int staggerDelay: (row * columns + col) * 40

                x: col * (wsCellW + workspaceSpacing) + workspacePadding
                y: row * (wsCellH + workspaceSpacing) + workspacePadding
                width: wsCellW
                height: wsCellH
                color: Qt.rgba(Colors.surfaceContainer.r, Colors.surfaceContainer.g, Colors.surfaceContainer.b, 0.15)
                radius: Styling.radius(2)
                border.width: 0
                clip: true

                // Staggered entrance
                opacity: 0
                scale: 0.85
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

                // Wallpaper thumbnail
                TintedWallpaper {
                    anchors.fill: parent; radius: Styling.radius(2)
                    tintEnabled: GlobalStates.wallpaperManager ? GlobalStates.wallpaperManager.tintEnabled : false
                    property string lfp: GlobalStates.wallpaperManager ? GlobalStates.wallpaperManager.getLockscreenFramePath(GlobalStates.wallpaperManager.currentWallpaper) : ""
                    source: lfp ? "file://" + lfp : ""
                }

                // ── Window cards dentro del cell ──
                Repeater {
                    model: cellWindows

                    Rectangle {
                        required property var modelData
                        readonly property var win: modelData
                        readonly property var winSize: win.size || [100, 100]
                        readonly property var winAt: win.at || [0, 0]
                        readonly property int winW: winSize[0]
                        readonly property int winH: winSize[1]
                        readonly property string cls: win.class || ""
                        readonly property string title: win.title || cls

                        // Scale window to fit inside cell manteniendo proporcion
                        readonly property real scaleX: wsCellW / winW
                        readonly property real scaleY: wsCellH / winH
                        readonly property real fitScale: Math.min(scaleX, scaleY) * 0.9
                        readonly property real cardW: Math.round(winW * fitScale)
                        readonly property real cardH: Math.round(winH * fitScale)
                        readonly property real posX: {
                            var mx = 0;
                            if (cellWindows.length <= 1) return (wsCellW - cardW) / 2;
                            return Math.round((winAt[0] / (1920)) * wsCellW * 0.7) + wsCellW * 0.15;
                        }
                        readonly property real posY: {
                            if (cellWindows.length <= 1) return (wsCellH - cardH) / 2;
                            return Math.round((winAt[1] / (1080)) * wsCellH * 0.7) + wsCellH * 0.15;
                        }

                        x: posX
                        y: posY
                        width: cardW
                        height: cardH
                        radius: Styling.radius(-2)
                        color: Qt.rgba(Colors.surfaceContainer.r, Colors.surfaceContainer.g, Colors.surfaceContainer.b, 0.5)
                        border.color: Qt.rgba(Colors.onSurface.r, Colors.onSurface.g, Colors.onSurface.b, 0.12)
                        border.width: 1

                        // Accent strip
                        Rectangle {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: Math.max(2, Math.round(parent.height * 0.04))
                            color: overviewRoot.colorForClass(cls)
                            radius: parent.radius
                        }

                        // App icon
                        Image {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: Math.round(-parent.height * 0.03)
                            width: Math.round(parent.width * 0.35)
                            height: Math.round(parent.height * 0.35)
                            source: Quickshell.iconPath(overviewRoot.iconForClass(cls), "image-missing")
                            sourceSize: Qt.size(width, height)
                            asynchronous: true
                            opacity: 0.7
                        }

                        // Title
                        Text {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Math.max(1, Math.round(parent.height * 0.02))
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: Math.max(1, Math.round(parent.width * 0.02))
                            anchors.rightMargin: Math.max(1, Math.round(parent.width * 0.02))
                            text: title
                            font.family: Config.theme.font
                            font.pixelSize: Math.max(5, Math.round(parent.height * 0.08))
                            color: Colors.onSurface
                            opacity: 0.6
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            horizontalAlignment: Text.AlignHCenter
                            visible: parent.height > 40
                        }
                    }
                }

                // Workspace number
                Text {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 4
                    text: String(wsNum)
                    font.family: Config.theme.font
                    font.pixelSize: Math.max(10, Math.round(wsCellH * 0.08))
                    font.bold: true
                    color: Colors.onSurface
                    opacity: 0.25
                    z: 5
                }

                // Click → switch
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
