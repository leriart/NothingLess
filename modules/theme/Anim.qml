pragma Singleton
import QtQuick
import qs.config

/*!
    Anim.qml — Animation system for NothingLess.

    Provides animation style profiles inspired by classic and modern OS platforms.
    Each style defines unique easing curves, durations, and behaviors for
    different motion types (standard, emphasized, spatial, spring).

    Usage:
        import qs.modules.theme

        Behavior on opacity {
            NumberAnimation { Anim.apply(this, "standard", "normal") }
        }

        NumberAnimation {
            target: foo; property: "x"
            Anim.configure(this, "emphasized", "large", "enter")
        }

        // Platform-specific easing:
        duration: Anim.duration("standard", "normal")
        easing.type: Anim.easing("standard").type
        easing.bezierCurve: Anim.easing("standard").bezierCurve
*/
QtObject {
    id: root

    // ============================================
    // ANIMATION STYLE PROFILES
    // ============================================
    // Each profile defines:
    //   durations  — base ms per motion type
    //   easings    — bezier curves per motion type
    //   name       — human-readable name

    readonly property var _profiles: ({
        // ─── Material 3 (default) ──────────────────────────────────────
        "m3": {
            name: "Material 3",
            durations: {
                standard:   { small: 120,  normal: 250, large: 350, extraLarge: 450 },
                emphasized: { small: 200,  normal: 350, large: 500 },
                spatial:    { fast: 150,   default: 300, slow: 450 },
                spring:     { small: 300,  normal: 450, large: 600 }
            },
            easings: {
                standard:       [0.2, 0.0, 0.0, 1.0],
                emphasized:     [0.05, 0.7, 0.1, 1.0],
                emphasizedExit: [0.3, 0.0, 0.8, 0.15],
                spatial:        [0.4, 0.0, 0.2, 1.0],
                decelerate:     [0.0, 0.0, 0.2, 1.0],
                accelerate:     [0.4, 0.0, 1.0, 1.0],
                linear:         null
            }
        },

        // ─── Windows Classic (95/98/ME/2000) ────────────────────────────
        // Minimal animations, linear or very simple easing, short durations.
        // Design principle: functional, no-nonsense, instant feedback.
        "windows-classic": {
            name: "Windows Classic",
            durations: {
                standard:   { small: 50,   normal: 100, large: 150, extraLarge: 200 },
                emphasized: { small: 100,  normal: 150, large: 250 },
                spatial:    { fast: 50,    default: 100, slow: 200 },
                spring:     { small: 100,  normal: 150, large: 200 }
            },
            easings: {
                standard:       [0.0, 0.0, 1.0, 1.0],  // Linear
                emphasized:     [0.0, 0.0, 1.0, 1.0],  // Linear
                emphasizedExit: [0.0, 0.0, 1.0, 1.0],  // Linear
                spatial:        [0.0, 0.0, 1.0, 1.0],  // Linear
                decelerate:     [0.0, 0.0, 1.0, 1.0],  // Linear
                accelerate:     [0.0, 0.0, 1.0, 1.0],  // Linear
                linear:         null
            }
        },

        // ─── Windows XP ─────────────────────────────────────────────────
        // Gentle ease-out, slightly playful, medium durations.
        // "Luna" theme: smooth but not overly animated.
        "windows-xp": {
            name: "Windows XP",
            durations: {
                standard:   { small: 100,  normal: 200, large: 300, extraLarge: 400 },
                emphasized: { small: 150,  normal: 250, large: 350 },
                spatial:    { fast: 100,   default: 200, slow: 350 },
                spring:     { small: 200,  normal: 300, large: 400 }
            },
            easings: {
                standard:       [0.25, 0.1, 0.25, 1.0],  // Gentle ease
                emphasized:     [0.0, 0.0, 0.2, 1.0],    // Ease-out emphasis
                emphasizedExit: [0.4, 0.0, 1.0, 1.0],    // Ease-in
                spatial:        [0.25, 0.1, 0.25, 1.0],
                decelerate:     [0.0, 0.0, 0.2, 1.0],
                accelerate:     [0.4, 0.0, 1.0, 1.0],
                linear:         null
            }
        },

        // ─── Windows 7 (Aero) ───────────────────────────────────────────
        // Glass aesthetic, smooth transitions, subtle overshoot.
        // Aero Glass: animated taskbar thumbnails, flip3d, window previews.
        "windows-7": {
            name: "Windows 7",
            durations: {
                standard:   { small: 150,  normal: 250, large: 350, extraLarge: 500 },
                emphasized: { small: 200,  normal: 350, large: 500 },
                spatial:    { fast: 150,   default: 300, slow: 450 },
                spring:     { small: 300,  normal: 400, large: 550 }
            },
            easings: {
                standard:       [0.1, 0.0, 0.2, 1.0],   // Smooth ease-out
                emphasized:     [0.0, 0.8, 0.2, 1.0],   // Slight overshoot
                emphasizedExit: [0.4, 0.0, 0.8, 0.5],   // Smooth accelerate
                spatial:        [0.2, 0.0, 0.3, 1.0],
                decelerate:     [0.0, 0.0, 0.1, 1.0],
                accelerate:     [0.4, 0.0, 0.9, 0.5],
                linear:         null
            }
        },

        // ─── Mac OS Classic (pre-OS X) ──────────────────────────────────
        // Almost no animations. Checkerboard, iris effects (Platinum).
        // In practice: linear fades if anything.
        "mac-classic": {
            name: "Mac OS Classic",
            durations: {
                standard:   { small: 30,   normal: 80,  large: 120, extraLarge: 180 },
                emphasized: { small: 80,   normal: 120, large: 200 },
                spatial:    { fast: 30,    default: 80,  slow: 150 },
                spring:     { small: 80,   normal: 120, large: 150 }
            },
            easings: {
                standard:       [0.0, 0.0, 1.0, 1.0],  // All linear
                emphasized:     [0.0, 0.0, 1.0, 1.0],
                emphasizedExit: [0.0, 0.0, 1.0, 1.0],
                spatial:        [0.0, 0.0, 1.0, 1.0],
                decelerate:     [0.0, 0.0, 1.0, 1.0],
                accelerate:     [0.0, 0.0, 1.0, 1.0],
                linear:         null
            }
        },

        // ─── Mac OS X Leopard/Snow Leopard ──────────────────────────────
        // Genie effect, smooth fade, sine-based curves.
        // Aqua UI: jelly buttons, smooth scrolling, cover flow.
        "mac-legacy": {
            name: "Mac OS X",
            durations: {
                standard:   { small: 200,  normal: 350, large: 500, extraLarge: 650 },
                emphasized: { small: 300,  normal: 450, large: 600 },
                spatial:    { fast: 200,   default: 350, slow: 500 },
                spring:     { small: 350,  normal: 500, large: 700 }
            },
            easings: {
                standard:       [0.42, 0.0, 0.58, 1.0],  // Sine ease-in-out
                emphasized:     [0.25, 0.46, 0.45, 0.94], // Gentle overshoot
                emphasizedExit: [0.55, 0.06, 0.68, 0.53], // Smooth exit
                spatial:        [0.42, 0.0, 0.58, 1.0],   // Sine ease
                decelerate:     [0.0, 0.0, 0.2, 1.0],
                accelerate:     [0.4, 0.0, 1.0, 1.0],
                linear:         null
            }
        },

        // ─── macOS Modern (10.7+) ───────────────────────────────────────
        // Spring animations, natural physics, smooth scrolling.
        // Natural easing: mimic real-world physics (slight bounce).
        "mac-modern": {
            name: "macOS",
            durations: {
                standard:   { small: 150,  normal: 300, large: 450, extraLarge: 600 },
                emphasized: { small: 250,  normal: 400, large: 550 },
                spatial:    { fast: 150,   default: 300, slow: 450 },
                spring:     { small: 400,  normal: 550, large: 750 }
            },
            easings: {
                standard:       [0.34, 0.01, 0.12, 1.0],  // Natural ease-out
                emphasized:     [0.11, 0.8, 0.23, 1.0],   // Spring-like overshoot
                emphasizedExit: [0.32, 0.0, 0.67, 0.3],   // Gentle accelerate
                spatial:        [0.28, 0.0, 0.45, 1.0],
                decelerate:     [0.0, 0.0, 0.25, 1.0],
                accelerate:     [0.3, 0.0, 1.0, 0.5],
                linear:         null
            }
        },

        // ─── Android Gingerbread/Honeycomb (pre-Material) ──────────────
        // Simple transitions, basic fade, short durations.
        "android-legacy": {
            name: "Android (Legacy)",
            durations: {
                standard:   { small: 80,   normal: 150, large: 250, extraLarge: 350 },
                emphasized: { small: 150,  normal: 250, large: 350 },
                spatial:    { fast: 80,    default: 150, slow: 300 },
                spring:     { small: 150,  normal: 250, large: 350 }
            },
            easings: {
                standard:       [0.4, 0.0, 0.6, 1.0],    // Gentle ease
                emphasized:     [0.0, 0.0, 0.35, 1.0],   // Ease-out
                emphasizedExit: [0.4, 0.0, 1.0, 1.0],    // Ease-in
                spatial:        [0.4, 0.0, 0.6, 1.0],
                decelerate:     [0.0, 0.0, 0.35, 1.0],
                accelerate:     [0.4, 0.0, 1.0, 1.0],
                linear:         null
            }
        },

        // ─── Android Material Design (5.0-11) ───────────────────────────
        // Responsive: fast start, slow end. Standard Material curves.
        // FastOutSlowIn: immediate response + smooth deceleration.
        "android-material": {
            name: "Android Material",
            durations: {
                standard:   { small: 100,  normal: 200, large: 300, extraLarge: 400 },
                emphasized: { small: 200,  normal: 300, large: 450 },
                spatial:    { fast: 150,   default: 250, slow: 400 },
                spring:     { small: 250,  normal: 350, large: 500 }
            },
            easings: {
                standard:       [0.4, 0.0, 0.2, 1.0],   // FastOutSlowIn
                emphasized:     [0.4, 0.0, 0.2, 1.0],   // Same for emphasis
                emphasizedExit: [0.4, 0.0, 1.0, 1.0],   // FastOutLinearIn
                spatial:        [0.4, 0.0, 0.2, 1.0],
                decelerate:     [0.0, 0.0, 0.2, 1.0],   // LinearOutSlowIn
                accelerate:     [0.4, 0.0, 1.0, 1.0],   // FastOutLinearIn
                linear:         null
            }
        },

        // ─── Android 12+ (Material You) ─────────────────────────────────
        // Expressive, organic, spring physics. Longer durations.
        // Emphasized deceleration, adaptive motion based on context.
        "android-you": {
            name: "Android 12+",
            durations: {
                standard:   { small: 200,  normal: 350, large: 500, extraLarge: 700 },
                emphasized: { small: 350,  normal: 500, large: 700 },
                spatial:    { fast: 250,   default: 400, slow: 600 },
                spring:     { small: 450,  normal: 600, large: 850 }
            },
            easings: {
                standard:       [0.2, 0.0, 0.0, 1.0],   // Emphasized decel (M3)
                emphasized:     [0.05, 0.7, 0.1, 1.0],  // Emphasized overshoot
                emphasizedExit: [0.3, 0.0, 0.8, 0.15],  // Emphasized accel
                spatial:        [0.4, 0.0, 0.2, 1.0],
                decelerate:     [0.0, 0.0, 0.2, 1.0],
                accelerate:     [0.4, 0.0, 1.0, 1.0],
                linear:         null
            }
        }
    })

    // ============================================
    // ACTIVE PROFILE
    // ============================================
    readonly property string _styleKey: {
        const s = Config.theme && Config.theme.animStyle;
        if (s && root._profiles[s]) return s;
        return "m3";
    }

    readonly property var _profile: root._profiles[root._styleKey] || root._profiles["m3"]

    // ============================================
    // GLOBAL SPEED SCALE
    // ============================================
    readonly property real _baseScale: {
        if (Config.animDuration <= 0) return 0;
        if (root._styleKey === "disabled") return 0;
        const cfgScale = Config.theme && Config.theme.animScale;
        let userScale = (cfgScale !== undefined && cfgScale > 0) ? cfgScale : 1.0;
        return userScale * Config.animDuration / 300;
    }

    function _scale(baseMs) {
        return Math.max(0, Math.round(baseMs * root._baseScale));
    }

    // ============================================
    // PUBLIC API
    // ============================================

    /*! Get duration in ms for a given type/size.
        @param type: "standard" | "emphasized" | "spatial" | "spring"
        @param size: "small" | "normal" | "large" | "extraLarge" / "fast" / "default" / "slow"
    */
    function duration(type, size) {
        const profile = root._profile;
        const t = profile.durations[type];
        if (!t) return 0;
        return root._scale(t[size] || t.normal || t.default || 0);
    }

    /*! Get easing configuration object for a given type.
        @param type: "standard" | "emphasized" | "emphasizedExit" | "spatial" | "decelerate" | "accelerate" | "linear"
        @param variant: (optional) "enter" | "exit" — shorthand for emphasized variants
        @returns {{ type: int, bezierCurve?: number[] }}
    */
    function easing(type, variant) {
        const profile = root._profile;
        let key = type;

        if (type === "emphasized") {
            if (variant === "exit" || variant === "accelerate")
                key = "emphasizedExit";
            else
                key = "emphasized";
        }

        const curve = profile.easings[key] || profile.easings.standard || [0.0, 0.0, 1.0, 1.0];
        if (curve === null)
            return { type: Easing.Linear };

        return { type: Easing.BezierSpline, bezierCurve: curve };
    }

    /*! Configure a NumberAnimation with the active profile's settings. */
    function configure(anim, type, size, variant) {
        if (!anim || !(anim instanceof NumberAnimation)) return;
        anim.duration = root.duration(type, size);
        const ease = root.easing(type, variant);
        anim.easing.type = ease.type;
        if (ease.bezierCurve !== undefined)
            anim.easing.bezierCurve = ease.bezierCurve;
    }

    /*! Shorthand: apply profile settings to a Behavior's default animation. */
    function apply(targetAnimation, type, size, variant) {
        if (!targetAnimation) return;
        root.configure(targetAnimation, type, size, variant);
    }

    // ============================================
    // STYLE INFO
    // ============================================
    readonly property string styleName: root._profile.name || "M3"
    readonly property string styleKey: root._styleKey
    readonly property var availableStyles: {
        const keys = Object.keys(root._profiles);
        return keys.map(k => ({ key: k, name: root._profiles[k].name }));
    }

    // ============================================
    // CONVENIENCE PROPERTIES
    // ============================================
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

    readonly property int springSmall:   root.duration("spring", "small")
    readonly property int springNormal:  root.duration("spring", "normal")
    readonly property int springLarge:   root.duration("spring", "large")

    readonly property bool animationsEnabled: root._baseScale > 0
}
