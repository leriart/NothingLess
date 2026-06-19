pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

/*!
    AgentStore — Per-file JSON persistence for AI agent profiles.

    Each agent lives in its own file under `agentsDir` (default
    `~/.config/nothingless/agents/<id>.json`). This is the new source of
    truth for the agent list, replacing `Config.ai.agents` (a
    `property list<var>` inside a JsonAdapter that suffered from
    unreliable `onAdapterUpdated` emission on re-assignment, causing
    agent additions to never reach disk).

    Why per-file:
      - File-based persistence is 100% reliable — no JSON adapter
        signal fragility.
      - Each agent is an atomic unit — saving one never risks
        corrupting the others.
      - The user can edit profiles directly with a text editor; the
        Settings → Agent profiles tab exposes this through a JSON
        editor.
      - Mirrors the pattern NothingLess already uses for bar/dock
        presets (`~/.config/nothingless/presets/`).

    Migration:
      - On first load, if `Config.ai.agents` (legacy) has entries, the
        store writes each one to its own file and clears the legacy
        list. This is a one-time operation.
*/
Singleton {
    id: root

    // ── Paths ──
    // Mirrors the convention used by PresetsService: store under
    // XDG_DATA_HOME/nothingless/agents (per-user, survives config
    // wipes). The user's home is the source of truth.
    readonly property string agentsDir: {
        const dataHome = Quickshell.env("XDG_DATA_HOME");
        const base = (dataHome && dataHome.length > 0)
            ? dataHome
            : Quickshell.env("HOME") + "/.local/share";
        return base + "/nothingless/agents";
    }

    // ── State ──
    // The list of loaded agent profiles, each is a plain JS object
    // matching the schema documented in AgentConnection.qml.
    property var profiles: []

    // Cached FileViews keyed by agent id. FileView watches the file
    // and emits fileChanged when the file is rewritten externally.
    property var _watchers: ({})

    // Pending migration: legacy Config.ai.agents entries that need to
    // be split into individual files. We do this lazily on first
    // access to avoid races during boot.
    property bool _migrationDone: false

    // Last error from a write operation (so the editor can surface it).
    property string lastError: ""

    // ── Signals ──
    // NOTE: profilesChanged is auto-generated for the `profiles` property
    // above — do NOT declare it manually. Consumers (AgentManager) bind
    // directly to the onProfilesChanged handler that QML provides.
    signal profileSaved(string id)
    signal profileDeleted(string id)
    signal migrationCompleted(int count)

    Component.onCompleted: {
        _reloadAll();
    }

    // ── Filesystem helpers ──
    function _profilePath(id) {
        return agentsDir + "/" + _safeFilename(id) + ".json";
    }

    // Make the id safe to use as a filename: alphanumerics, dash, dot,
    // underscore; everything else becomes underscore. Empty / weird
    // inputs get a fallback name.
    function _safeFilename(id) {
        if (!id || typeof id !== "string") return "agent";
        return id.replace(/[^A-Za-z0-9._-]/g, "_");
    }

    // ── Migration: legacy Config.ai.agents → per-file JSON ──
    function _migrateFromConfig() {
        if (_migrationDone) return;
        if (!Config || !Config.ai) {
            _migrationDone = true;
            return;
        }
        let legacy = Config.ai.agents;
        let n = legacy ? (legacy.length || 0) : 0;
        if (n === 0) {
            _migrationDone = true;
            return;
        }
        console.log("AgentStore: migrating", n, "legacy agent(s) to per-file JSON");
        let count = 0;
        for (let i = 0; i < n; i++) {
            let a = legacy[i];
            if (!a) continue;
            try {
                if (writeProfileSync(a)) count++;
            } catch (e) {
                console.warn("AgentStore: migration of", a.id, "failed:", e);
            }
        }
        // Clear the legacy list so we don't re-migrate.
        Config.ai.agents = [];
        _migrationDone = true;
        if (count > 0) {
            console.log("AgentStore: migration complete,", count, "agent(s) written");
            migrationCompleted(count);
        }
    }

    // ── Reload all profiles from disk ──
    function reloadFromDisk() {
        _migrateFromConfig();
        _reloadAll();
    }

    // Reads every .json file in the agents directory with a single
    // Python one-liner. Previously we ran `ls | while read f; cat
    // $f` through a per-file SplitParser→loadFileProc chain, but
    // that reused a single Quickshell Process (`loadFileProc`) and
    // setting `running = true` on an already-running process is
    // unreliable in Quickshell 0.3.0 — subsequent lines would
    // silently drop because the second `running = true` killed the
    // first cat mid-stream.
    function _reloadAll() {
        let py = [
            "import os, glob, sys, json",
            "agents_dir = '" + agentsDir.replace(/'/g, "'\\''") + "'",
            "os.makedirs(agents_dir, exist_ok=True)",
            "for f in sorted(glob.glob(os.path.join(agents_dir, '*.json'))):",
            "    try:",
            "        with open(f) as fp: data = json.load(fp); print(json.dumps(data))",
            "    except Exception as e: print(f, file=sys.stderr)"
        ].join("\n");
        let proc = reloadProc;
        proc.command = ["python3", "-c", py];
        proc.running = true;
    }

    property Process reloadProc: Process {
        running: false
        stdout: SplitParser {
            // Python emits one line of JSON per profile file.
            // No prefix/separator — just raw JSON, one blob per line.
            onRead: line => {
                var json = (line || "").trim();
                if (json) {
                    try {
                        var data = JSON.parse(json);
                        if (data && data.id) {
                            root._upsertProfile(data);
                            root._ensureWatcher(data.id);
                        }
                    } catch (e) {
                        console.warn("AgentStore: failed to parse profile:", e);
                    }
                }
            }
        }
        stderr: StdioCollector {
            id: reloadStderr
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                console.warn("AgentStore: reload from disk failed (exit", exitCode, "):", reloadStderr.text);
            }
        }
    }

    // ── Per-file watcher (FileView) ──
    // FileView watches the file and re-emits its content. We re-parse
    // and update the in-memory profile on fileChanged. This is what
    // makes the editor's "save" round-trip safe even from a different
    // process or a text editor.
    function _ensureWatcher(id) {
        if (_watchers[id]) return _watchers[id];
        // FileView is in Quickshell.Io. We instantiate one directly
        // as a child of the singleton (Quickshell.Io is already
        // imported at the top of the file) instead of via a Component
        // wrapper, because `Quickshell.Io.FileView` is not a valid
        // QML namespace reference inside a Component body.
        var fv = fileViewComponent.createObject(root, {
            path: _profilePath(id),
            watchChanges: true
        });
        fv.fileChanged.connect(function() {
            try {
                var contents = fv.read();
                if (!contents) return;
                var data = JSON.parse(contents);
                if (data && data.id) {
                    root._upsertProfile(data);
                }
            } catch (e) {
                // Don't clobber a perfectly good in-memory copy just
                // because a half-typed save is mid-write.
            }
        });
        _watchers[id] = fv;
        return fv;
    }

    // Component factory for the per-profile FileView. FileView is
    // imported via Quickshell.Io at the top of the file.
    Component {
        id: fileViewComponent
        FileView {
        }
    }

    // Drop the watcher for an agent that was deleted.
    function _dropWatcher(id) {
        if (_watchers[id]) {
            try { _watchers[id].destroy(); } catch (e) {}
            delete _watchers[id];
        }
    }

    // ── Public API ──

    // Return the list of profile objects (id, name, type, etc.).
    function listProfiles() {
        return profiles;
    }

    // Look up a profile by id.
    function getProfile(id) {
        if (!id) return null;
        for (let i = 0; i < profiles.length; i++) {
            if (profiles[i] && profiles[i].id === id) return profiles[i];
        }
        return null;
    }

    // Validate a profile object. Returns null on success, or a
    // human-readable error string.
    function validateProfile(p) {
        if (!p || typeof p !== "object") return "Profile must be an object";
        if (!p.id || typeof p.id !== "string") return "id is required (string)";
        if (!p.name || typeof p.name !== "string") return "name is required (string)";
        if (!p.type || typeof p.type !== "string") return "type is required (string)";
        const validTypes = ["http-bridge", "mcp-sse", "command", "mcp-stdio"];
        if (validTypes.indexOf(p.type) === -1) {
            return "type must be one of: " + validTypes.join(", ");
        }
        if ((p.type === "http-bridge" || p.type === "mcp-sse") && (!p.endpoint || typeof p.endpoint !== "string")) {
            return p.type + " requires an endpoint URL";
        }
        if ((p.type === "command" || p.type === "mcp-stdio")) {
            if (p.command !== undefined && typeof p.command !== "string") {
                return "command must be a string";
            }
            if (p.args !== undefined && !Array.isArray(p.args)) {
                return "args must be an array of strings";
            }
        }
        if (p.headers !== undefined && (typeof p.headers !== "object" || Array.isArray(p.headers))) {
            return "headers must be an object";
        }
        // Optional embedded process descriptor: command is required,
        // args must be an array of strings, cwd/env are optional
        // strings / objects. An empty / missing `process` is valid and
        // means the agent has no shell-managed lifecycle.
        if (p.process !== undefined && p.process !== null) {
            const proc = p.process;
            if (typeof proc !== "object" || Array.isArray(proc)) {
                return "process must be an object";
            }
            if (typeof proc.command !== "string" || proc.command.length === 0) {
                return "process.command is required (string)";
            }
            if (proc.args !== undefined && !Array.isArray(proc.args)) {
                return "process.args must be an array of strings";
            }
            for (let i = 0; i < (proc.args || []).length; i++) {
                if (typeof proc.args[i] !== "string") {
                    return "process.args[" + i + "] must be a string";
                }
            }
            if (proc.cwd !== undefined && typeof proc.cwd !== "string") {
                return "process.cwd must be a string";
            }
            if (proc.env !== undefined && (typeof proc.env !== "object" || Array.isArray(proc.env))) {
                return "process.env must be an object";
            }
        }
        return null;
    }

    // Save a profile to disk (atomic write via tmp+rename). Returns
    // true if the save was accepted, false if validation failed (the
    // write itself is asynchronous).
    function saveProfile(p) {
        const err = validateProfile(p);
        if (err) {
            lastError = err;
            return false;
        }
        const path = _profilePath(p.id);
        const json = JSON.stringify(_normalizeForDisk(p), null, 2);
        // Atomic write: write to .tmp, then rename over the real
        // file. The mkdir -p guards against the directory not
        // existing yet (first save, or the agents dir was wiped).
        const script =
            "mkdir -p '" + agentsDir.replace(/'/g, "'\\''") + "' && " +
            "printf '%s' '" + json.replace(/'/g, "'\\''") + "' > '" + path + ".tmp' && " +
            "mv '" + path + ".tmp' '" + path + "'";
        // Create a fresh Process each time so two rapid saves never
        // collide on the same `runProc` instance (Quickshell 0.3.0
        // does not reliably restart an already-running Process).
        let proc = writeProcFactory.createObject(root, {});
        proc._pendingPath = path;
        proc._pendingJson = json;
        proc._profileObj = p;
        proc.command = ["bash", "-c", script];
        proc.running = true;
        return true;
    }

    // Synchronous variant used by the migration. Writes directly
    // via a spawnSync / createObject approach.
    function writeProfileSync(p) {
        const err = validateProfile(p);
        if (err) {
            lastError = err;
            return false;
        }
        const path = _profilePath(p.id);
        const json = JSON.stringify(_normalizeForDisk(p), null, 2);
        const script =
            "mkdir -p '" + agentsDir.replace(/'/g, "'\\''") + "' && " +
            "printf '%s' '" + json.replace(/'/g, "'\\''") + "' > '" + path + ".tmp' && " +
            "mv '" + path + ".tmp' '" + path + "'";
        let proc = writeProcFactory.createObject(root, {});
        proc._pendingId = p.id;
        proc.command = ["bash", "-c", script];
        proc.running = true;
        return true;
    }

    // Component factory for write processes.
    // Each save creates a fresh Process so back-to-back saves
    // (e.g. editing two profiles in quick succession from the AI
    //  panel) don't step on each other's _pending* fields.
    Component {
        id: writeProcFactory
        Process {
            id: writeProcInstance
            property string _pendingPath: ""
            property string _pendingJson: ""
            property string _pendingId: ""
            property var _profileObj: null
            running: false
            onExited: exitCode => {
                if (exitCode === 0) {
                    if (_profileObj) {
                        root._upsertProfile(_profileObj);
                        root._ensureWatcher(_profileObj.id);
                        root.profileSaved(_profileObj.id);
                    } else if (_pendingPath && _pendingJson) {
                        try {
                            let obj = JSON.parse(_pendingJson);
                            root._upsertProfile(obj);
                            root._ensureWatcher(obj.id);
                            root.profileSaved(obj.id);
                        } catch (e) {
                            console.warn("AgentStore: wrote file but cant re-parse", _pendingPath);
                        }
                    } else if (_pendingId) {
                        // writeProfileSync path
                        root.profileSaved(_pendingId);
                    }
                    root.lastError = "";
                } else {
                    root.lastError = "Write failed (exit " + exitCode + ")";
                }
                // Self-destruct so we don't leak Process instances.
                Qt.callLater(() => { try { writeProcInstance.destroy(); } catch (e) {} });
            }
        }
    }

    // Strip runtime-only fields and apply defaults so the on-disk
    // JSON is clean and round-trips safely.
    function _normalizeForDisk(p) {
        // `process` is optional and only persisted when actually
        // populated. Anything missing / empty reduces to {} so the
        // AgentManager can simply check `process && process.command`.
        let proc = {};
        if (p.process && typeof p.process === "object" && !Array.isArray(p.process)
                && typeof p.process.command === "string" && p.process.command.length > 0) {
            proc = {
                command: p.process.command,
                args: Array.isArray(p.process.args) ? p.process.args : [],
                cwd: typeof p.process.cwd === "string" ? p.process.cwd : "",
                env: (p.process.env && typeof p.process.env === "object" && !Array.isArray(p.process.env))
                    ? p.process.env : {}
            };
        }
        return {
            id: p.id,
            name: p.name,
            type: p.type,
            enabled: p.enabled !== false,
            command: p.command || "",
            args: Array.isArray(p.args) ? p.args : [],
            endpoint: p.endpoint || "",
            headers: p.headers || {},
            toolsPath: p.toolsPath || "/tools",
            invokePath: p.invokePath || "/invoke",
            process: proc
        };
    }

    // Insert or replace a profile in the in-memory list.
    function _upsertProfile(p) {
        const arr = profiles.slice();
        let found = false;
        for (let i = 0; i < arr.length; i++) {
            if (arr[i] && arr[i].id === p.id) {
                arr[i] = p;
                found = true;
                break;
            }
        }
        if (!found) arr.push(p);
        profiles = arr;
    }

    // Delete a profile. Returns true if a file was removed.
    function deleteProfile(id) {
        if (!id) return false;
        const path = _profilePath(id);
        const proc = deleteProc;
        proc._pendingId = id;
        proc.command = ["bash", "-c", "rm -f '" + path + "'"];
        proc.running = true;
        return true;
    }

    property Process deleteProc: Process {
        property string _pendingId: ""
        running: false
        onExited: exitCode => {
            if (exitCode === 0 && _pendingId) {
                // Remove from in-memory list.
                const arr = [];
                for (let i = 0; i < root.profiles.length; i++) {
                    const p = root.profiles[i];
                    if (p && p.id !== _pendingId) arr.push(p);
                }
                root.profiles = arr;
                root._dropWatcher(_pendingId);
                root.profileDeleted(_pendingId);
            }
        }
    }

    // Generate a fresh id for a new profile.
    function generateId() {
        return "agent_" + Math.floor(Date.now() / 1000).toString(36) +
               "_" + Math.floor(Math.random() * 0x100000).toString(36);
    }

    // Build a fresh profile object pre-filled with sane defaults.
    function createBlankProfile(name) {
        return {
            id: generateId(),
            name: name || "New agent",
            type: "http-bridge",
            enabled: true,
            command: "",
            args: [],
            endpoint: "",
            headers: {},
            toolsPath: "/tools",
            invokePath: "/invoke",
            process: {}
        };
    }
}
