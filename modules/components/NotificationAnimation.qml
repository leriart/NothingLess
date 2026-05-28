import QtQuick
import qs.modules.theme

/**
 * NotificationAnimation — Animation controller for notification dismiss.
 *
 * Restored from Ambxst and adapted to use Anim.qml profiles.
 * Provides an overshoot slide-out effect when dismissing notifications.
 *
 * Usage:
 *     NotificationAnimation {
 *         id: animCtrl
 *         targetItem: myNotifDelegate
 *         parentWidth: listView.width
 *         onDestroyFinished: myModel.remove(index)
 *     }
 *     // Call when dismissing:
 *     animCtrl.startDestroy()
 */
Item {
    id: root

    // The notification delegate to animate out
    property Item targetItem: null

    // How far it overshoots past the edge (pixels)
    property real dismissOvershoot: 20

    // Width of the parent container (for animation calculation)
    property real parentWidth: 0

    // Whether this is a "discard all" bulk operation
    property bool isDiscardAll: false

    // Emitted when the dismiss animation completes
    signal destroyFinished

    // Dismiss animation: slide right + scale down + fade out
    ParallelAnimation {
        id: destroyAnimation
        running: false

        NumberAnimation {
            target: root.targetItem?.anchors
            property: "leftMargin"
            to: root.parentWidth / 8 + root.dismissOvershoot
            duration: Anim.emphasizedNormal
            easing.type: Anim.easing("emphasized").type
            easing.bezierCurve: Anim.easing("emphasized").bezierCurve
        }

        NumberAnimation {
            target: root.targetItem
            property: "scale"
            from: 1.0
            to: 0.8
            duration: Anim.standardNormal
            easing.type: Anim.easing("standard").type
            easing.bezierCurve: Anim.easing("standard").bezierCurve
        }

        NumberAnimation {
            target: root.targetItem
            property: "opacity"
            from: 1.0
            to: 0.0
            duration: Anim.standardNormal
            easing.type: Anim.easing("standard").type
            easing.bezierCurve: Anim.easing("standard").bezierCurve
        }

        onFinished: {
            root.destroyFinished();
        }
    }

    // Public: trigger the dismiss animation
    function startDestroy() {
        if (root.targetItem) {
            destroyAnimation.running = true;
        }
    }
}
