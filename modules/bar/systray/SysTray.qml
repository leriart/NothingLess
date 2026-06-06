import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.modules.theme
import qs.config
import qs.modules.components

StyledRect {
    variant: "bg"
    id: root

    topLeftRadius: root.vertical ? root.startRadius : root.startRadius
    topRightRadius: root.vertical ? root.startRadius : root.endRadius
    bottomLeftRadius: root.vertical ? root.endRadius : root.startRadius
    bottomRightRadius: root.vertical ? root.endRadius : root.endRadius

    required property var bar

    property real radius: 0
    property real startRadius: radius
    property real endRadius: radius

    property bool vertical: bar.orientation === "vertical"
    property bool isExpanded: true

    // Size when collapsed (set to islandButtonSize in notch)
    property int preferredSize: 36
    // Show first tray icon as preview when collapsed
    property bool showPreviewIcon: true

    // Filtered tray items
    readonly property var filteredItems: {
        var result = [];
        var items = SystemTray.items;
        var hidden = Config.bar.hiddenIcons;
        for (var i = 0; i < items.length; i++) {
            var item = items[i];
            var title = (item.title || item.tooltipTitle || "").toLowerCase();
            var hide = false;
            for (var j = 0; j < hidden.length; j++) {
                if (title.includes(hidden[j].toLowerCase())) {
                    hide = true;
                    break;
                }
            }
            if (!hide) result.push(item);
        }
        return result;
    }

    readonly property var firstItem: filteredItems.length > 0 ? filteredItems[0] : null
    readonly property bool hasItems: SystemTray.items.length > 0

    // ── Always has a size; external visible handles show/hide ──
    height: vertical ? implicitHeight : (parent ? parent.height : preferredSize)

    // Always provide a size even when empty, so Row layout works from the start
    implicitWidth: isExpanded ? rowLayout.implicitWidth + 16 : preferredSize
    implicitHeight: isExpanded ? (vertical ? columnLayout.implicitHeight + 16 : preferredSize) : preferredSize

    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight

    Behavior on implicitWidth {
        enabled: Anim.animationsEnabled
        AnimatedBehavior { type: "standard"; size: "normal" }
    }
    Behavior on implicitHeight {
        enabled: Anim.animationsEnabled
        AnimatedBehavior { type: "standard"; size: "normal" }
    }

    // ── HORIZONTAL ──
    RowLayout {
        id: rowLayout
        visible: !root.vertical
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        MouseArea {
            id: toggleBtnRow
            Layout.alignment: Qt.AlignCenter
            implicitWidth: 20
            implicitHeight: 20
            Layout.fillWidth: !root.isExpanded
            Layout.fillHeight: true
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.isExpanded = !root.isExpanded

            StyledRect {
                anchors.fill: parent
                variant: "bg"
                radius: Styling.radius(3)
                visible: !root.isExpanded || toggleBtnRow.containsMouse
                opacity: !root.isExpanded ? 1.0 : (toggleBtnRow.containsMouse ? 0.6 : 0)
                Behavior on opacity {
                    enabled: Anim.animationsEnabled
                    AnimatedBehavior { type: "standard"; size: "small" }
                }
            }

            IconImage {
                anchors.centerIn: parent
                width: 16; height: 16
                source: firstItem ? firstItem.icon : ""
                smooth: true
                visible: firstItem && !root.isExpanded && root.showPreviewIcon
            }

            Text {
                anchors.centerIn: parent
                text: root.isExpanded ? Icons.caretLeft : Icons.caretRight
                font.family: Icons.font
                font.pixelSize: Styling.fontSize(-1)
                color: toggleBtnRow.containsMouse ? Colors.primary : Colors.onSurfaceVariant
                visible: !firstItem || !root.showPreviewIcon || root.isExpanded
            }
        }

        Repeater {
            model: root.isExpanded ? root.filteredItems : []
            SysTrayItem {
                required property SystemTrayItem modelData
                bar: root.bar
                item: modelData
            }
        }
    }

    // ── VERTICAL ──
    ColumnLayout {
        id: columnLayout
        visible: root.vertical
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        MouseArea {
            id: toggleBtnCol
            Layout.alignment: Qt.AlignCenter
            implicitWidth: 20
            implicitHeight: 20
            Layout.fillWidth: true
            Layout.fillHeight: !root.isExpanded
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.isExpanded = !root.isExpanded

            StyledRect {
                anchors.fill: parent
                variant: "bg"
                radius: Styling.radius(3)
                visible: !root.isExpanded || toggleBtnCol.containsMouse
                opacity: !root.isExpanded ? 1.0 : (toggleBtnCol.containsMouse ? 0.6 : 0)
                Behavior on opacity {
                    enabled: Anim.animationsEnabled
                    AnimatedBehavior { type: "standard"; size: "small" }
                }
            }

            IconImage {
                anchors.centerIn: parent
                width: 16; height: 16
                source: firstItem ? firstItem.icon : ""
                smooth: true
                visible: firstItem && !root.isExpanded && root.showPreviewIcon
            }

            Text {
                anchors.centerIn: parent
                text: root.isExpanded ? Icons.caretUp : Icons.caretDown
                font.family: Icons.font
                font.pixelSize: Styling.fontSize(-1)
                color: toggleBtnCol.containsMouse ? Colors.primary : Colors.onSurfaceVariant
                visible: !firstItem || !root.showPreviewIcon || root.isExpanded
            }
        }

        Repeater {
            model: root.isExpanded ? root.filteredItems : []
            SysTrayItem {
                required property SystemTrayItem modelData
                bar: root.bar
                item: modelData
            }
        }
    }
}
