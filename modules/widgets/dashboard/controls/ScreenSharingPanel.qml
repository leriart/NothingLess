pragma ComponentBehavior: Bound

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

    property int maxContentWidth: 480
    readonly property int contentWidth: Math.min(width, maxContentWidth)
    readonly property real sideMargin: (width - contentWidth) / 2

    Component.onCompleted: ScreenSharingService.initialize()

    Flickable {
        id: mainFlickable
        anchors.fill: parent
        contentHeight: mainColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: mainColumn
            width: mainFlickable.width
            spacing: 8

            // Header wrapper
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: titlebar.height

                PanelTitlebar {
                    id: titlebar
                    width: root.contentWidth
                    anchors.horizontalCenter: parent.horizontalCenter
                    title: "Screen Sharing"
                    statusText: {
                        if (!ScreenSharingService.available) return "Not installed";
                        if (ScreenSharingService.running) {
                            return ScreenSharingService.clientName
                                || (ScreenSharingService.mode === "sink" ? "Waiting for client..." : "Ready to cast");
                        }
                        return "Ready";
                    }
                    statusColor: ScreenSharingService.running ? Colors.primary : (ScreenSharingService.available ? Colors.outline : Colors.error)
                    showToggle: ScreenSharingService.available
                    toggleChecked: ScreenSharingService.running

                    actions: ScreenSharingService.available ? [
                        {
                            icon: Icons.sync,
                            tooltip: "Restart server",
                            onClicked: function () { ScreenSharingService.restart(); }
                        }
                    ] : []

                    onToggleChanged: checked => {
                        if (checked !== ScreenSharingService.running) {
                            ScreenSharingService.toggle();
                        }
                    }
                }
            }

            // Content wrapper - centered
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: contentColumn.implicitHeight

                ColumnLayout {
                    id: contentColumn
                    width: root.contentWidth
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 14

                    // Not available state
                    StyledRect {
                        visible: !ScreenSharingService.available
                        variant: "pane"
                        Layout.fillWidth: true
                        Layout.preferredHeight: notAvailableColumn.implicitHeight + 32
                        radius: Styling.radius(0)

                        ColumnLayout {
                            id: notAvailableColumn
                            anchors.fill: parent; anchors.margins: 16; spacing: 8

                            Text {
                                text: Icons.broadcast
                                font.family: Icons.font; font.pixelSize: 32
                                color: Colors.outline
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: "No wireless display backend installed"
                                font.family: Config.theme.font; font.pixelSize: Styling.fontSize(1)
                                font.bold: true
                                color: Colors.overBackground
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: "Install one or more backends to share your screen or receive other devices:\n" +
                                      "• UxPlay — AirPlay (iOS/macOS)\n" +
                                      "• miraclecast or GNOME Network Displays — Miracast / Chromecast"
                                font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-2)
                                color: Colors.outline
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    // Mode + Protocol selection
                    StyledRect {
                        visible: ScreenSharingService.available
                        variant: "pane"
                        Layout.fillWidth: true
                        Layout.preferredHeight: protocolColumn.implicitHeight + 28
                        radius: Styling.radius(0)
                        enableShadow: true

                        ColumnLayout {
                            id: protocolColumn
                            anchors.fill: parent; anchors.margins: 14; spacing: 12

                            Text {
                                text: "Mode"
                                font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Medium
                                color: Colors.overSurfaceVariant
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Button {
                                    flat: true
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    enabled: ScreenSharingService.mode !== "sink"
                                    background: StyledRect { variant: ScreenSharingService.mode === "sink" ? "primary" : "common"; radius: Styling.radius(-4) }
                                    contentItem: Text {
                                        text: Icons.downloadSimple + " Receive"
                                        font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1)
                                        color: ScreenSharingService.mode === "sink" ? Styling.srItem("primary") : Colors.overBackground
                                        anchors.centerIn: parent
                                    }
                                    onClicked: ScreenSharingService.setSetting("mode", "sink")
                                }
                                Button {
                                    flat: true
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    enabled: ScreenSharingService.mode !== "source"
                                    background: StyledRect { variant: ScreenSharingService.mode === "source" ? "primary" : "common"; radius: Styling.radius(-4) }
                                    contentItem: Text {
                                        text: Icons.uploadSimple + " Send"
                                        font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1)
                                        color: ScreenSharingService.mode === "source" ? Styling.srItem("primary") : Colors.overBackground
                                        anchors.centerIn: parent
                                    }
                                    onClicked: ScreenSharingService.setSetting("mode", "source")
                                }
                            }

                            Text {
                                text: "Protocol"
                                font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Medium
                                color: Colors.overSurfaceVariant
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                rowSpacing: 10; columnSpacing: 10

                                Text { text: "Auto"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 80 }
                                NLSwitch {
                                    checked: ScreenSharingService.protocol === "auto"
                                    onToggled: ScreenSharingService.setSetting("protocol", checked ? "auto" : "airplay")
                                }

                                Text { text: "AirPlay"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 80 }
                                RowLayout {
                                    spacing: 8
                                    NLSwitch {
                                        checked: ScreenSharingService.protocol === "airplay"
                                        enabled: ScreenSharingService.hasProtocol("airplay")
                                        onToggled: ScreenSharingService.setSetting("protocol", checked ? "airplay" : "auto")
                                    }
                                    Text {
                                        text: ScreenSharingService.hasProtocol("airplay") ? "" : "(not installed)"
                                        font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-3)
                                        color: Colors.outline
                                    }
                                }

                                Text { text: "Miracast"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 80 }
                                RowLayout {
                                    spacing: 8
                                    NLSwitch {
                                        checked: ScreenSharingService.protocol === "miracast"
                                        enabled: ScreenSharingService.hasProtocol("miracast")
                                        onToggled: ScreenSharingService.setSetting("protocol", checked ? "miracast" : "auto")
                                    }
                                    Text {
                                        text: ScreenSharingService.hasProtocol("miracast") ? "" : "(not installed)"
                                        font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-3)
                                        color: Colors.outline
                                    }
                                }

                                Text { text: "Chromecast"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 80 }
                                RowLayout {
                                    spacing: 8
                                    NLSwitch {
                                        checked: ScreenSharingService.protocol === "chromecast"
                                        enabled: ScreenSharingService.hasProtocol("chromecast") && ScreenSharingService.mode === "source"
                                        onToggled: ScreenSharingService.setSetting("protocol", checked ? "chromecast" : "auto")
                                    }
                                    Text {
                                        text: ScreenSharingService.hasProtocol("chromecast") ? (ScreenSharingService.mode === "sink" ? "(send only)" : "") : "(not installed)"
                                        font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-3)
                                        color: Colors.outline
                                    }
                                }
                            }
                        }
                    }

                    // Server settings
                    StyledRect {
                        visible: ScreenSharingService.available
                        variant: "pane"
                        Layout.fillWidth: true
                        Layout.preferredHeight: serverSettingsColumn.implicitHeight + 28
                        radius: Styling.radius(0)
                        enableShadow: true

                        ColumnLayout {
                            id: serverSettingsColumn
                            anchors.fill: parent; anchors.margins: 14; spacing: 12

                            Text {
                                text: "Server"
                                font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Medium
                                color: Colors.overSurfaceVariant
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                rowSpacing: 10; columnSpacing: 10

                                Text { text: "Name"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 80 }
                                TextField {
                                    id: nameInput
                                    Layout.fillWidth: true
                                    text: ScreenSharingService.serverName
                                    font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1)
                                    color: Colors.overBackground
                                    background: Rectangle { color: parent.hovered ? Colors.surfaceContainerHigh : Colors.surfaceContainer; radius: Styling.radius(-2); border.color: Colors.surfaceBright; border.width: 1 }
                                    onEditingFinished: ScreenSharingService.setSetting("serverName", text.trim())
                                }

                                Text { text: "Auto-start"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 80 }
                                NLSwitch {
                                    checked: ScreenSharingService.autoStart
                                    onToggled: ScreenSharingService.setSetting("autoStart", checked)
                                }

                                Text { text: "PIN"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 80 }
                                NLSwitch {
                                    checked: ScreenSharingService.pinAuth
                                    onToggled: ScreenSharingService.setSetting("pinAuth", checked)
                                }

                                Text { text: "Password"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 80 }
                                TextField {
                                    id: pwInput
                                    Layout.fillWidth: true
                                    text: ScreenSharingService.password
                                    echoMode: TextInput.Password
                                    font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1)
                                    color: Colors.overBackground
                                    background: Rectangle { color: parent.hovered ? Colors.surfaceContainerHigh : Colors.surfaceContainer; radius: Styling.radius(-2); border.color: Colors.surfaceBright; border.width: 1 }
                                    onEditingFinished: ScreenSharingService.setSetting("password", text.trim())
                                }
                            }
                        }
                    }

                    // AirPlay stream settings
                    StyledRect {
                        visible: ScreenSharingService.available && ScreenSharingService.effectiveProtocol() === "airplay"
                        variant: "pane"
                        Layout.fillWidth: true
                        Layout.preferredHeight: airplayColumn.implicitHeight + 28
                        radius: Styling.radius(0)
                        enableShadow: true

                        ColumnLayout {
                            id: airplayColumn
                            anchors.fill: parent; anchors.margins: 14; spacing: 12

                            Text {
                                text: "AirPlay Stream"
                                font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Medium
                                color: Colors.overSurfaceVariant
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                rowSpacing: 10; columnSpacing: 10

                                Text { text: "Audio only"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 80 }
                                NLSwitch {
                                    checked: ScreenSharingService.audioOnly
                                    onToggled: ScreenSharingService.setSetting("audioOnly", checked)
                                }

                                Text { text: "VSync"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 80 }
                                NLSwitch {
                                    checked: ScreenSharingService.vsync
                                    onToggled: ScreenSharingService.setSetting("vsync", checked)
                                }

                                Text { text: "Fullscreen"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 80 }
                                NLSwitch {
                                    checked: ScreenSharingService.fullscreen
                                    onToggled: ScreenSharingService.setSetting("fullscreen", checked)
                                }

                                Text { text: "FPS"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 80 }
                                SpinBox {
                                    id: fpsSpin
                                    from: 15; to: 120; stepSize: 5; value: ScreenSharingService.fps; editable: true; Layout.preferredWidth: 100
                                    background: Rectangle { color: Colors.surfaceContainer; border.color: Colors.surfaceBright; border.width: 1; radius: Styling.radius(-2) }
                                    contentItem: TextInput { text: fpsSpin.value; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                    onValueModified: ScreenSharingService.setSetting("fps", value)
                                }

                                Text { text: "Video sink"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 80 }
                                NLCombo {
                                    id: videoSinkCombo
                                    Layout.fillWidth: true
                                    model: ["waylandsink", "glimagesink", "xvimagesink", "ximagesink", "kmssink", "Disabled"]
                                    currentIndex: {
                                        var v = ScreenSharingService.videoSink;
                                        if (v === "0" || v === "disabled" || v === "Disabled") return 5;
                                        var idx = model.indexOf(v);
                                        return idx >= 0 ? idx : 0;
                                    }
                                    onActivated: {
                                        var val = model[index];
                                        ScreenSharingService.setSetting("videoSink", val === "Disabled" ? "0" : val);
                                    }
                                }

                                Text { text: "Audio sink"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 80 }
                                NLCombo {
                                    id: audioSinkCombo
                                    Layout.fillWidth: true
                                    model: ["Auto", "pipewiresink", "pulsesink", "alsasink"]
                                    currentIndex: {
                                        var v = ScreenSharingService.audioSink;
                                        if (!v) return 0;
                                        var idx = model.indexOf(v);
                                        return idx >= 0 ? idx : 0;
                                    }
                                    onActivated: ScreenSharingService.setSetting("audioSink", index === 0 ? "" : model[index])
                                }
                            }

                            Text {
                                text: "On Wayland use waylandsink; on X11 use xvimagesink or glimagesink."
                                font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-3)
                                color: Colors.outline
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }
                    }

                    // Miracast settings
                    StyledRect {
                        visible: ScreenSharingService.available && ScreenSharingService.effectiveProtocol() === "miracast"
                        variant: "pane"
                        Layout.fillWidth: true
                        Layout.preferredHeight: miracastColumn.implicitHeight + 28
                        radius: Styling.radius(0)
                        enableShadow: true

                        ColumnLayout {
                            id: miracastColumn
                            anchors.fill: parent; anchors.margins: 14; spacing: 12

                            Text {
                                text: "Miracast"
                                font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Medium
                                color: Colors.overSurfaceVariant
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                rowSpacing: 10; columnSpacing: 10

                                Text { text: "Backend"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 80 }
                                NLCombo {
                                    id: miracastBackendCombo
                                    Layout.fillWidth: true
                                    model: ["Auto", "miraclecast", "GNOME Network Displays"]
                                    currentIndex: {
                                        var v = ScreenSharingService.miracastBackend;
                                        if (v === "miraclecast") return 1;
                                        if (v === "gnd") return 2;
                                        return 0;
                                    }
                                    onActivated: {
                                        var map = ["auto", "miraclecast", "gnd"];
                                        ScreenSharingService.setSetting("miracastBackend", map[index]);
                                    }
                                }

                                Text { text: "Interface"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 80 }
                                TextField {
                                    id: ifaceInput
                                    Layout.fillWidth: true
                                    text: ScreenSharingService.miracastInterface
                                    font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1)
                                    color: Colors.overBackground
                                    placeholderText: "Auto"
                                    background: Rectangle { color: parent.hovered ? Colors.surfaceContainerHigh : Colors.surfaceContainer; radius: Styling.radius(-2); border.color: Colors.surfaceBright; border.width: 1 }
                                    onEditingFinished: ScreenSharingService.setSetting("miracastInterface", text.trim())
                                }

                                Text { text: "UIBC"; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1); color: Colors.overBackground; Layout.preferredWidth: 80 }
                                NLSwitch {
                                    checked: ScreenSharingService.miracastUibc
                                    onToggled: ScreenSharingService.setSetting("miracastUibc", checked)
                                }
                            }

                            Text {
                                text: "Miraclecast requires stopping NetworkManager/wpa_supplicant and uses sudo. GNOME Network Displays is simpler but currently sink-only."
                                font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-3)
                                color: Colors.outline
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }
                    }

                    // Chromecast source settings
                    StyledRect {
                        visible: ScreenSharingService.available && ScreenSharingService.effectiveProtocol() === "chromecast"
                        variant: "pane"
                        Layout.fillWidth: true
                        Layout.preferredHeight: chromecastColumn.implicitHeight + 28
                        radius: Styling.radius(0)
                        enableShadow: true

                        ColumnLayout {
                            id: chromecastColumn
                            anchors.fill: parent; anchors.margins: 14; spacing: 12

                            Text {
                                text: "Chromecast"
                                font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Medium
                                color: Colors.overSurfaceVariant
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                NLCombo {
                                    id: chromecastTargetCombo
                                    Layout.fillWidth: true
                                    model: ScreenSharingService.chromecastTargets.length > 0
                                        ? ScreenSharingService.chromecastTargets.map(function(t) { return typeof t === "string" ? t : (t.name || t.friendlyName || JSON.stringify(t)); })
                                        : ["No targets found"]
                                    currentIndex: 0
                                    onActivated: {
                                        if (model[index] !== "No targets found") {
                                            ScreenSharingService.setSetting("chromecastTarget", model[index]);
                                        }
                                    }
                                }
                                Button {
                                    flat: true; Layout.preferredHeight: 28
                                    contentItem: Text { text: Icons.sync; font.family: Icons.font; font.pixelSize: 14; color: Colors.outline; anchors.centerIn: parent }
                                    background: StyledRect { variant: "common"; radius: Styling.radius(-4) }
                                    onClicked: ScreenSharingService.scanChromecastTargets()
                                }
                            }

                            Text {
                                text: "Select a target and start the service to cast this desktop. Target scanning uses GNOME Network Displays."
                                font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-3)
                                color: Colors.outline
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }
                    }

                    // Log output
                    StyledRect {
                        visible: ScreenSharingService.available
                        variant: "pane"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 180
                        radius: Styling.radius(0)
                        enableShadow: true

                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 14; spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "Log"
                                    font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1)
                                    font.weight: Font.Medium
                                    color: Colors.overSurfaceVariant
                                    Layout.fillWidth: true
                                }
                                Button {
                                    flat: true; Layout.preferredHeight: 24
                                    contentItem: Text {
                                        text: Icons.trash
                                        font.family: Icons.font; font.pixelSize: 12
                                        color: Colors.outline
                                        anchors.centerIn: parent
                                    }
                                    background: StyledRect { variant: "common"; radius: Styling.radius(-4) }
                                    onClicked: logModel.clear()
                                }
                            }

                            StyledRect {
                                variant: "internalbg"
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: Styling.radius(-2)
                                clip: true

                                ListView {
                                    id: logView
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    clip: true
                                    model: ListModel { id: logModel }
                                    spacing: 2
                                    delegate: Text {
                                        required property string line
                                        width: logView.width
                                        text: line
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-3)
                                        color: Colors.outline
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: ScreenSharingService
        function onLogLine(line) {
            logModel.append({ line: line });
            if (logModel.count > 200) logModel.remove(0);
        }
    }

    component NLSwitch: Switch {
        id: nlSwitch
        indicator: Rectangle {
            implicitWidth: 36; implicitHeight: 20; radius: 10
            color: nlSwitch.checked ? Colors.primary : Qt.rgba(Colors.outline.r, Colors.outline.g, Colors.outline.b, 0.3)
            border.color: nlSwitch.checked ? Colors.primary : Colors.outline; border.width: 1
            Rectangle {
                x: nlSwitch.checked ? parent.width - width - 3 : 3
                y: (parent.height - height) / 2
                width: 14; height: 14; radius: 7
                color: nlSwitch.checked ? "#ffffff" : Colors.outline
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

    component NLCombo: ComboBox {
        id: nlCombo
        Layout.preferredWidth: 140
        Layout.preferredHeight: 28
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
}
