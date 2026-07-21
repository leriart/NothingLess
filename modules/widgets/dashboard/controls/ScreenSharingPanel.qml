pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

/*!
    ScreenSharingPanel — Complete Miracast control surface for NothingLess.

    Front-end over the [Mirai](https://github.com/leriart/Mirai) daemon. All
    discovery, streaming, and rendering is handled by the daemon; this panel
    is just the UI and the IPC layer.

    Sections, in order:
      1. Daemon header   — start, refresh, restart, view logs.
      2. Error banner    — only when something is wrong.
      3. Source (Cast)   — pick a display, scan for sinks, connect/disconnect.
      4. Sink (Receive)  — make this PC a Miracast display, set mode.
      5. Logs            — collapsible, recent daemon activity.
      6. Install hint    — only when mirai is missing.
      7. Footer          — docs / version line.

    The panel re-uses the StyledRect/Anim palette; all popups use the
    shell's popup variant, all chips use common/focus/primary variants.
*/
Item {
    id: root

    property int maxContentWidth: 620
    readonly property int contentWidth: Math.min(width, maxContentWidth)
    readonly property real sideMargin: (width - contentWidth) / 2

    property bool logsExpanded: false

    Component.onCompleted: {
        MiraiService.refreshStatus();
    }

    Flickable {
        id: mainFlickable
        anchors.fill: parent
        contentHeight: mainColumn.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: mainColumn
            x: root.sideMargin
            width: root.contentWidth
            spacing: 12

            // ── 1. Daemon header ────────────────────────────────────────
            StyledRect {
                variant: "pane"
                Layout.fillWidth: true
                Layout.preferredHeight: headerLayout.implicitHeight + 28
                radius: Styling.radius(0)
                enableShadow: true

                RowLayout {
                    id: headerLayout
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    // Animated status dot
                    Rectangle {
                        id: statusDot
                        width: 12; height: 12; radius: 6
                        color: {
                            if (!MiraiService.daemonAvailable) return Colors.outline;
                            if (MiraiService.lastError) return Colors.error;
                            if (MiraiService.streaming || MiraiService.receiving) return Colors.primary;
                            if (MiraiService.daemonRunning) return Colors.secondary;
                            return Colors.outline;
                        }
                        SequentialAnimation on opacity {
                            running: MiraiService.daemonRunning && !MiraiService.lastError
                                && (MiraiService.streaming || MiraiService.receiving)
                            loops: Animation.Infinite
                            NumberAnimation { from: 1.0; to: 0.35; duration: Anim.standardLarge; easing.type: Anim.easing("standard").type; easing.bezierCurve: Anim.easing("standard").bezierCurve || [] }
                            NumberAnimation { from: 0.35; to: 1.0; duration: Anim.standardLarge; easing.type: Anim.easing("standard").type; easing.bezierCurve: Anim.easing("standard").bezierCurve || [] }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: {
                                if (!MiraiService.daemonAvailable) return "Mirai is not installed";
                                if (MiraiService.lastError) return "Mirai error";
                                if (MiraiService.streaming) return "Casting to " + MiraiService.activeSinkName;
                                if (MiraiService.receiving) return "Receiving (" + MiraiService.sinkMode + ")";
                                if (MiraiService.daemonRunning) return "Mirai daemon is running";
                                return "Mirai daemon is stopped";
                            }
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            font.weight: Font.Medium
                            color: Colors.overBackground
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: {
                                if (!MiraiService.daemonAvailable)
                                    return "Install Mirai: github.com/leriart/Mirai";
                                if (MiraiService.daemonError)
                                    return MiraiService.daemonError;
                                if (MiraiService.daemonRunning && MiraiService.daemonVersion)
                                    return "v" + MiraiService.daemonVersion + " · socket: /tmp/mirai.sock";
                                if (MiraiService.daemonRunning)
                                    return "socket: /tmp/mirai.sock";
                                return "Click Start to bring the daemon up";
                            }
                            font.family: "Monospace"
                            font.pixelSize: Styling.fontSize(-3)
                            color: Colors.outline
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    // Action buttons
                    RowLayout {
                        spacing: 6
                        StyledRect {
                            visible: MiraiService.daemonAvailable && !MiraiService.daemonRunning
                            radius: Styling.radius(-3)
                            Layout.preferredHeight: 32
                            Layout.preferredWidth: 72
                            variant: "primary"
                            Text {
                                anchors.centerIn: parent
                                text: "Start"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Medium
                                color: Colors.overPrimary
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: MiraiService.startDaemon()
                            }
                        }
                        StyledRect {
                            visible: MiraiService.daemonRunning
                            radius: Styling.radius(-3)
                            Layout.preferredHeight: 32
                            Layout.preferredWidth: 72
                            variant: hover1.containsMouse ? "focus" : "common"
                            Text {
                                anchors.centerIn: parent
                                text: "Refresh"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                color: Colors.overBackground
                            }
                            MouseArea {
                                id: hover1
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: MiraiService.refreshStatus()
                            }
                        }
                        StyledRect {
                            visible: MiraiService.daemonRunning
                            radius: Styling.radius(-3)
                            Layout.preferredHeight: 32
                            Layout.preferredWidth: 72
                            variant: hover2.containsMouse ? "focus" : "common"
                            Text {
                                anchors.centerIn: parent
                                text: "Restart"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                color: Colors.overBackground
                            }
                            MouseArea {
                                id: hover2
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: MiraiService.restartDaemon()
                            }
                        }
                        StyledRect {
                            visible: MiraiService.daemonRunning
                            radius: Styling.radius(-3)
                            Layout.preferredHeight: 32
                            Layout.preferredWidth: 72
                            variant: hoverStop.containsMouse ? "error" : "common"
                            Text {
                                anchors.centerIn: parent
                                text: "Stop"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                color: hoverStop.containsMouse ? Colors.overError : Colors.overBackground
                            }
                            MouseArea {
                                id: hoverStop
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: MiraiService.stopDaemon()
                            }
                        }
                    }
                }
            }

            // ── 2. Error banner ─────────────────────────────────────────
            StyledRect {
                visible: MiraiService.lastError.length > 0
                variant: "error"
                Layout.fillWidth: true
                Layout.preferredHeight: errCol.implicitHeight + 24
                radius: Styling.radius(-1)
                ColumnLayout {
                    id: errCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 4
                    Text {
                        text: Icons.alert + "  " + MiraiService.lastError
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        font.weight: Font.Medium
                        color: Colors.overError
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Text {
                        text: "See the Logs section below for the full daemon output."
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-3)
                        color: Colors.overError
                        opacity: 0.7
                    }
                }
            }

            // ── 3. Source (Cast) ────────────────────────────────────────
            StyledRect {
                variant: "pane"
                Layout.fillWidth: true
                Layout.preferredHeight: sourceCol.implicitHeight + 28
                radius: Styling.radius(0)
                enableShadow: true

                ColumnLayout {
                    id: sourceCol
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    // Title row + status pill
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: Icons.broadcast + "  Cast screen"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            font.weight: Font.Medium
                            color: Colors.overBackground
                            Layout.fillWidth: true
                        }
                        StyledRect {
                            visible: MiraiService.streaming
                            radius: Styling.radius(-2)
                            Layout.preferredHeight: 22
                            Layout.preferredWidth: 80
                            variant: "primary"
                            Text {
                                anchors.centerIn: parent
                                text: "Streaming"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-3)
                                font.weight: Font.Medium
                                color: Styling.srItem("primary")
                            }
                        }
                    }

                    // Subtitle
                    Text {
                        text: "Like Windows Win+K: discover Miracast sinks on the local network and stream a chosen monitor. Backed by gnome-network-displays and the XDG Desktop Portal."
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.outline
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    // Status line
                    Text {
                        text: {
                            if (MiraiService.streaming) {
                                var name = MiraiService.activeSinkName || MiraiService.activeSinkId;
                                var disp = MiraiService.activeDisplay ? " · " + MiraiService.activeDisplay : "";
                                return "→ Streaming to " + name + disp;
                            }
                            if (MiraiService.sinks.length > 0) {
                                return MiraiService.sinks.length + " sink(s) discovered. Pick one below.";
                            }
                            return "Ready. Click Scan to discover sinks.";
                        }
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: MiraiService.streaming ? Colors.primary : Colors.outline
                        Layout.fillWidth: true
                    }

                    // Display picker
                    RowLayout {
                        spacing: 8
                        Layout.fillWidth: true
                        Text {
                            text: "Display"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            color: Colors.overBackground
                            Layout.preferredWidth: 60
                        }
                        ComboBox {
                            id: displayCombo
                            Layout.fillWidth: true
                            model: {
                                var arr = [{ name: "default" }];
                                if (MiraiService.displays && MiraiService.displays.length > 0) {
                                    for (var i = 0; i < MiraiService.displays.length; i++) {
                                        arr.push(MiraiService.displays[i]);
                                    }
                                }
                                return arr;
                            }
                            textRole: "name"
                            valueRole: "name"
                            currentIndex: {
                                if (MiraiService.preferredDisplay) {
                                    for (var i = 0; i < model.length; i++) {
                                        if (model[i].name === MiraiService.preferredDisplay) return i;
                                    }
                                }
                                return 0;
                            }
                            onActivated: (idx) => {
                                var d = model[idx];
                                if (d && d.name) {
                                    if (MiraiService.streaming) {
                                        // Live switch — the daemon supports it.
                                        MiraiService.setDisplay(d.name);
                                    } else {
                                        MiraiService.preferredDisplay = d.name;
                                    }
                                }
                            }
                        }
                        StyledRect {
                            radius: Styling.radius(-3)
                            Layout.preferredHeight: 28
                            Layout.preferredWidth: 28
                            variant: refreshDispMa.containsMouse ? "focus" : "common"
                            enabled: MiraiService.daemonRunning
                            Text {
                                anchors.centerIn: parent
                                text: Icons.arrowClockwise
                                font.family: Icons.font
                                font.pixelSize: Styling.fontSize(-1)
                                color: Colors.overBackground
                            }
                            MouseArea {
                                id: refreshDispMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: MiraiService.refreshStatus()
                            }
                        }
                    }

                    // Quick-cast: re-connect to the last sink in one click.
                    StyledRect {
                        visible: !MiraiService.streaming
                                 && MiraiService.preferredSinkId.length > 0
                                 && MiraiService.sinks.some(function(s) { return s.id === MiraiService.preferredSinkId; })
                        variant: "internalbg"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        radius: Styling.radius(-2)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        spacing: 8
                        Text {
                            text: Icons.clock + "  Last sink:"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            color: Colors.outline
                        }
                            Text {
                                text: {
                                    for (var i = 0; i < MiraiService.sinks.length; i++) {
                                        if (MiraiService.sinks[i].id === MiraiService.preferredSinkId) {
                                            return MiraiService.sinks[i].name || MiraiService.sinks[i].id;
                                        }
                                    }
                                    return MiraiService.preferredSinkId;
                                }
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Medium
                                color: Colors.overBackground
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            StyledRect {
                                radius: Styling.radius(-3)
                                Layout.preferredHeight: 24
                                Layout.preferredWidth: 80
                                variant: lastMa.containsMouse ? "primary" : "common"
                                Text {
                                    anchors.centerIn: parent
                                    text: "Re-cast"
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-3)
                                    color: lastMa.containsMouse ? Colors.overPrimary : Colors.overBackground
                                }
                                MouseArea {
                                    id: lastMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: MiraiService.connectToSink(MiraiService.preferredSinkId)
                                }
                            }
                        }
                    }

                    // Action row: scan / disconnect + status info
                    RowLayout {
                        spacing: 8
                        Layout.fillWidth: true

                        StyledRect {
                            id: scanBtn
                            radius: Styling.radius(-3)
                            Layout.preferredHeight: 32
                            Layout.preferredWidth: 110
                            enabled: MiraiService.daemonRunning && !MiraiService.scanning
                            variant: enabled ? "primary" : "common"
                            Text {
                                anchors.centerIn: parent
                                text: MiraiService.scanning
                                    ? "Scanning…"
                                    : (Icons.broadcast + "  Scan (10s)")
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Medium
                                color: scanBtn.enabled ? Colors.overPrimary : Colors.outline
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                enabled: scanBtn.enabled
                                onClicked: MiraiService.scanSinks(10)
                            }
                        }

                        Item { Layout.fillWidth: true }

                        StyledRect {
                            visible: MiraiService.streaming
                            radius: Styling.radius(-3)
                            Layout.preferredHeight: 32
                            Layout.preferredWidth: 110
                            variant: discMa.containsMouse ? "error" : "common"
                            Text {
                                anchors.centerIn: parent
                                text: Icons.stop + "  Disconnect"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Medium
                                color: discMa.containsMouse ? Colors.overError : Colors.error
                            }
                            MouseArea {
                                id: discMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: MiraiService.disconnect()
                            }
                        }
                    }

                    Text {
                        visible: MiraiService.lastScanTime.length > 0
                        text: "Last scan: " + MiraiService.lastScanTime
                              + (MiraiService.lastScanDurationMs > 0
                                 ? " (" + (MiraiService.lastScanDurationMs / 1000).toFixed(1) + "s)"
                                 : "")
                        font.family: "Monospace"
                        font.pixelSize: Styling.fontSize(-3)
                        color: Colors.outline
                    }

                    // Discovered sinks list
                    StyledRect {
                        visible: MiraiService.sinks.length > 0
                        variant: "internalbg"
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(220, sinkList.contentHeight + 12)
                        radius: Styling.radius(-2)
                        clip: true

                        ListView {
                            id: sinkList
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 4
                            clip: true
                            model: MiraiService.sinks
                            delegate: Rectangle {
                                id: sinkRow
                                required property var modelData
                                required property int index
                                width: ListView.view.width
                                height: 56
                                radius: Styling.radius(-3)
                                color: "transparent"

                                // Background on hover / streaming
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    radius: Styling.radius(-3)
                                    color: {
                                        if (MiraiService.streaming && MiraiService.activeSinkId === sinkRow.modelData.id)
                                            return Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.18);
                                        if (sinkRowMa.containsMouse)
                                            return Qt.rgba(Colors.outline.r, Colors.outline.g, Colors.outline.b, 0.12);
                                        return "transparent";
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    Text {
                                        text: Icons.monitor
                                        font.family: Icons.font
                                        font.pixelSize: Styling.fontSize(2)
                                        color: {
                                            if (MiraiService.streaming && MiraiService.activeSinkId === sinkRow.modelData.id)
                                                return Colors.primary;
                                            return Colors.overBackground;
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Text {
                                            text: sinkRow.modelData.name || sinkRow.modelData.id || "Unknown sink"
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-1)
                                            font.weight: Font.Medium
                                            color: Colors.overBackground
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: {
                                                var parts = [];
                                                if (sinkRow.modelData.protocol) parts.push(sinkRow.modelData.protocol);
                                                if (sinkRow.modelData.address) parts.push(sinkRow.modelData.address);
                                                if (sinkRow.modelData.port) parts.push(":" + sinkRow.modelData.port);
                                                if (sinkRow.modelData.id && sinkRow.modelData.id !== sinkRow.modelData.name)
                                                    parts.push("id: " + sinkRow.modelData.id);
                                                return parts.join(" · ") || "—";
                                            }
                                            font.family: "Monospace"
                                            font.pixelSize: Styling.fontSize(-3)
                                            color: Colors.outline
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    // "Cast" button per row, only when idle
                                    StyledRect {
                                        visible: !MiraiService.streaming
                                        radius: Styling.radius(-3)
                                        Layout.preferredHeight: 24
                                        Layout.preferredWidth: 56
                                        variant: rowCastMa.containsMouse ? "primary" : "common"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "Cast"
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-3)
                                            font.weight: Font.Medium
                                            color: rowCastMa.containsMouse ? Colors.overPrimary : Colors.overBackground
                                        }
                                        MouseArea {
                                            id: rowCastMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: MiraiService.connectToSink(sinkRow.modelData.id)
                                        }
                                    }
                                    StyledRect {
                                        visible: MiraiService.streaming && MiraiService.activeSinkId === sinkRow.modelData.id
                                        radius: Styling.radius(-3)
                                        Layout.preferredHeight: 24
                                        Layout.preferredWidth: 72
                                        variant: "primary"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "Active"
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-3)
                                            font.weight: Font.Medium
                                            color: Styling.srItem("primary")
                                        }
                                    }
                                }

                                MouseArea {
                                    id: sinkRowMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !MiraiService.streaming
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: MiraiService.connectToSink(sinkRow.modelData.id)
                                }
                            }
                        }
                    }

                    // Empty state when no sinks
                    Text {
                        visible: !MiraiService.scanning && MiraiService.sinks.length === 0
                        text: MiraiService.lastScanTime.length > 0
                            ? "No sinks found in the last scan. Make sure the TV or dongle is in Miracast mode and on the same network."
                            : "No sinks discovered yet. Click Scan to look for TVs or dongles on the local network."
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.outline
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            // ── 4. Sink (Receive) ───────────────────────────────────────
            StyledRect {
                variant: "pane"
                Layout.fillWidth: true
                Layout.preferredHeight: sinkCol.implicitHeight + 28
                radius: Styling.radius(0)
                enableShadow: true

                ColumnLayout {
                    id: sinkCol
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: Icons.cast + "  Receive from phone / tablet"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            font.weight: Font.Medium
                            color: Colors.overBackground
                            Layout.fillWidth: true
                        }
                        StyledRect {
                            visible: MiraiService.receiving
                            radius: Styling.radius(-2)
                            Layout.preferredHeight: 22
                            Layout.preferredWidth: 70
                            variant: "primary"
                            Text {
                                anchors.centerIn: parent
                                text: "Active"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-3)
                                font.weight: Font.Medium
                                color: Styling.srItem("primary")
                            }
                        }
                    }

                    Text {
                        text: "Makes this PC appear as a Miracast display. Other devices (phone, tablet, laptop) can mirror to it. The actual video is rendered by Mirai via GStreamer or mpv."
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.outline
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    // Status info row
                    Text {
                        text: {
                            if (MiraiService.receiving) {
                                var n = MiraiService.sinkLinkCount;
                                return "← Receiving (" + MiraiService.sinkMode + " mode)" + (n > 0 ? " · " + n + " P2P link(s)" : "");
                            }
                            if (MiraiService.daemonRunning) {
                                return "Will advertise as \"" + MiraiService.sinkFriendlyName + "\" when started.";
                            }
                            return "Start the daemon to enable receiving.";
                        }
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: MiraiService.receiving ? Colors.primary : Colors.outline
                        Layout.fillWidth: true
                    }

                    // Mode toggle + start/stop
                    RowLayout {
                        spacing: 8
                        Layout.fillWidth: true

                        StyledRect {
                            id: sinkStartBtn
                            radius: Styling.radius(-3)
                            Layout.preferredHeight: 32
                            Layout.preferredWidth: 110
                            enabled: MiraiService.daemonRunning
                            variant: {
                                if (!sinkStartBtn.enabled) return "common";
                                if (MiraiService.receiving) return "error";
                                return "primary";
                            }
                            Text {
                                anchors.centerIn: parent
                                text: MiraiService.receiving
                                    ? Icons.stop + "  Stop"
                                    : Icons.play + "  Start"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Medium
                                color: {
                                    if (!sinkStartBtn.enabled) return Colors.outline;
                                    if (MiraiService.receiving) return Colors.overError;
                                    return Colors.overPrimary;
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                enabled: sinkStartBtn.enabled
                                onClicked: {
                                    if (MiraiService.receiving) {
                                        MiraiService.stopSink();
                                    } else {
                                        MiraiService.startSink();
                                    }
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Mode toggle
                        StyledRect {
                            radius: Styling.radius(-2)
                            Layout.preferredHeight: 28
                            Layout.preferredWidth: 76
                            enabled: MiraiService.daemonRunning
                            variant: MiraiService.sinkMode === "window" ? "primary" : "common"
                            Text {
                                anchors.centerIn: parent
                                text: "Window"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                font.weight: MiraiService.sinkMode === "window" ? Font.Medium : Font.Normal
                                color: MiraiService.sinkMode === "window" ? Styling.srItem("primary") : Colors.overBackground
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: MiraiService.setSinkMode("window")
                            }
                        }
                        StyledRect {
                            radius: Styling.radius(-2)
                            Layout.preferredHeight: 28
                            Layout.preferredWidth: 88
                            enabled: MiraiService.daemonRunning
                            variant: MiraiService.sinkMode === "fullscreen" ? "primary" : "common"
                            Text {
                                anchors.centerIn: parent
                                text: "Fullscreen"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                font.weight: MiraiService.sinkMode === "fullscreen" ? Font.Medium : Font.Normal
                                color: MiraiService.sinkMode === "fullscreen" ? Styling.srItem("primary") : Colors.overBackground
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: MiraiService.setSinkMode("fullscreen")
                            }
                        }
                    }
                }
            }

            // ── 5. Logs ────────────────────────────────────────────────
            StyledRect {
                variant: "pane"
                Layout.fillWidth: true
                Layout.preferredHeight: logHeader.implicitHeight + (root.logsExpanded ? 24 + logList.contentHeight + 12 : 24)
                radius: Styling.radius(0)
                enableShadow: false
                clip: true

                RowLayout {
                    id: logHeader
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 8

                    Text {
                        text: Icons.terminal + "  Logs"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        font.weight: Font.Medium
                        color: Colors.overBackground
                        Layout.fillWidth: true
                    }
                    StyledRect {
                        radius: Styling.radius(-2)
                        Layout.preferredHeight: 22
                        Layout.preferredWidth: 64
                        variant: logLoadMa.containsMouse ? "focus" : "common"
                        enabled: MiraiService.daemonRunning
                        Text {
                            anchors.centerIn: parent
                            text: MiraiService.logsLoading ? "…" : "Reload"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-3)
                            color: Colors.overBackground
                        }
                        MouseArea {
                            id: logLoadMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: MiraiService.loadRecentLogs(20)
                        }
                    }
                    StyledRect {
                        radius: Styling.radius(-2)
                        Layout.preferredHeight: 22
                        Layout.preferredWidth: 70
                        variant: logToggleMa.containsMouse ? "focus" : "common"
                        Text {
                            anchors.centerIn: parent
                            text: root.logsExpanded ? "Hide" : "Show"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-3)
                            color: Colors.overBackground
                        }
                        MouseArea {
                            id: logToggleMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.logsExpanded = !root.logsExpanded;
                                if (root.logsExpanded && MiraiService.recentLogs.length === 0) {
                                    MiraiService.loadRecentLogs(20);
                                }
                            }
                        }
                    }
                }

                ListView {
                    id: logList
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: logHeader.bottom
                    anchors.topMargin: 6
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 12
                    visible: root.logsExpanded
                    clip: true
                    spacing: 1
                    model: MiraiService.recentLogs
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: RowLayout {
                        required property var modelData
                        width: ListView.view.width
                        spacing: 8
                        Text {
                            text: {
                                if (modelData.level === "ERROR") return Icons.warningCircle;
                                if (modelData.level === "WARNING") return Icons.alert;
                                if (modelData.level === "INFO") return Icons.info;
                                return "•";
                            }
                            font.family: Icons.font
                            font.pixelSize: Styling.fontSize(-3)
                            color: {
                                if (modelData.level === "ERROR") return Colors.error;
                                if (modelData.level === "WARNING") return Colors.yellow;
                                return Colors.outline;
                            }
                        }
                        Text {
                            text: modelData.ts || ""
                            font.family: "Monospace"
                            font.pixelSize: Styling.fontSize(-3)
                            color: Colors.outline
                        }
                        Text {
                            text: "[" + modelData.level + "]"
                            font.family: "Monospace"
                            font.pixelSize: Styling.fontSize(-3)
                            color: Colors.outline
                            Layout.preferredWidth: 64
                        }
                        Text {
                            text: modelData.msg || ""
                            font.family: "Monospace"
                            font.pixelSize: Styling.fontSize(-3)
                            color: Colors.overBackground
                            wrapMode: Text.WrapAnywhere
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            // ── 6. Install hint when mirai is missing ──────────────────
            StyledRect {
                visible: !MiraiService.daemonAvailable
                variant: "internalbg"
                Layout.fillWidth: true
                Layout.preferredHeight: hintCol.implicitHeight + 28
                radius: Styling.radius(-2)

                ColumnLayout {
                    id: hintCol
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8
                    Text {
                        text: Icons.info + "  Mirai is not installed"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(0)
                        font.weight: Font.Medium
                        color: Colors.error
                    }
                    Text {
                        text: "Install Mirai to enable Miracast screen sharing. It wraps miraclecast (sink mode) and gnome-network-displays (source mode) into a single daemon with a JSON socket API."
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.outline
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Text {
                        text: "$ curl -fsSL https://raw.githubusercontent.com/leriart/Mirai/main/install.sh | sh"
                        font.family: "Monospace"
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overBackground
                        wrapMode: Text.WrapAnywhere
                        Layout.fillWidth: true
                    }
                }
            }

            // ── 7. Footer ───────────────────────────────────────────────
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 8
                text: {
                    var bits = [];
                    bits.push("Mirai v" + (MiraiService.daemonVersion || "?"));
                    bits.push("github.com/leriart/Mirai");
                    return bits.join(" · ");
                }
                font.family: "Monospace"
                font.pixelSize: Styling.fontSize(-3)
                color: Colors.outline
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
