import QtQuick
import qs.modules.theme

/**
 * NotchAnimationBehavior — Animation wrapper for notch items.
 *
 * Restored from Ambxst and adapted to use Anim.qml profiles.
 * Provides standard entrance/exit animation for items appearing
 * in the notch: scale + opacity with spring easing.
 *
 * Usage:
 *     NotchAnimationBehavior {
 *         isVisible: myItemVisible
 *         // child items here
 *     }
 */
Item {
    id: root

    // Whether this item should be visible (triggers animation)
    property bool isVisible: false

    // Optional: custom duration multiplier (0.5 = half speed, 2.0 = double)
    property real speedMultiplier: 1.0

    // Apply entrance animations
    scale: isVisible ? 1.0 : 0.85
    opacity: isVisible ? 1.0 : 0.0
    visible: opacity > 0

    Behavior on scale {
        enabled: Anim.animationsEnabled
        NumberAnimation {
            duration: Math.round(Anim.emphasizedNormal * root.speedMultiplier)
            easing.type: Anim.springSnappy().type
            easing.bezierCurve: Anim.springSnappy().bezierCurve
        }
    }

    Behavior on opacity {
        enabled: Anim.animationsEnabled
        NumberAnimation {
            duration: Math.round(Anim.standardNormal * root.speedMultiplier)
            easing.type: Anim.easing("emphasized").type
            easing.bezierCurve: Anim.easing("emphasized").bezierCurve
        }
    }
}
