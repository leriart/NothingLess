import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.modules.theme
import qs.modules.components
import qs.config

MouseArea {
    id: root

    required property var bar
    required property SystemTrayItem item
    property int trayItemSize: 20
    property bool isHovered: false

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    Layout.fillHeight: bar.orientation === "horizontal"
    Layout.fillWidth: bar.orientation === "vertical"
    implicitWidth: trayItemSize
    implicitHeight: trayItemSize

    onClicked: event => {
        switch (event.button) {
        case Qt.LeftButton:
            item.activate();
            break;
        case Qt.RightButton:
            item.secondaryActivate();
            break;
        }
        event.accepted = true;
    }

    IconImage {
        id: trayIcon
        source: {
            const iconPath = root.item.icon.toString();
            if (iconPath.includes("spotify")) {
                return Quickshell.iconPath("spotify-client");
            }
            return root.item.icon;
        }
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        smooth: true
    }

    Tinted {
        anchors.fill: trayIcon
        sourceItem: trayIcon
    }

    HoverHandler {
        onHoveredChanged: root.isHovered = hovered
    }

    StyledToolTip {
        visible: root.isHovered
        tooltipText: root.item.tooltipTitle || root.item.id || ""
    }
}
