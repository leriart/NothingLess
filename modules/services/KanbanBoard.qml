pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.config

/**
 * KanbanBoard — Three-column task board with JSON persistence.
 *
 * Columns: 0=todo, 1=doing, 2=done
 * Tasks stored at ~/.config/nothingless/kanban/tasks.json
 *
 * Task shape:
 *   { id, column, title, priority (0/1/2 = none/low/med/high), dueDate (ISO string or "") }
 */
QtObject {
    id: root

    // Columns
    readonly property int colTodo: 0
    readonly property int colDoing: 1
    readonly property int colDone: 2

    property var tasks: []
    property int nextId: 0
    property bool initialized: false

    signal taskAdded(int id)
    signal taskRemoved(int id)
    signal taskMoved(int id, int newColumn, int newIndex)
    signal taskUpdated(int id)

    readonly property string _dataDir: Quickshell.env("HOME") + "/.config/nothingless/kanban"
    readonly property string _dataFile: _dataDir + "/tasks.json"

    readonly property var priorityColors: ({
        0: Colors.outline,
        1: Styling.srItem("secondary") || Colors.outline,
        2: Styling.srItem("overprimary") || Colors.outline,
        3: Styling.srItem("error") || Colors.outline
    })

    readonly property var priorityNames: ["", "Low", "Med", "High"]

    // ── Init: ensure dir + file exist, then load ──
    property Process mkProc: Process {
        id: mkProc
        command: ["bash", "-c",
            "mkdir -p '" + root._dataDir + "' && " +
            "[ -f '" + root._dataFile + "' ] || " +
            "printf '%s' '{\"tasks\":[],\"nextId\":1}' > '" + root._dataFile + "'"]
        running: true
        onExited: {
            rdProc.running = true
        }
    }

    property Process rdProc: Process {
        id: rdProc
        command: ["cat", root._dataFile]
        running: false
        stdout: StdioCollector {
            id: rdBuf
            onStreamFinished: {
                try {
                    var o = JSON.parse(rdBuf.text)
                    root.tasks = o.tasks || []
                    root.nextId = o.nextId || 1
                } catch (e) {
                    root.tasks = []
                    root.nextId = 1
                }
                root.initialized = true
            }
        }
    }

    function _save() {
        if (!_dataFile) return
        var s = JSON.stringify({ tasks: tasks, nextId: nextId })
        wrProc.command = ["bash", "-c",
            "printf '%s' '" + s.replace(/'/g, "'\\''") + "' > '" + _dataFile + ".tmp' && " +
            "mv '" + _dataFile + ".tmp' '" + _dataFile + "'"]
        wrProc.running = true
    }

    property Process wrProc: Process {
        id: wrProc
        command: []
        running: false
    }

    // ── Public API ──
    function addTask(title, column = colTodo, priority = 0, dueDate = "") {
        var t = { id: nextId, column: column, title: title, priority: priority, dueDate: dueDate }
        tasks = tasks.concat([t])
        nextId++
        _save()
        taskAdded(t.id)
        return t.id
    }

    function removeTask(id) {
        tasks = tasks.filter(t => t.id !== id)
        _save()
        taskRemoved(id)
    }

    function moveTask(id, newColumn) {
        var idx = tasks.findIndex(t => t.id === id)
        if (idx < 0) return
        var task = tasks[idx]
        // Remove from current position
        var newTasks = tasks.slice()
        newTasks.splice(idx, 1)
        // Insert at end of new column (find first index with column >= newColumn)
        var insertAt = newTasks.length
        for (var i = 0; i < newTasks.length; i++) {
            if (newTasks[i].column > newColumn) {
                insertAt = i
                break
            }
        }
        task.column = newColumn
        newTasks.splice(insertAt, 0, task)
        tasks = newTasks
        _save()
        taskMoved(id, newColumn, insertAt)
    }

    function setPriority(id, priority) {
        for (var i = 0; i < tasks.length; i++) {
            if (tasks[i].id === id) {
                var t = Object.assign({}, tasks[i])
                t.priority = priority
                var newTasks = tasks.slice()
                newTasks[i] = t
                tasks = newTasks
                _save()
                taskUpdated(id)
                return
            }
        }
    }

    function setTitle(id, title) {
        for (var i = 0; i < tasks.length; i++) {
            if (tasks[i].id === id) {
                var t = Object.assign({}, tasks[i])
                t.title = title
                var newTasks = tasks.slice()
                newTasks[i] = t
                tasks = newTasks
                _save()
                taskUpdated(id)
                return
            }
        }
    }

    function setDueDate(id, dueDate) {
        for (var i = 0; i < tasks.length; i++) {
            if (tasks[i].id === id) {
                var t = Object.assign({}, tasks[i])
                t.dueDate = dueDate
                var newTasks = tasks.slice()
                newTasks[i] = t
                tasks = newTasks
                _save()
                taskUpdated(id)
                return
            }
        }
    }

    function tasksInColumn(column) {
        return tasks.filter(t => t.column === column)
    }

    // ── Formatted due date helper ──
    function formatDue(due) {
        if (!due) return ""
        // Today check
        var d = new Date(due)
        var now = new Date()
        if (d.toDateString() === now.toDateString()) {
            return "Today " + d.toTimeString().substring(0, 5)
        }
        var months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        return months[d.getMonth()] + " " + d.getDate() + " " + d.toTimeString().substring(0, 5)
    }

    function isOverdue(due) {
        if (!due) return false
        return new Date(due) < new Date()
    }
}
