pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.config

// ─────────────────────────────────────────────────────────────
// MonitorCard — Per-monitor editor inspired by nwg-displays
// Used inside MonitorsPanel. Edits are emitted through
// settingChanged(); the parent batches and applies them.
// ─────────────────────────────────────────────────────────────
StyledRect {
    id: root

    required property int monitorIndex
    property var monitor: null
    property var monitorList: []
    property bool isPrimary: false

    property bool isCollapsed: false
    property var detailedInfo: null
    property var availableModes: []
    property var resolutionList: []
    property var refreshMap: ({})
    property bool isFetchingModes: false

    signal settingChanged(string key, var value)
    signal requestPrimary(bool makePrimary)

    variant: "pane"
    Layout.fillWidth: true
    Layout.preferredHeight: cardLayout.implicitHeight + 28
    radius: Styling.radius(0)
    enableShadow: true

    readonly property string displayName: root.monitor ? (root.monitor.name || "") : ""
    readonly property bool enabled: root.monitor ? (root.monitor.enabled !== false) : false
    readonly property int monitorWidth: root.monitor ? (root.monitor.width || 0) : 0
    readonly property int monitorHeight: root.monitor ? (root.monitor.height || 0) : 0
    readonly property int monitorX: root.monitor ? (root.monitor.x || 0) : 0
    readonly property int monitorY: root.monitor ? (root.monitor.y || 0) : 0
    readonly property real monitorScale: root.monitor ? (root.monitor.scale || 1.0) : 1.0
    readonly property real monitorRefresh: root.monitor ? (root.monitor.refreshRate || root.monitor.refresh_rate || 60) : 60
    readonly property int monitorTransform: root.monitor ? (root.monitor.transform || 0) : 0
    readonly property int monitorVrr: root.monitor ? (root.monitor.vrr || 0) : 0
    readonly property bool monitorHdr: root.monitor ? (root.monitor.hdr || false) : false
    readonly property bool hdrSupported: root.detailedInfo ? (root.detailedInfo.hdrSupported || root.detailedInfo.hdr_supported || false)
                                                          : (root.monitor ? (root.monitor.hdrSupported || root.monitor.hdr_supported || false) : false)

    onDisplayNameChanged: if (displayName) Qt.callLater(root.fetchDetailedInfo)

    function fetchDetailedInfo() {
        if (isFetchingModes || !displayName) return;
        isFetchingModes = true;
        modeFetcherHyprctl.running = true;
    }

    property Process modeFetcherHyprctl: Process {
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {}
        running: false
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    root.parseMonitorList(JSON.parse(modeFetcherHyprctl.stdout.text));
                    return;
                } catch (e) { console.warn("MonitorCard: hyprctl parse failed:", e); }
            }
            modeFetcherAxctl.running = true;
        }
    }

    property Process modeFetcherAxctl: Process {
        command: ["axctl", "monitor", "list"]
        stdout: StdioCollector {}
        running: false
        onExited: exitCode => {
            root.isFetchingModes = false;
            if (exitCode === 0) {
                try { root.parseMonitorList(JSON.parse(modeFetcherAxctl.stdout.text)); }
                catch (e) { console.warn("MonitorCard: axctl parse failed:", e); root.useFallbackModes(); }
            } else { root.useFallbackModes(); }
        }
    }

    function parseModeString(s) {
        var clean = (s + "").replace(/Hz/gi, "").trim();
        var at = clean.lastIndexOf("@");
        var wh = (at >= 0 ? clean.substring(0, at) : clean).split("x");
        var rate = at >= 0 ? parseFloat(clean.substring(at + 1)) : root.monitorRefresh;
        return { w: parseInt(wh[0]) || 0, h: parseInt(wh[1]) || 0, rate: isNaN(rate) ? root.monitorRefresh : rate };
    }

    function parseMonitorList(allMonitors) {
        root.isFetchingModes = false;
        if (!allMonitors || !Array.isArray(allMonitors)) { root.useFallbackModes(); return; }
        var found = null;
        for (var i = 0; i < allMonitors.length; i++) {
            if (allMonitors[i].name === root.displayName) { found = allMonitors[i]; break; }
        }
        if (!found) { root.useFallbackModes(); return; }
        root.detailedInfo = found;

        var modes = found.availableModes || found.available_modes || found.modes || [];
        if (modes.length === 0 && found.width && found.height) {
            modes = [found.width + "x" + found.height + "@" + (found.refreshRate || found.refresh_rate || root.monitorRefresh).toFixed(2) + "Hz"];
        }
        root.availableModes = modes;
        root.buildResolutionMap();
    }

    function useFallbackModes() {
        root.isFetchingModes = false;
        if (root.monitorWidth > 0 && root.monitorHeight > 0) {
            root.availableModes = [root.monitorWidth + "x" + root.monitorHeight + "@" + root.monitorRefresh.toFixed(2) + "Hz"];
        } else {
            root.availableModes = [];
        }
        root.buildResolutionMap();
    }

    function buildResolutionMap() {
        var map = {};
        var list = [];
        for (var i = 0; i < root.availableModes.length; i++) {
            var p = root.parseModeString(root.availableModes[i]);
            if (p.w <= 0 || p.h <= 0) continue;
            var key = p.w + "x" + p.h;
            if (!map[key]) { map[key] = []; list.push(key); }
            if (map[key].indexOf(p.rate) === -1) map[key].push(p.rate);
        }
        for (var k in map) map[k].sort(function(a, b){ return b - a; });
        root.refreshMap = map;
        root.resolutionList = list;
    }

    function resolutionIndex() {
        var target = root.monitorWidth + "x" + root.monitorHeight;
        for (var i = 0; i < root.resolutionList.length; i++) {
            if (root.resolutionList[i] === target) return i;
        }
        return 0;
    }

    function refreshIndex() {
        var key = root.monitorWidth + "x" + root.monitorHeight;
        var rates = root.refreshMap[key] || [];
        var best = 0, bestDiff = Infinity;
        for (var i = 0; i < rates.length; i++) {
            var diff = Math.abs(rates[i] - root.monitorRefresh);
            if (diff < bestDiff) { bestDiff = diff; best = i; }
        }
        return best;
    }

    function refreshRateStrings() {
        var key = root.monitorWidth + "x" + root.monitorHeight;
        var rates = root.refreshMap[key] || [];
        return rates.map(function(r) { return r.toFixed(2) + " Hz"; });
    }

    function refreshDisplayIndex() {
        var key = root.monitorWidth + "x" + root.monitorHeight;
        var rates = root.refreshMap[key] || [];
        var best = 0, bestDiff = Infinity;
        for (var i = 0; i < rates.length; i++) {
            var diff = Math.abs(rates[i] - root.monitorRefresh);
            if (diff < bestDiff) { bestDiff = diff; best = i; }
        }
        return best;
    }

    function transformLabel(idx) {
        var labels = ["0° Normal", "90°", "180°", "270°", "Flipped", "90° Flipped", "180° Flipped", "270° Flipped"];
        return labels[idx] || labels[0];
    }

    function duplicateFrom(sourceName) {
        if (!root.monitorList || !sourceName) return;
        for (var i = 0; i < root.monitorList.length; i++) {
            var s = root.monitorList[i];
            if (s && s.name === sourceName) {
                root.settingChanged("width", s.width || 0);
                root.settingChanged("height", s.height || 0);
                root.settingChanged("refreshRate", s.refreshRate || s.refresh_rate || 60);
                root.settingChanged("scale", s.scale || 1.0);
                root.settingChanged("x", s.x || 0);
                root.settingChanged("y", s.y || 0);
                root.settingChanged("transform", s.transform || 0);
                root.settingChanged("vrr", s.vrr || 0);
                return;
            }
        }
    }

    // ─── Shared controls ───
    component NLCombo: ComboBox {
        id: nlCombo
        Layout.preferredWidth: 140
        Layout.preferredHeight: 28
        textRole: "modelData"
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(-1)

        background: Rectangle {
            color: nlCombo.hovered ? Colors.surfaceContainerHigh : Colors.surfaceContainer
            radius: Styling.radius(-2)
            border.color: Colors.surfaceBright; border.width: 1
        }
        contentItem: Text {
            leftPadding: 8; rightPadding: 8
            text: nlCombo.displayText
            color: Colors.overBackground
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        indicator: Text {
            x: nlCombo.width - width - 8
            y: (nlCombo.height - height) / 2
            text: Icons.caretDown
            font.family: Icons.font; font.pixelSize: 10
            color: Colors.overSurfaceVariant
        }
        popup: Popup {
            y: nlCombo.height + 2
            width: nlCombo.width
            implicitHeight: Math.min(contentItem.implicitHeight + 12, 260)
            padding: 4
            background: Rectangle {
                color: Colors.surfaceContainer
                radius: Styling.radius(-2)
                border.color: Colors.surfaceBright; border.width: 1
            }
            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: nlCombo.delegateModel
                currentIndex: nlCombo.currentIndex
                interactive: contentHeight > 240
                spacing: 2
            }
        }
        delegate: ItemDelegate {
            required property var modelData
            width: nlCombo.width - 8
            height: 28
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-1)
            leftPadding: 10
            contentItem: Text {
                text: modelData && modelData.text !== undefined ? modelData.text : (typeof modelData === "string" ? modelData : "")
                font: parent.font
                color: parent.highlighted ? Styling.srItem("primary") : Colors.overBackground
                opacity: parent.highlighted ? 1.0 : 0.85
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                color: {
                    if (parent.highlighted) return Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.35);
                    if (parent.hovered) return Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.08);
                    return "transparent";
                }
                radius: Styling.radius(-4)
            }
        }
    }

    component NLToggle: RowLayout {
        property string label: ""
        property bool checked: false
        property bool enabled: true
        signal toggled(bool value)
        spacing: 8
        Layout.fillWidth: true
        Text {
            text: parent.label
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-1)
            color: Colors.overBackground
            Layout.fillWidth: true
            visible: parent.label !== ""
        }
        Switch {
            id: toggleSwitch
            checked: parent.checked
            enabled: parent.enabled
            onToggled: parent.toggled(checked)
            indicator: Rectangle {
                implicitWidth: 36; implicitHeight: 20; radius: 10
                color: toggleSwitch.checked ? Colors.primary : Qt.rgba(Colors.outline.r, Colors.outline.g, Colors.outline.b, 0.3)
                border.color: toggleSwitch.checked ? Colors.primary : Colors.outline; border.width: 1
                Rectangle {
                    x: toggleSwitch.checked ? parent.width - width - 3 : 3
                    y: (parent.height - height) / 2
                    width: 14; height: 14; radius: 7
                    color: toggleSwitch.checked ? "#ffffff" : Colors.outline
                    Behavior on x {
                        enabled: Anim.animationsEnabled
                        NumberAnimation { duration: Anim.standardSmall; easing.type: Anim.easing("standard").type; easing.bezierCurve: Anim.easing("standard").bezierCurve }
                    }
                }
                Behavior on color {
                    enabled: Anim.animationsEnabled
                    ColorAnimation { duration: Anim.standardSmall }
                }
            }
        }
    }

    // ─── UI ───
    ColumnLayout {
        id: cardLayout
        anchors.fill: parent; anchors.margins: 14; spacing: 12

        // Header
        RowLayout {
            Layout.fillWidth: true; spacing: 10

            Rectangle {
                width: 10; height: 10; radius: 5
                color: root.isPrimary ? Colors.primary : (root.enabled ? Colors.outline : Colors.outlineVariant)
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true; spacing: 1
                RowLayout {
                    spacing: 6
                    Text {
                        text: root.displayName || "Monitor"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(1)
                        font.bold: true
                        color: root.enabled ? Colors.overBackground : Colors.outline
                    }
                    Text {
                        visible: root.isPrimary
                        text: Icons.pin
                        font.family: Icons.font; font.pixelSize: 12
                        color: Colors.primary
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Text {
                        visible: !root.enabled
                        text: "Disabled"
                        font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-3)
                        color: Colors.outline
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
                Text {
                    text: {
                        var p = [];
                        if (root.detailedInfo && root.detailedInfo.make) p.push(root.detailedInfo.make);
                        if (root.detailedInfo && root.detailedInfo.model) p.push(root.detailedInfo.model);
                        if (root.monitorWidth > 0) p.push(root.monitorWidth + "×" + root.monitorHeight + " @ " + Math.round(root.monitorRefresh) + "Hz");
                        return p.join("  ·  ");
                    }
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    color: Colors.outline
                    elide: Text.ElideRight
                }
            }

            Button {
                flat: true
                Layout.preferredWidth: 30; Layout.preferredHeight: 30
                Layout.alignment: Qt.AlignVCenter
                contentItem: Text {
                    text: root.isCollapsed ? Icons.caretDown : Icons.caretUp
                    font.family: Icons.font; font.pixelSize: 14
                    color: Colors.outline
                    anchors.centerIn: parent
                }
                background: StyledRect { variant: "common"; radius: Styling.radius(-6) }
                onClicked: root.isCollapsed = !root.isCollapsed
            }
        }

        // Quick chips
        RowLayout {
            Layout.fillWidth: true; spacing: 6
            visible: root.enabled

            MonitorChip { icon: Icons.arrowsOutCardinal; text: root.monitorX + ", " + root.monitorY }
            MonitorChip { icon: Icons.arrowsOut; text: root.monitorScale.toFixed(2) + "×" }
            MonitorChip { icon: Icons.arrowCounterClockwise; text: Math.round(root.monitorRefresh) + "Hz" }
            MonitorChip { icon: Icons.arrowCounterClockwise; text: root.transformLabel(root.monitorTransform) }

            Item { Layout.fillWidth: true }

            Button {
                flat: true; enabled: !root.isPrimary
                Layout.preferredHeight: 26
                visible: !root.isPrimary
                contentItem: Text {
                    text: Icons.pin + " Primary"
                    font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-2)
                    color: parent.enabled ? Colors.primary : Colors.outline
                    anchors.centerIn: parent
                }
                background: StyledRect { variant: "common"; radius: Styling.radius(-4) }
                onClicked: root.requestPrimary(true)
            }
        }

        // Expandable settings
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.isCollapsed ? 0 : settingsColumn.implicitHeight
            clip: true
            visible: !root.isCollapsed
            Behavior on Layout.preferredHeight {
                enabled: Anim.animationsEnabled
                NumberAnimation { duration: Anim.standardSmall; easing.type: Anim.easing("standard").type; easing.bezierCurve: Anim.easing("standard").bezierCurve }
            }

            ColumnLayout {
                id: settingsColumn; width: parent.width; spacing: 10
                opacity: root.enabled ? 1.0 : 0.5

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    rowSpacing: 10; columnSpacing: 10

                    // Enabled toggle
                    Text { text: Icons.accept; font.family: Icons.font; font.pixelSize: 14; color: Colors.outline; Layout.alignment: Qt.AlignVCenter }
                    NLToggle {
                        label: "Enabled"
                        checked: root.enabled
                        onToggled: root.settingChanged("enabled", value)
                    }

                    // Primary toggle
                    Text { text: Icons.pin; font.family: Icons.font; font.pixelSize: 14; color: Colors.outline; Layout.alignment: Qt.AlignVCenter }
                    NLToggle {
                        label: "Primary output"
                        checked: root.isPrimary
                        onToggled: root.requestPrimary(value)
                    }

                    // Resolution
                    Text { text: Icons.layout; font.family: Icons.font; font.pixelSize: 14; color: Colors.outline; Layout.alignment: Qt.AlignVCenter }
                    RowLayout { Layout.fillWidth: true; spacing: 8
                        Text { text: "Resolution"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 76 }
                        NLCombo {
                            id: resCombo
                            Layout.fillWidth: true
                            model: root.resolutionList
                            currentIndex: root.resolutionIndex()
                            onActivated: {
                                var wh = root.resolutionList[index].split("x");
                                root.settingChanged("width", parseInt(wh[0]));
                                root.settingChanged("height", parseInt(wh[1]));
                                // Keep a sensible refresh rate for the new resolution
                                var rates = root.refreshMap[root.resolutionList[index]] || [];
                                if (rates.length > 0) root.settingChanged("refreshRate", rates[0]);
                            }
                        }
                    }

                    // Refresh rate
                    Text { text: Icons.clock; font.family: Icons.font; font.pixelSize: 14; color: Colors.outline; Layout.alignment: Qt.AlignVCenter }
                    RowLayout { Layout.fillWidth: true; spacing: 8
                        Text { text: "Refresh"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 76 }
                        NLCombo {
                            id: refreshCombo
                            Layout.fillWidth: true
                            model: root.refreshRateStrings()
                            currentIndex: root.refreshDisplayIndex()
                            onActivated: root.settingChanged("refreshRate", parseFloat(model[index].replace("Hz", "").trim()))
                        }
                    }

                    // Scale
                    Text { text: Icons.arrowsOut; font.family: Icons.font; font.pixelSize: 14; color: Colors.outline; Layout.alignment: Qt.AlignVCenter }
                    RowLayout { Layout.fillWidth: true; spacing: 8
                        Text { text: "Scale"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 76 }
                        TextField {
                            id: scaleInput
                            text: root.monitorScale.toFixed(2)
                            font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1)
                            color: Colors.overBackground
                            Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight
                            validator: DoubleValidator { bottom: 0.25; top: 10.0; decimals: 2 }
                            background: Rectangle {
                                color: scaleInput.hovered ? Colors.surfaceContainerHigh : Colors.surfaceContainer
                                radius: Styling.radius(-2)
                                border.color: Colors.surfaceBright; border.width: 1
                            }
                            onEditingFinished: {
                                var v = parseFloat(text);
                                if (!isNaN(v) && v >= 0.25 && v <= 10.0) root.settingChanged("scale", v);
                                else text = root.monitorScale.toFixed(2);
                            }
                        }
                        Text { text: "×"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.outline }
                    }

                    // Position
                    Text { text: Icons.arrowsOutCardinal; font.family: Icons.font; font.pixelSize: 14; color: Colors.outline; Layout.alignment: Qt.AlignVCenter }
                    RowLayout { Layout.fillWidth: true; spacing: 8
                        Text { text: "Position"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 76 }
                        SpinBox {
                            id: posX; from: -10000; to: 30000; stepSize: 10; value: root.monitorX; editable: true; Layout.preferredWidth: 82
                            background: Rectangle { color: Colors.surfaceContainer; border.color: Colors.surfaceBright; border.width: 1; radius: Styling.radius(-2) }
                            contentItem: TextInput { text: posX.value; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            onValueModified: root.settingChanged("x", posX.value)
                        }
                        Text { text: "Y"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-2); color: Colors.outline }
                        SpinBox {
                            id: posY; from: -10000; to: 30000; stepSize: 10; value: root.monitorY; editable: true; Layout.preferredWidth: 82
                            background: Rectangle { color: Colors.surfaceContainer; border.color: Colors.surfaceBright; border.width: 1; radius: Styling.radius(-2) }
                            contentItem: TextInput { text: posY.value; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            onValueModified: root.settingChanged("y", posY.value)
                        }
                    }

                    // Rotation
                    Text { text: Icons.arrowCounterClockwise; font.family: Icons.font; font.pixelSize: 14; color: Colors.outline; Layout.alignment: Qt.AlignVCenter }
                    RowLayout { Layout.fillWidth: true; spacing: 8
                        Text { text: "Rotation"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 76 }
                        NLCombo {
                            id: transformCombo
                            Layout.fillWidth: true
                            model: ["0° Normal", "90°", "180°", "270°", "Flipped", "90° Flipped", "180° Flipped", "270° Flipped"]
                            currentIndex: Math.min(root.monitorTransform, 7)
                            onActivated: root.settingChanged("transform", index)
                        }
                    }

                    // VRR
                    Text { text: Icons.waveform; font.family: Icons.font; font.pixelSize: 14; color: Colors.outline; Layout.alignment: Qt.AlignVCenter }
                    RowLayout { Layout.fillWidth: true; spacing: 8
                        Text { text: "VRR"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 76 }
                        NLCombo {
                            id: vrrCombo
                            Layout.fillWidth: true
                            model: ["Global Default", "Disabled", "Enabled", "Fullscreen", "Fullscreen+Gaming"]
                            currentIndex: {
                                var v = root.monitorVrr;
                                if (v === 0) return 0;
                                if (v === 1) return 2;
                                if (v === 2) return 3;
                                if (v === 3) return 4;
                                return 0;
                            }
                            onActivated: { var v = [0, 0, 1, 2, 3]; root.settingChanged("vrr", v[index]); }
                        }
                    }

                    // HDR
                    Text { text: Icons.sun; font.family: Icons.font; font.pixelSize: 14; color: Colors.outline; Layout.alignment: Qt.AlignVCenter }
                    NLToggle {
                        label: "HDR" + (root.hdrSupported ? "" : " (unsupported)")
                        checked: root.monitorHdr
                        enabled: root.hdrSupported
                        onToggled: root.settingChanged("hdr", value)
                    }

                    // Duplicate from
                    Text { text: Icons.copy; font.family: Icons.font; font.pixelSize: 14; color: Colors.outline; Layout.alignment: Qt.AlignVCenter }
                    RowLayout { Layout.fillWidth: true; spacing: 8
                        Text { text: "Duplicate"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 76 }
                        NLCombo {
                            id: dupCombo
                            Layout.fillWidth: true
                            model: {
                                var names = ["None"];
                                if (!root.monitorList) return names;
                                for (var i = 0; i < root.monitorList.length; i++) {
                                    var m = root.monitorList[i];
                                    if (m && m.name && m.name !== root.displayName && m.enabled !== false) names.push(m.name);
                                }
                                return names;
                            }
                            currentIndex: 0
                            onActivated: {
                                if (index > 0) root.duplicateFrom(model[index]);
                                dupCombo.currentIndex = 0;
                            }
                        }
                    }
                }
            }
        }
    }

    component MonitorChip: StyledRect {
        id: chipRoot
        property string icon: ""
        property string text: ""
        variant: "internalbg"
        Layout.preferredHeight: 22
        radius: Styling.radius(-6)
        implicitWidth: chipRow.implicitWidth + 12
        RowLayout {
            id: chipRow; anchors.centerIn: parent; spacing: 3
            Text { text: chipRoot.icon; font.family: Icons.font; font.pixelSize: 10; color: Colors.outline }
            Text { text: chipRoot.text; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-3); color: Colors.outline }
        }
    }

    component SettingsRow: RowLayout {
        property string icon: ""
        property string label: ""
        spacing: 8
        Text { text: icon; font.family: Icons.font; font.pixelSize: 14; color: Colors.outline; Layout.preferredWidth: 18 }
        Text { text: label; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 76 }
    }
}
