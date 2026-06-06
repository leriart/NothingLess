pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme

/*!
    AnimatedBehavior.qml — Reusable pre-configured NumberAnimation for NothingLess.

    Centralizes the most common animation patterns so individual components
    don't copy-paste NumberAnimation blocks. Respects the active Anim profile,
    spring configs, and the global animationsEnabled flag via the wrapping
    Behavior.

    Usage inside a Behavior:
        Behavior on opacity {
            AnimatedBehavior {
                type: "standard"
                size: "normal"
                variant: ""          // optional: "enter" | "exit" | "expand" | "collapse"
                useSpring: false     // if true, uses spring instead of bezier
                springName: "snappy" // "", "snappy", "expressive"
                speedMultiplier: 1.0
            }
        }
*/
NumberAnimation {
    id: root

    // Animation profile selection
    property string type: "standard"
    property string size: "normal"
    property string variant: ""

    // Spring overrides
    property bool useSpring: false
    property string springName: ""

    // Timing
    property real speedMultiplier: 1.0

    // ── Pre-resolved spring (once per instance) ──
    readonly property var _spring: useSpring ? Anim.springByName(springName) : null

    // ── Optimized duration: |0 integer truncation (≈2× faster than Math.round) ──
    readonly property int _duration: {
        if (useSpring && _spring && _spring.duration > 0)
            return (_spring.duration * speedMultiplier + 0.5) | 0;
        // Fast-path: Anim.duration() now uses precomputed flat-table lookup
        return (Anim.duration(type, size) * speedMultiplier + 0.5) | 0;
    }

    // ── Optimized easing: cached object reference from Anim._easeCache ──
    readonly property var _easing: useSpring && _spring ? _spring : Anim.easing(type, variant)

    // ── Direct property bindings (no intermediate function calls) ──
    duration: root._duration
    easing.type: root._easing ? root._easing.type : Easing.Linear
    easing.bezierCurve: root._easing && root._easing.bezierCurve !== undefined
        ? root._easing.bezierCurve
        : []
    easing.overshoot: root._easing && root._easing.overshoot !== undefined
        ? root._easing.overshoot
        : 0
}
