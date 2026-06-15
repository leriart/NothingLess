pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.globals

/**
 * ChargeLimitService — Battery charge limit (preserves battery longevity).
 *
 * Backends tried in order (see scripts/set-charge-limit.sh):
 *   1. tlp       (sudo -n tlp setcharge)
 *   2. sysfs     (direct write to /sys/class/power_supply/BATn/charge_control_end_threshold)
 *
 * The script self-detects and self-reports; the service just wraps the call
 * and tracks the last applied value.
 */
Singleton {
    id: root

    readonly property string scriptPath: {
        // Look up scripts/set-charge-limit.sh relative to shell
        return Quickshell.shellDir + "/scripts/set-charge-limit.sh";
    }

    property bool isAvailable: false
    property string backendType: ""  // "tlp" | "sysfs" | ""
    property bool enabled: false  // user toggle
    property int limit: 80  // [50..100]
    property int lastApplied: 0  // last value successfully applied (0 = never)
    property bool initialized: false

    // ── Detection (runs once) ────────────────────────────────────────────
    property Process detectProc: Process {
        id: detectProc
        workingDirectory: "/"
        command: ["bash", "-c", "command -v tlp >/dev/null 2>&1 && echo tlp || true; for b in /sys/class/power_supply/BAT*/charge_control_end_threshold; do [ -w \"$b\" ] && echo sysfs && break; done; exit 0"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                const out = (data || "").trim();
                if (out === "tlp") {
                    root.backendType = "tlp";
                    root.isAvailable = true;
                } else if (out === "sysfs" && !root.isAvailable) {
                    root.backendType = "sysfs";
                    root.isAvailable = true;
                }
            }
        }
        onExited: exitCode => {
            root.initialized = true;
            if (!root.isAvailable) {
                console.info("ChargeLimit: no backend available (install tlp or configure udev)");
            } else {
                console.info("ChargeLimit: backend =", root.backendType);
                // Apply persisted preference if enabled
                if (root.enabled && StateService.initialized) {
                    root.apply();
                }
            }
        }
    }

    function refresh() {
        backendType = "";
        isAvailable = false;
        detectProc.running = true;
    }

    // ── Apply ────────────────────────────────────────────────────────────
    property Process applyProc: Process {
        id: applyProc
        workingDirectory: "/"
        running: false
        stdout: SplitParser {
            onRead: data => {
                const line = (data || "").trim();
                if (line.length > 0) {
                    console.info("ChargeLimit:", line);
                }
            }
        }
        stderr: SplitParser {
            onRead: data => {
                const line = (data || "").trim();
                if (line.length > 0) {
                    console.warn("ChargeLimit:", line);
                }
            }
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                root.lastApplied = root.limit;
            } else {
                console.warn("ChargeLimit: apply failed with exit code", exitCode);
            }
        }
    }

    function apply() {
        if (!isAvailable) return;
        applyProc.command = ["bash", scriptPath, String(limit)];
        applyProc.running = true;
    }

    function setEnabled(value) {
        enabled = value;
        if (StateService.initialized) {
            StateService.set("chargeLimitEnabled", value);
        }
        if (value) apply();
    }

    function setLimit(value) {
        const v = Math.max(50, Math.min(100, value));
        limit = v;
        if (StateService.initialized) {
            StateService.set("chargeLimit", v);
        }
        if (enabled) apply();
    }

    // ── Persistence ──────────────────────────────────────────────────────
    Connections {
        target: StateService
        function onStateLoaded() {
            const persistedEnabled = StateService.get("chargeLimitEnabled", false);
            const persistedLimit = StateService.get("chargeLimit", 80);
            if (persistedLimit >= 50 && persistedLimit <= 100) {
                root.limit = persistedLimit;
            }
            if (persistedEnabled) {
                root.enabled = true;
                if (root.isAvailable) root.apply();
            }
        }
    }

    Timer {
        interval: 500
        running: true
        repeat: false
        onTriggered: {
            if (!root.initialized) {
                detectProc.running = true;
            }
        }
    }
}
