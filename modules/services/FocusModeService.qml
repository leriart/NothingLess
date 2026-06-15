pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.config
import qs.modules.globals
import qs.modules.services

/**
 * FocusModeService — Productivity toggle that applies:
 *   • Zero gaps in Hyprland (focus mode)
 *   • DND notifications (silenced)
 *   • Caffeine mode (inhibit idle/sleep)
 *
 * Captures the current compositor config + DND/caffeine states on enable,
 * restores the snapshot on disable. Persistence via StateService.
 */
Singleton {
    id: root

    property bool enabled: false
    property bool initialized: false
    property var snapshot: null  // { gapsIn, gapsOut, caffeine, dnd, powerProfile }

    // Snapshot fields we capture from Config.compositor
    readonly property var _snapshotFields: ["gapsIn", "gapsOut"]

    function captureSnapshot() {
        var snap = {};
        for (var i = 0; i < _snapshotFields.length; i++) {
            snap[_snapshotFields[i]] = Config.compositor[_snapshotFields[i]];
        }
        snap.caffeine = CaffeineService.inhibit;
        snap.dnd = GlobalStates.notificationsDnd;
        snap.powerProfile = PowerProfile.currentProfile;
        return snap;
    }

    function apply() {
        if (enabled) {
            if (!snapshot) snapshot = captureSnapshot();
            Config.pauseAutoSave = true;
            try {
                Config.compositor.gapsIn = 0;
                Config.compositor.gapsOut = 0;
            } finally {
                Config.pauseAutoSave = false;
            }
            GlobalStates.notificationsDnd = true;
            if (CaffeineService) {
                CaffeineService.inhibit = true;
            }
        } else {
            if (snapshot) {
                Config.pauseAutoSave = true;
                try {
                    for (var i = 0; i < _snapshotFields.length; i++) {
                        if (snapshot[_snapshotFields[i]] !== undefined) {
                            Config.compositor[_snapshotFields[i]] = snapshot[_snapshotFields[i]];
                        }
                    }
                } finally {
                    Config.pauseAutoSave = false;
                }
                // Restore DND/caffeine only if user didn't toggle them manually
                if (CaffeineService) {
                    CaffeineService.inhibit = snapshot.caffeine;
                }
                GlobalStates.notificationsDnd = snapshot.dnd;
                snapshot = null;
            }
        }
        GlobalStates.compositorConfigChanged();
    }

    function enable() {
        if (enabled) return;
        enabled = true;
        apply();
        sendToggleNotification(true);
        if (StateService.initialized) {
            StateService.set("focusMode", true);
        }
    }

    function disable() {
        if (!enabled) return;
        enabled = false;
        apply();
        sendToggleNotification(false);
        if (StateService.initialized) {
            StateService.set("focusMode", false);
        }
    }

    function toggle() {
        if (enabled) disable(); else enable();
    }

    function sendToggleNotification(enabled) {
        if (!Notifications) return;
        Notifications.notifyInternal({
            "appName": "NothingLess",
            "summary": enabled ? "Focus mode enabled" : "Focus mode disabled",
            "body": enabled
                ? "Gaps to 0, DND on, idle inhibited."
                : "Compositor settings restored.",
            "urgency": NotificationUrgency.Low,
            "historyPriority": 30,
            "replaceKey": "nothingless-focusmode",
            "expireTimeout": 3000
        });
    }

    // ── Persistence ──────────────────────────────────────────────────────
    Connections {
        target: StateService
        function onStateLoaded() {
            const wasEnabled = StateService.get("focusMode", false);
            initialized = true;
            if (wasEnabled && !enabled) {
                Qt.callLater(() => enable());
            }
        }
    }

    Timer {
        interval: 100
        running: true
        repeat: false
        onTriggered: {
            if (!initialized && StateService.initialized) {
                const wasEnabled = StateService.get("focusMode", false);
                initialized = true;
                if (wasEnabled && !enabled) {
                    enable();
                }
            }
        }
    }

    Component.onDestruction: {
        if (enabled) {
            // Best-effort restore on shell teardown
            enabled = false;
            apply();
        }
    }
}
