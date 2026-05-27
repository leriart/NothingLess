pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

/*!
 * \brief Maps hyprctl window data to WlrToplevel handles for ScreencopyView.
 *
 * ToplevelManager.toplevels.values provides WlrToplevel objects from
 * native Wayland surfaces, but they don't carry the hyprctl "address".
 * This mapper bridges the gap by matching on appId + title heuristics.
 *
 * Usage in Overview:
 *   ScreencopyView {
 *       captureSource: WlrToplevelMapper.find(win.class, win.title)
 *   }
 */
Singleton {
    id: root

    // ── Internal cache ──
    property var _cachedToplevels: []

    // Re-populate cache whenever ToplevelManager changes
    property var _toplevelValues: ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    on_ToplevelValuesChanged: {
        root._cachedToplevels = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : [];
    }

    // Also poll periodically for toplevels that register late
    Timer {
        id: pollTimer
        interval: 800
        running: true
        repeat: true
        onTriggered: {
            var fresh = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : [];
            if (fresh.length !== root._cachedToplevels.length) {
                root._cachedToplevels = fresh;
            }
        }
    }

    // ── Public API ──

    /*!
     * Find the best WlrToplevel match for a given window class and title.
     * Returns null if no match found.
     *
     * Matching strategy:
     *   1. appId exact match
     *   2. Among appId matches, exact title match
     *   3. Among appId matches, partial title match
     *   4. Fallback: focused instance, then first match
     */
    function find(cls, title) {
        var tls = root._cachedToplevels;
        if (!tls || tls.length === 0) return null;

        var clsLower = (cls || "").toLowerCase().trim();
        if (!clsLower) return null;

        // ── Pass 1: Filter by appId ──
        var matches = [];
        for (var i = 0; i < tls.length; i++) {
            var t = tls[i];
            var appId = (t.appId || "").toLowerCase().trim();
            if (appId === clsLower) {
                matches.push(t);
            }
        }

        // Also try partial appId match (e.g. "zen" matches "app.zen_browser.zen")
        if (matches.length === 0) {
            for (var j = 0; j < tls.length; j++) {
                var tj = tls[j];
                var appIdJ = (tj.appId || "").toLowerCase().trim();
                if (appIdJ.indexOf(clsLower) >= 0 || clsLower.indexOf(appIdJ) >= 0) {
                    matches.push(tj);
                }
            }
        }

        if (matches.length === 0) return null;
        if (matches.length === 1) return matches[0];

        // ── Pass 2: Exact title match ──
        var titleStr = (title || "").trim();
        for (var k = 0; k < matches.length; k++) {
            if ((matches[k].title || "").trim() === titleStr) {
                return matches[k];
            }
        }

        // ── Pass 3: Partial title match ──
        var titleLower = titleStr.toLowerCase();
        for (var l = 0; l < matches.length; l++) {
            var tTitle = (matches[l].title || "").toLowerCase().trim();
            if (titleLower.indexOf(tTitle) >= 0 || tTitle.indexOf(titleLower) >= 0) {
                return matches[l];
            }
        }

        // ── Pass 4: Focused instance or first ──
        for (var m = 0; m < matches.length; m++) {
            if (matches[m].activated) {
                return matches[m];
            }
        }

        return matches[0];
    }

    /*!
     * Returns true if any WlrToplevel is available (cache is populated).
     */
    readonly property bool hasToplevels: _cachedToplevels.length > 0

    /*!
     * Number of cached toplevels.
     */
    readonly property int count: _cachedToplevels.length
}
