pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.modules.components
import qs.modules.theme
import qs.modules.services
import qs.modules.globals
import qs.config

PanelWindow {
    id: root

    property ShellScreen targetScreen
    screen: targetScreen

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "nothingless:osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    WlrLayershell.margins.bottom: 100

    color: "transparent"

    visible: GlobalStates.osdVisible

    // Internal state for responsiveness
    property real osdValue: 0
    property bool osdMuted: false

    // Centering wrapper
    Item {
        anchors.fill: parent

        StyledRect {
            id: osdRect
            variant: "popup"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            implicitWidth: 240
            implicitHeight: 56
            radius: Styling.radius(12)

            opacity: GlobalStates.osdVisible ? 1 : 0
            scale: GlobalStates.osdVisible ? 1 : 0.92
            transformOrigin: Item.Bottom

            Behavior on opacity {
                AnimatedBehavior { type: "standard"; size: "normal" }
            }
            Behavior on scale {
                AnimatedBehavior {
                    type: "emphasized"
                    size: "normal"
                    useSpring: true
                    springName: "snappy"
                }
            }

            visible: opacity > 0

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 24
                anchors.topMargin: 8
                anchors.bottomMargin: 8
                spacing: 14

                Text {
                    id: iconText
                    text: {
                        if (GlobalStates.osdIndicator === "volume") {
                            return Audio.volumeIcon(root.osdValue, root.osdMuted);
                        } else if (GlobalStates.osdIndicator === "mic") {
                            return root.osdMuted ? Icons.micSlash : Icons.mic;
                        } else {
                            return Icons.sun;
                        }
                    }
                    font.family: Icons.font
                    font.pixelSize: 22
                    color: Colors.overBackground
                    Layout.alignment: Qt.AlignVCenter

                    rotation: GlobalStates.osdIndicator === "brightness" ? (root.osdValue * 180) : 0
                    scale: GlobalStates.osdIndicator === "brightness" ? (0.8 + (root.osdValue * 0.2)) : 1

                    Behavior on rotation {
                        AnimatedBehavior {
                            type: "standard"
                            size: "normal"
                            useSpring: true
                            springName: "snappy"
                        }
                    }

                    Behavior on scale {
                        AnimatedBehavior {
                            type: "standard"
                            size: "normal"
                            useSpring: true
                            springName: "snappy"
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            text: {
                                if (GlobalStates.osdIndicator === "volume")
                                    return "VOLUME";
                                if (GlobalStates.osdIndicator === "mic")
                                    return "MICROPHONE";
                                if (GlobalStates.osdIndicator === "brightness")
                                    return "BRIGHTNESS";
                                return "";
                            }
                            font.family: Config.theme.monoFont
                            font.pixelSize: 10
                            font.bold: true
                            font.letterSpacing: 3
                            color: Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.55)
                            Layout.alignment: Qt.AlignBottom
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        Text {
                            text: Math.round(root.osdValue * 100)
                            font.family: Config.theme.monoFont
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 0.5
                            color: Colors.overBackground
                            Layout.alignment: Qt.AlignBottom
                        }
                    }

                    StyledSlider {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 12
                        value: root.osdValue
                        wavy: false
                        enabled: false
                        thickness: 3
                        handleSpacing: 0
                        progressColor: root.osdMuted ? Colors.outline : Styling.srItem("overprimary")
                        backgroundColor: Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.2)
                    }
                }
            }
        }
    }

    // Close on click or hover
    MouseArea {
        anchors.fill: parent
        onEntered: {
            hideTimer.stop();
            hideTimer.triggered();
        }
        hoverEnabled: true
    }

    Timer {
        id: hideTimer
        interval: 2500
        onTriggered: GlobalStates.osdVisible = false
    }

    Connections {
        target: GlobalStates
        function onOsdVisibleChanged() {
            if (GlobalStates.osdVisible) {
                hideTimer.restart();
            }
        }
    }

    // Services connections - Direct and responsive
    Connections {
        target: Audio
        function onVolumeChanged(volume, muted, node) {
            root.osdValue = volume;
            root.osdMuted = muted;
            GlobalStates.osdIndicator = "volume";
            GlobalStates.osdVisible = true;
            hideTimer.restart();
        }
        function onMicVolumeChanged(volume, muted, node) {
            root.osdValue = volume;
            root.osdMuted = muted;
            GlobalStates.osdIndicator = "mic";
            GlobalStates.osdVisible = true;
            hideTimer.restart();
        }
    }

    Connections {
        target: Brightness
        function onBrightnessChanged(value, screen) {
            // Check if the change happened on THIS screen or if it's a sync change
            if (!screen || !root.targetScreen || screen.name === root.targetScreen.name || Brightness.syncBrightness) {
                root.osdValue = value;
                root.osdMuted = false;
                GlobalStates.osdIndicator = "brightness";
                GlobalStates.osdVisible = true;
                hideTimer.restart();
            }
        }
    }
Component.onDestruction: {
    hideTimer.stop ? hideTimer.stop() : undefined;
    hideTimer.running !== undefined ? hideTimer.running = false : undefined;
    hideTimer.destroy !== undefined ? hideTimer.destroy() : undefined;
}
}
