import QtQuick
import QtQuick.Controls
import qs.modules.theme
import qs.config

// Horizontal disk usage bar — shows mount label, fill bar, percentage, and size info.
// Inspired by Brain_Shell's DiskBar component.
//
// Properties:
//   source   — disk identifier (e.g. "nvme0n1p2")
//   mount    — mount point label (e.g. "/")
//   usedPct  — 0–100 usage percentage
//   usedStr  — human-readable used size (e.g. "45 GB")
//   totalStr — human-readable total size (e.g. "512 GB")

Item {
    id: root

    property string source: ""
    property string mount: ""
    property int usedPct: 0
    property string usedStr: "—"
    property string totalStr: "—"

    implicitWidth: 200
    implicitHeight: 40

    readonly property color barColor: {
        if (usedPct >= 90) return "#f38ba8"
        if (usedPct >= 75) return "#f5c47a"
        return Config.resolveColor("primary")
    }

    // Mount label — left
    Text {
        id: mountLabel
        anchors.left: parent.left
        anchors.verticalCenter: barTrack.verticalCenter
        text: root.mount
        font.pixelSize: Styling.fontSize(-3)
        font.family: Config.theme.monoFont
        color: Qt.rgba(1, 1, 1, 0.5)
        width: 32
        elide: Text.ElideRight
    }

    // Bar track + fill
    Item {
        id: barTrack
        anchors.left: mountLabel.right
        anchors.right: pctLabel.left
        anchors.top: parent.top
        anchors.topMargin: 12
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        height: 6

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.07)
            border.color: Qt.rgba(1, 1, 1, 0.06)
            border.width: 1
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * Math.max(0, Math.min(1, root.usedPct / 100))
            radius: height / 2
            color: root.barColor

            Behavior on width {
                AnimatedBehavior { type: "standard"; size: "normal" }
            }
            Behavior on color {
                AnimatedBehavior { type: "standard"; size: "small" }
            }
        }
    }

    // Percentage — right of bar
    Text {
        id: pctLabel
        anchors.right: parent.right
        anchors.verticalCenter: barTrack.verticalCenter
        text: root.usedPct + "%"
        font.pixelSize: Styling.fontSize(-3)
        font.weight: Font.Medium
        font.family: Config.theme.monoFont
        color: root.barColor
        width: 28
        horizontalAlignment: Text.AlignRight
        Behavior on color {
            AnimatedBehavior { type: "standard"; size: "small" }
        }
    }

    // Size info — below the bar
    Text {
        anchors.horizontalCenter: barTrack.horizontalCenter
        anchors.top: barTrack.bottom
        anchors.topMargin: 4
        text: root.usedStr + " / " + root.totalStr + "  ·  " + root.source
        font.pixelSize: Styling.fontSize(-4)
        font.family: Config.theme.monoFont
        color: Qt.rgba(1, 1, 1, 0.45)
    }
}
