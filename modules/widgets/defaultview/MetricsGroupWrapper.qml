import QtQuick
import QtQuick.Layouts

/**
 * MetricsGroupWrapper — Layout container for a MetricsGroup inside a RowLayout.
 * Ensures each metric is centered in its allocated cell and supports expanded mode.
 */
Item {
    id: root

    required property string label
    required property color labelColor
    property string valueText: ""
    property string valueUnit: ""
    property string subValue: ""
    property string subUnit: ""
    property bool expanded: false

    Layout.fillWidth: true
    Layout.fillHeight: true
    implicitWidth: metricGroup.implicitWidth
    implicitHeight: metricGroup.implicitHeight

    MetricsGroup {
        id: metricGroup
        anchors.centerIn: parent
        expanded: root.expanded
        label: root.label
        labelColor: root.labelColor
        valueText: root.valueText
        valueUnit: root.valueUnit
        subValue: root.subValue
        subUnit: root.subUnit
    }
}
