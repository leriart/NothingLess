import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root
    implicitHeight: layout.implicitHeight
    Layout.fillWidth: true

    property var monitorList: []
    property int selectedIndex: 0
    property bool hasChanges: false
    property bool isApplying: false
    property string statusMsg: ""

    property string primaryMonitorName: ""

    Component.onCompleted: {
        root.primaryMonitorName = StateService.get("monitors.primaryMonitor", "");
        MonitorsWriter.listMonitors();
    }

    function setPrimaryMonitor(name) {
        if (root.primaryMonitorName !== name) {
            root.primaryMonitorName = name;
            root.hasChanges = true;
        }
    }

    Connections {
        target: StateService
        function onStateLoaded() {
            var saved = StateService.get("monitors.primaryMonitor", "");
            if (saved && root.primaryMonitorName !== saved) {
                root.primaryMonitorName = saved;
            }
        }
    }

    Connections {
        target: MonitorsWriter
        function onMonitorsListed(data) {
            root.monitorList = data || [];
            if (root.selectedIndex >= root.monitorList.length) {
                root.selectedIndex = 0;
            }
            root.hasChanges = false;
        }
        function onSyncFinished(success, msg) {
            root.isApplying = false;
            if (success) {
                root.statusMsg = "Applied ✓";
                statusClearTimer.restart();
                StateService.set("monitors.primaryMonitor", root.primaryMonitorName);
                MonitorsWriter.listMonitors();
            } else {
                root.statusMsg = "Error: " + msg;
            }
        }
    }

    Timer { id: statusClearTimer; interval: 3000; onTriggered: root.statusMsg = "" }

    function updateSetting(idx, key, value) {
        var list = JSON.parse(JSON.stringify(root.monitorList));
        list[idx][key] = value;
        root.monitorList = list;
        root.hasChanges = true;
    }

    function applyChanges() {
        if (!root.hasChanges || root.isApplying || root.monitorList.length === 0) return;
        root.isApplying = true;
        root.statusMsg = "Applying...";
        MonitorsWriter.syncWithData(root.monitorList);
    }

    function identifyMonitors() {
        for (var i = 0; i < root.monitorList.length; i++) {
            var m = root.monitorList[i];
            if (!m || m.enabled === false) continue;
            var msg = m.name + "  ·  " + (m.width || 0) + "×" + (m.height || 0);
            Notifications.notifyInternal({
                summary: "Monitor " + (i + 1),
                body: msg,
                expireTimeout: 2500,
                popup: true
            });
        }
    }

    ColumnLayout {
        id: layout
        anchors.left: parent.left; anchors.right: parent.right; spacing: 14

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "Monitor Layout"
                font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1)
                font.weight: Font.Medium; color: Colors.outline
                Layout.fillWidth: true
            }
            RowLayout {
                spacing: 8
                Button {
                    flat: true; hoverEnabled: true
                    Layout.preferredHeight: 28
                    enabled: root.monitorList.length > 0
                    background: StyledRect { variant: "common"; radius: Styling.radius(-4) }
                    contentItem: Text {
                        text: Icons.info + " Identify"
                        font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overBackground
                        anchors.centerIn: parent
                    }
                    onClicked: root.identifyMonitors()
                }
                Button {
                    flat: true; hoverEnabled: true
                    Layout.preferredHeight: 28
                    enabled: root.hasChanges && !root.isApplying
                    background: StyledRect { variant: "common"; radius: Styling.radius(-4) }
                    contentItem: Text {
                        text: Icons.arrowCounterClockwise + " Reset"
                        font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overBackground
                        anchors.centerIn: parent
                    }
                    onClicked: { root.hasChanges = false; MonitorsWriter.listMonitors(); }
                }
                Button {
                    flat: true; hoverEnabled: true
                    Layout.preferredHeight: 28
                    enabled: root.hasChanges && !root.isApplying
                    background: StyledRect {
                        variant: root.hasChanges ? "primary" : "common"
                        radius: Styling.radius(-4)
                        opacity: root.hasChanges ? 1.0 : 0.5
                    }
                    contentItem: Text {
                        text: root.isApplying ? (Icons.circleNotch + " Applying...") : (Icons.shieldCheck + " Apply")
                        font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-2)
                        color: root.hasChanges ? Styling.srItem("primary") : Colors.overBackground
                        anchors.centerIn: parent
                    }
                    onClicked: root.applyChanges()
                }
            }
        }

        MonitorArrangementView {
            id: arrangementView
            Layout.fillWidth: true
            monitors: root.monitorList
            selectedIndex: root.selectedIndex
            onMonitorMoved: (idx, x, y) => {
                var list = JSON.parse(JSON.stringify(root.monitorList));
                list[idx].x = x; list[idx].y = y;
                root.monitorList = list;
                root.hasChanges = true;
            }
            onMonitorSelected: (idx) => { root.selectedIndex = idx; }
        }

        Text {
            text: "Selected Monitor Settings"
            font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1)
            font.weight: Font.Medium; color: Colors.outline
            Layout.topMargin: 4
        }

        MonitorCard {
            Layout.fillWidth: true
            monitorIndex: root.selectedIndex
            monitor: root.monitorList.length > root.selectedIndex ? root.monitorList[root.selectedIndex] : null
            monitorList: root.monitorList
            isPrimary: root.monitorList.length > root.selectedIndex && root.monitorList[root.selectedIndex] && root.monitorList[root.selectedIndex].name === root.primaryMonitorName
            onSettingChanged: (key, value) => {
                root.updateSetting(root.selectedIndex, key, value);
            }
            onRequestPrimary: (makePrimary) => {
                if (makePrimary) {
                    root.setPrimaryMonitor(root.monitorList[root.selectedIndex] ? root.monitorList[root.selectedIndex].name : "");
                } else {
                    root.setPrimaryMonitor("");
                }
            }
        }

        // Status bar
        StyledRect {
            Layout.fillWidth: true; Layout.preferredHeight: 24
            variant: root.hasChanges ? "focus" : "internalbg"
            radius: Styling.radius(-4)
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 8
                Text {
                    Layout.fillWidth: true
                    text: root.statusMsg || (root.hasChanges ? Icons.edit + " Unsaved changes" : "All changes applied")
                    font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-3)
                    color: root.hasChanges ? Styling.srItem("primary") : Colors.outline; elide: Text.ElideRight
                }
            }
        }
    }
Component.onDestruction: {
    layout.stop ? layout.stop() : undefined;
    layout.running !== undefined ? layout.running = false : undefined;
    layout.destroy !== undefined ? layout.destroy() : undefined;
}
}
