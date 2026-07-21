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
    property var monitorProfiles: ({})
    property string selectedProfile: ""
    property string newProfileName: ""

    Component.onCompleted: {
        root.primaryMonitorName = StateService.get("monitors.primaryMonitor", "");
        root.monitorProfiles = StateService.get("monitors.profiles", {});
        MonitorsWriter.listMonitors();
    }

    function setPrimaryMonitor(name) {
        if (root.primaryMonitorName !== name) {
            root.primaryMonitorName = name;
            root.hasChanges = true;
        }
    }

    function profileNames() {
        return Object.keys(root.monitorProfiles).sort();
    }

    function saveProfile(name) {
        var trimmed = (name || "").trim();
        if (!trimmed) return;
        var profiles = JSON.parse(JSON.stringify(root.monitorProfiles));
        profiles[trimmed] = {
            monitors: JSON.parse(JSON.stringify(root.monitorList)),
            primaryMonitor: root.primaryMonitorName
        };
        root.monitorProfiles = profiles;
        StateService.set("monitors.profiles", profiles);
        root.selectedProfile = trimmed;
        root.newProfileName = "";
        root.statusMsg = "Profile saved: " + trimmed;
        statusClearTimer.restart();
    }

    function loadProfile(name) {
        var p = root.monitorProfiles[name];
        if (!p || !p.monitors) return;
        root.monitorList = JSON.parse(JSON.stringify(p.monitors));
        root.primaryMonitorName = p.primaryMonitor || "";
        root.selectedProfile = name;
        root.hasChanges = true;
        root.statusMsg = "Profile loaded: " + name + " (Apply to confirm)";
        statusClearTimer.restart();
    }

    function deleteProfile(name) {
        var profiles = JSON.parse(JSON.stringify(root.monitorProfiles));
        delete profiles[name];
        root.monitorProfiles = profiles;
        StateService.set("monitors.profiles", profiles);
        if (root.selectedProfile === name) root.selectedProfile = "";
        root.statusMsg = "Profile deleted: " + name;
        statusClearTimer.restart();
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

        // ── Profiles (nwg-displays style) ──
        StyledRect {
            Layout.fillWidth: true
            Layout.preferredHeight: profileRow.implicitHeight + 20
            variant: "pane"
            radius: Styling.radius(0)
            enableShadow: true

            RowLayout {
                id: profileRow
                anchors.fill: parent; anchors.margins: 10; spacing: 8

                Text {
                    text: "Profiles"
                    font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1)
                    font.weight: Font.Medium; color: Colors.overBackground
                }

                ComboBox {
                    id: profileCombo
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    model: root.profileNames()
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    currentIndex: {
                        var names = root.profileNames();
                        return names.indexOf(root.selectedProfile);
                    }

                    background: Rectangle {
                        color: profileCombo.hovered ? Colors.surfaceContainerHigh : Colors.surfaceContainer
                        radius: Styling.radius(-2)
                        border.color: Colors.surfaceBright; border.width: 1
                    }
                    contentItem: Text {
                        leftPadding: 8
                        text: profileCombo.displayText || "Select profile..."
                        font: profileCombo.font
                        color: profileCombo.displayText ? Colors.overBackground : Colors.outline
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    indicator: Text {
                        x: profileCombo.width - width - 8
                        y: (profileCombo.height - height) / 2
                        text: Icons.caretDown
                        font.family: Icons.font; font.pixelSize: 10
                        color: Colors.overSurfaceVariant
                    }
                    popup: Popup {
                        y: profileCombo.height + 2
                        width: profileCombo.width
                        implicitHeight: Math.min(contentItem.implicitHeight + 12, 200)
                        padding: 4
                        background: Rectangle {
                            color: Colors.surfaceContainer
                            radius: Styling.radius(-2)
                            border.color: Colors.surfaceBright; border.width: 1
                        }
                        contentItem: ListView {
                            clip: true
                            implicitHeight: contentHeight
                            model: profileCombo.delegateModel
                            currentIndex: profileCombo.currentIndex
                        }
                    }
                    delegate: ItemDelegate {
                        required property var modelData
                        width: profileCombo.width - 8
                        height: 28
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        leftPadding: 10
                        contentItem: Text {
                            text: modelData
                            font: parent.font
                            color: parent.highlighted ? Styling.srItem("primary") : Colors.overBackground
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: parent.highlighted ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.35)
                                : (parent.hovered ? Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.08) : "transparent")
                            radius: Styling.radius(-4)
                        }
                    }

                    onActivated: index => {
                        var names = root.profileNames();
                        if (index >= 0 && index < names.length) {
                            root.loadProfile(names[index]);
                        }
                    }
                }

                Button {
                    flat: true; hoverEnabled: true
                    Layout.preferredHeight: 28
                    enabled: root.selectedProfile !== ""
                    background: StyledRect { variant: "common"; radius: Styling.radius(-4) }
                    contentItem: Text {
                        text: Icons.trash
                        font.family: Icons.font; font.pixelSize: Styling.fontSize(-1)
                        color: Colors.overBackground
                        anchors.centerIn: parent
                    }
                    StyledToolTip { show: parent.hovered; tooltipText: "Delete selected profile" }
                    onClicked: root.deleteProfile(root.selectedProfile)
                }

                TextField {
                    id: profileNameField
                    Layout.preferredWidth: 140
                    Layout.preferredHeight: 28
                    placeholderText: "Profile name..."
                    text: root.newProfileName
                    onTextChanged: root.newProfileName = text
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    color: Colors.overBackground
                    background: Rectangle {
                        color: profileNameField.activeFocus ? Colors.surfaceContainerHigh : Colors.surfaceContainer
                        radius: Styling.radius(-2)
                        border.color: profileNameField.activeFocus ? Colors.primary : Colors.surfaceBright
                        border.width: 1
                    }
                    onAccepted: root.saveProfile(root.newProfileName)
                }

                Button {
                    flat: true; hoverEnabled: true
                    Layout.preferredHeight: 28
                    enabled: root.newProfileName.trim() !== "" && root.monitorList.length > 0
                    background: StyledRect {
                        variant: root.newProfileName.trim() !== "" ? "primary" : "common"
                        radius: Styling.radius(-4)
                        opacity: root.newProfileName.trim() !== "" ? 1.0 : 0.5
                    }
                    contentItem: Text {
                        text: Icons.accept + " Save"
                        font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-2)
                        color: root.newProfileName.trim() !== "" ? Styling.srItem("primary") : Colors.overBackground
                        anchors.centerIn: parent
                    }
                    StyledToolTip { show: parent.hovered; tooltipText: "Save current layout as profile" }
                    onClicked: root.saveProfile(root.newProfileName)
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
