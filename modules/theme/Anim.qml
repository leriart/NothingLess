pragma Singleton
import QtQuick
import qs.config

/*!
    Anim.qml — Material 3 animation system for NothingLess.

    Provides duration + easing presets for three M3 motion types:
    - standard:   UI transitions (buttons, panels, opacity, scale)
    - emphasized: High-emphasis feedback (notch expand, modal enter/exit)
    - spatial:    Layout/orientation changes (workspace switch, overview)

    Usage:
        import qs.modules.theme

        Behavior on opacity {
            NumberAnimation { Anim.apply(this, "standard", "normal") }
        }

        NumberAnimation {
            target: foo; property: "x"
            Anim.configure(this, "emphasized", "large", "enter")
        }

        // Or manually:
        duration: Anim.duration("standard", "normal")
        easing.type: Anim.easing("standard")
*/
QtObject {
    id: root

    // ============================================
    // BASE DURATIONS (ms) — Material 3 spec
    // ============================================
    readonly property var _durations: ({
        standard: {
            small:      100,
            normal:     200,
            large:      300,
            extraLarge: 400
        },
        emphasized: {
            small:  150,
            normal: 300,
            large:  450
        },
        spatial: {
            fast:    100,
            default: 250,
            slow:    400
        }
    })

    // ============================================
    // EASING CURVES — Material 3 spec
    // ============================================
    // Standard:   cubic-bezier(0.2, 0.0, 0.0, 1.0)  — ease-out deceleration
    // Emphasized: cubic-bezier(0.05, 0.7, 0.1, 1.0) — enter (overshoot deceleration)
    // Emphasized (accelerate): cubic-bezier(0.3, 0.0, 0.8, 0.15) — exit (accelerate out)
    // Spatial:    cubic-bezier(0.4, 0.0, 0.2, 1.0)  — standard Material curve
    // Decelerate: cubic-bezier(0.0, 0.0, 0.2, 1.0)  — entering from off-screen
    // Accelerate: cubic-bezier(0.4, 0.0, 1.0, 1.0)  — exiting to off-screen
    // Linear:     linear                             — color/value interpolation
    readonly property var _easings: ({
        standard:   { type: Easing.BezierSpline, bezierCurve: [0.2, 0.0, 0.0, 1.0] },
        emphasized: { type: Easing.BezierSpline, bezierCurve: [0.05, 0.7, 0.1, 1.0] },
        emphasizedAccel: { type: Easing.BezierSpline, bezierCurve: [0.3, 0.0, 0.8, 0.15] },
        spatial:    { type: Easing.BezierSpline, bezierCurve: [0.4, 0.0, 0.2, 1.0] },
        decelerate: { type: Easing.BezierSpline, bezierCurve: [0.0, 0.0, 0.2, 1.0] },
        accelerate: { type: Easing.BezierSpline, bezierCurve: [0.4, 0.0, 1.0, 1.0] },
        linear:     { type: Easing.Linear }
    })

    // ============================================
    // GLOBAL SPEED SCALE
    // ============================================
    // Falls back to Config.animDuration / 300 so existing configs remain valid.
    // If Config adds animScale in the future, that takes precedence.
    readonly property real _baseScale: {
        const cfgScale = Config.theme && Config.theme.animScale;
        if (cfgScale !== undefined && cfgScale > 0) return cfgScale;
        // Derive from legacy animDuration so we don't break existing configs.
        // animDuration 0 (GameMode) disables animations entirely.
        if (Config.animDuration <= 0) return 0;
        return Config.animDuration / 300;
    }

    function _scale(baseMs) {
        return Math.max(0, Math.round(baseMs * root._baseScale));
    }

    // ============================================
    // PUBLIC API
    // ============================================

    /*! Get duration in ms for a given type/size. */
    function duration(type, size) {
        const t = root._durations[type];
        if (!t) return 0;
        return root._scale(t[size] || t.normal || t.default || 0);
    }

    /*! Get easing configuration object.
        @param type: "standard" | "emphasized" | "emphasizedAccel" | "spatial" | "decelerate" | "accelerate" | "linear"
        @param variant: (optional) "enter" | "exit" — shorthand for emphasized variants
    */
    function easing(type, variant) {
        if (type === "emphasized") {
            if (variant === "exit" || variant === "accelerate")
                return root._easings.emphasizedAccel;
            return root._easings.emphasized;
        }
        if (variant === "enter" && root._easings[type + "Enter"])
            return root._easings[type + "Enter"];
        if (variant === "exit" && root._easings[type + "Exit"])
            return root._easings[type + "Exit"];
        return root._easings[type] || root._easings.standard;
    }

    /*! Configure an existing NumberAnimation in-place. */
    function configure(anim, type, size, variant) {
        if (!anim || !(anim instanceof NumberAnimation)) return;
        anim.duration = root.duration(type, size);
        const ease = root.easing(type, variant);
        anim.easing.type = ease.type;
        if (ease.bezierCurve !== undefined)
            anim.easing.bezierCurve = ease.bezierCurve;
    }

    /*! Shorthand: apply to a Behavior's default animation. */
    function apply(targetAnimation, type, size, variant) {
        if (!targetAnimation) return;
        root.configure(targetAnimation, type, size, variant);
    }

    // Convenience properties for common cases (updated when Config changes)
    readonly property int standardSmall:      root.duration("standard", "small")
    readonly property int standardNormal:     root.duration("standard", "normal")
    readonly property int standardLarge:      root.duration("standard", "large")
    readonly property int standardExtraLarge: root.duration("standard", "extraLarge")

    readonly property int emphasizedSmall:  root.duration("emphasized", "small")
    readonly property int emphasizedNormal: root.duration("emphasized", "normal")
    readonly property int emphasizedLarge:  root.duration("emphasized", "large")

    readonly property int spatialFast:    root.duration("spatial", "fast")
    readonly property int spatialDefault: root.duration("spatial", "default")
    readonly property int spatialSlow:    root.duration("spatial", "slow")

    readonly property bool animationsEnabled: root._baseScale > 0
}
