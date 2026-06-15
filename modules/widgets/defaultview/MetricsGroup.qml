import QtQuick
import qs.modules.theme
import qs.config

/**
 * Individual metrics group in the notch metrics overlay.
 * Compact pill showing label, value and optional sub-value.
 * Styling follows the shell palette for consistent contrast.
 */
Item {
    id: root

    required property string label
    required property color labelColor
    property string valueText: ""
    property string valueUnit: ""
    property string subValue: ""
    property string subUnit: ""

    implicitHeight: parent ? parent.height : 32
    implicitWidth: innerRow.implicitWidth

    Row {
        id: innerRow
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 4

        // Colored indicator dot
        Rectangle {
            width: 6
            height: 6
            radius: 3
            color: root.labelColor
            anchors.verticalCenter: parent.verticalCenter
        }

        // Label
        Text {
            text: root.label
            color: root.labelColor
            font.pixelSize: 11
            font.weight: Font.Bold
            font.family: Config.theme.font
            anchors.verticalCenter: parent.verticalCenter
        }

        // Value number
        Text {
            text: root.valueText
            color: Colors.overBackground
            font.pixelSize: 13
            font.weight: Font.DemiBold
            font.family: Config.theme.font
            anchors.verticalCenter: parent.verticalCenter
            visible: root.valueText !== ""
        }

        // Value unit (small)
        Text {
            text: root.valueUnit
            color: Colors.outline
            font.pixelSize: 9
            font.weight: Font.Normal
            font.family: Config.theme.font
            anchors.verticalCenter: parent.verticalCenter
            visible: root.valueUnit !== ""
        }

        // Sub value (e.g. watts)
        Text {
            text: root.subValue
            color: Colors.overBackground
            font.pixelSize: 12
            font.weight: Font.DemiBold
            font.family: Config.theme.font
            anchors.verticalCenter: parent.verticalCenter
            visible: root.subValue !== ""
        }

        // Sub unit
        Text {
            text: root.subUnit
            color: Colors.outline
            font.pixelSize: 8
            font.weight: Font.Normal
            font.family: Config.theme.font
            anchors.verticalCenter: parent.verticalCenter
            visible: root.subUnit !== ""
        }
    }
}
