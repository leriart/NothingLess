pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.config

/**
 * TodoBoard — Flat task list with priority, due dates, and reminders.
 *
 * Based on NVitschDEV/ptodo's data model.
 *
 * Task shape:
 *   { id, task, done, priority (0..3), dueDate, startDate, endDate, createdAt }
 *
 * Persisted at ~/.config/nothingless/todo/tasks.json
 */
QtObject {
    id: root

    readonly property int prioNone: 0
    readonly property int prioLow: 1
    readonly property int prioMed: 2
    readonly property int prioHigh: 3

    readonly property var priorityNames: ["None", "Low", "Med", "High"]
    readonly property var priorityShort: ["", "L", "M", "H"]

    function priorityColor(p) {
        if (p === prioHigh) return Colors.error
        if (p === prioMed) return Colors.yellow
        if (p === prioLow) return Colors.blue
        return Colors.outline
    }

    function priorityBgColor(p) {
        return Qt.rgba(priorityColor(p).r, priorityColor(p).g, priorityColor(p).b, 0.18)
    }

    property var tasks: []
    property int nextId: 0
    property bool initialized: false

    property int reminderMinutes: 30
    property var _notifiedTasks: ({})

    property int filterPriority: -1
    property bool hideDone: false

    signal taskAdded(int id)
    signal taskRemoved(int id)
    signal taskUpdated(int id)

    readonly property string _dataDir: Quickshell.env("HOME") + "/.config/nothingless/todo"
    readonly property string _dataFile: _dataDir + "/tasks.json"

    property Process mkProc: Process {
        id: mkProc
        command: ["bash", "-c",
            "mkdir -p '" + root._dataDir + "' && " +
            "[ -f '" + root._dataFile + "' ] || " +
            "printf '%s' '{\"tasks\":[],\"nextId\":1}' > '" + root._dataFile + "'"]
        running: true
        onExited: rdProc.running = true
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
                    var loaded = o.tasks || []
                    for (var i = 0; i < loaded.length; i++) {
                        var t = loaded[i]
                        if (t.title !== undefined && t.task === undefined) {
                            t.task = t.title
                            delete t.title
                        }
                        if (t.column !== undefined) {
                            t.done = (t.column === 2)
                            delete t.column
                        }
                        if (t.priority === undefined) t.priority = 0
                        if (t.dueDate === undefined) t.dueDate = ""
                        if (t.startDate === undefined) t.startDate = ""
                        if (t.endDate === undefined) t.endDate = ""
                        if (t.createdAt === undefined) t.createdAt = new Date().toISOString()
                    }
                    root.tasks = loaded
                    var maxId = 0
                    for (var j = 0; j < loaded.length; j++) {
                        if (loaded[j].id > maxId) maxId = loaded[j].id
                    }
                    root.nextId = o.nextId || (maxId + 1)
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

    function addTask(task, priority, dueDate, startDate, endDate) {
        if (priority === undefined) priority = 0
        if (dueDate === undefined) dueDate = ""
        if (startDate === undefined) startDate = ""
        if (endDate === undefined) endDate = ""
        var t = {
            id: nextId,
            task: task,
            done: false,
            priority: priority,
            dueDate: dueDate,
            startDate: startDate,
            endDate: endDate,
            createdAt: new Date().toISOString()
        }
        tasks = tasks.concat([t])
        nextId++
        _save()
        taskAdded(t.id)
        return t.id
    }

    function setDateRange(id, startDate, endDate) {
        for (var i = 0; i < tasks.length; i++) {
            if (tasks[i].id === id) {
                var t = Object.assign({}, tasks[i])
                t.startDate = startDate !== undefined ? startDate : t.startDate
                t.endDate = endDate !== undefined ? endDate : t.endDate
                var newTasks = tasks.slice()
                newTasks[i] = t
                tasks = newTasks
                _save()
                taskUpdated(id)
                return
            }
        }
    }

    function removeTask(id) {
        tasks = tasks.filter(t => t.id !== id)
        _save()
        taskRemoved(id)
    }

    function removeAllDone() {
        tasks = tasks.filter(t => !t.done)
        _save()
    }

    function setDone(id, done) {
        for (var i = 0; i < tasks.length; i++) {
            if (tasks[i].id === id) {
                var t = Object.assign({}, tasks[i])
                t.done = done
                var newTasks = tasks.slice()
                newTasks[i] = t
                tasks = newTasks
                _save()
                taskUpdated(id)
                return
            }
        }
    }

    function toggleDone(id) {
        for (var i = 0; i < tasks.length; i++) {
            if (tasks[i].id === id) {
                setDone(id, !tasks[i].done)
                return
            }
        }
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

    function setTask(id, task) {
        for (var i = 0; i < tasks.length; i++) {
            if (tasks[i].id === id) {
                var t = Object.assign({}, tasks[i])
                t.task = task
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
                clearReminderFlag(id)
                return
            }
        }
    }

    function sortedTasks() {
        return tasks.slice().sort(function(a, b) {
            if (a.done !== b.done) return a.done ? 1 : -1
            if (a.priority !== b.priority) return b.priority - a.priority
            var aKey = a.startDate || a.dueDate || ""
            var bKey = b.startDate || b.dueDate || ""
            if (aKey && bKey) {
                if (aKey < bKey) return -1
                if (aKey > bKey) return 1
            }
            if (aKey && !bKey) return -1
            if (!aKey && bKey) return 1
            if (a.createdAt < b.createdAt) return -1
            if (a.createdAt > b.createdAt) return 1
            return 0
        })
    }

    function formatDate(d) {
        if (!d) return ""
        var x = new Date(d)
        var months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        return months[x.getMonth()] + " " + x.getDate()
    }

    function formatTime(d) {
        if (!d) return ""
        var x = new Date(d)
        return x.toTimeString().substring(0, 5)
    }

    function formatRange(startDate, endDate) {
        if (!startDate && !endDate) return ""
        if (startDate && endDate) {
            var s = new Date(startDate)
            var e = new Date(endDate)
            if (s.toDateString() === e.toDateString()) {
                return formatDate(startDate) + " " + formatTime(startDate) + "–" + formatTime(endDate)
            }
            return formatDate(startDate) + " → " + formatDate(endDate)
        }
        if (startDate) return "From " + formatDate(startDate) + " " + formatTime(startDate)
        return "Until " + formatDate(endDate) + " " + formatTime(endDate)
    }

    function rangeIsOverdue(startDate, endDate, done) {
        if (done) return false
        var now = new Date()
        if (endDate) return new Date(endDate) < now
        if (startDate) return new Date(startDate) < now
        return false
    }

    function isInRangeToday(startDate, endDate) {
        if (!startDate && !endDate) return false
        var now = new Date()
        var todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0)
        var todayEnd = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59)
        if (startDate) {
            var s = new Date(startDate)
            if (s >= todayStart && s <= todayEnd) return true
        }
        if (endDate) {
            var e = new Date(endDate)
            if (e >= todayStart && e <= todayEnd) return true
        }
        return false
    }

    function visibleTasks() {
        var list = sortedTasks()
        if (filterPriority >= 0) {
            list = list.filter(t => t.priority === filterPriority)
        }
        if (hideDone) {
            list = list.filter(t => !t.done)
        }
        return list
    }

    property Timer reminderTimer: Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root._checkReminders()
    }

    function _checkReminders() {
        if (!Notifications) return
        var now = new Date()
        for (var i = 0; i < tasks.length; i++) {
            var task = tasks[i]
            if (!task.dueDate || task.done) continue
            if (_notifiedTasks[task.id]) continue
            var due = new Date(task.dueDate)
            var diffMin = (due - now) / 60000
            if (diffMin <= reminderMinutes) {
                _notifiedTasks[task.id] = true
                _sendReminder(task, diffMin < 0)
            }
        }
    }

    function _sendReminder(task, isOverdue) {
        if (!Notifications) return
        var title = isOverdue ? "TODO: Tarea vencida" : "TODO: Tarea próxima a vencer"
        var timeStr = formatDue(task.dueDate)
        var body = (task.task || "(sin título)") + " — " + timeStr
        try {
            Notifications.notifyInternal({
                "appName": "TODO",
                "summary": title,
                "body": body,
                "urgency": isOverdue ? 2 : 1,
                "historyPriority": 30,
                "replaceKey": "nothingless-todo-" + task.id,
                "expireTimeout": 8000
            })
        } catch (e) {
            console.warn("TodoBoard: reminder failed:", e)
        }
    }

    function clearReminderFlag(id) {
        var newMap = JSON.parse(JSON.stringify(_notifiedTasks))
        delete newMap[id]
        _notifiedTasks = newMap
    }

    function formatDue(due) {
        if (!due) return ""
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
