pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.modules.globals
import qs.config

/**
 * KanbanTaskCard — Single task card in a Kanban column.
 * Drag horizontally past the column edges to move between columns.
 * Click to expand controls (priority, due date, delete).
 */
StyledRect {
    id: cardRoot

    required property var task
    property int editingTitle: -1

    variant: cardRoot.task.priority > 0 ? "common" : "bg"
    radius: Styling.radius(-2)
    Layout.preferredHeight: cardCol.implicitHeight + 12
    clip: true

    // Track drag state from parent column
    property real pressX: 0
    property real dragX: 0
    property bool isDragging: false

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 3
        color: cardRoot.task.priority === 3 ? Styling.srItem("error") || Colors.outline
            : cardRoot.task.priority === 2 ? Styling.srItem("overprimary") || Colors.outline
            : cardRoot.task.priority === 1 ? Styling.srItem("secondary") || Colors.outline
            : "transparent"
    }

    ColumnLayout {
        id: cardCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        spacing: 4

        // Title row
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            TextField {
                id: titleField
                Layout.fillWidth: true
                text: cardRoot.task.title
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                color: Colors.overBackground
                readOnly: cardRoot.editingTitle !== cardRoot.task.id
                background: Rectangle {
                    color: "transparent"
                    border.color: titleField.activeFocus && !titleField.readOnly ? Colors.outline : "transparent"
                }
                onAccepted: {
                    if (text !== cardRoot.task.title) KanbanBoard.setTitle(cardRoot.task.id, text)
                    cardRoot.editingTitle = -1
                }
                onActiveFocusChanged: {
                    if (!activeFocus && cardRoot.editingTitle === cardRoot.task.id) {
                        if (text !== cardRoot.task.title) KanbanBoard.setTitle(cardRoot.task.id, text)
                        cardRoot.editingTitle = -1
                    }
                }
            }

            Text {
                text: Icons.dotsThree
                font.family: Icons.font
                font.pixelSize: 14
                color: Colors.outline
                opacity: cardRoot.dragX !== 0 || cardMouse.containsMouse ? 1 : 0.5

                Behavior on opacity { enabled: Anim.animationsEnabled
                    NumberAnimation { duration: Anim.standardSmall } }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        cardRoot.editingTitle = (cardRoot.editingTitle === cardRoot.task.id) ? -1 : cardRoot.task.id
                    }
                }
            }
        }

        // Meta row: due date, priority badges
        RowLayout {
            Layout.fillWidth: true
            visible: cardRoot.task.dueDate || cardRoot.task.priority > 0
            spacing: 6

            Text {
                visible: cardRoot.task.dueDate !== ""
                text: Icons.clock
                font.family: Icons.font
                font.pixelSize: 11
                color: KanbanBoard.isOverdue(cardRoot.task.dueDate)
                    ? Styling.srItem("error") || Colors.outline
                    : Colors.outline
            }
            Text {
                visible: cardRoot.task.dueDate !== ""
                text: KanbanBoard.formatDue(cardRoot.task.dueDate)
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-3)
                color: KanbanBoard.isOverdue(cardRoot.task.dueDate)
                    ? Styling.srItem("error") || Colors.overBackground
                    : Colors.outline
            }

            Item { Layout.fillWidth: true }

            // Priority indicator pill
            Rectangle {
                visible: cardRoot.task.priority > 0
                width: 8
                height: 8
                radius: 4
                color: cardRoot.task.priority === 3 ? Styling.srItem("error") || Colors.outline
                    : cardRoot.task.priority === 2 ? Styling.srItem("overprimary") || Colors.outline
                    : Styling.srItem("secondary") || Colors.outline
            }
        }

        // Expanded controls
        ColumnLayout {
            Layout.fillWidth: true
            visible: cardRoot.editingTitle === cardRoot.task.id
            spacing: 4

            // Priority selector
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: [
                        { val: 0, label: "None" },
                        { val: 1, label: "Low" },
                        { val: 2, label: "Med" },
                        { val: 3, label: "High" }
                    ]
                    delegate: StyledRect {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 22
                        variant: cardRoot.task.priority === modelData.val ? "primary" : "common"
                        radius: Styling.radius(-2)
                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-3)
                            color: cardRoot.task.priority === modelData.val
                                ? Styling.srItem("onprimary")
                                : Colors.overBackground
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: KanbanBoard.setPriority(cardRoot.task.id, modelData.val)
                        }
                    }
                }
            }

            // Action row
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledRect {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22
                    variant: "common"
                    radius: Styling.radius(-2)
                    Text {
                        anchors.centerIn: parent
                        text: Icons.clock + " Date"
                        font.family: Icons.font
                        font.pixelSize: Styling.fontSize(-3)
                        color: Colors.overBackground
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // Trigger date picker in parent KanbanTab
                            const tab = cardRoot.parent ? cardRoot.parent.parent : null
                            // Find root KanbanTab via traversal
                            let p = cardRoot
                            while (p && !p._openDatePicker) p = p.parent
                            if (p) p._openDatePicker(cardRoot.task.id, cardRoot.task.dueDate)
                        }
                    }
                }

                StyledRect {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22
                    variant: "common"
                    radius: Styling.radius(-2)
                    Text {
                        anchors.centerIn: parent
                        text: Icons.trash
                        font.family: Icons.font
                        font.pixelSize: Styling.fontSize(-3)
                        color: Colors.outline
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: KanbanBoard.removeTask(cardRoot.task.id)
                    }
                }
            }
        }
    }

    // Hover background
    MouseArea {
        id: cardMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: cardRoot.dragX !== 0 ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        z: 1
        propagateComposedEvents: true

        property int pressTaskId: -1
        onPressed: mouse => {
            pressTaskId = cardRoot.task.id
            cardRoot.pressX = mouse.x
        }
        onReleased: {
            if (cardRoot.dragX !== 0) {
                // Determine target column based on drag direction
                const parent = cardRoot.parent
                const curIdx = cardRoot.task.column
                let targetCol = curIdx
                if (cardRoot.dragX > 40 && curIdx < 2) targetCol = curIdx + 1
                else if (cardRoot.dragX < -40 && curIdx > 0) targetCol = curIdx - 1
                if (targetCol !== curIdx) {
                    KanbanBoard.moveTask(cardRoot.task.id, targetCol)
                }
            }
            cardRoot.dragX = 0
            pressTaskId = -1
        }
        onPositionChanged: mouse => {
            if (pressed) {
                cardRoot.dragX = mouse.x - cardRoot.pressX
            } else {
                cardRoot.dragX = 0
            }
        }
    }

    // Apply drag transform
    transform: Translate {
        x: cardRoot.dragX
        Behavior on x { enabled: cardRoot.dragX === 0 && Anim.animationsEnabled
            NumberAnimation { duration: Anim.standardNormal; easing.type: Anim.easing("emphasizedDecelerate").type
                easing.bezierCurve: Anim.easing("emphasizedDecelerate").bezierCurve } }
    }
}
