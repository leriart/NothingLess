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

Rectangle {
    id: root
    color: "transparent"
    implicitWidth: 800
    implicitHeight: 600

    property int pickerTaskId: -1
    property int pickerYear: 0
    property int pickerMonth: 0
    property int pickerDay: 0
    property int pickerTimeH: 12
    property int pickerTimeM: 0

    readonly property var _monthNames: [
        "January","February","March","April","May","June",
        "July","August","September","October","November","December"
    ]
    readonly property var _dowNames: ["Su","Mo","Tu","We","Th","Fr","Sa"]

    function _openDatePicker(taskId, existingDue) {
        pickerTaskId = taskId
        var d = existingDue ? new Date(existingDue) : new Date()
        pickerYear = d.getFullYear()
        pickerMonth = d.getMonth()
        pickerDay = existingDue ? d.getDate() : 0
        pickerTimeH = existingDue ? d.getHours() : 12
        pickerTimeM = existingDue ? d.getMinutes() : 0
    }

    function _closeDatePicker() { pickerTaskId = -1 }

    function _saveDatePicker() {
        if (pickerDay === 0) {
            KanbanBoard.setDueDate(pickerTaskId, "")
        } else {
            var d = new Date(pickerYear, pickerMonth, pickerDay, pickerTimeH, pickerTimeM)
            KanbanBoard.setDueDate(pickerTaskId, d.toISOString())
        }
        _closeDatePicker()
    }

    function _buildMonthDays(year, month) {
        var first = new Date(year, month, 1)
        var last = new Date(year, month + 1, 0)
        var startDow = first.getDay()
        var totalDays = last.getDate()
        var days = []
        var prevLast = new Date(year, month, 0).getDate()
        for (var i = startDow - 1; i >= 0; i--) {
            days.push({ n: prevLast - i, cur: false })
        }
        for (var d = 1; d <= totalDays; d++) {
            days.push({ n: d, cur: true })
        }
        while (days.length < 42) {
            days.push({ n: days.length - totalDays - startDow + 1, cur: false })
        }
        return days
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            spacing: 12

            Text {
                text: Icons.kanban
                font.family: Icons.font
                font.pixelSize: 22
                color: Styling.srItem("overprimary")
            }
            Text {
                text: "Kanban"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(2)
                font.weight: Font.Medium
                color: Colors.overBackground
            }
            Item { Layout.fillWidth: true }
            Text {
                text: KanbanBoard.tasks.length + " tasks"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                color: Colors.outline
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            Repeater {
                model: [
                    { idx: KanbanBoard.colTodo, title: "To Do" },
                    { idx: KanbanBoard.colDoing, title: "Doing" },
                    { idx: KanbanBoard.colDone, title: "Done" }
                ]
                delegate: KanbanColumn {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columnIndex: modelData.idx
                    title: modelData.title
                }
            }
        }
    }
        // Date picker overlay
        Item {
            anchors.fill: parent
            visible: pickerTaskId !== -1
            z: 10
    
            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: 0.4
            }
            MouseArea {
                anchors.fill: parent
                onClicked: _closeDatePicker()
            }
    
            StyledRect {
                anchors.centerIn: parent
                width: 320
                radius: Styling.radius(0)
                variant: "popup"
                clip: true
    
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
    
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "<"
                            font.family: Icons.font
                            font.pixelSize: 16
                            color: Colors.overBackground
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    pickerMonth--
                                    if (pickerMonth < 0) { pickerMonth = 11; pickerYear-- }
                                }
                            }
                        }
                        Text {
                            text: root._monthNames[pickerMonth] + " " + pickerYear
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            font.weight: Font.Medium
                            color: Colors.overBackground
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            text: ">"
                            font.family: Icons.font
                            font.pixelSize: 16
                            color: Colors.overBackground
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    pickerMonth++
                                    if (pickerMonth > 11) { pickerMonth = 0; pickerYear++ }
                                }
                            }
                        }
                    }
    
                    RowLayout {
                        Layout.fillWidth: true
                        Repeater {
                            model: root._dowNames
                            delegate: Text {
                                text: modelData
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-3)
                                color: Colors.outline
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
    
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 7
                        rowSpacing: 2
                        columnSpacing: 2
    
                        Repeater {
                            model: root._buildMonthDays(pickerYear, pickerMonth)
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                radius: Styling.radius(-2)
                                color: !modelData.cur ? "transparent"
                                    : (pickerDay > 0 && new Date(pickerYear, pickerMonth, modelData.n).toDateString()
                                        === new Date(pickerYear, pickerMonth, pickerDay).toDateString())
                                        ? Styling.srItem("primary")
                                        : (mouse.containsMouse ? Colors.surfaceBright : "transparent")
                                border.color: modelData.cur ? Colors.outline : "transparent"
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.n
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1)
                                    color: !parent.modelData.cur ? Colors.outline
                                        : (parent.color === Styling.srItem("primary")
                                            ? Styling.srItem("onprimary")
                                            : Colors.overBackground)
                                }
                                MouseArea {
                                    id: mouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: parent.modelData.cur ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    enabled: parent.modelData.cur
                                    onClicked: pickerDay = parent.modelData.n
                                }
                            }
                        }
                    }
    
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Text {
                            text: "Time:"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            color: Colors.outline
                        }
                        TextField {
                            text: String(pickerTimeH).padStart(2, '0')
                            Layout.preferredWidth: 40
                            inputMask: "99"
                            validator: IntValidator { bottom: 0; top: 23 }
                            onTextChanged: {
                                var v = parseInt(text)
                                if (!isNaN(v) && v >= 0 && v <= 23) pickerTimeH = v
                            }
                        }
                        Text {
                            text: ":"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            color: Colors.overBackground
                        }
                        TextField {
                            text: String(pickerTimeM).padStart(2, '0')
                            Layout.preferredWidth: 40
                            inputMask: "99"
                            validator: IntValidator { bottom: 0; top: 59 }
                            onTextChanged: {
                                var v = parseInt(text)
                                if (!isNaN(v) && v >= 0 && v <= 59) pickerTimeM = v
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }
    
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        StyledRect {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            variant: "common"
                            radius: Styling.radius(-2)
                            Text {
                                anchors.centerIn: parent
                                text: "Clear"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                color: Colors.overBackground
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { pickerDay = 0; root._saveDatePicker() }
                            }
                        }
                        StyledRect {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            variant: "common"
                            radius: Styling.radius(-2)
                            Text {
                                anchors.centerIn: parent
                                text: "Cancel"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                color: Colors.overBackground
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root._closeDatePicker()
                            }
                        }
                        StyledRect {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            variant: "primary"
                            radius: Styling.radius(-2)
                            Text {
                                anchors.centerIn: parent
                                text: "Save"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                color: Styling.srItem("onprimary")
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root._saveDatePicker()
                            }
                        }
                    }
                }
            }
}
}
