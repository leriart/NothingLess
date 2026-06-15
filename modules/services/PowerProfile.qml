pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.theme

/**
 * PowerProfile — Wrapper for power-profiles-daemon (powerprofilesctl).
 *
 * Detection: single check at startup; `refresh()` can be called manually to
 * re-detect (e.g. after installing the daemon post-boot).
 *
 * State machine:
 *   - isAvailable=false  → no UI shown, calls become no-ops
 *   - isAvailable=true   → currentProfile + availableProfiles populated
 *
 * setProfile(name):
 *   - Validates against availableProfiles
 *   - Optimistically updates currentProfile (for snappy UI)
 *   - Spawns setProc; on exit re-reads via getProc to confirm
 *   - If set fails, getProc restores correct value
 */
Singleton {
    id: root

    readonly property var _orderedProfiles: ["power-saver", "balanced", "performance"]

    property bool isAvailable: false
    property string backendType: ""  // "powerprofilesctl" or ""
    property var availableProfiles: []
    property string currentProfile: ""
    property bool initialized: false

    signal availabilityChanged(bool available)
    signal profileChanged(string profile)

    // ── Detection ───────────────────────────────────────────────────────
    property Process checkProc: Process {
        id: checkProc
        workingDirectory: "/"
        command: ["powerprofilesctl", "version"]
        running: false
        stdout: SplitParser {}
        onExited: exitCode => {
            if (exitCode === 0) {
                root._adoptBackend("powerprofilesctl");
                root.getProc.running = true;
                root.listProc.running = true;
            } else {
                root._adoptBackend("");
            }
        }
    }

    function refresh() {
        checkProc.running = true;
    }

    function _adoptBackend(backend) {
        const wasAvail = isAvailable;
        if (backend === "powerprofilesctl") {
            backendType = backend;
            isAvailable = true;
            availableProfiles = _orderedProfiles.slice();
        } else {
            backendType = "";
            isAvailable = false;
            availableProfiles = [];
            currentProfile = "";
        }
        if (wasAvail !== isAvailable) {
            availabilityChanged(isAvailable);
        }
        initialized = true;
    }

    // ── Get current profile ─────────────────────────────────────────────
    property Process getProc: Process {
        id: getProc
        workingDirectory: "/"
        command: ["powerprofilesctl", "get"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                const p = (data || "").trim();
                if (p && p.length > 0 && root.availableProfiles.indexOf(p) !== -1) {
                    if (root.currentProfile !== p) {
                        root.currentProfile = p;
                        root.profileChanged(p);
                    }
                }
            }
        }
    }

    // ── List available profiles (sanity check; mostly informational) ────
    property Process listProc: Process {
        id: listProc
        workingDirectory: "/"
        command: ["powerprofilesctl", "list"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                if (!data) return;
                // Lines look like:
                //   "  performance:"
                //   "* balanced:"            (active profile is prefixed with *)
                //   "  power-saver:"
                // Strip the optional "*" active-marker, then match the profile name.
                const m = data.match(/^\s*\*?\s*(\S+):\s*$/);
                if (!m) return;
                const name = m[1];
                if (root._orderedProfiles.indexOf(name) === -1) return;
                if (root.availableProfiles.indexOf(name) === -1) {
                    // Preserve canonical order
                    const ordered = root._orderedProfiles.filter(n =>
                        n === name || root.availableProfiles.indexOf(n) !== -1);
                    root.availableProfiles = ordered;
                }
            }
        }
    }

    // ── Set profile ─────────────────────────────────────────────────────
    property Process setProc: Process {
        id: setProc
        workingDirectory: "/"
        running: false
        stdout: SplitParser {}
        stderr: SplitParser {
            onRead: data => {
                const err = (data || "").trim();
                if (err.length > 0) {
                    console.warn("PowerProfile: set error:", err);
                }
            }
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                console.info("PowerProfile: profile changed to", root.currentProfile);
            } else {
                console.warn("PowerProfile: set failed, re-reading current state");
            }
            // Always re-read to confirm ground truth
            Qt.callLater(() => { root.getProc.running = true; });
        }
    }

    // ── Public API ──────────────────────────────────────────────────────
    function setProfile(name) {
        if (!isAvailable) {
            console.warn("PowerProfile: setProfile called but service unavailable");
            return;
        }
        if (availableProfiles.indexOf(name) === -1) {
            console.warn("PowerProfile: unknown profile", name);
            return;
        }
        // Optimistic UI update
        currentProfile = name;
        setProc.command = ["powerprofilesctl", "set", name];
        setProc.running = true;
    }

    function cycle() {
        if (!isAvailable || availableProfiles.length === 0) return;
        const idx = availableProfiles.indexOf(currentProfile);
        const nextIdx = (idx + 1) % availableProfiles.length;
        setProfile(availableProfiles[nextIdx]);
    }

    function getProfileIcon(name) {
        if (name === "power-saver") return Icons.powerSave;
        if (name === "balanced") return Icons.balanced;
        if (name === "performance") return Icons.performance;
        return Icons.balanced;
    }

    function getProfileDisplayName(name) {
        if (name === "power-saver") return "Power Save";
        if (name === "balanced") return "Balanced";
        if (name === "performance") return "Performance";
        return name;
    }

    // ── Init ────────────────────────────────────────────────────────────
    Component.onCompleted: {
        // Defer first detection so the shell can finish initializing
        Qt.callLater(() => { checkProc.running = true; });
    }
}
