pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme

/*!
    AnimatedListView.qml — ListView with unified add/remove/displaced transitions.

    Encapsulates the standard NothingLess list animation policy:
    - New items fade + scale in with emphasized easing
    - Removed items fade + scale out
    - Displaced items slide smoothly with spatial easing

    Usage: drop-in replacement for ListView.
*/
ListView {
    id: root

    // Animation tuning
    property bool enableAddTransition: true
    property bool enableRemoveTransition: true
    property bool enableDisplacedTransition: true

    property string addType: "emphasized"
    property string addSize: "normal"
    property string removeType: "standard"
    property string removeSize: "normal"
    property string displacedType: "spatial"
    property string displacedSize: "default"

    clip: true

    add: Transition {
        enabled: root.enableAddTransition && Anim.animationsEnabled

        ParallelAnimation {
            NumberAnimation {
                property: "scale"
                from: Anim.listAddConfig.scaleFrom
                to: Anim.listAddConfig.scaleTo
                duration: Anim.duration(root.addType, root.addSize)
                easing.type: Anim.easing(root.addType).type
                easing.bezierCurve: Anim.easing(root.addType).bezierCurve || []
            }
            NumberAnimation {
                property: "opacity"
                from: Anim.listAddConfig.opacityFrom
                to: Anim.listAddConfig.opacityTo
                duration: Anim.duration("standard", "normal")
                easing.type: Anim.easing("standard").type
                easing.bezierCurve: Anim.easing("standard").bezierCurve || []
            }
        }
    }

    remove: Transition {
        enabled: root.enableRemoveTransition && Anim.animationsEnabled

        ParallelAnimation {
            NumberAnimation {
                property: "scale"
                from: Anim.listRemoveConfig.scaleFrom
                to: Anim.listRemoveConfig.scaleTo
                duration: Anim.duration(root.removeType, root.removeSize)
                easing.type: Anim.collapseEasing.type
                easing.bezierCurve: Anim.collapseEasing.bezierCurve || []
            }
            NumberAnimation {
                property: "opacity"
                from: Anim.listRemoveConfig.opacityFrom
                to: Anim.listRemoveConfig.opacityTo
                duration: Anim.duration("standard", "normal")
                easing.type: Anim.easing("standard").type
                easing.bezierCurve: Anim.easing("standard").bezierCurve || []
            }
        }
    }

    displaced: Transition {
        enabled: root.enableDisplacedTransition && Anim.animationsEnabled

        NumberAnimation {
            properties: "x,y"
            duration: Anim.duration(root.displacedType, root.displacedSize)
            easing.type: Anim.easing(root.displacedType).type
            easing.bezierCurve: Anim.easing(root.displacedType).bezierCurve || []
        }
    }

    populate: Transition {
        enabled: Anim.animationsEnabled

        ParallelAnimation {
            NumberAnimation {
                property: "scale"
                from: Anim.listAddConfig.scaleFrom
                to: Anim.listAddConfig.scaleTo
                duration: Anim.duration(root.addType, root.addSize)
                easing.type: Anim.easing(root.addType).type
                easing.bezierCurve: Anim.easing(root.addType).bezierCurve || []
            }
            NumberAnimation {
                property: "opacity"
                from: Anim.listAddConfig.opacityFrom
                to: Anim.listAddConfig.opacityTo
                duration: Anim.duration("standard", "normal")
                easing.type: Anim.easing("standard").type
                easing.bezierCurve: Anim.easing("standard").bezierCurve || []
            }
        }
    }
}
