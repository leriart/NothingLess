pragma Singleton
import QtQuick
import Quickshell

// Compositor-agnostic focus grab coordinator.
// Tracks active focus grabs and provides a backdrop-click clearing mechanism.
// When any grab is active, consumers (e.g., UnifiedShellPanel) can expand their
// input mask to full-screen and show a backdrop MouseArea that calls clearTopGrab().
Singleton {
    id: root

    // Whether any focus grab is currently active
    property int _activeCount: 0
    // Derive directly from _grabs so any desync in _activeCount cannot
    // permanently lock the screen.
    readonly property bool hasActiveGrab: Object.keys(_grabs).length > 0

    // Internal storage: grabId -> callback
    property var _grabs: ({})
    // Ordered list for stack behavior (last-in-first-cleared)
    property var _grabOrder: []

    function requestGrab(grabId, clearCallback) {
        if (_grabs[grabId] === undefined) {
            _grabOrder = [..._grabOrder, grabId];
            _activeCount++;
        }
        let updated = {};
        Object.keys(_grabs).forEach(k => { updated[k] = _grabs[k]; });
        updated[grabId] = clearCallback;
        _grabs = updated;
        sanityCheck();
    }

    function releaseGrab(grabId) {
        if (_grabs[grabId] !== undefined) {
            let updated = {};
            Object.keys(_grabs).forEach(k => {
                if (k !== grabId) updated[k] = _grabs[k];
            });
            _grabs = updated;
            _grabOrder = _grabOrder.filter(id => id !== grabId);
            _activeCount = Math.max(0, _activeCount - 1);
        }
        sanityCheck();
    }

    // Defensive: recalculate _activeCount from _grabOrder to recover from
    // any desync caused by orphan grabs.
    function sanityCheck() {
        const expected = _grabOrder.length;
        if (_activeCount !== expected) {
            console.warn("FocusGrabManager: count desync detected (" + _activeCount + " vs " + expected + "), correcting.");
            _activeCount = expected;
        }
    }

    // Clear the most recent (top) grab — typically called by a backdrop MouseArea
    function clearTopGrab() {
        if (_grabOrder.length === 0) return;
        const topId = _grabOrder[_grabOrder.length - 1];
        const callback = _grabs[topId];
        releaseGrab(topId);
        if (callback) {
            Qt.callLater(callback);
        }
    }

    // Nuclear option: clear ALL grabs unconditionally.
    // Used by the backdrop when the user explicitly clicks the transparent
    // overlay to unblock the screen, and by the periodic safety timer to
    // clean up orphaned grabs from destroyed components.
    function clearAllGrabs() {
        if (_grabOrder.length === 0) return;
        // Save callbacks before clearing so we can invoke them
        const savedGrabs = {};
        Object.keys(_grabs).forEach(k => { savedGrabs[k] = _grabs[k]; });
        const savedOrder = [..._grabOrder];
        _grabs = {};
        _grabOrder = [];
        _activeCount = 0;
        // Notify components that their grabs were force-cleared
        for (let i = savedOrder.length - 1; i >= 0; i--) {
            const cb = savedGrabs[savedOrder[i]];
            if (cb) Qt.callLater(cb);
        }
    }

    // Periodic safety net: clear orphaned grabs from destroyed components
    // that missed their destruction handler.
    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: {
            root.sanityCheck();
            if (Object.keys(_grabs).length > 0 && _activeCount === 0) {
                console.warn("FocusGrabManager: orphan grabs detected, force-clearing");
                root.clearAllGrabs();
            }
        }
    }
}
