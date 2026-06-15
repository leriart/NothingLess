pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.config
import qs.modules.globals
import qs.modules.services

/**
 * GameModeService — Toggle that reduces distractions and shell overhead for fullscreen apps.
 *
 * Captures the current compositor config on enable, applies the game-mode preset
 * from Config.performance.gameMode.*, and restores the snapshot on disable.
 *
 * Persistence: state["gameMode"] (boolean) via StateService.
 * Snapshot: kept in memory only (rebuilt on every enable).
 *
 * Side effects on enable (configurable):
 *   - Config.compositor.gapsIn/gapsOut/borderSize/rounding/blurEnabled/shadowEnabled/animationsEnabled
 *   - Anim.instantMode = true  (via Anim.qml)
 *   - Notifications suppressed (via GlobalStates.notificationsDnd)
 *   - VideoWallpaperService paused (via screenLocked flag)
 *
 * Side effects on disable:
 *   - All of the above restored
 *   - apply-config.sh invoked to live-apply to Hyprland via sync-hyprland.py
 */
Singleton {
    id: root

    property bool toggled: false
    property bool initialized: false
    property var snapshot: null  // { gapsIn, gapsOut, borderSize, rounding, blurEnabled, shadowEnabled, animationsEnabled }

    // Snapshot fields we capture
    readonly property var _snapshotFields: [
        "gapsIn", "gapsOut",
        "borderSize", "rounding",
        "blurEnabled", "shadowEnabled",
        "animationsEnabled"
    ]

    function captureSnapshot() {
        var snap = {};
        for (var i = 0; i < _snapshotFields.length; i++) {
            var f = _snapshotFields[i];
            var v = Config.compositor[f];
            if (v === undefined && f === "animationsEnabled") {
                v = true;  // default
            }
            snap[f] = v;
        }
        return snap;
    }

    function applyPreset() {
        var p = Config.performance.gameMode;
        if (!p) return;

        // Wrap in pauseAutoSave to avoid disk write for transient state
        Config.pauseAutoSave = true;
        try {
            if (p.zeroGaps) {
                Config.compositor.gapsIn = 0;
                Config.compositor.gapsOut = 0;
            }
            if (p.reduceBorder) {
                Config.compositor.borderSize = Math.min(Config.compositor.borderSize || 1, 1);
                Config.compositor.rounding = 0;
            }
            if (p.disableBlur) {
                Config.compositor.blurEnabled = false;
            }
            if (p.disableShadows) {
                Config.compositor.shadowEnabled = false;
            }
            if (p.disableAnimations) {
                Config.compositor.animationsEnabled = false;
            }
        } finally {
            Config.pauseAutoSave = false;
        }
    }

    function restoreSnapshot() {
        if (!snapshot) return;
        Config.pauseAutoSave = true;
        try {
            for (var i = 0; i < _snapshotFields.length; i++) {
                var f = _snapshotFields[i];
                if (snapshot[f] !== undefined) {
                    Config.compositor[f] = snapshot[f];
                }
            }
        } finally {
            Config.pauseAutoSave = false;
        }
    }

    function enable() {
        if (toggled) return;
        snapshot = captureSnapshot();
        toggled = true;
        applyPreset();
        // Side effects: notify + pause video wallpaper
        if (Config.performance.gameMode && Config.performance.gameMode.pauseVideoWallpaper) {
            VideoWallpaperService.onScreenLocked();
        }
        GlobalStates.gameModeActive = true;
        sendToggleNotification(true);
        if (StateService.initialized) {
            StateService.set("gameMode", true);
        }
        GlobalStates.compositorConfigChanged();
    }

    function disable() {
        if (!toggled) return;
        restoreSnapshot();
        toggled = false;
        snapshot = null;
        if (Config.performance.gameMode && Config.performance.gameMode.pauseVideoWallpaper) {
            VideoWallpaperService.onScreenUnlocked();
        }
        GlobalStates.gameModeActive = false;
        sendToggleNotification(false);
        if (StateService.initialized) {
            StateService.set("gameMode", false);
        }
        GlobalStates.compositorConfigChanged();
    }

    function toggle() {
        if (toggled) disable(); else enable();
    }

    function sendToggleNotification(enabled) {
        if (!Notifications) return;
        Notifications.notifyInternal({
            "appName": "NothingLess",
            "summary": enabled ? "Game mode enabled" : "Game mode disabled",
            "body": enabled
                ? "Reduced gaps, animations, blur and shadows. Press the toggle again to restore."
                : "Compositor settings restored.",
            "urgency": NotificationUrgency.Low,
            "historyPriority": 30,
            "replaceKey": "nothingless-gamemode",
            "expireTimeout": 3000
        });
    }

    // ── Persistence ──────────────────────────────────────────────────────
    Connections {
        target: StateService
        function onStateLoaded() {
            const wasEnabled = StateService.get("gameMode", false);
            initialized = true;
            if (wasEnabled && !toggled) {
                // Re-apply on shell reload
                Qt.callLater(() => enable());
            }
        }
    }

    // Fallback init in case StateService loads before we connect
    Timer {
        interval: 100
        running: true
        repeat: false
        onTriggered: {
            if (!initialized && StateService.initialized) {
                const wasEnabled = StateService.get("gameMode", false);
                initialized = true;
                if (wasEnabled && !toggled) {
                    enable();
                }
            }
        }
    }

    // Ensure we never leave the compositor in a weird state on shell teardown
    Component.onDestruction: {
        if (toggled) {
            restoreSnapshot();
        }
    }
}
