import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.services
import qs.modules.components
import "./NotificationDelegate.qml"

AnimatedListView {
    id: root
    property bool popup: false

    spacing: 8

    // Unified list transitions are provided by AnimatedListView via Anim.listAddConfig /
    // Anim.listRemoveConfig / Anim.listDisplacedConfig.

    // Show all individual notifications instead of groups
    model: root.popup ? Notifications.popupNotifications : Notifications.notifications

    delegate: NotificationDelegate {
        required property int index
        required property var modelData
        anchors.left: parent?.left
        anchors.right: parent?.right
        notificationObject: modelData
        expanded: true // Always expanded to show all info
        onlyNotification: true // Show as individual notification with header

        onDestroyRequested:
        // No special logic needed here
        {}
    }
}
