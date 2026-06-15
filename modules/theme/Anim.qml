pragma Singleton
import QtQuick
import qs.config
import qs.modules.globals

/*!
    Anim.qml — Animation system for NothingLess.

    Provides animation style profiles inspired by classic and modern OS platforms.
    Each style defines unique easing curves, durations, and behaviors for
    different motion types (standard, emphasized, spatial, spring).

    Usage:
        import qs.modules.theme

        Behavior on opacity {
            enabled: Anim.animationsEnabled
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
        // ─── AMBXST (New) ──────────────────────────────────────────────
        "ambxst": {
            name: "ambxst",
            durations: {
                standard:   { small: 150,  normal: 300, large: 450, extraLarge: 600 },
                emphasized: { small: 250,  normal: 400, large: 550 },
                spatial:    { fast: 150,   default: 300, slow: 450 },
                spring:     { small: 400,  normal: 550, large: 750 }
            },
            easings: {
                standard:       [0.2, 0.0, 0.0, 1.0],
                emphasized:     [0.05, 0.7, 0.1, 1.0],
                emphasizedExit: [0.3, 0.0, 0.8, 0.15],
                collapse:       [0.25, 1.0, 0.5, 1.0],  // OutQuart
                spatial:        [0.4, 0.0, 0.2, 1.0],
                decelerate:     [0.0, 0.0, 0.2, 1.0],
                accelerate:     [0.4, 0.0, 1.0, 1.0],
                linear:         null
            },
            spring: { stiffness: 220, damping: 14, mass: 1.0 },
            _overshoot: 1.7,
            compositor: { curve: [0.34, 1.2, 0.64, 1.0], speed: 4.0, name: "nl-ambxst" },
            transitions: {
                pushEnter: {
                    scale:       { from: 0.87, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                pushExit: {
                    scale:       { from: 1.0, to: 0.5, duration: "emphasizedNormal", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "standardNormal", easing: "collapse" }
                },
                popEnter: {
                    scale:       { from: 0.87, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                popExit: {
                    scale:       { from: 1.0, to: 0.5, duration: "emphasizedLarge", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "emphasizedLarge", easing: "collapse" }
                },
                animScale: {
                    expand:     { from: 0.90, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    collapse:   { from: 1.0, to: 0.8, duration: "emphasizedNormal", easing: "expand" }
                },
                radius: {
                    expand:     { duration: "standardNormal", easing: "expand" },
                    collapse:   { duration: "standardNormal", easing: "collapse" }
                }
            }
        },

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
                collapse:       [0.3, 0.0, 0.8, 0.15],
                spatial:        [0.4, 0.0, 0.2, 1.0],
                decelerate:     [0.0, 0.0, 0.2, 1.0],
                accelerate:     [0.4, 0.0, 1.0, 1.0],
                linear:         null
            },
            spring: { stiffness: 200, damping: 20, mass: 1.0 },
            _overshoot: 1.08,
            compositor: { curve: [0.2, 0.0, 0.0, 1.0], speed: 2.5, name: "nl-standard" },
            transitions: {
                pushEnter: {
                    scale:       { from: 0.92, to: 1.0, duration: "standardNormal", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                pushExit: {
                    scale:       { from: 1.0, to: 0.88, duration: "standardNormal", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "standardNormal", easing: "collapse" }
                },
                popEnter: {
                    scale:       { from: 0.92, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                popExit: {
                    scale:       { from: 1.0, to: 0.88, duration: "emphasizedLarge", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "emphasizedLarge", easing: "collapse" }
                },
                animScale: {
                    expand:     { from: 0.95, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    collapse:   { from: 1.0, to: 0.92, duration: "emphasizedNormal", easing: "expand" }
                },
                radius: {
                    expand:     { duration: "standardNormal", easing: "expand" },
                    collapse:   { duration: "standardNormal", easing: "collapse" }
                }
            }
        },

        // ─── Windows Classic (95/98/ME/2000) ────────────────────────────
        "windows-classic": {
            name: "Windows Classic",
            durations: {
                standard:   { small: 50,   normal: 100, large: 150, extraLarge: 200 },
                emphasized: { small: 100,  normal: 150, large: 250 },
                spatial:    { fast: 50,    default: 100, slow: 200 },
                spring:     { small: 100,  normal: 150, large: 200 }
            },
            easings: {
                standard:       [0.0, 0.0, 1.0, 1.0],
                emphasized:     [0.0, 0.0, 1.0, 1.0],
                emphasizedExit: [0.0, 0.0, 1.0, 1.0],
                collapse:       [0.0, 0.0, 1.0, 1.0],
                spatial:        [0.0, 0.0, 1.0, 1.0],
                decelerate:     [0.0, 0.0, 1.0, 1.0],
                accelerate:     [0.0, 0.0, 1.0, 1.0],
                linear:         null
            },
            spring: { stiffness: 500, damping: 50, mass: 1.0 },
            _overshoot: 1.0,
            compositor: { curve: [0.0, 0.0, 1.0, 1.0], speed: 1.0, name: "nl-linear" },
            transitions: {
                pushEnter: {
                    scale:       { from: 0.92, to: 1.0, duration: "standardSmall", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                pushExit: {
                    scale:       { from: 1.0, to: 1.0, duration: "standardSmall", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "standardNormal", easing: "collapse" }
                },
                popEnter: {
                    scale:       { from: 0.92, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                popExit: {
                    scale:       { from: 1.0, to: 1.0, duration: "emphasizedLarge", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "emphasizedLarge", easing: "collapse" }
                },
                animScale: {
                    expand:     { from: 0.95, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    collapse:   { from: 1.0, to: 0.97, duration: "emphasizedNormal", easing: "expand" }
                },
                radius: {
                    expand:     { duration: "standardNormal", easing: "expand" },
                    collapse:   { duration: "standardNormal", easing: "collapse" }
                }
            }
        },

        // ─── Windows XP ─────────────────────────────────────────────────
        "windows-xp": {
            name: "Windows XP",
            durations: {
                standard:   { small: 100,  normal: 200, large: 300, extraLarge: 400 },
                emphasized: { small: 150,  normal: 250, large: 350 },
                spatial:    { fast: 100,   default: 200, slow: 350 },
                spring:     { small: 200,  normal: 300, large: 400 }
            },
            easings: {
                standard:       [0.25, 0.1, 0.25, 1.0],
                emphasized:     [0.0, 0.0, 0.2, 1.0],
                emphasizedExit: [0.4, 0.0, 1.0, 1.0],
                collapse:       [0.4, 0.0, 1.0, 1.0],
                spatial:        [0.25, 0.1, 0.25, 1.0],
                decelerate:     [0.0, 0.0, 0.2, 1.0],
                accelerate:     [0.4, 0.0, 1.0, 1.0],
                linear:         null
            },
            spring: { stiffness: 180, damping: 18, mass: 1.0 },
            _overshoot: 1.12,
            compositor: { curve: [0.25, 0.1, 0.25, 1.0], speed: 2.0, name: "nl-xp" },
            transitions: {
                pushEnter: {
                    scale:       { from: 0.90, to: 1.0, duration: "standardNormal", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                pushExit: {
                    scale:       { from: 1.0, to: 0.84, duration: "standardNormal", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "standardNormal", easing: "collapse" }
                },
                popEnter: {
                    scale:       { from: 0.90, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                popExit: {
                    scale:       { from: 1.0, to: 0.84, duration: "emphasizedLarge", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "emphasizedLarge", easing: "collapse" }
                },
                animScale: {
                    expand:     { from: 0.93, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    collapse:   { from: 1.0, to: 0.9, duration: "emphasizedNormal", easing: "expand" }
                },
                radius: {
                    expand:     { duration: "standardNormal", easing: "expand" },
                    collapse:   { duration: "standardNormal", easing: "collapse" }
                }
            }
        },

        // ─── Windows 7 (Aero) ───────────────────────────────────────────
        "windows-7": {
            name: "Windows 7",
            durations: {
                standard:   { small: 150,  normal: 250, large: 350, extraLarge: 500 },
                emphasized: { small: 200,  normal: 350, large: 500 },
                spatial:    { fast: 150,   default: 300, slow: 450 },
                spring:     { small: 300,  normal: 400, large: 550 }
            },
            easings: {
                standard:       [0.15, 0.60, 0.25, 0.90],
                emphasized:     [0.05, 0.80, 0.15, 0.95],
                emphasizedExit: [0.35, 0.05, 0.75, 0.35],
                collapse:       [0.35, 0.05, 0.75, 0.35],
                spatial:        [0.22, 0.50, 0.30, 0.88],
                decelerate:     [0.0, 0.0, 0.2, 1.0],
                accelerate:     [0.4, 0.0, 1.0, 1.0],
                linear:         null
            },
            spring: { stiffness: 150, damping: 12, mass: 1.0 },
            _overshoot: 1.20,
            compositor: { curve: [0.1, 0.8, 0.1, 1.0], speed: 2.8, name: "nl-aero" },
            transitions: {
                pushEnter: {
                    scale:       { from: 0.89, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                pushExit: {
                    scale:       { from: 1.0, to: 0.82, duration: "emphasizedNormal", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "standardNormal", easing: "collapse" }
                },
                popEnter: {
                    scale:       { from: 0.89, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                popExit: {
                    scale:       { from: 1.0, to: 0.82, duration: "emphasizedLarge", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "emphasizedLarge", easing: "collapse" }
                },
                animScale: {
                    expand:     { from: 0.92, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    collapse:   { from: 1.0, to: 0.88, duration: "emphasizedNormal", easing: "expand" }
                },
                radius: {
                    expand:     { duration: "standardNormal", easing: "expand" },
                    collapse:   { duration: "standardNormal", easing: "collapse" }
                }
            }
        },

        // ─── Mac OS Classic (pre-OS X) ──────────────────────────────────
        "mac-classic": {
            name: "Mac OS Classic",
            durations: {
                standard:   { small: 30,   normal: 80,  large: 120, extraLarge: 180 },
                emphasized: { small: 80,   normal: 120, large: 200 },
                spatial:    { fast: 30,    default: 80,  slow: 150 },
                spring:     { small: 80,   normal: 120, large: 150 }
            },
            easings: {
                standard:       [0.0, 0.0, 1.0, 1.0],
                emphasized:     [0.0, 0.0, 1.0, 1.0],
                emphasizedExit: [0.0, 0.0, 1.0, 1.0],
                collapse:       [0.0, 0.0, 1.0, 1.0],
                spatial:        [0.0, 0.0, 1.0, 1.0],
                decelerate:     [0.0, 0.0, 1.0, 1.0],
                accelerate:     [0.0, 0.0, 1.0, 1.0],
                linear:         null
            },
            spring: { stiffness: 400, damping: 40, mass: 1.0 },
            _overshoot: 1.0,
            compositor: { curve: [0.0, 0.0, 1.0, 1.0], speed: 0.5, name: "nl-linear" },
            transitions: {
                pushEnter: {
                    scale:       { from: 0.95, to: 1.0, duration: "standardSmall", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                pushExit: {
                    scale:       { from: 1.0, to: 1.0, duration: "standardSmall", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "standardNormal", easing: "collapse" }
                },
                popEnter: {
                    scale:       { from: 0.95, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                popExit: {
                    scale:       { from: 1.0, to: 1.0, duration: "emphasizedLarge", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "emphasizedLarge", easing: "collapse" }
                },
                animScale: {
                    expand:     { from: 0.98, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    collapse:   { from: 1.0, to: 0.98, duration: "emphasizedNormal", easing: "expand" }
                },
                radius: {
                    expand:     { duration: "standardNormal", easing: "expand" },
                    collapse:   { duration: "standardNormal", easing: "collapse" }
                }
            }
        },

        // ─── Mac OS X Leopard/Snow Leopard ──────────────────────────────
        "mac-legacy": {
            name: "Mac OS X",
            durations: {
                standard:   { small: 200,  normal: 350, large: 500, extraLarge: 650 },
                emphasized: { small: 300,  normal: 450, large: 600 },
                spatial:    { fast: 200,   default: 350, slow: 500 },
                spring:     { small: 350,  normal: 500, large: 700 }
            },
            easings: {
                standard:       [0.42, 0.0, 0.58, 1.0],
                emphasized:     [0.25, 0.46, 0.45, 0.94],
                emphasizedExit: [0.55, 0.06, 0.68, 0.53],
                collapse:       [0.55, 0.06, 0.68, 0.53],
                spatial:        [0.42, 0.0, 0.58, 1.0],
                decelerate:     [0.0, 0.0, 0.2, 1.0],
                accelerate:     [0.4, 0.0, 1.0, 1.0],
                linear:         null
            },
            spring: { stiffness: 160, damping: 16, mass: 1.0 },
            _overshoot: 1.30,
            compositor: { curve: [0.42, 0.0, 0.58, 1.0], speed: 3.0, name: "nl-aqua" },
            transitions: {
                pushEnter: {
                    scale:       { from: 0.87, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                pushExit: {
                    scale:       { from: 1.0, to: 0.78, duration: "emphasizedNormal", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "standardNormal", easing: "collapse" }
                },
                popEnter: {
                    scale:       { from: 0.87, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                popExit: {
                    scale:       { from: 1.0, to: 0.78, duration: "emphasizedLarge", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "emphasizedLarge", easing: "collapse" }
                },
                animScale: {
                    expand:     { from: 0.90, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    collapse:   { from: 1.0, to: 0.85, duration: "emphasizedNormal", easing: "expand" }
                },
                radius: {
                    expand:     { duration: "standardNormal", easing: "expand" },
                    collapse:   { duration: "standardNormal", easing: "collapse" }
                }
            }
        },

        // ─── macOS Modern (10.7+) ───────────────────────────────────────
        "mac-modern": {
            name: "macOS",
            durations: {
                standard:   { small: 150,  normal: 300, large: 450, extraLarge: 600 },
                emphasized: { small: 250,  normal: 400, large: 550 },
                spatial:    { fast: 150,   default: 300, slow: 450 },
                spring:     { small: 400,  normal: 550, large: 750 }
            },
            easings: {
                standard:       [0.28, 0.65, 0.18, 0.88],
                emphasized:     [0.15, 0.78, 0.22, 0.90],
                emphasizedExit: [0.30, 0.08, 0.65, 0.25],
                collapse:       [0.30, 0.08, 0.65, 0.25],
                spatial:        [0.32, 0.55, 0.25, 0.85],
                decelerate:     [0.0, 0.0, 0.2, 1.0],
                accelerate:     [0.4, 0.0, 1.0, 1.0],
                linear:         null
            },
            spring: { stiffness: 180, damping: 14, mass: 1.0 },
            _overshoot: 1.40,
            compositor: { curve: [0.34, 0.6, 0.12, 0.8], speed: 2.5, name: "nl-natural" },
            transitions: {
                pushEnter: {
                    scale:       { from: 0.87, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                pushExit: {
                    scale:       { from: 1.0, to: 0.75, duration: "emphasizedNormal", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "standardNormal", easing: "collapse" }
                },
                popEnter: {
                    scale:       { from: 0.87, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                popExit: {
                    scale:       { from: 1.0, to: 0.75, duration: "emphasizedLarge", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "emphasizedLarge", easing: "collapse" }
                },
                animScale: {
                    expand:     { from: 0.90, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    collapse:   { from: 1.0, to: 0.82, duration: "emphasizedNormal", easing: "expand" }
                },
                radius: {
                    expand:     { duration: "standardNormal", easing: "expand" },
                    collapse:   { duration: "standardNormal", easing: "collapse" }
                }
            }
        },

        // ─── Android Gingerbread/Honeycomb (pre-Material) ──────────────
        "android-legacy": {
            name: "Android (Legacy)",
            durations: {
                standard:   { small: 80,   normal: 150, large: 250, extraLarge: 350 },
                emphasized: { small: 150,  normal: 250, large: 350 },
                spatial:    { fast: 80,    default: 150, slow: 300 },
                spring:     { small: 150,  normal: 250, large: 350 }
            },
            easings: {
                standard:       [0.4, 0.0, 0.6, 1.0],
                emphasized:     [0.0, 0.0, 0.35, 1.0],
                emphasizedExit: [0.4, 0.0, 1.0, 1.0],
                collapse:       [0.4, 0.0, 1.0, 1.0],
                spatial:        [0.4, 0.0, 0.6, 1.0],
                decelerate:     [0.0, 0.0, 0.35, 1.0],
                accelerate:     [0.4, 0.0, 1.0, 1.0],
                linear:         null
            },
            spring: { stiffness: 220, damping: 22, mass: 1.0 },
            _overshoot: 1.06,
            compositor: { curve: [0.4, 0.0, 0.6, 1.0], speed: 1.5, name: "nl-android-legacy" },
            transitions: {
                pushEnter: {
                    scale:       { from: 0.91, to: 1.0, duration: "standardNormal", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                pushExit: {
                    scale:       { from: 1.0, to: 0.9, duration: "standardNormal", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "standardNormal", easing: "collapse" }
                },
                popEnter: {
                    scale:       { from: 0.91, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                popExit: {
                    scale:       { from: 1.0, to: 0.9, duration: "emphasizedLarge", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "emphasizedLarge", easing: "collapse" }
                },
                animScale: {
                    expand:     { from: 0.94, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    collapse:   { from: 1.0, to: 0.94, duration: "emphasizedNormal", easing: "expand" }
                },
                radius: {
                    expand:     { duration: "standardNormal", easing: "expand" },
                    collapse:   { duration: "standardNormal", easing: "collapse" }
                }
            }
        },

        // ─── Android Material Design (5.0-11) ───────────────────────────
        "android-material": {
            name: "Android Material",
            durations: {
                standard:   { small: 100,  normal: 200, large: 300, extraLarge: 400 },
                emphasized: { small: 200,  normal: 300, large: 450 },
                spatial:    { fast: 150,   default: 250, slow: 400 },
                spring:     { small: 250,  normal: 350, large: 500 }
            },
            easings: {
                standard:       [0.4, 0.0, 0.2, 1.0],
                emphasized:     [0.4, 0.0, 0.2, 1.0],
                emphasizedExit: [0.4, 0.0, 1.0, 1.0],
                collapse:       [0.4, 0.0, 1.0, 1.0],
                spatial:        [0.4, 0.0, 0.2, 1.0],
                decelerate:     [0.0, 0.0, 0.2, 1.0],
                accelerate:     [0.4, 0.0, 1.0, 1.0],
                linear:         null
            },
            spring: { stiffness: 200, damping: 20, mass: 1.0 },
            _overshoot: 1.10,
            compositor: { curve: [0.4, 0.0, 0.2, 1.0], speed: 2.0, name: "nl-material" },
            transitions: {
                pushEnter: {
                    scale:       { from: 0.90, to: 1.0, duration: "standardNormal", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                pushExit: {
                    scale:       { from: 1.0, to: 0.86, duration: "standardNormal", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "standardNormal", easing: "collapse" }
                },
                popEnter: {
                    scale:       { from: 0.90, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                popExit: {
                    scale:       { from: 1.0, to: 0.86, duration: "emphasizedLarge", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "emphasizedLarge", easing: "collapse" }
                },
                animScale: {
                    expand:     { from: 0.93, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    collapse:   { from: 1.0, to: 0.9, duration: "emphasizedNormal", easing: "expand" }
                },
                radius: {
                    expand:     { duration: "standardNormal", easing: "expand" },
                    collapse:   { duration: "standardNormal", easing: "collapse" }
                }
            }
        },

        // ─── Hyprland Vanilla ──────────────────────────────────────────
        "hyprland": {
            name: "Hyprland (Vanilla)",
            durations: {
                standard:   { small: 100,  normal: 200, large: 300, extraLarge: 400 },
                emphasized: { small: 150,  normal: 250, large: 400 },
                spatial:    { fast: 100,   default: 200, slow: 350 },
                spring:     { small: 200,  normal: 300, large: 400 }
            },
            easings: {
                standard:       [0.2, 0.0, 0.1, 1.0],
                emphasized:     [0.2, 0.0, 0.1, 1.0],
                emphasizedExit: [0.4, 0.0, 0.8, 0.15],
                collapse:       [0.4, 0.0, 0.8, 0.15],
                spatial:        [0.2, 0.0, 0.1, 1.0],
                decelerate:     [0.0, 0.0, 0.2, 1.0],
                accelerate:     [0.4, 0.0, 1.0, 1.0],
                linear:         null
            },
            spring: { stiffness: 220, damping: 18, mass: 1.0 },
            _overshoot: 1.10,
            compositor: { curve: [0.2, 0.0, 0.1, 1.0], speed: 4.0, name: "nl-hyprland" },
            transitions: {
                pushEnter: {
                    scale:       { from: 0.90, to: 1.0, duration: "standardNormal", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                pushExit: {
                    scale:       { from: 1.0, to: 0.88, duration: "standardNormal", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "standardNormal", easing: "collapse" }
                },
                popEnter: {
                    scale:       { from: 0.90, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                popExit: {
                    scale:       { from: 1.0, to: 0.88, duration: "emphasizedLarge", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "emphasizedLarge", easing: "collapse" }
                },
                animScale: {
                    expand:     { from: 0.93, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    collapse:   { from: 1.0, to: 0.92, duration: "emphasizedNormal", easing: "expand" }
                },
                radius: {
                    expand:     { duration: "standardNormal", easing: "expand" },
                    collapse:   { duration: "standardNormal", easing: "collapse" }
                }
            }
        },

        // ─── Android 12+ (Material You) ─────────────────────────────────
        "android-you": {
            name: "Android 12+",
            durations: {
                standard:   { small: 200,  normal: 350, large: 500, extraLarge: 700 },
                emphasized: { small: 350,  normal: 500, large: 700 },
                spatial:    { fast: 250,   default: 400, slow: 600 },
                spring:     { small: 450,  normal: 600, large: 850 }
            },
            easings: {
                standard:       [0.15, 0.70, 0.20, 0.88],
                emphasized:     [0.05, 0.85, 0.12, 0.92],
                emphasizedExit: [0.30, 0.10, 0.68, 0.18],
                collapse:       [0.30, 0.10, 0.68, 0.18],
                spatial:        [0.30, 0.48, 0.25, 0.90],
                decelerate:     [0.0, 0.0, 0.2, 1.0],
                accelerate:     [0.4, 0.0, 1.0, 1.0],
                linear:         null
            },
            spring: { stiffness: 180, damping: 14, mass: 1.0 },
            _overshoot: 1.7,
            compositor: { curve: [0.05, 0.7, 0.1, 1.0], speed: 3.0, name: "nl-you" },
            transitions: {
                pushEnter: {
                    scale:       { from: 0.85, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                pushExit: {
                    scale:       { from: 1.0, to: 0.52, duration: "emphasizedNormal", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "standardNormal", easing: "collapse" }
                },
                popEnter: {
                    scale:       { from: 0.85, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    opacity:     { from: 0, to: 1, duration: "standardNormal", easing: "collapse" }
                },
                popExit: {
                    scale:       { from: 1.0, to: 0.52, duration: "emphasizedLarge", easing: "expand" },
                    opacity:     { from: 1, to: 0, duration: "emphasizedLarge", easing: "collapse" }
                },
                animScale: {
                    expand:     { from: 0.88, to: 1.0, duration: "emphasizedNormal", easing: "expand" },
                    collapse:   { from: 1.0, to: 0.78, duration: "emphasizedNormal", easing: "expand" }
                },
                radius: {
                    expand:     { duration: "standardNormal", easing: "expand" },
                    collapse:   { duration: "standardNormal", easing: "collapse" }
                }
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
        if (root._styleKey === "disabled") return 0;
        // Check Config availability — during startup Config may not be ready
        if (typeof Config === "undefined" || Config === null) return 1.0;
        const ad = Config.animDuration;
        if (ad === undefined || ad === null || ad <= 0) return 1.0; // Default to enabled
        const cfgScale = Config.theme && Config.theme.animScale;
        let userScale = (cfgScale !== undefined && cfgScale > 0) ? cfgScale : 1.0;
        return userScale * ad / 300;
    }

    // ============================================
    // PRECOMPUTED CACHE — O(1) flat lookups
    // ============================================
    // Instead of computing durations and building easing objects on every
    // frame, we pre-flatten the profile into indexed tables at init time.
    // The cache auto-invalidates when _profile changes (animation style switch).

    // Duration type enumeration → stable index
    readonly property var _durTypeIdx: ({ "standard": 0, "emphasized": 1, "spatial": 2, "spring": 3 })
    // Size enumeration per type → stable sub-index
    readonly property var _durSizeIdx: ({
        standard:   { small: 0, normal: 1, large: 2, extraLarge: 3 },
        emphasized: { small: 0, normal: 1, large: 2 },
        spatial:    { fast: 0, default: 1, slow: 2 },
        spring:     { small: 0, normal: 1, large: 2 }
    })

    // Flattened raw base-ms table: [typeIdx][sizeIdx] → raw ms BEFORE scaling
    // Built once per profile; only _baseScale changes at runtime.
    readonly property var _durTable: {
        const p = root._profile;
        const d = p.durations;
        // 4 types × max 4 sizes = 16 entries, all ints
        const t = [[0,0,0,0], [0,0,0,0], [0,0,0,0], [0,0,0,0]];
        const std = d.standard || {};
        t[0][0] = std.small  || 0; t[0][1] = std.normal || 0; t[0][2] = std.large || 0; t[0][3] = std.extraLarge || 0;
        const emp = d.emphasized || {};
        t[1][0] = emp.small  || 0; t[1][1] = emp.normal || 0; t[1][2] = emp.large  || 0;
        const spa = d.spatial || {};
        t[2][0] = spa.fast    || 0; t[2][1] = spa.default || 0; t[2][2] = spa.slow    || 0;
        const spr = d.spring || {};
        t[3][0] = spr.small   || 0; t[3][1] = spr.normal  || 0; t[3][2] = spr.large   || 0;
        return t;
    }

    // Precomputed easing objects — built once, returned by reference (no GC pressure)
    readonly property var _easeCache: {
        const p = root._profile;
        const e = p.easings;
        const c = {};
        const keys = ["standard","emphasized","emphasizedExit","collapse","spatial","decelerate","accelerate","expand"];
        for (let i = 0; i < keys.length; i++) {
            const k = keys[i];
            const curve = e[k];
            if (curve === null || curve === undefined) {
                c[k] = { type: Easing.Linear, bezierCurve: [] };
            } else {
                c[k] = { type: Easing.BezierSpline, bezierCurve: curve };
            }
        }
        return c;
    }

    // ============================================
    // OPTIMIZED DURATION — flat array lookup
    // ============================================
    // Approximations:
    //   - Integer math via bitwise OR 0 (faster than Math.round in Qt's V4)
    //   - Early-exit for disabled animations (zero scale → zero duration)
    //   - No function call overhead for _scale — inlined multiply

    function _scale(baseMs) {
        // Fast-path: disabled → 0
        if (root._baseScale <= 0) return 0;
        // Fast-path: instant mode (game mode) → 0
        if (root.instantMode === true) return 0;
        // Integer rounding via |0 (≈2× faster than Math.round in V4 JIT)
        return (baseMs * root._baseScale + 0.5) | 0;
    }

    function duration(type, size) {
        // Fast-path: disabled animations
        if (root._baseScale <= 0) return 0;
        // Fast-path: instant mode (game mode) → 0
        if (root.instantMode === true) return 0;
        const ti = root._durTypeIdx[type];
        if (ti === undefined) return 0;
        const si = root._durSizeIdx[type] ? root._durSizeIdx[type][size] : undefined;
        if (si === undefined) return 0;
        const raw = root._durTable[ti][si];
        if (raw <= 0) return 0;
        return (raw * root._baseScale + 0.5) | 0;
    }

    function easing(type, variant) {
        // Variant shortcuts: route to semantic easings (OutBack/OutQuart)
        // so AnimatedBehavior { variant: "expand" } gets real overshoot.
        if (variant === "expand") return root.expandEasing;
        if (variant === "collapse") return root.collapseEasing;

        let key = type;
        if (type === "emphasized") {
            key = (variant === "exit" || variant === "accelerate") ? "emphasizedExit" : "emphasized";
        }

        // Direct cache hit — returns shared object, zero allocation
        const cached = root._easeCache[key];
        if (cached) return cached;

        // Fallback for unknown keys
        return root._easeCache["standard"] || { type: Easing.Linear, bezierCurve: [] };
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
    // HIGH-LEVEL ANIMATION HELPERS
    // ============================================
    // These return ready-to-use { duration, easing } configs so components
    // can bind consistently without copy-pasting NumberAnimation blocks.

    /*! Returns a complete config for opacity fade animations. */
    function fade(type, size, variant) {
        return {
            duration: root.duration(type || "standard", size || "normal"),
            easing: root.easing(type || "standard", variant || "")
        };
    }

    /*! Returns a complete config for scale pop animations (uses emphasized). */
    function scalePop(type, size, variant) {
        return {
            duration: root.duration(type || "emphasized", size || "normal"),
            easing: root.easing(type || "emphasized", variant || "")
        };
    }

    /*! Returns a complete config for spatial slide animations (x/y). */
    function slide(type, size, variant) {
        return {
            duration: root.duration(type || "spatial", size || "default"),
            easing: root.easing(type || "spatial", variant || "")
        };
    }

    /*! Returns a complete config for expand animations (radius/size). */
    function expand(type, size) {
        return {
            duration: root.duration(type || "standard", size || "normal"),
            easing: root.expandEasing
        };
    }

    /*! Returns a complete config for collapse animations. */
    function collapse(type, size) {
        return {
            duration: root.duration(type || "standard", size || "normal"),
            easing: root.collapseEasing
        };
    }

    /*! Configure a Behavior's default NumberAnimation in one call.
        Usage inside a Behavior:
            Anim.setupBehavior(this, "standard", "normal", "")
    */
    function setupBehavior(behavior, type, size, variant) {
        if (!behavior || !(behavior instanceof Behavior)) return;
        behavior.enabled = Qt.binding(function() { return root.animationsEnabled; });
        // Note: actual NumberAnimation child must still exist; this only sets
        // the Behavior's enabled flag. Use configure() on the child animation.
    }

    /*! Returns a spring config by name: "", "snappy", "expressive". */
    function springByName(name) {
        switch (name) {
        case "snappy": return root.springSnappy();
        case "expressive": return root.springExpressive();
        default: return root.spring();
        }
    }

    // ============================================
    // LIST VIEW TRANSITIONS
    // ============================================
    // Reusable Transition components for ListView add/remove/displaced.
    // Because we cannot create QML objects from JS, these return property
    // bags that AnimatedListView consumes to build its transitions.

    readonly property var listAddConfig: ({
        duration: root.duration("emphasized", "normal"),
        easing: root.easing("emphasized"),
        scaleFrom: 0.92, scaleTo: 1.0,
        opacityFrom: 0, opacityTo: 1
    })

    readonly property var listRemoveConfig: ({
        duration: root.duration("standard", "normal"),
        easing: root.collapseEasing,
        scaleFrom: 1.0, scaleTo: 0.9,
        opacityFrom: 1, opacityTo: 0
    })

    readonly property var listDisplacedConfig: ({
        duration: root.duration("spatial", "default"),
        easing: root.easing("spatial")
    })

    // ============================================
    // HYPRLAND ANIMATION CONFIG
    // ============================================
    /*! Get Hyprland bezier animation config for the current style.
        @returns { curve: number[], speed: number, name: string }
        - curve: bezier control points for Hyprland's bezier keyword
        - speed: animation speed multiplier for Hyprland
        - name: unique bezier name to use in animation keywords */
    function hyprConfig() {
        if (root._profile && root._profile.compositor) {
            return root._profile.compositor;
        }
        return { curve: [0.2, 0.0, 0.0, 1.0], speed: 2.5, name: "nl-standard" };
    }

    /*! Get the Hyprland bezier definition line(s) needed for the current style.
        Returns: "bezier = nl-name, cx1, cy1, cx2, cy2" */
    function hyprBezierDef() {
        const cfg = root.hyprConfig();
        const c = cfg.curve;
        return `bezier = ${cfg.name}, ${c[0]}, ${c[1]}, ${c[2]}, ${c[3]}`;
    }

    /*! Get the Hyprland animation command for a specific type.
        @param type: "windows" | "border" | "fade" | "workspaces"
        @param orientation: "horizontal" | "vertical" (for workspaces)
        @returns the keyword command string */
    function hyprAnimation(type, orientation) {
        const cfg = root.hyprConfig();
        const speed = cfg.speed.toFixed(1);
        const bezierName = cfg.name;
        const enabled = root.animationsEnabled ? "1" : "0";

        switch (type) {
        case "windows":
            return `keyword animation windows,${enabled},${speed},${bezierName},popin 80%`;
        case "border":
            return `keyword animation border,${enabled},${speed},${bezierName}`;
        case "fade":
            return `keyword animation fade,${enabled},${speed},${bezierName}`;
        case "workspaces":
            const anim = orientation === "vertical" ? "slidefadevert 20%" : "slidefade 20%";
            return `keyword animation workspaces,${enabled},${speed},${bezierName},${anim}`;
        default:
            return "";
        }
    }

    /*! Get Hyprland config file line for an animation type.
        Unlike hyprAnimation() which outputs 'keyword ...' for runtime,
        this outputs the hyprland.conf syntax (no 'keyword' prefix).
        @param type: "windows" | "border" | "fade" | "workspaces"
        @param orientation: "horizontal" | "vertical" (for workspaces)
        @returns config file line like: 'animation = windows, 1, 4.0, nl-name, popin 80%' */
    function hyprConfLine(type, orientation) {
        const cfg = root.hyprConfig();
        const speed = cfg.speed.toFixed(1);
        const bezierName = cfg.name;
        const enabled = root.animationsEnabled ? "1" : "0";

        switch (type) {
        case "windows":
            return `animation = windows, ${enabled}, ${speed}, ${bezierName}, popin 80%`;
        case "border":
            return `animation = border, ${enabled}, ${speed}, ${bezierName}`;
        case "fade":
            return `animation = fade, ${enabled}, ${speed}, ${bezierName}`;
        case "workspaces":
            const anim = orientation === "vertical" ? "slidefadevert 20%" : "slidefade 20%";
            return `animation = workspaces, ${enabled}, ${speed}, ${bezierName}, ${anim}`;
        default:
            return "";
        }
    }

    // ============================================
    // ORGANIC PHYSICS — Spring, Anticipation, Overshoot, Momentum
    // ============================================
    // Mathematical approximations replace expensive transcendental calls:
    //   √(1-x²) ≈ 1 - x²/2 - x⁴/8        (Taylor, error < 0.6% for x<0.9)
    //   exp(y)  ≈ 1 + y + y²/2 + y³/6    (Taylor, error < 2% for y∈[-2,0])
    //   Settle time uses 4.6/(ζ·ω₀) which is the exact envelope decay.
    //
    // GPU-friendly principle: opacity/scale/rotation cost ~1µs,
    // while x/y/width/height cost ~100µs (trigger relayout).

    // Precomputed spring configs per profile — built once, shared by all spring calls
    readonly property var _springCache: {
        const sp = root._profile && root._profile.spring
            ? root._profile.spring
            : { stiffness: 180, damping: 18, mass: 1.0 };
        const k = sp.stiffness || 180;
        const d = sp.damping || 18;
        const m = Math.max(0.1, sp.mass || 1.0);

        // Natural frequency ω₀ = √(k/m)
        const w0 = Math.sqrt(k / m);
        // Damping ratio ζ = d / (2√(k·m))
        const zeta = d / (2 * Math.sqrt(k * m));

        // Settle time: envelope e^(-ζ·ω₀·t) reaches 1% at t = 4.6/(ζ·ω₀)
        const settleSec = (zeta * w0 > 0.01) ? 4.6 / (zeta * w0) : 10.0;
        const baseDuration = Math.max(80, Math.min(800, Math.round(settleSec * 1000)));

        // Overshoot amplitude via polynomial approximation of e^(-π·ζ/√(1-ζ²))
        // Exact: springOv = exp(-π · ζ / √(1 - ζ²))
        // Approximation: let x = 1 - ζ², then √(1-ζ²) = √x ≈ 1 - (1-x)/2 - (1-x)²/8
        // Combined with exp Taylor for the argument: -π·ζ / √x
        let springOv = 0;
        if (zeta < 1.0 && zeta > 0.001) {
            const oneMinusZ2 = 1.0 - zeta * zeta;
            // √(1-ζ²) ≈ 1 - (1-x)/2 - (1-x)²/8  where x = oneMinusZ2
            const dX = 1.0 - oneMinusZ2;  // = ζ²
            const invSqrt = 1.0 + dX * 0.5 + dX * dX * 0.375;  // 1/√(1-ζ²) via binomial
            const arg = -Math.PI * zeta * invSqrt;  // arg ∈ [-3.14, 0]
            // e^arg via Taylor: 1 + arg + arg²/2 + arg³/6
            springOv = 1.0 + arg * (1.0 + arg * (0.5 + arg * 0.1666667));
            if (springOv < 0) springOv = 0;
        }

        // Map spring amplitude → Qt OutBack overshoot (0 to 2.0)
        const qtOv = Math.min(2.0, springOv * 4.0);

        // Build cached configs for the 3 spring variants
        return {
            base: {
                k: k, d: d, m: m, w0: w0, zeta: zeta,
                duration: baseDuration, overshoot: qtOv
            },
            // Snappy: +30% stiffness, +40% damping
            snappy: (function() {
                const k2 = k * 1.3;
                const d2 = d * 1.4;
                const w2 = Math.sqrt(k2 / m);
                const z2 = d2 / (2 * Math.sqrt(k2 * m));
                const st2 = (z2 * w2 > 0.01) ? 4.6 / (z2 * w2) : 10.0;
                let ov2 = 0;
                if (z2 < 1.0 && z2 > 0.001) {
                    const dm = 1.0 - z2 * z2;
                    const iv = 1.0 + dm * 0.5 + dm * dm * 0.375;
                    const ag = -Math.PI * z2 * iv;
                    ov2 = 1.0 + ag * (1.0 + ag * (0.5 + ag * 0.1666667));
                    if (ov2 < 0) ov2 = 0;
                }
                return {
                    duration: Math.max(60, Math.min(600, Math.round(st2 * 1000))),
                    overshoot: Math.min(2.0, ov2 * 4.0)
                };
            })(),
            // Expressive: -30% damping (= more bounce)
            expressive: (function() {
                const d3 = d * 0.7;
                const w3 = Math.sqrt(k / m);
                const z3 = d3 / (2 * Math.sqrt(k * m));
                const st3 = (z3 * w3 > 0.01) ? 4.6 / (z3 * w3) : 10.0;
                let ov3 = 0;
                if (z3 < 1.0 && z3 > 0.001) {
                    const dm = 1.0 - z3 * z3;
                    const iv = 1.0 + dm * 0.5 + dm * dm * 0.375;
                    const ag = -Math.PI * z3 * iv;
                    ov3 = 1.0 + ag * (1.0 + ag * (0.5 + ag * 0.1666667));
                    if (ov3 < 0) ov3 = 0;
                }
                return {
                    duration: Math.max(100, Math.min(900, Math.round(st3 * 1000))),
                    overshoot: Math.min(2.0, ov3 * 4.0)
                };
            })()
        };
    }

    /*! Damped Spring Oscillator — uses Easing.OutBack for REAL overshoot.
        Bezier curves get clamped to [0,1] by Qt Quick, killing the bounce.
        OutBack is Qt's native overshoot easing — it ACTUALLY bounces.
        @param stiffness: (default 170) — spring tension, higher = snappier
        @param damping:   (default 16)  — resistance, higher = less bounce
        @param mass:      (default 1.0) — inertial mass, higher = slower
        @returns { type: Easing.OutBack, overshoot: Number, duration: ms, zeta: Number } */
    function springBezier(stiffness, damping, mass, initialV) {
        const k = stiffness || 170;
        const d = damping || 16;
        const m = Math.max(0.1, mass || 1.0);

        // Natural frequency & damping ratio
        const w0 = Math.sqrt(k / m);
        const zeta = d / (2 * Math.sqrt(k * m));

        // Settle time (when envelope decays to 1%)
        const settleTime = zeta * w0 > 0.01 ? 4.6 / (zeta * w0) : 10.0;
        const settleMs = Math.round(settleTime * 1000);

        // Spring overshoot via polynomial approximation
        let springOv = 0;
        if (zeta < 1.0 && zeta > 0.001) {
            const oneMinusZ2 = 1.0 - zeta * zeta;
            const dZ2 = 1.0 - oneMinusZ2;  // = ζ²
            const invSqrt = 1.0 + dZ2 * 0.5 + dZ2 * dZ2 * 0.375;
            const arg = -Math.PI * zeta * invSqrt;
            springOv = 1.0 + arg * (1.0 + arg * (0.5 + arg * 0.1666667));
            if (springOv < 0) springOv = 0;
        }

        const qtOvershoot = Math.min(2.0, springOv * 4.0);
        const duration = Math.max(80, Math.min(800, settleMs));

        return {
            type: Easing.OutBack,
            overshoot: qtOvershoot,
            bezierCurve: [],
            duration: duration,
            zeta: zeta
        };
    }

    /*! Natural spring easing — uses precomputed profile spring cache. */
    function spring(type, size) {
        const c = root._springCache.base;
        return {
            type: Easing.OutBack,
            overshoot: c.overshoot,
            bezierCurve: [],
            duration: c.duration,
            zeta: c.zeta
        };
    }

    /*! Snappy spring — uses precomputed snappy cache. */
    function springSnappy() {
        const c = root._springCache.snappy;
        return {
            type: Easing.OutBack,
            overshoot: c.overshoot,
            bezierCurve: [],
            duration: c.duration,
            zeta: c.zeta
        };
    }

    /*! Expressive spring — uses precomputed expressive cache. */
    function springExpressive() {
        const c = root._springCache.expressive;
        return {
            type: Easing.OutBack,
            overshoot: c.overshoot,
            bezierCurve: [],
            duration: c.duration,
            zeta: c.zeta
        };
    }

    /*! Anticipation easing — pull back before moving forward.
        Creates a "recoil" effect that makes animations feel alive.
        @param intensity: 0.0 (subtle) to 1.0 (dramatic) */
    function anticipation(intensity) {
        const i = Math.max(0, Math.min(1, intensity || 0.3));
        return {
            type: Easing.BezierSpline,
            bezierCurve: [0.3 + i * 0.15, -i * 0.5, 0.1, 1.0]
        };
    }

    /*! Overshoot easing — go past target, then settle back.
        Creates a satisfying "stretch" effect.
        @param amount: 0.0 (none) to 0.5 (maximum) */
    function overshoot(amount) {
        const a = amount || 0.2;
        return {
            type: Easing.BezierSpline,
            bezierCurve: [0.2, 1.0 + a * 2.0, 0.3, 0.8 - a * 0.5]
        };
    }

    /*! Adaptive duration — scales with distance for natural feel.
        Small movements = fast, large movements = proportionate.
        @param distance: pixel distance or normalized delta
        @param baseMs: base duration at distance=1
        @returns adaptive duration in ms */
    function adaptiveDuration(distance, baseMs) {
        const d = Math.abs(distance || 1);
        // Weber-Fechner: perceived speed is logarithmic
        // Fast for small moves, scales slowly for large moves
        const logDist = Math.log(Math.max(1, d * 10)) / Math.log(10);
        return Math.max(50, Math.min(600, Math.round(baseMs * (0.3 + logDist * 0.3))));
    }

    /*! GPU-friendly animation config.
        Optimizes for transform animations (opacity/scale/rotation).
        ~70% duration of standard, uses decelerate easing.
        @returns { duration: number, easing: object } */
    function gpuFriendly(type, size) {
        const base = root.duration(type, size || "normal");
        const gpuMs = Math.max(60, Math.round(base * 0.65));
        return {
            duration: gpuMs,
            easing: root.easing("decelerate")
        };
    }

    /*! Multi-stage animation — uses precomputed spring cache.
        Combines anticipation, move, and overshoot.
        Use for elements that enter the screen (cards, modals, notifications). */
    function enterAnimation() {
        // Use expressive spring (less damping = more visible entrance)
        const c = root._springCache.expressive;
        return {
            duration: c.duration,
            easing: {
                type: Easing.OutBack,
                overshoot: c.overshoot,
                bezierCurve: []
            }
        };
    }

    /*! Quick helper: get { duration, easing } for common cases.
        Uses precomputed cache via duration()/easing(). */
    function animate(type, size) {
        return {
            duration: root.duration(type, size),
            easing: root.easing(type),
            type: type,
            size: size || "normal"
        };
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

    // instantMode: when true, all animations are forced to duration 0
    // (set externally by GameModeService via GlobalStates.gameModeActive).
    // Using GlobalStates (no circular dep) instead of GameModeService directly.
    property bool _instantMode: false
    readonly property bool instantMode: root._instantMode || (typeof Services !== "undefined" && typeof GlobalStates !== "undefined" && GlobalStates.gameModeActive === true)

    // ============================================
    // PROFILE-AWARE EASING ACCESSORS (REACTIVE)
    // ============================================
    // expandEasing uses Easing.OutBack for VISIBLE overshoot (bezier can't)
    // collapseEasing uses Easing.BezierSpline (stays in [0,1] range)

    // ============================================
    // PER-PROFILE TRANSITIONS
    // ============================================
    // Anim.transitions → the active profile's transition config
    // Used by Notch.qml, Bar, Dock, Lockscreen, OSD
    readonly property var transitions: {
        const p = root._safeProfile;
        if (p && p.transitions) return p.transitions;
        return root._profiles["ambxst"].transitions || {};
    }

    // Convenience: pushEnter config
    readonly property var pushEnterConfig: root.transitions.pushEnter || {}
    readonly property var pushExitConfig:  root.transitions.pushExit || {}
    readonly property var popEnterConfig:   root.transitions.popEnter || {}
    readonly property var popExitConfig:    root.transitions.popExit || {}
    readonly property var animScaleConfig:  root.transitions.animScale || {}
    readonly property var radiusConfig:     root.transitions.radius || {}

    readonly property var _safeProfile: root._profile || root._profiles["m3"]
    readonly property var expandEasing: {
        const p = root._safeProfile;
        const ov = p._overshoot !== undefined ? p._overshoot : 1.0;
        return { type: Easing.OutBack, overshoot: ov, bezierCurve: [] };
    }
    // collapseEasing: Easing.OutQuart — exactly what Ambxst uses
    // The return bounce comes from StackView transitions (scale: OutBack),
    // not from the size Behaviors which use OutQuart for smooth closure.
    readonly property var collapseEasing: {
        return { type: Easing.OutQuart, bezierCurve: [] };
    }
}
