import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

ColumnLayout {
    id: root
    spacing: 6

    StatCard {
        Layout.fillWidth: true; Layout.preferredHeight: 48; padding: 8
        RowLayout {
            anchors.fill: parent; spacing: 8
            Text { text: Icons.cpu; font.family: Icons.font; font.pixelSize: 16; color: Colors.red; Layout.preferredWidth: 20 }
            Text { text: "CPU"; font.pixelSize: Styling.fontSize(-1); font.weight: Font.Medium; color: Colors.overBackground; Layout.preferredWidth: 32 }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 8; radius: 4; color: Colors.surfaceContainerHighest
                Rectangle { anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                    width: parent.width * Math.max(0, Math.min(1, (SystemResources.cpuUsageEnabled ? SystemResources.cpuUsage : 0) / 100))
                    radius: 4; color: Colors.red
                    Behavior on width { AnimatedBehavior { type: "standard"; size: "normal" } } } }
            Text { text: SystemResources.cpuUsageEnabled ? Math.round(SystemResources.cpuUsage) + "%" : "--"
                font.pixelSize: Styling.fontSize(-1); font.family: Config.theme.monoFont; font.weight: Font.Bold
                color: Colors.overBackground; Layout.preferredWidth: 36; horizontalAlignment: Text.AlignRight }
        }
    }

    StatCard {
        Layout.fillWidth: true; Layout.preferredHeight: 48; padding: 8
        RowLayout {
            anchors.fill: parent; spacing: 8
            Text { text: Icons.ram; font.family: Icons.font; font.pixelSize: 16; color: Colors.cyan; Layout.preferredWidth: 20 }
            Text { text: "RAM"; font.pixelSize: Styling.fontSize(-1); font.weight: Font.Medium; color: Colors.overBackground; Layout.preferredWidth: 32 }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 8; radius: 4; color: Colors.surfaceContainerHighest
                Rectangle { anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                    width: parent.width * Math.max(0, Math.min(1, (SystemResources.ramEnabled ? SystemResources.ramUsage : 0) / 100))
                    radius: 4; color: Colors.cyan
                    Behavior on width { AnimatedBehavior { type: "standard"; size: "normal" } } } }
            Text { text: SystemResources.ramEnabled ? Math.round(SystemResources.ramUsage) + "%" : "--"
                font.pixelSize: Styling.fontSize(-1); font.family: Config.theme.monoFont; font.weight: Font.Bold
                color: Colors.overBackground; Layout.preferredWidth: 36; horizontalAlignment: Text.AlignRight }
            Text { visible: SystemResources.ramEnabled
                text: { var u=(SystemResources.ramUsed/1048576).toFixed(1); var t=(SystemResources.ramTotal/1048576).toFixed(1); return u+"/"+t+"G" }
                font.pixelSize: Styling.fontSize(-3); font.family: Config.theme.monoFont; color: Qt.rgba(1,1,1,0.4); Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
        }
    }

    StatCard {
        Layout.fillWidth: true; Layout.preferredHeight: 48; padding: 8
        visible: SystemResources.gpuDetected
        RowLayout {
            anchors.fill: parent; spacing: 8
            Text { text: Icons.gpu; font.family: Icons.font; font.pixelSize: 16; color: Colors.green; Layout.preferredWidth: 20 }
            Text { text: "GPU"; font.pixelSize: Styling.fontSize(-1); font.weight: Font.Medium; color: Colors.overBackground; Layout.preferredWidth: 32 }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 8; radius: 4; color: Colors.surfaceContainerHighest
                Rectangle { anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                    width: parent.width * Math.max(0, Math.min(1, (SystemResources.gpuUsages[0] || 0) / 100))
                    radius: 4; color: Colors.green
                    Behavior on width { AnimatedBehavior { type: "standard"; size: "normal" } } } }
            Text { text: SystemResources.gpuDetected ? Math.round(SystemResources.gpuUsages[0]||0) + "%" : "--"
                font.pixelSize: Styling.fontSize(-1); font.family: Config.theme.monoFont; font.weight: Font.Bold
                color: Colors.overBackground; Layout.preferredWidth: 36; horizontalAlignment: Text.AlignRight }
        }
    }

    StatCard {
        Layout.fillWidth: true; Layout.preferredHeight: 48; padding: 8
        visible: SystemResources.cpuTempEnabled
        RowLayout {
            anchors.fill: parent; spacing: 8
            Text { text: Icons.temperature; font.family: Icons.font; font.pixelSize: 16; color: Colors.yellow; Layout.preferredWidth: 20 }
            Text { text: "TEMP"; font.pixelSize: Styling.fontSize(-1); font.weight: Font.Medium; color: Colors.overBackground; Layout.preferredWidth: 32 }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 8; radius: 4; color: Colors.surfaceContainerHighest
                Rectangle { anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                    width: parent.width * Math.max(0, Math.min(1, (SystemResources.cpuTempEnabled ? SystemResources.cpuTemp : 0) / 100))
                    radius: 4
                    color: { var t=SystemResources.cpuTemp; if(t>=90) return "#f38ba8"; if(t>=75) return "#f5c47a"; if(t>=60) return "#fab387"; return Colors.cyan }
                    Behavior on width { AnimatedBehavior { type: "standard"; size: "normal" } } } }
            Text { text: SystemResources.cpuTempEnabled && SystemResources.cpuTemp>=0 ? SystemResources.cpuTemp + "°" : "--"
                font.pixelSize: Styling.fontSize(-1); font.family: Config.theme.monoFont; font.weight: Font.Bold
                color: Colors.overBackground; Layout.preferredWidth: 36; horizontalAlignment: Text.AlignRight }
        }
    }
}
