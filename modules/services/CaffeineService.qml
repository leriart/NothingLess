import QtQuick
import Quickshell

pragma Singleton

/**
 * CaffeineService — Wraps Quickshell's IdleInhibitor and persists state.
 *
 * State persistence via StateService. Listens to StateService.stateLoaded
 * so we don't miss the initial value (eliminates the previous 500ms race).
 */
Singleton {
    id: root

    property alias inhibit: idleInhibitor.enabled

    function toggleInhibit() {
        inhibit = !inhibit;
    }

    IdleInhibitor {
        id: idleInhibitor

        onEnabledChanged: {
            if (StateService.initialized) {
                StateService.set("caffeine", enabled);
            }
        }
    }

    Connections {
        target: StateService
        function onStateLoaded() {
            root.inhibit = StateService.get("caffeine", false);
        }
    }
}
