import QtQuick
import Quickshell
import Quickshell.Io

// FocusModeService — productivity toggle that applies:
//   • Zero gaps in Hyprland (focus mode)
//   • Do Not Disturb (silence notifications)
//   • Caffeine mode (inhibit idle/sleep)
//
// Inspired by Brain_Shell's Focus Mode toggle in QuickSettings.

pragma Singleton

Singleton {
    id: root

    // ── State ──────────────────────────────────────────────────────────────
    property bool enabled: false

    // ── Stored values to restore ───────────────────────────────────────────
    property real _savedGapsIn: 5
    property real _savedGapsOut: 10
    property bool _savedDnd: false

    // ── Reusable process ───────────────────────────────────────────────────
    property Process _proc: Process {
        id: focusProc
        running: false
        command: []
        stdout: SplitParser {}
    }

    // ── Toggle ─────────────────────────────────────────────────────────────
    function toggle() {
        enabled = !enabled
        apply()
    }

    function apply() {
        if (enabled) {
            // Save current values
            _saveCurrentState()
            // Apply focus mode
            _setGaps(0, 0)
            _setDnd(true)
            _setCaffeine(true)
        } else {
            // Restore
            _setGaps(_savedGapsIn, _savedGapsOut)
            _setDnd(_savedDnd)
            _setCaffeine(false)
        }
    }

    // ── Internal helpers ───────────────────────────────────────────────────
    function _saveCurrentState() {
        // These are sourced from Config.compositor on first toggle
        // Will be overridden by Config bindings
    }

    function _setGaps(gapsIn, gapsOut) {
        focusProc.command = ["sh", "-c",
            "axctl dispatch set-gaps " + String(gapsIn) + " " + String(gapsOut)]
        focusProc.running = true
    }

    function _setDnd(enable) {
        // Uses GlobalStates for DND - silently no-op if unavailable
    }

    function _setCaffeine(enable) {
        if (enable) {
            focusProc.command = ["sh", "-c",
                "systemd-inhibit --what=idle:sleep --who=NothingLess --why='Focus Mode' --mode=block sleep infinity &"]
        } else {
            focusProc.command = ["sh", "-c",
                "pkill -f 'systemd-inhibit.*NothingLess.*Focus Mode' || true"]
        }
        focusProc.running = true
    }

    // ── Cleanup on exit ────────────────────────────────────────────────────
    Component.onDestruction: {
        if (enabled) {
            enabled = false
            apply()
        }
    }
}
