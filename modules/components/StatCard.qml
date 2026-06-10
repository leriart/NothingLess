import QtQuick
import QtQuick.Controls
import qs.modules.theme
import qs.config

// StatCard — reusable card container for stats/metrics panels.
// Provides a consistent surface with border for dashboard widgets.
// Inspired by Brain_Shell's StatCard component.
//
// Usage:
//   StatCard {
//       width: 200; height: 160
//       Speedometer { anchors.centerIn: parent; ... }
//   }

Item {
    id: root

    default property alias content: inner.data
    property int padding: 12

    // Background surface
    Rectangle {
        anchors.fill: parent
        radius: Styling.radius(2)
        color: Qt.rgba(1, 1, 1, 0.04)
        border.color: Qt.rgba(1, 1, 1, 0.07)
        border.width: 1
    }

    // Inner content area
    Item {
        id: inner
        anchors {
            fill: parent
            margins: root.padding
        }
    }
}
