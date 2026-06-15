import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.modules.globals
import qs.config
import "../controls"

StyledRect {
    id: root
    variant: "pane"
    Layout.alignment: Qt.AlignHCenter
    implicitWidth: internalBgRect.implicitWidth + 8
    implicitHeight: internalBgRect.implicitHeight + 8
    radius: Styling.radius(4)
    
    property int expandedPanel: -1 // -1: none, 0: wifi, 1: bluetooth, 2: modes

    onVisibleChanged: {
        if (!visible) {
            root.expandedPanel = -1;
        } else {
            BluetoothService.initialize();
        }
    }
    
    Behavior on implicitHeight {
        enabled: Anim.animationsEnabled
        NumberAnimation {
            duration: Anim.standardNormal
            easing.type: Anim.easing("standard").type
                        easing.bezierCurve: Anim.easing("standard").bezierCurve
        }
    }

    ColumnLayout {
        id: columnLayout
        anchors.fill: parent
        anchors.margins: 4
        spacing: 0
        
        StyledRect {
            id: internalBgRect
            variant: "internalbg"
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: buttonRow.implicitWidth + 8
            implicitHeight: buttonRow.implicitHeight + 8
            radius: Styling.radius(0)

            RowLayout {
                id: buttonRow
                anchors.centerIn: parent
                spacing: 4

                ControlButton {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    iconName: {
                        if (!NetworkService.wifiEnabled)
                            return Icons.wifiOff;
                        const strength = NetworkService.networkStrength;
                        if (strength === 0)
                            return Icons.wifiHigh;
                        if (strength < 25)
                            return Icons.wifiNone;
                        if (strength < 50)
                            return Icons.wifiLow;
                        if (strength < 75)
                            return Icons.wifiMedium;
                        return Icons.wifiHigh;
                    }
                    isActive: NetworkService.wifiEnabled || root.expandedPanel === 0
                    tooltipText: NetworkService.wifiEnabled ? "Wi-Fi: On" : "Wi-Fi: Off"
                    onClicked: NetworkService.toggleWifi()
                    onRightClicked: root.togglePanel(0)
                    onLongPressed: root.togglePanel(0)
                }

                ControlButton {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    iconName: {
                        if (!BluetoothService.enabled)
                            return Icons.bluetoothOff;
                        if (BluetoothService.connected)
                            return Icons.bluetoothConnected;
                        return Icons.bluetooth;
                    }
                    isActive: BluetoothService.enabled || root.expandedPanel === 1
                    tooltipText: {
                        if (!BluetoothService.enabled)
                            return "Bluetooth: Off";
                        if (BluetoothService.connected)
                            return "Bluetooth: Connected";
                        return "Bluetooth: On";
                    }
                    onClicked: BluetoothService.toggle()
                    onRightClicked: root.togglePanel(1)
                    onLongPressed: root.togglePanel(1)
                }

                ControlButton {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    iconName: Icons.nightLight
                    isActive: NightLightService.active
                    tooltipText: NightLightService.active ? "Night Light: On" : "Night Light: Off"
                    onClicked: NightLightService.toggle()
                }

                ControlButton {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    iconName: Icons.caffeine
                    isActive: CaffeineService.inhibit
                    tooltipText: CaffeineService.inhibit ? "Caffeine: On" : "Caffeine: Off"
                    onClicked: CaffeineService.toggleInhibit()
                }

                // Modes panel launcher — opens ModesPanel (game/focus/dnd/profile/battery)
                ControlButton {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    iconName: Icons.faders
                    isActive: root.expandedPanel === 2
                            || GameModeService.toggled
                            || FocusModeService.enabled
                            || GlobalStates.notificationsDnd
                    tooltipText: {
                        const flags = [];
                        if (GameModeService.toggled) flags.push("Game");
                        if (FocusModeService.enabled) flags.push("Focus");
                        if (GlobalStates.notificationsDnd) flags.push("DND");
                        if (flags.length > 0) return "Modes: " + flags.join(" + ");
                        return "Modes & Power";
                    }
                    onClicked: root.togglePanel(2)
                    onRightClicked: root.togglePanel(2)
                    onLongPressed: root.togglePanel(2)
                }
            }
        }
    }
    
    function togglePanel(index) {
        if (root.expandedPanel === index) {
            root.expandedPanel = -1;
        } else {
            root.expandedPanel = index;
        }
    }
}
