pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.modules.globals
import qs.config
import "../controls"

/**
 * ModesPanel — Comprehensive side panel for system modes and power profile.
 *
 * Sections:
 *   1. Active modes summary (compact status row)
 *   2. Modes           — Game Mode, Focus Mode, DND, Caffeine
 *   3. Power Profile   — Saver / Balanced / Performance cards + cycle button
 *   4. Battery         — Charge limit (if ChargeLimitService available)
 *   5. System actions  — Lock, Suspend (quick access)
 */
Item {
    id: root

    property int maxContentWidth: 480
    readonly property int contentWidth: Math.min(width, maxContentWidth)
    readonly property real sideMargin: (width - contentWidth) / 2

    readonly property int _activeModeCount:
        (GameModeService.toggled ? 1 : 0) +
        (FocusModeService.enabled ? 1 : 0)

    Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight + 16
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: contentColumn
            width: root.contentWidth
            x: root.sideMargin
            y: 8
            spacing: 12

            // ─── ACTIVE MODES SUMMARY ────────────────────────────────────
            StyledRect {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: Styling.radius(0)
                variant: root._activeModeCount > 0 ? "primary" : "bg"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 6

                    Text {
                        text: Icons.faders
                        font.family: Icons.font
                        font.pixelSize: 14
                        color: root._activeModeCount > 0
                            ? Styling.srItem("onprimary")
                            : Colors.overBackground
                    }
                    Text {
                        text: root._activeModeCount > 0
                            ? root._activeModeCount + " mode" + (root._activeModeCount === 1 ? "" : "s") + " active"
                            : "All modes off"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        font.weight: Font.Medium
                        color: root._activeModeCount > 0
                            ? Styling.srItem("onprimary")
                            : Colors.overBackground
                        Layout.fillWidth: true
                    }
                    Text {
                        visible: PowerProfile.isAvailable && PowerProfile.currentProfile
                        text: PowerProfile.isAvailable ? PowerProfile.getProfileIcon(PowerProfile.currentProfile) : ""
                        font.family: Icons.font
                        font.pixelSize: 16
                        color: root._activeModeCount > 0
                            ? Styling.srItem("onprimary")
                            : Colors.overBackground
                    }
                }
            }

            // ─── MODES GROUP ─────────────────────────────────────────────
            PanelTitlebar {
                title: "Modes"
                statusText: root._activeModeCount + " active"
            }

            StyledRect {
                variant: "bg"
                Layout.fillWidth: true
                Layout.preferredHeight: modesCol.implicitHeight + 16
                radius: Styling.radius(0)

                ColumnLayout {
                    id: modesCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    // Game Mode row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: Icons.gamepad
                            font.family: Icons.font
                            font.pixelSize: 18
                            color: GameModeService.toggled ? Styling.srItem("primary") : Colors.overBackground
                            Layout.preferredWidth: 24
                        }
                        Text {
                            text: "Game Mode"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            color: Colors.overBackground
                            Layout.fillWidth: true
                        }
                        Switch {
                            id: gameModeSwitch
                            checked: GameModeService.toggled
                            onCheckedChanged: {
                                if (checked !== GameModeService.toggled) {
                                    GameModeService.toggle();
                                }
                            }

                            indicator: Rectangle {
                                implicitWidth: 40
                                implicitHeight: 20
                                x: gameModeSwitch.leftPadding
                                y: parent.height / 2 - height / 2
                                radius: height / 2
                                color: gameModeSwitch.checked ? Styling.srItem("overprimary") : Colors.surfaceBright
                                border.color: gameModeSwitch.checked ? Styling.srItem("overprimary") : Colors.outline

                                Behavior on color {
                                    enabled: Anim.animationsEnabled
                                    ColorAnimation { duration: Anim.standardSmall }
                                }

            Rectangle {
                                    x: gameModeSwitch.checked ? parent.width - width - 2 : 2
                                    y: 2
                                    width: parent.height - 4
                                    height: width
                                    radius: width / 2
                                    color: gameModeSwitch.checked ? Colors.background : Colors.overSurfaceVariant

                                    Behavior on x {
                                        enabled: Anim.animationsEnabled
                                        NumberAnimation {
                                            duration: Anim.standardSmall
                                            easing.type: Anim.easing("standard").type
                                            easing.bezierCurve: Anim.easing("standard").bezierCurve
                                        }
                                    }
                                }
                            }
                            background: null
                        }
                    }

                    // Focus Mode row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: Icons.aperture
                            font.family: Icons.font
                            font.pixelSize: 18
                            color: FocusModeService.enabled ? Styling.srItem("primary") : Colors.overBackground
                            Layout.preferredWidth: 24
                        }
                        Text {
                            text: "Focus Mode"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            color: Colors.overBackground
                            Layout.fillWidth: true
                        }
                        Switch {
                            id: focusModeSwitch
                            checked: FocusModeService.enabled
                            onCheckedChanged: {
                                if (checked !== FocusModeService.enabled) {
                                    FocusModeService.toggle();
                                }
                            }

                            indicator: Rectangle {
                                implicitWidth: 40
                                implicitHeight: 20
                                x: focusModeSwitch.leftPadding
                                y: parent.height / 2 - height / 2
                                radius: height / 2
                                color: focusModeSwitch.checked ? Styling.srItem("overprimary") : Colors.surfaceBright
                                border.color: focusModeSwitch.checked ? Styling.srItem("overprimary") : Colors.outline

                                Behavior on color {
                                    enabled: Anim.animationsEnabled
                                    ColorAnimation { duration: Anim.standardSmall }
                                }

            Rectangle {
                                    x: focusModeSwitch.checked ? parent.width - width - 2 : 2
                                    y: 2
                                    width: parent.height - 4
                                    height: width
                                    radius: width / 2
                                    color: focusModeSwitch.checked ? Colors.background : Colors.overSurfaceVariant

                                    Behavior on x {
                                        enabled: Anim.animationsEnabled
                                        NumberAnimation {
                                            duration: Anim.standardSmall
                                            easing.type: Anim.easing("standard").type
                                            easing.bezierCurve: Anim.easing("standard").bezierCurve
                                        }
                                    }
                                }
                            }
                            background: null
                        }
                    }

                }
            }

            // ─── POWER PROFILE GROUP ─────────────────────────────────────
            PanelTitlebar {
                title: "Power Profile"
                statusText: PowerProfile.isAvailable
                    ? (PowerProfile.currentProfile
                        ? PowerProfile.getProfileDisplayName(PowerProfile.currentProfile)
                        : "")
                    : "Unavailable"
                statusColor: PowerProfile.isAvailable
                    ? Styling.srItem("overprimary")
                    : Styling.srItem("error")
            }

            StyledRect {
                variant: "bg"
                Layout.fillWidth: true
                Layout.preferredHeight: profilesRow.implicitHeight + 16
                radius: Styling.radius(0)
                visible: PowerProfile.isAvailable

                RowLayout {
                    id: profilesRow
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    // Power-saver button
                    StyledRect {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        variant: PowerProfile.currentProfile === "power-saver" ? "primary" : "common"
                        radius: Styling.radius(-4)
                        Layout.alignment: Qt.AlignHCenter

                        Text {
                            anchors.centerIn: parent
                            text: PowerProfile.getProfileIcon("power-saver")
                            font.family: Icons.font
                            font.pixelSize: 18
                            color: PowerProfile.currentProfile === "power-saver"
                                ? Styling.srItem("onprimary")
                                : (Styling.srItem("overprimary") || Colors.foreground)
                        }
                        StateLayer {
                            anchors.fill: parent
                            onClicked: PowerProfile.setProfile("power-saver")
                        }
                    }

                    // Balanced button
                    StyledRect {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        variant: PowerProfile.currentProfile === "balanced" ? "primary" : "common"
                        radius: Styling.radius(-4)
                        Layout.alignment: Qt.AlignHCenter

                        Text {
                            anchors.centerIn: parent
                            text: PowerProfile.getProfileIcon("balanced")
                            font.family: Icons.font
                            font.pixelSize: 18
                            color: PowerProfile.currentProfile === "balanced"
                                ? Styling.srItem("onprimary")
                                : (Styling.srItem("overprimary") || Colors.foreground)
                        }
                        StateLayer {
                            anchors.fill: parent
                            onClicked: PowerProfile.setProfile("balanced")
                        }
                    }

                    // Performance button
                    StyledRect {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        variant: PowerProfile.currentProfile === "performance" ? "primary" : "common"
                        radius: Styling.radius(-4)
                        Layout.alignment: Qt.AlignHCenter

                        Text {
                            anchors.centerIn: parent
                            text: PowerProfile.getProfileIcon("performance")
                            font.family: Icons.font
                            font.pixelSize: 18
                            color: PowerProfile.currentProfile === "performance"
                                ? Styling.srItem("onprimary")
                                : (Styling.srItem("overprimary") || Colors.foreground)
                        }
                        StateLayer {
                            anchors.fill: parent
                            onClicked: PowerProfile.setProfile("performance")
                        }
                    }
                }
            }

            // Cycle button (always visible if PowerProfile available)
            StyledRect {
                visible: PowerProfile.isAvailable
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: Styling.radius(0)
                variant: "common"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Text {
                        text: Icons.sync
                        font.family: Icons.font
                        font.pixelSize: 14
                        color: Colors.overBackground
                    }
                    Text {
                        text: "Cycle profile"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        color: Colors.overBackground
                        Layout.fillWidth: true
                    }
                    Text {
                        text: PowerProfile.isAvailable && PowerProfile.currentProfile
                            ? PowerProfile.getProfileIcon(PowerProfile.currentProfile)
                            : ""
                        font.family: Icons.font
                        font.pixelSize: 14
                        color: Colors.overBackground
                    }
                }
                StateLayer {
                    anchors.fill: parent
                    onClicked: PowerProfile.cycle()
                }
            }

            // ─── BATTERY GROUP ───────────────────────────────────────────
            PanelTitlebar {
                title: "Battery"
                statusText: ChargeLimitService.isAvailable
                    ? (ChargeLimitService.enabled ? ChargeLimitService.limit + "%" : "Off")
                    : (Battery.available
                        ? Math.round(Battery.percentage) + "%" + (Battery.isCharging ? " ↑" : "")
                        : "—")
                statusColor: ChargeLimitService.isAvailable && ChargeLimitService.enabled
                    ? Styling.srItem("overprimary")
                    : Colors.overBackground
            }

            // Auto power-saver
            StyledRect {
                variant: "bg"
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: Styling.radius(0)
                visible: Battery.available && PowerProfile.isAvailable

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    Text {
                        text: Icons.batteryMedium
                        font.family: Icons.font
                        font.pixelSize: 18
                        color: Config.system.batteryNotifications?.autoPowerSave
                            ? Styling.srItem("primary")
                            : Colors.overBackground
                        Layout.preferredWidth: 24
                    }
                    Text {
                        text: "Auto power-save at " + (Config.system.batteryNotifications?.powerSaveThreshold ?? 15) + "%"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(0)
                        color: Colors.overBackground
                        Layout.fillWidth: true
                    }
                    Switch {
                        id: autoPowerSaveSwitch
                        checked: Config.system.batteryNotifications?.autoPowerSave ?? false
                        onCheckedChanged: {
                            if (checked !== (Config.system.batteryNotifications?.autoPowerSave ?? false)) {
                                GlobalStates.markShellChanged();
                                Config.system.batteryNotifications.autoPowerSave = checked;
                            }
                        }

                        indicator: Rectangle {
                            implicitWidth: 40
                            implicitHeight: 20
                            x: autoPowerSaveSwitch.leftPadding
                            y: parent.height / 2 - height / 2
                            radius: height / 2
                            color: autoPowerSaveSwitch.checked ? Styling.srItem("overprimary") : Colors.surfaceBright
                            border.color: autoPowerSaveSwitch.checked ? Styling.srItem("overprimary") : Colors.outline

                            Behavior on color {
                                enabled: Anim.animationsEnabled
                                ColorAnimation { duration: Anim.standardSmall }
                            }

        Rectangle {
                                x: autoPowerSaveSwitch.checked ? parent.width - width - 2 : 2
                                y: 2
                                width: parent.height - 4
                                height: width
                                radius: width / 2
                                color: autoPowerSaveSwitch.checked ? Colors.background : Colors.overSurfaceVariant

                                Behavior on x {
                                    enabled: Anim.animationsEnabled
                                    NumberAnimation {
                                        duration: Anim.standardSmall
                                        easing.type: Anim.easing("standard").type
                                        easing.bezierCurve: Anim.easing("standard").bezierCurve
                                    }
                                }
                            }
                        }
                        background: null
                    }
                }
            }

            // Charge limit
            StyledRect {
                variant: "bg"
                Layout.fillWidth: true
                Layout.preferredHeight: chargeLimitCol.implicitHeight + 16
                radius: Styling.radius(0)
                visible: ChargeLimitService.isAvailable

                ColumnLayout {
                    id: chargeLimitCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: Icons.batteryCharging
                            font.family: Icons.font
                            font.pixelSize: 18
                            color: ChargeLimitService.enabled ? Styling.srItem("primary") : Colors.overBackground
                            Layout.preferredWidth: 24
                        }
                        Text {
                            text: "Charge Limit (" + ChargeLimitService.limit + "%)"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            color: Colors.overBackground
                            Layout.fillWidth: true
                        }
                        Switch {
                            id: chargeLimitSwitch
                            checked: ChargeLimitService.enabled
                            onCheckedChanged: {
                                if (checked !== ChargeLimitService.enabled) {
                                    ChargeLimitService.setEnabled(checked);
                                }
                            }

                            indicator: Rectangle {
                                implicitWidth: 40
                                implicitHeight: 20
                                x: chargeLimitSwitch.leftPadding
                                y: parent.height / 2 - height / 2
                                radius: height / 2
                                color: chargeLimitSwitch.checked ? Styling.srItem("overprimary") : Colors.surfaceBright
                                border.color: chargeLimitSwitch.checked ? Styling.srItem("overprimary") : Colors.outline

                                Behavior on color {
                                    enabled: Anim.animationsEnabled
                                    ColorAnimation { duration: Anim.standardSmall }
                                }

            Rectangle {
                                    x: chargeLimitSwitch.checked ? parent.width - width - 2 : 2
                                    y: 2
                                    width: parent.height - 4
                                    height: width
                                    radius: width / 2
                                    color: chargeLimitSwitch.checked ? Colors.background : Colors.overSurfaceVariant

                                    Behavior on x {
                                        enabled: Anim.animationsEnabled
                                        NumberAnimation {
                                            duration: Anim.standardSmall
                                            easing.type: Anim.easing("standard").type
                                            easing.bezierCurve: Anim.easing("standard").bezierCurve
                                        }
                                    }
                                }
                            }
                            background: null
                        }
                    }

                    StyledSlider {
                        Layout.fillWidth: true
                        progressColor: Styling.srItem("overprimary")
                        tooltipText: `${Math.round(value * 50 + 50)}%`
                        stepSize: 0.1   // 5% steps within 50-100 range
                        snapMode: "always"
                        value: (ChargeLimitService.limit - 50) / 50
                        enabled: ChargeLimitService.enabled

                        onValueChanged: {
                            const pct = Math.round(value * 50 + 50);
                            if (pct !== ChargeLimitService.limit) {
                                ChargeLimitService.setLimit(pct);
                            }
                        }
                    }
                }
            }

            // Battery unavailable hint
            Text {
                visible: !Battery.available && !ChargeLimitService.isAvailable
                text: "Battery not detected"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                color: Colors.outline
                Layout.alignment: Qt.AlignHCenter
            }

            // ─── SYSTEM ACTIONS ──────────────────────────────────────────
            PanelTitlebar {
                title: "System"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledRect {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: Styling.radius(0)
                    variant: "common"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 6
                        Text {
                            text: Icons.lock
                            font.family: Icons.font
                            font.pixelSize: 14
                            color: Colors.overBackground
                        }
                        Text {
                            text: "Lock"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            color: Colors.overBackground
                            Layout.fillWidth: true
                        }
                    }
                StateLayer {
                    anchors.fill: parent
                    onClicked: PowerProfile.cycle()
                }
                }

                StyledRect {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: Styling.radius(0)
                    variant: "common"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 6
                        Text {
                            text: Icons.suspend
                            font.family: Icons.font
                            font.pixelSize: 14
                            color: Colors.overBackground
                        }
                        Text {
                            text: "Suspend"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            color: Colors.overBackground
                            Layout.fillWidth: true
                        }
                    }
                    StateLayer {
                        anchors.fill: parent
                        onClicked: cliSuspendProc.running = true
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 8
            }
        }
    }

    property Process cliSuspendProc: Process {
        id: cliSuspendProc
        command: ["nothingless", "suspend"]
        running: false
    }
}
