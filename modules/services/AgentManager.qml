import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

/*!
    AgentManager — In-memory registry of active AI agent connections.

    Source of truth for the *list of agents* is `AgentStore` (per-file
    JSON in `~/.local/share/nothingless/agents/<id>.json`). This service
    is responsible for:
      - Subscribing to AgentStore.profilesChanged and rebuilding the
        in-memory `AgentConnection` objects when profiles appear, change
        or disappear.
      - Spawning the appropriate client (HTTP / MCP / command) for
        each enabled profile.
      - Optionally spawning a shell-managed child process whose
        lifecycle is tied to the agent (the `process` block on the
        profile). When present, the child process is started before
        the HTTP client connects and killed on disconnect.
      - Forwarding tool invocations to the live client.

    Note: `AgentStore.writeProfile` is the only path that touches the
    disk. This service never writes files directly.
*/
QtObject {
    id: root

    property var connections: [] // AgentConnection objects
    property var _clients: ({})  // agentId -> client QtObject
    // agentId -> Quickshell.Io.Process instance for the shell-managed
    // child process declared in the profile's `process` block.
    property var _processes: ({})
    // Auto-reset bookkeeping. agentId -> integer retry count. Reset to
    // 0 when the HTTP client reports connected. Caps at
    // AUTO_RESET_MAX_ATTEMPTS to avoid an infinite loop when the
    // binary is permanently broken.
    property var _autoResetAttempts: ({})
    readonly property int autoResetMaxAttempts: 5
    property QtObject toolRegistry: null

    signal statusChanged(string agentId, string status, string message)
    // Emitted when the lifecycle of a shell-managed child process
    // changes (started, exited cleanly, exited with error, etc.).
    signal processStateChanged(string agentId, string state, string message)

    property Component agentConnectionFactory: Component {
        AgentConnection {}
    }

    property Component httpClientFactory: Component {
        HttpAgentClient {}
    }

    property Component commandClientFactory: Component {
        CommandAgentClient {}
    }

    property Component mcpStdioClientFactory: Component {
        McpStdioClient {}
    }

    Component.onCompleted: {
        reloadFromStore();
    }

    // Tear down all live clients + shell-managed processes. Called
    // before a full rebuild and on shell shutdown.
    function _teardownAll() {
        for (let id in _clients) {
            try {
                if (_clients[id]) {
                    _clients[id].stop();
                    _clients[id].destroy();
                }
            } catch (e) {
                // already destroyed
            }
        }
        _clients = {};
        for (let id in _processes) {
            try {
                if (_processes[id]) _processes[id].running = false;
            } catch (e) {}
            try {
                if (_processes[id]) _processes[id].destroy();
            } catch (e) {}
        }
        _processes = {};
    }

    // Full rebuild from AgentStore. Guarded against re-entrancy: if
    // two profile-change signals arrive before the first reload
    // completes, we defer the second. Without this, overlapping
    // _connectAgent / _teardownAll calls can keep the shell main
    // thread busy and cause the "se queda trabado" (stuck/frozen)
    // user experience.
    property bool _storeReloading: false
    function reloadFromStore() {
        if (_storeReloading) {
            Qt.callLater(root.reloadFromStore);
            return;
        }
        _storeReloading = true;
        _teardownAll();

        let store = AgentStore.listProfiles();
        let newConnections = [];
        for (let i = 0; i < store.length; i++) {
            let c = store[i];
            if (!c) continue;
            let conn = agentConnectionFactory.createObject(root, {
                id: c.id,
                name: c.name,
                type: c.type,
                enabled: c.enabled !== false,
                command: c.command || "",
                args: c.args || [],
                endpoint: c.endpoint || "",
                headers: c.headers || {},
                toolsPath: c.toolsPath || "/tools",
                invokePath: c.invokePath || "/invoke",
                process: (c.process && typeof c.process === "object") ? c.process : ({})
            });
            if (!conn) {
                console.warn("AgentManager: failed to create AgentConnection for", c.id,
                    "— missing AgentConnection.qml?");
                continue;
            }
            newConnections.push(conn);

            if (conn.enabled) {
                _connectAgent(conn);
            }
        }
        connections = newConnections;
        _storeReloading = false;
    }

    // Re-read a single profile from the store and apply it. Used when
    // the user edits a profile from the editor and the FileView
    // triggers a refresh — we want to re-spawn the client if the
    // connection params changed.
    function refreshOne(profileId) {
        let p = AgentStore.getProfile(profileId);
        if (!p) {
            // Profile was deleted — drop the connection.
            _teardownOne(profileId);
            let arr = [];
            for (let i = 0; i < connections.length; i++) {
                if (connections[i] && connections[i].id !== profileId) arr.push(connections[i]);
            }
            connections = arr;
            return;
        }
        // Find existing conn; if found, tear down its client and
        // replace the in-memory object.
        let existingIdx = -1;
        for (let i = 0; i < connections.length; i++) {
            if (connections[i] && connections[i].id === profileId) {
                existingIdx = i;
                break;
            }
        }
        if (existingIdx >= 0) {
            _teardownOne(profileId);
        }
        let conn = agentConnectionFactory.createObject(root, {
            id: p.id,
            name: p.name,
            type: p.type,
            enabled: p.enabled !== false,
            command: p.command || "",
            args: p.args || [],
            endpoint: p.endpoint || "",
            headers: p.headers || {},
            toolsPath: p.toolsPath || "/tools",
            invokePath: p.invokePath || "/invoke",
            process: (p.process && typeof p.process === "object") ? p.process : ({})
        });
        let arr = connections.slice();
        if (existingIdx >= 0) {
            arr[existingIdx] = conn;
        } else {
            arr.push(conn);
        }
        connections = arr;
        if (conn.enabled) {
            _connectAgent(conn);
        }
    }

    function _teardownOne(agentId) {
        if (_clients[agentId]) {
            try {
                _clients[agentId].stop();
                _clients[agentId].destroy();
            } catch (e) {}
            delete _clients[agentId];
        }
        // Always kill the shell-managed process, even if the HTTP
        // client was the only thing explicitly torn down — the
        // process lifecycle is owned by AgentManager.
        _stopProcess(agentId);
        if (root.toolRegistry) root.toolRegistry.unregister(agentId);
    }

    // Subscribe to AgentStore: rebuild on full change, refresh one on
    // single save/delete.
    property Connections storeWatcher: Connections {
        target: AgentStore
        function onProfilesChanged() {
            Qt.callLater(root.reloadFromStore);
        }
        function onProfileSaved(id) {
            Qt.callLater(function() { root.refreshOne(id); });
        }
        function onProfileDeleted(id) {
            Qt.callLater(function() { root.refreshOne(id); });
        }
    }

    function _connectAgent(conn) {
        conn.status = "connecting";
        conn.statusMessage = "";
        statusChanged(conn.id, "connecting", "");

        // If the profile declares an embedded process, spawn it now
        // and defer the client start until the child has had a moment
        // to bind its endpoint. The HTTP/stdio client's own timeouts
        // are a safety net: if the process never starts we surface a
        // clear error rather than hanging forever.
        const hasProcess = conn.process && typeof conn.process === "object"
            && typeof conn.process.command === "string"
            && conn.process.command.length > 0;
        if (hasProcess) {
            if (!_startProcess(conn)) {
                // _startProcess already populated conn.procState /
                // conn.procMessage; bail before wiring a doomed client.
                conn.status = "error";
                conn.statusMessage = conn.procMessage || "Failed to start agent process";
                statusChanged(conn.id, "error", conn.statusMessage);
                return;
            }
        }

        let client;
        if (conn.type === "http-bridge" || conn.type === "mcp-sse") {
            client = httpClientFactory.createObject(root, {});
            _wireClientSignals(client, conn);
            if (hasProcess) {
                // Defer the HTTP discovery by ~500 ms so the child
                // process has time to bind the port. Without this,
                // GET /tools races the listen() call on slow systems.
                const target = client;
                const targetConn = conn;
                const startHttp = function() {
                    if (_clients[targetConn.id] !== target) return; // user disconnected meanwhile
                    target.start(targetConn.endpoint, targetConn.headers,
                        targetConn.toolsPath, targetConn.invokePath);
                };
                Qt.callLater(function() {
                    let t = _procGraceTimer.createObject(root, { _cb: startHttp });
                    t.start();
                });
            } else {
                client.start(conn.endpoint, conn.headers, conn.toolsPath, conn.invokePath);
            }
        } else if (conn.type === "command") {
            client = commandClientFactory.createObject(root, {});
            _wireClientSignals(client, conn);
            client.start(conn.command, conn.args);
        } else if (conn.type === "mcp-stdio") {
            client = mcpStdioClientFactory.createObject(root, {});
            _wireClientSignals(client, conn);
            client.start(conn.command, conn.args);
        } else {
            conn.status = "error";
            conn.statusMessage = "Unsupported agent type: " + conn.type;
            statusChanged(conn.id, "error", conn.statusMessage);
            return;
        }

        _clients[conn.id] = client;
    }

    // ── Shell-managed process lifecycle ───────────────────────────
    // Profiles with an embedded `process` block have their backing
    // server (typically an HTTP bridge written in stdlib Python)
    // spawned and torn down by AgentManager so the user never has to
    // run install scripts or manage systemd units.

    // Spawn the agent's child process. Returns true if the spawn
    // command was issued successfully. The actual readiness is
    // tracked via procState + processStateChanged; the caller can
    // either poll or just attempt the HTTP connection immediately.
    function _startProcess(conn) {
        if (!conn || !conn.process || typeof conn.process.command !== "string"
                || conn.process.command.length === 0) {
            return false;
        }
        // Don't double-spawn.
        if (_processes[conn.id]) return true;

        const proc = conn.process;
        // Cross-realm Array quirk: JSON-parsed arrays flow through
        // the QML engine's own V4 context and end up as Arrays with
        // our context's `Array` constructor, but `Array.isArray`
        // returns false for them. Quickshell's `var` properties
        // also drop Array identity on assignment, so `proc.args`
        // often shows up as `typeof === "object"`, `Array.isArray
        // === false`, with numeric keys but no `Array.prototype`
        // in its chain. Normalize via `[].concat(...)` which works
        // for both real arrays and Array-like cross-realm objects,
        // and yields a real array in *our* realm.
        const args = (proc.args && (typeof proc.args === "object")
            && proc.args.length !== undefined && typeof proc.args.length === "number")
            ? [].concat(Array.from(proc.args))
            : [];
        const argv = [proc.command].concat(args);
        const cwd = (typeof proc.cwd === "string" && proc.cwd.length > 0) ? proc.cwd : "";

        // Per-agent Process instance. We create a fresh one each time
        // rather than reusing a shared Process: Quickshell 0.3.0 does
        // not reliably restart a Process whose `running` was toggled,
        // and we want stderr/stdout isolation per agent.
        let p = _procFactory.createObject(root, {});
        p._agentId = conn.id;
        p._procDescriptor = {
            command: proc.command,
            args: args,
            cwd: cwd
        };
        try {
            p.command = argv;
            if (cwd) {
                p.workingDirectory = cwd;
            }
            // Apply env overrides ONLY when the profile actually
            // declares `process.env`. Setting `environment = []`
            // wipes PATH and breaks the spawned interpreter, so
            // we leave it untouched otherwise — Quickshell then
            // inherits the parent shell's environment, which is
            // exactly what we want.
            const envKeys = (proc.env && typeof proc.env === "object")
                ? Object.keys(proc.env) : [];
            if (envKeys.length > 0) {
                const flat = [];
                for (let i = 0; i < envKeys.length; i++) {
                    const k = envKeys[i];
                    flat.push(k + "=" + String(proc.env[k]));
                }
                p.environment = flat;
            }

            conn.procState = "starting";
            conn.procMessage = "Spawning " + argv.join(" ");
            processStateChanged(conn.id, conn.procState, conn.procMessage);
            p.running = true;
            _processes[conn.id] = p;
            return true;
        } catch (e) {
            conn.procState = "error";
            conn.procMessage = "Failed to start process: " + e;
            processStateChanged(conn.id, conn.procState, conn.procMessage);
            try { p.destroy(); } catch (e2) {}
            return false;
        }
    }

    // Kill the agent's child process if any. Safe to call multiple
    // times and safe to call when no process is running.
    function _stopProcess(agentId) {
        const p = _processes[agentId];
        if (!p) return;
        try { p.running = false; } catch (e) {}
        try { p.destroy(); } catch (e) {}
        delete _processes[agentId];
        // Mark on the connection if we still have a reference to it.
        for (let i = 0; i < connections.length; i++) {
            if (connections[i] && connections[i].id === agentId) {
                if (connections[i].procState !== "error") {
                    connections[i].procState = "stopped";
                    connections[i].procMessage = "";
                    processStateChanged(agentId, "stopped", "");
                }
                break;
            }
        }
    }

    // Public: start the embedded process only (no HTTP client).
    // Used by the Settings UI's manual Start/Stop buttons so the user
    // can run the bridge on demand without an active AI session.
    function startProcess(agentId) {
        let conn = null;
        for (let i = 0; i < connections.length; i++) {
            if (connections[i] && connections[i].id === agentId) {
                conn = connections[i];
                break;
            }
        }
        if (!conn) {
            console.warn("AgentManager.startProcess: no connection for", agentId);
            return false;
        }
        return _startProcess(conn);
    }

    // Public: stop the embedded process only. Idempotent.
    function stopProcess(agentId) {
        _stopProcess(agentId);
    }

    // Public: kill any orphan process matching this agent's process
    // descriptor (command + cwd), then re-spawn. Useful when an old
    // shell session left a python3 server.py bound to the same port
    // and the new shell can't bind — the user clicks "Reset" in the
    // UI, we run `pkill -f -<signature>` against the orphan, and
    // start fresh.
    //
    // `pkill` is invoked through a one-shot Quickshell Process so we
    // don't block the QML event loop. The actual spawn happens
    // ~300 ms later, after the kernel has fully released the socket.
    function resetProcess(agentId) {
        let conn = null;
        for (let i = 0; i < connections.length; i++) {
            if (connections[i] && connections[i].id === agentId) {
                conn = connections[i];
                break;
            }
        }
        if (!conn || !conn.process || typeof conn.process.command !== "string") {
            console.warn("AgentManager.resetProcess: no managed process for", agentId);
            return false;
        }
        // Make sure our own handle is gone first.
        _stopProcess(agentId);

        // Build a `pkill -f` signature that uniquely identifies
        // orphans of *this* agent. The descriptor.args usually
        // contains the script path which is unique per agent.
        let sigParts = [conn.process.command];
        if (Array.isArray(conn.process.args)) {
            for (let i = 0; i < conn.process.args.length; i++) {
                sigParts.push(String(conn.process.args[i]));
            }
        }
        // Filter to the longest unique token (the script path) so we
        // don't accidentally kill unrelated python3 processes.
        let scriptPath = (conn.process.args && conn.process.args.length > 0)
            ? String(conn.process.args[conn.process.args.length - 1])
            : "";
        let pattern = scriptPath || sigParts.join(" ");
        // Escape single quotes for the bash -c body.
        const esc = pattern.replace(/'/g, "'\\''");
        const cmd = "pkill -9 -f '" + esc + "' || true; sleep 0.3; true";

        const killer = _killerFactory.createObject(root, {});
        killer._agentId = agentId;
        killer.command = ["bash", "-c", cmd];
        killer.running = true;
        return true;
    }

    // Factory for one-shot pkill invocations. After pkill runs we
    // wait ~300 ms (handled inside the bash script) for the kernel
    // to release the port, then re-spawn the agent's process.
    property Component _killerFactory: Component {
        Process {
            property string _agentId: ""
            running: false
            onExited: function(exitCode) {
                // pkill exits 1 when no matches found; that's fine.
                // Re-spawn after a small grace period so the kernel
                // has time to release the socket.
                const id = _agentId;
                Qt.callLater(function() {
                    for (let i = 0; i < root.connections.length; i++) {
                        const c = root.connections[i];
                        if (c && c.id === id) {
                            if (c.enabled) {
                                root._connectAgent(c);
                            } else {
                                root.startProcess(id);
                            }
                            break;
                        }
                    }
                });
                try { this.destroy(); } catch (e) {}
            }
        }
    }

    // ── Auto-reset on unexpected death ──────────────────────────────
    // When a shell-managed process exits with non-zero while the
    // profile is still enabled, the user clearly wants the agent
    // active. Instead of leaving the agent in `error` state and
    // forcing the user to click Reset, schedule an automatic
    // re-spawn with exponential backoff.
    //
    // The backoff (1s → 2s → 4s → 8s → 16s, max 5 attempts) gives a
    // brief grace period for transient issues (port still in TIME_WAIT,
    // race with a previous instance exiting) while capping the worst
    // case at ~31 s before we give up.
    //
    // resetProcess() does the heavy lifting: it pkill's any orphan
    // holding the port, waits 300 ms for the kernel to release the
    // socket, then re-spawns the agent. We reuse it so the manual
    // "Reset" button and the auto path produce identical behaviour.
    //
    // The retry counter is cleared by the HTTP client's connected
    // signal above, so a successful re-spawn resets the streak.

    function _scheduleAutoReset(conn) {
        if (!conn) return;
        const id = conn.id;
        const attempts = (_autoResetAttempts[id] || 0) + 1;
        if (attempts > autoResetMaxAttempts) {
            console.warn("AgentManager: gave up auto-resetting", id,
                "after " + autoResetMaxAttempts + " failed attempts.");
            conn.procMessage = (conn.procMessage || "") +
                "  • Auto-reset disabled (max attempts reached).";
            root.processStateChanged(id, conn.procState, conn.procMessage);
            return;
        }
        _autoResetAttempts[id] = attempts;

        // Exponential backoff: 1s, 2s, 4s, 8s, 16s (capped).
        const delayMs = Math.min(16000, 1000 * Math.pow(2, attempts - 1));

        console.log("AgentManager: auto-reset for", id, "in", delayMs,
            "ms (attempt " + attempts + "/" + autoResetMaxAttempts + ")");

        // Reuse the same Timer instance — only one auto-reset can be
        // pending per agent at a time, and only one across the
        // whole manager in practice (rare to have two fail at once).
        if (typeof autoResetTimer._pendingId === "string"
                && autoResetTimer._pendingId !== "") {
            // A previous timer is still armed for a DIFFERENT agent.
            // Skip this round to avoid clobbering it — the next
            // process exit will reschedule.
            if (autoResetTimer._pendingId !== id) {
                console.log("AgentManager: auto-reset already pending for",
                    autoResetTimer._pendingId + ", skipping", id);
                return;
            }
        }
        autoResetTimer._pendingId = id;
        autoResetTimer.interval = delayMs;
        autoResetTimer.restart();
    }

    // Public: convenience used by UI — is this agent under shell
    // management (i.e. does its profile carry a non-empty process
    // block)?
    function hasManagedProcess(agentId) {
        for (let i = 0; i < connections.length; i++) {
            if (connections[i] && connections[i].id === agentId) {
                const p = connections[i].process;
                return !!(p && typeof p === "object" && typeof p.command === "string"
                    && p.command.length > 0);
            }
        }
        return false;
    }

    // Factory for per-agent child processes. Each instance owns its
    // own stdout/stderr buffering so a noisy bridge can't block the
    // QML event loop.
    property Component _procFactory: Component {
        Process {
            property string _agentId: ""
            property var _procDescriptor: ({})
            // Per-process stderr buffer. We only surface this on
            // failure (when the child exits with non-zero) so the UI
            // can show the *actual* Python traceback instead of an
            // opaque "exit code 1". Successful agents keep stderr
            // empty in the UI.
            property string _stderrTail: ""
            property int _stderrLines: 0
            running: false
            stdout: SplitParser {
                onRead: function(line) {
                    const msg = (line || "").toString();
                    if (!msg) return;
                    const agentId = _agentId;
                    for (let i = 0; i < root.connections.length; i++) {
                        const c = root.connections[i];
                        if (c && c.id === agentId) {
                            // Surface only on the connection's procMessage
                            // for visibility — we don't pollute the global
                            // AI log with bridge chatter.
                            if (c.procState === "starting") {
                                c.procState = "running";
                                c.procMessage = "";
                                root.processStateChanged(c.id, "running", "");
                            }
                            break;
                        }
                    }
                }
            }
            stderr: SplitParser {
                onRead: function(line) {
                    const msg = (line || "").toString();
                    if (!msg) return;
                    // Keep at most the last ~8 lines so a long Python
                    // traceback doesn't blow up the connection's
                    // procMessage buffer.
                    _stderrLines++;
                    let tail = (_stderrTail ? _stderrTail + "\n" : "") + msg;
                    let lines = tail.split("\n");
                    if (lines.length > 8) {
                        tail = lines.slice(lines.length - 8).join("\n");
                    }
                    _stderrTail = tail;
                    console.warn("AgentManager[" + _agentId + "] stderr:", msg);
                }
            }
            onExited: function(exitCode, exitStatus) {
                // Clean up our handle so a subsequent reconnect can
                // re-spawn.
                if (root._processes[_agentId] === this) {
                    delete root._processes[_agentId];
                }
                // Capture stderr tail so we can show the real reason
                // for failure (port-in-use, syntax error, missing
                // file, etc.) on the connection's procMessage.
                let stderrTail = _stderrTail || "";
                let didScheduleAutoReset = false;
                for (let i = 0; i < root.connections.length; i++) {
                    const c = root.connections[i];
                    if (!c || c.id !== _agentId) continue;
                    if (exitCode === 0) {
                        c.procState = "stopped";
                        c.procMessage = "";
                        root.processStateChanged(c.id, "stopped", "");
                    } else {
                        c.procState = "error";
                        // First line of stderr is the most useful —
                        // usually a clean OSError or traceback head.
                        // Fall back to "exited with code N" if stderr
                        // was empty (e.g. SIGKILL).
                        const firstLine = stderrTail
                            ? stderrTail.split("\n").filter(function(l) { return l.trim().length > 0; }).pop()
                            : "";
                        c.procMessage = firstLine
                            ? ("Process exited: " + firstLine.trim())
                            : ("Process exited with code " + exitCode);
                        root.processStateChanged(c.id, "error", c.procMessage);
                        // The HTTP client (if any) sees its own
                        // disconnect shortly after; just make sure
                        // the connection surfaces the failure.
                        if (c.status === "connected" || c.status === "connecting") {
                            c.status = "error";
                            c.statusMessage = c.procMessage;
                            root.statusChanged(c.id, "error", c.statusMessage);
                        }
                        // ── Auto-reset on unexpected death ──
                        // The user has this agent marked as enabled,
                        // so silently leaving it broken is bad UX.
                        // Schedule a reset with exponential backoff
                        // (1s, 2s, 4s, 8s, 16s) up to 5 attempts, then
                        // give up so we don't loop forever if the
                        // binary is permanently broken. The counter
                        // is reset by the HTTP client's connected
                        // signal below, so a successful re-spawn
                        // clears the streak.
                        if (c.enabled && c.process && typeof c.process.command === "string"
                                && c.process.command.length > 0) {
                            root._scheduleAutoReset(c);
                            didScheduleAutoReset = true;
                        }
                    }
                    break;
                }
                try { this.destroy(); } catch (e) {}
            }
        }
    }

    // Tiny Timer factory used to defer HTTP client start by ~500 ms
    // after spawning the child process, giving `listen()` time to
    // bind on slow systems.
    property Component _procGraceTimer: Component {
        Timer {
            property var _cb: null
            interval: 500
            repeat: false
            onTriggered: {
                if (typeof _cb === "function") _cb();
                this.destroy();
            }
        }
    }

    // ── Auto-reset timer (single instance, reused) ────────────────
    // A single shared Timer is enough because (a) two agents rarely
    // fail at the exact same instant and (b) even if they do, the
    // _pendingId guard rejects the second schedule. Reusing one
    // Timer avoids a clutter of single-shot Timers in the scene graph.
    property Timer autoResetTimer: Timer {
        property string _pendingId: ""
        interval: 1000
        repeat: false
        onTriggered: {
            const id = _pendingId;
            _pendingId = "";
            // Re-validate: the agent might have been disabled or
            // removed between scheduling and firing.
            let target = null;
            for (let i = 0; i < root.connections.length; i++) {
                const c = root.connections[i];
                if (c && c.id === id) {
                    target = c;
                    break;
                }
            }
            if (!target || !target.enabled) {
                console.log("AgentManager: auto-reset timer fired for", id,
                    "but agent is no longer enabled — skipping.");
                return;
            }
            // Skip if a fresh process is already running (e.g. user
            // clicked Reset manually between the schedule and fire).
            if (root._processes[id]) {
                console.log("AgentManager: auto-reset timer fired for", id,
                    "but process is already running — skipping.");
                return;
            }
            console.log("AgentManager: auto-resetting", id);
            root.resetProcess(id);
        }
    }

    function _wireClientSignals(client, conn) {
        client.connected.connect(() => {
            conn.status = "connected";
            statusChanged(conn.id, "connected", "");
            // Clear the auto-reset retry counter — the connection
            // is healthy, no further recovery needed.
            delete root._autoResetAttempts[conn.id];
        });
        client.disconnected.connect(() => {
            conn.status = "disconnected";
            statusChanged(conn.id, "disconnected", "");
        });
        client.error.connect(msg => {
            conn.status = "error";
            conn.statusMessage = msg;
            statusChanged(conn.id, "error", msg);
        });
        client.toolsDiscovered.connect(tools => {
            conn.discoveredTools = tools || [];
            if (root.toolRegistry) root.toolRegistry.register(conn.id, conn, tools);
        });
    }

    // Disconnect (stop the client, mark disabled). The next time the
    // profile is reloaded (e.g. on shell restart), the disabled state
    // is honored.
    function disconnectAgent(agentId) {
        _teardownOne(agentId);
        for (let i = 0; i < connections.length; i++) {
            if (connections[i] && connections[i].id === agentId) {
                if (connections[i].enabled) {
                    connections[i].enabled = false;
                    // Persist the disabled state via the store.
                    let p = AgentStore.getProfile(agentId);
                    if (p) {
                        p.enabled = false;
                        AgentStore.saveProfile(p);
                    }
                }
                connections[i].status = "disconnected";
                break;
            }
        }
    }

    // Reconnect: re-enable the profile and spawn the client.
    function reconnectAgent(agentId) {
        _teardownOne(agentId);
        for (let i = 0; i < connections.length; i++) {
            if (connections[i] && connections[i].id === agentId) {
                connections[i].enabled = true;
                let p = AgentStore.getProfile(agentId);
                if (p) {
                    p.enabled = true;
                    AgentStore.saveProfile(p);
                }
                if (connections[i].enabled) _connectAgent(connections[i]);
                break;
            }
        }
    }

    // ── Migration shim ──
    // Kept for back-compat with anything in the dashboard that still
    // calls these. They all delegate to AgentStore.
    function addConnection(config) {
        if (!config || !config.id) {
            console.warn("AgentManager.addConnection: invalid config, missing id");
            return;
        }
        AgentStore.saveProfile(config);
    }

    function removeConnection(agentId) {
        // Tear down the live client, then remove the file.
        _teardownOne(agentId);
        AgentStore.deleteProfile(agentId);
    }

    function saveConnections() {
        // Force a re-snapshot from in-memory connections back to disk.
        for (let i = 0; i < connections.length; i++) {
            AgentStore.saveProfile(connections[i]);
        }
    }

    // Agent tool invocation dispatcher
    property Connections invokeDispatcher: Connections {
        target: root.toolRegistry
        function onToolInvokeRequested(agentId, tool, args, callback) {
            let client = root._clients[agentId];
            if (!client) {
                if (callback) callback({ content: "", error: "Agent not connected", done: true });
                return;
            }
            if (typeof client.invokeTool === "function") {
                client.invokeTool(tool.name, args, callback);
            } else if (typeof client.sendRequest === "function") {
                client.sendRequest("tools/call", { name: tool.name, arguments: args || {} }, function(err, result) {
                    if (err) {
                        let msg = err.message || (typeof err === "string" ? err : JSON.stringify(err));
                        callback({ content: "", error: msg, done: true });
                        return;
                    }
                    let content = "";
                    if (result) {
                        if (typeof result === "string") content = result;
                        else if (result.content !== undefined) content = typeof result.content === "string" ? result.content : JSON.stringify(result.content);
                        else if (result.result !== undefined) content = typeof result.result === "string" ? result.result : JSON.stringify(result.result);
                        else content = JSON.stringify(result);
                    }
                    let isError = !!(result && result.isError);
                    callback({ content: content, error: isError ? content : null, done: true });
                });
            } else {
                if (callback) callback({ content: "", error: "Client does not support tool invocation", done: true });
            }
        }
    }
}
