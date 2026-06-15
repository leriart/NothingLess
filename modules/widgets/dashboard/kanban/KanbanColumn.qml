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
 * KanbanColumn — Single column of a Kanban board.
 * Exposes a `title` and `columnIndex` for the KanbanBoard column constant.
 * Drag a card horizontally past the column edges to move it to the next column.
 */
StyledRect {
    id: columnRoot

    required property int columnIndex
    required property string title

    variant: "bg"
    radius: Styling.radius(0)
    clip: true

    // Drag tracking for column-to-column moves
    property int draggingTaskId: -1
    property real dragStartX: 0
    property real dragOffset: 0

    // Get tasks for this column from the singleton
    property var columnTasks: KanbanBoard.tasksInColumn(columnIndex)

    Connections {
        target: KanbanBoard
        function onTaskAdded() { columnRoot._refreshTasks() }
        function onTaskRemoved() { columnRoot._refreshTasks() }
        function onTaskMoved() { columnRoot._refreshTasks() }
        function onTaskUpdated() { columnRoot._refreshTasks() }
    }
    function _refreshTasks() {
        columnTasks = KanbanBoard.tasksInColumn(columnIndex)
    }
    onColumnIndexChanged: _refreshTasks()
    Component.onCompleted: _refreshTasks()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Column header
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            Layout.leftMargin: 10
            Layout.rightMargin: 8

            Text {
                text: columnRoot.title
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(0)
                font.weight: Font.Medium
                color: Colors.overBackground
            }
            Text {
                text: columnRoot.columnTasks.length
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.outline
            }
            Item { Layout.fillWidth: true }
        }

        // New task input
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.bottomMargin: 4

            TextField {
                id: newTaskInput
                Layout.fillWidth: true
                placeholderText: "+ Add task"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                background: Rectangle {
                    color: "transparent"
                    border.color: newTaskInput.activeFocus ? Colors.outline : "transparent"
                    border.width: 1
                    radius: Styling.radius(-2)
                }
                color: Colors.overBackground
                onAccepted: {
                    if (text.trim().length > 0) {
                        KanbanBoard.addTask(text.trim(), columnRoot.columnIndex)
                        text = ""
                    }
                }
            }
        }

        // Tasks list
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: tasksColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: tasksColumn
                width: parent.width
                spacing: 4

                Repeater {
                    model: columnRoot.columnTasks
                    delegate: KanbanTaskCard {
                        required property var modelData
                        width: tasksColumn.width - 16
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        task: modelData
                    }
                }

                Item {
                    Layout.preferredHeight: 8
                }
            }
        }
    }
}
