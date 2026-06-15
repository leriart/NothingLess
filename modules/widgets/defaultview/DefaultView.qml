import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs.modules.theme
import qs.modules.services
import qs.modules.notch
import qs.modules.components
import qs.modules.bar.clock
import qs.config

Item {
    id: root
    anchors.top: parent.top
    focus: false

    // Layout constants
    readonly property int notificationPadding: 16
    readonly property int notificationPaddingBottom: Config.notchTheme === "island" ? 20 : 16
    readonly property int notificationPaddingTop: 8

    // State
    readonly property bool hasActiveNotifications: Notifications.popupList.length > 0
    readonly property var activePlayer: MprisController.activePlayer
    property bool notchHovered: false
    property bool parentHoverActive: false
    property bool isNavigating: false

    // Position detection
    readonly property string notchPosition: Config.notchPosition ?? "top"
    readonly property bool isBottom: notchPosition === "bottom"

    HoverHandler {
        id: contentHoverHandler
    }

    readonly property bool expandedState: contentHoverHandler.hovered || notchHovered || parentHoverActive || isNavigating || Visibilities.playerMenuOpen

    property bool mediaHoverExpanded: false

    Timer {
        id: mediaHoverTimer
        interval: 1000
        running: expandedState && activePlayer !== null && !hasActiveNotifications && !mediaHoverExpanded && !(Config.notch.disableHoverExpansion ?? true)
        onTriggered: mediaHoverExpanded = true
    }

    onExpandedStateChanged: {
        if (!expandedState) {
            mediaHoverExpanded = false;
        }
    }

    onActivePlayerChanged: {
        if (!activePlayer) {
            mediaHoverExpanded = false;
        }
    }

    property real mainRowMargin: 16

    Behavior on mainRowMargin {
        enabled: Anim.animationsEnabled
        NumberAnimation {
            duration: Anim.standardNormal
            easing.type: Anim.springSnappy().type
            easing.bezierCurve: Anim.springSnappy().bezierCurve
        }
    }

    // Metrics mode
    readonly property bool metricsActive: Config.notch && Config.notch.showMetrics === true

    // Dynamic notch metrics model (ordered by notchMetricsOrder from StateService)
    property ListModel notchMetrics: ListModel {}
    property var notchOrder: []

    function rebuildNotchMetrics() {
        notchMetrics.clear()
        var order = StateService.get("notchMetricsOrder", ["cpu","gpu","fps","ram","disk"])
        notchOrder = order
        var items = {}

        // Unified CPU: temp + usage % + power
        items.cpu = {
            id: "cpu", label: "CPU",
            visible: SystemResources.cpuUsageEnabled || SystemResources.cpuTempEnabled || SystemResources.cpuPowerEnabled,
            labelColor: SystemResources.metricColorCpu,
            valueText: (SystemResources.metricsAvailable && SystemResources.cpuTempEnabled && SystemResources.cpuTemp > 0) ? SystemResources.cpuTemp.toString() : (SystemResources.metricsAvailable && SystemResources.cpuUsageEnabled) ? Math.round(SystemResources.cpuUsage).toString() : "--",
            valueUnit: (SystemResources.metricsAvailable && SystemResources.cpuTempEnabled && SystemResources.cpuTemp > 0) ? "°C" : (SystemResources.metricsAvailable && SystemResources.cpuUsageEnabled) ? "%" : "",
            subValue: (SystemResources.metricsAvailable && SystemResources.cpuPowerEnabled && SystemResources.cpuPower > 0) ? SystemResources.cpuPower.toFixed(0) : "",
            subUnit: (SystemResources.metricsAvailable && SystemResources.cpuPowerEnabled && SystemResources.cpuPower > 0) ? "W" : ""
        }
        // Unified GPU: temp + usage % + power
        items.gpu = {
            id: "gpu", label: "GPU",
            visible: SystemResources.gpuUsageEnabled || SystemResources.gpuTempEnabled || SystemResources.gpuPowerEnabled,
            labelColor: SystemResources.metricColorGpu,
            valueText: (SystemResources.metricsAvailable && SystemResources.gpuTempEnabled && SystemResources.gpuTemp > 0) ? SystemResources.gpuTemp.toString() : (SystemResources.metricsAvailable && SystemResources.gpuUsageEnabled && SystemResources.gpuUsages.length > 0) ? Math.round(SystemResources.gpuUsages[0]).toString() : "--",
            valueUnit: (SystemResources.metricsAvailable && SystemResources.gpuTempEnabled && SystemResources.gpuTemp > 0) ? "°C" : (SystemResources.metricsAvailable && SystemResources.gpuUsageEnabled) ? "%" : "",
            subValue: (SystemResources.metricsAvailable && SystemResources.gpuPowerEnabled && SystemResources.gpuPower > 0) ? SystemResources.gpuPower.toFixed(0) : "",
            subUnit: (SystemResources.metricsAvailable && SystemResources.gpuPowerEnabled && SystemResources.gpuPower > 0) ? "W" : ""
        }
        // FPS
        items.fps = {
            id: "fps", label: "FPS", visible: SystemResources.fpsEnabled,
            labelColor: SystemResources.metricColorFps,
            valueText: (SystemResources.metricsAvailable && SystemResources.fpsEnabled && SystemResources.fps > 0) ? Math.round(SystemResources.fps).toString() : "--",
            valueUnit: "", subValue: "", subUnit: ""
        }
        // RAM
        items.ram = {
            id: "ram", label: "RAM", visible: SystemResources.ramEnabled,
            labelColor: SystemResources.metricColorRam,
            valueText: (SystemResources.metricsAvailable && SystemResources.ramEnabled && SystemResources.ramUsage > 0) ? Math.round(SystemResources.ramUsage).toString() : "--",
            valueUnit: (SystemResources.metricsAvailable && SystemResources.ramEnabled && SystemResources.ramUsage > 0) ? "%" : "",
            subValue: "", subUnit: ""
        }
        // Disk
        items.disk = {
            id: "disk", label: "DSK", visible: SystemResources.diskEnabled,
            labelColor: SystemResources.metricColorDisk,
            valueText: (SystemResources.metricsAvailable && SystemResources.diskEnabled && SystemResources.validDisks.length > 0 && SystemResources.diskUsage[SystemResources.validDisks[0]]) ? Math.round(SystemResources.diskUsage[SystemResources.validDisks[0]]).toString() : "--",
            valueUnit: (SystemResources.metricsAvailable && SystemResources.diskEnabled && SystemResources.validDisks.length > 0) ? "%" : "",
            subValue: "", subUnit: ""
        }

        for (var i = 0; i < order.length; i++) {
            var it = items[order[i]]
            if (it) notchMetrics.append(it)
        }
    }

    // Rebuild when any toggle or color changes
    Connections {
        target: SystemResources
        function onCpuUsageEnabledChanged() { rebuildNotchMetrics() }
        function onCpuTempEnabledChanged() { rebuildNotchMetrics() }
        function onCpuPowerEnabledChanged() { rebuildNotchMetrics() }
        function onRamEnabledChanged() { rebuildNotchMetrics() }
        function onGpuUsageEnabledChanged() { rebuildNotchMetrics() }
        function onGpuTempEnabledChanged() { rebuildNotchMetrics() }
        function onGpuPowerEnabledChanged() { rebuildNotchMetrics() }
        function onFpsEnabledChanged() { rebuildNotchMetrics() }
        function onDiskEnabledChanged() { rebuildNotchMetrics() }
        function onMetricColorCpuChanged() { rebuildNotchMetrics() }
        function onMetricColorGpuChanged() { rebuildNotchMetrics() }
        function onMetricColorFpsChanged() { rebuildNotchMetrics() }
        function onMetricColorRamChanged() { rebuildNotchMetrics() }
        function onMetricColorDiskChanged() { rebuildNotchMetrics() }
        function onNotchVersionChanged() { rebuildNotchMetrics() }
    }

    Component.onCompleted: rebuildNotchMetrics()
    readonly property real metricsRowWidth: (metricsActive && metricsModeRow.visible) ? metricsModeRow.implicitWidth : 0

    // Computed dimensions
    readonly property real mainRowContentWidth: metricsActive
        ? Math.max(metricsRowWidth + mainRowMargin * 2, 200)
        : (200
            + (userInfo.visible ? userInfo.width + mainRow.spacing : 0)
            + (separator1.visible ? separator1.width + mainRow.spacing : 0)
            + (clockRow.visible ? clockRow.implicitWidth + mainRow.spacing : 0)
            + (separator2.visible ? separator2.width + mainRow.spacing : 0)
            + (weatherRow.visible ? weatherRow.implicitWidth + mainRow.spacing : 0)
            + (notifIndicatorStandalone.visible ? notifIndicatorStandalone.width + mainRow.spacing : 0)
            + mainRowMargin)
    readonly property real mainRowHeight: Config.showBackground ? (Config.notchTheme === "island" ? 36 : 44) : (Config.notchTheme === "island" ? 36 : 40)
    readonly property real notificationMinWidth: expandedState ? 420 : 320
    readonly property real notificationContainerHeight: notificationView.implicitHeight + notificationPaddingTop + notificationPaddingBottom

    implicitWidth: Math.round((hasActiveNotifications || mediaHoverExpanded) ? Math.max(notificationMinWidth + (notificationPadding * 2), mainRowContentWidth) : mainRowContentWidth)

    implicitHeight: hasActiveNotifications ? mainRowHeight + notificationContainerHeight : mainRowHeight

    Behavior on implicitWidth {
        enabled: Anim.animationsEnabled
        NumberAnimation {
            duration: Anim.standardNormal
            easing.type: Anim.springSnappy().type
            easing.bezierCurve: Anim.springSnappy().bezierCurve
        }
    }

    Keys.onPressed: event => {
        if (expandedState && activePlayer) {
            if (event.key === Qt.Key_Space) {
                activePlayer.togglePlaying();
                event.accepted = true;
            } else if (event.key === Qt.Key_Left && activePlayer.canSeek) {
                activePlayer.position = Math.max(0, activePlayer.position - 10);
                event.accepted = true;
            } else if (event.key === Qt.Key_Right && activePlayer.canSeek) {
                activePlayer.position = Math.min(activePlayer.length, activePlayer.position + 10);
                event.accepted = true;
            } else if (event.key === Qt.Key_Up && activePlayer.canGoPrevious) {
                activePlayer.previous();
                event.accepted = true;
            } else if (event.key === Qt.Key_Down && activePlayer.canGoNext) {
                activePlayer.next();
                event.accepted = true;
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: 0

        // If bottom position, we populate content bottom-up.
        // But Column fills top-down. 
        // We can move the mainRow to the bottom of this Column or use a different layout strategy.
        // Easiest is to reverse the visual order by using move property or just conditionally rendering order? 
        // QML items can be reordered visually? No.
        // We can use States or just conditional anchoring if not using Column.
        // But this uses Column.

        // Reorder children based on position:
        // Top: mainRow then notificationContainer
        // Bottom: notificationContainer then mainRow
        
        // Since we cannot dynamically reorder children in a Column easily without Repeater/Loader tricks,
        // we can use Item + Anchors instead of Column for full control.
        
    }

    Item {
        anchors.fill: parent
        clip: true

        // Metrics mode content (replaces mainRow when showMetrics is active)
        RowLayout {
            id: metricsModeRow
            visible: metricsActive

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            height: mainRowHeight
            spacing: 16
            z: 3

            MetricsGroupWrapper {
                visible: SystemResources.cpuUsageEnabled || SystemResources.cpuTempEnabled || SystemResources.cpuPowerEnabled
                label: "CPU"
                labelColor: SystemResources.metricColorCpu
                valueText: (SystemResources.metricsAvailable && SystemResources.cpuTempEnabled && SystemResources.cpuTemp > 0) ? (SystemResources.cpuTemp.toString() + (SystemResources.metricsAvailable && SystemResources.cpuUsageEnabled ? "° " + Math.round(SystemResources.cpuUsage).toString() : "")) : (SystemResources.metricsAvailable && SystemResources.cpuUsageEnabled) ? Math.round(SystemResources.cpuUsage).toString() : "--"
                valueUnit: (SystemResources.metricsAvailable && SystemResources.cpuTempEnabled && SystemResources.cpuTemp > 0) ? (SystemResources.metricsAvailable && SystemResources.cpuUsageEnabled ? "" : "°C") : (SystemResources.metricsAvailable && SystemResources.cpuUsageEnabled) ? "%" : ""
                subValue: (SystemResources.metricsAvailable && SystemResources.cpuPowerEnabled && SystemResources.cpuPower > 0) ? SystemResources.cpuPower.toFixed(0) : ""
                subUnit: (SystemResources.metricsAvailable && SystemResources.cpuPowerEnabled && SystemResources.cpuPower > 0) ? "W" : ""
            }

            MetricsGroupWrapper {
                visible: SystemResources.gpuUsageEnabled || SystemResources.gpuTempEnabled || SystemResources.gpuPowerEnabled
                label: "GPU"
                labelColor: SystemResources.metricColorGpu
                valueText: (SystemResources.metricsAvailable && SystemResources.gpuTempEnabled && SystemResources.gpuTemp > 0) ? (SystemResources.gpuTemp.toString() + (SystemResources.metricsAvailable && SystemResources.gpuUsageEnabled && SystemResources.gpuUsages.length > 0 ? "° " + Math.round(SystemResources.gpuUsages[0]).toString() : "")) : (SystemResources.metricsAvailable && SystemResources.gpuUsageEnabled && SystemResources.gpuUsages.length > 0) ? Math.round(SystemResources.gpuUsages[0]).toString() : "--"
                valueUnit: (SystemResources.metricsAvailable && SystemResources.gpuTempEnabled && SystemResources.gpuTemp > 0) ? (SystemResources.metricsAvailable && SystemResources.gpuUsageEnabled ? "" : "°C") : (SystemResources.metricsAvailable && SystemResources.gpuUsageEnabled) ? "%" : ""
                subValue: (SystemResources.metricsAvailable && SystemResources.gpuPowerEnabled && SystemResources.gpuPower > 0) ? SystemResources.gpuPower.toFixed(0) : ""
                subUnit: (SystemResources.metricsAvailable && SystemResources.gpuPowerEnabled && SystemResources.gpuPower > 0) ? "W" : ""
            }

            MetricsGroupWrapper {
                visible: SystemResources.ramEnabled
                label: "RAM"
                labelColor: SystemResources.metricColorRam
                valueText: (SystemResources.metricsAvailable && SystemResources.ramEnabled && SystemResources.ramUsage > 0) ? Math.round(SystemResources.ramUsage).toString() : "--"
                valueUnit: (SystemResources.metricsAvailable && SystemResources.ramEnabled && SystemResources.ramUsage > 0) ? "%" : ""
                subValue: ""
                subUnit: ""
            }

            MetricsGroupWrapper {
                visible: SystemResources.diskEnabled
                label: "DSK"
                labelColor: SystemResources.metricColorDisk
                valueText: (SystemResources.metricsAvailable && SystemResources.diskEnabled && SystemResources.validDisks.length > 0 && SystemResources.diskUsage[SystemResources.validDisks[0]]) ? Math.round(SystemResources.diskUsage[SystemResources.validDisks[0]]).toString() : "--"
                valueUnit: (SystemResources.metricsAvailable && SystemResources.diskEnabled && SystemResources.validDisks.length > 0) ? "%" : ""
                subValue: ""
                subUnit: ""
            }

            MetricsGroupWrapper {
                visible: SystemResources.fpsEnabled
                label: "FPS"
                labelColor: SystemResources.metricColorFps
                valueText: (SystemResources.metricsAvailable && SystemResources.fpsEnabled && SystemResources.fps > 0) ? Math.round(SystemResources.fps).toString() : "--"
                valueUnit: ""
                subValue: ""
                subUnit: ""
            }
        }

        // mainRow container (hidden when metrics mode is active)
        Row {
            id: mainRow
            visible: !metricsActive
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: isBottom ? undefined : parent.top
            anchors.bottom: isBottom ? parent.bottom : undefined
            width: parent.width - mainRowMargin
            height: mainRowHeight
            spacing: 4
            z: 2 // Ensure it stays above notifications if overlap occurs (though they shouldn't)

            // Clock section (compact, visible in island mode)
            RowLayout {
                id: clockRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                visible: Config.notchTheme === "island"

                ClockIndicator {
                    Layout.alignment: Qt.AlignVCenter
                }

                Item {
                    id: clockTextArea
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: dateLabel.implicitWidth
                    implicitHeight: dateLabel.implicitHeight

                    Text {
                        id: dateLabel
                        text: new Date().toLocaleTimeString(Config.locale || Qt.locale(), "HH:mm")
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: 14
                        font.weight: Font.Medium

                        Timer {
                            interval: 10000
                            running: true
                            repeat: true
                            onTriggered: parent.text = new Date().toLocaleTimeString(Config.locale || Qt.locale(), "HH:mm")
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: clockPopupInvoker.togglePopup()
                    }
                }

            }

            // Hidden Clock used only for its popup (outside the Row to avoid layout gap)
            Clock {
                id: clockPopupInvoker
                anchors.top: parent.bottom
                anchors.topMargin: 4
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: 0
                width: 0; height: 0
                bar: QtObject {
                    property string orientation: "horizontal"
                    property bool vertical: false
                    property string barPosition: "top"
                }
                layerEnabled: false
            }

            UserInfo {
                id: userInfo
                anchors.verticalCenter: parent.verticalCenter
            }

            Separator {
                id: separator1
                vert: true
                anchors.verticalCenter: parent.verticalCenter
                visible: clockRow.visible || userInfo.visible
            }

            CompactPlayer {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                    - (userInfo.visible ? userInfo.width + parent.spacing : 0)
                    - (separator1.visible ? separator1.width + parent.spacing : 0)
                    - (clockRow.visible ? clockRow.implicitWidth + parent.spacing : 0)
                    - (separator2.visible ? separator2.width + parent.spacing : 0)
                    - (weatherRow.visible ? weatherRow.implicitWidth + parent.spacing : 0)
                    - (notifIndicatorStandalone.visible ? notifIndicatorStandalone.width + parent.spacing : 0)
                height: 32
                player: activePlayer
                notchHovered: expandedState
            }

            Separator {
                id: separator2
                vert: true
                anchors.verticalCenter: parent.verticalCenter
                visible: clockRow.visible || weatherRow.visible
            }

            // Weather next to notification indicator (island mode only)
            RowLayout {
                id: weatherRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                visible: Config.notchTheme === "island"

                Weather {
                    id: weatherItem
                    Layout.alignment: Qt.AlignVCenter
                    Layout.maximumWidth: 120
                    bar: QtObject {
                        property string orientation: "horizontal"
                        property bool vertical: false
                    }

                    // Click overlay on top of weather
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: clockPopupInvoker.togglePopup()
                    }
                }

                NotificationIndicator {
                    id: notifIndicator
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            // Non-island: NotificationIndicator standalone
            NotificationIndicator {
                id: notifIndicatorStandalone
                anchors.verticalCenter: parent.verticalCenter
                visible: Config.notchTheme !== "island"
            }
        }

        // Notification container with its own padding
        Item {
            id: notificationContainer
            width: parent.width
            height: hasActiveNotifications ? notificationContainerHeight : 0
            visible: hasActiveNotifications
            
            // Position relative to mainRow
            anchors.top: isBottom ? undefined : mainRow.bottom
            anchors.bottom: isBottom ? mainRow.top : undefined
            
            NotchNotificationView {
                id: notificationView
                anchors.fill: parent
                // Invert padding based on position? Or keep as is?
                // If bottom, "top" margin is visually the one close to mainRow?
                // Let's keep padding consistent for now, but ensure proper spacing.
                anchors.topMargin: notificationPaddingTop
                anchors.leftMargin: notificationPadding
                anchors.rightMargin: notificationPadding
                anchors.bottomMargin: notificationPaddingBottom
                visible: hasActiveNotifications
                opacity: visible ? 1 : 0
                notchHovered: expandedState
                onIsNavigatingChanged: root.isNavigating = isNavigating

                Behavior on opacity {
                    enabled: Anim.animationsEnabled
                    NumberAnimation {
                        duration: Anim.standardNormal
                        easing.type: Anim.easing("standard").type
                        easing.bezierCurve: Anim.easing("standard").bezierCurve
                    }
                }
            }
        }
    }
Component.onDestruction: {
    mediaHoverTimer.stop ? mediaHoverTimer.stop() : undefined;
    mediaHoverTimer.running !== undefined ? mediaHoverTimer.running = false : undefined;
    mediaHoverTimer.destroy !== undefined ? mediaHoverTimer.destroy() : undefined;
}
}
