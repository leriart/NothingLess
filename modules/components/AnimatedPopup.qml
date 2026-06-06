pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme

/*!
    AnimatedPopup.qml — Reusable animated popup wrapper.

    Provides opacity + scale entrance/exit animations that respect the active
    Anim profile. Use this as the root of any popup-like content that should
    appear/disappear smoothly.

    Usage:
        AnimatedPopup {
            isOpen: myModel.showPopup
            transformOrigin: Item.Top
            contentItem: MyPopupContent { }
        }
*/
Item {
    id: root

    // Public API
    property bool isOpen: false
    property int transformOrigin: Item.Center
    property real openScale: 1.0
    property real closedScale: 0.92
    property real openOpacity: 1.0
    property real closedOpacity: 0.0

    // Animation tuning
    property string type: "emphasized"
    property string size: "normal"
    property bool useSpring: true
    property string springName: "snappy"

    // The actual content; assign via `contentItem: ...`
    default property alias contentData: container.data

    // Visibility tracks opacity
    visible: opacity > 0

    // Animation state
    scale: isOpen ? openScale : closedScale
    opacity: isOpen ? openOpacity : closedOpacity

    Behavior on scale {
        enabled: Anim.animationsEnabled
        AnimatedBehavior {
            type: root.type
            size: root.size
            useSpring: root.useSpring
            springName: root.springName
        }
    }

    Behavior on opacity {
        enabled: Anim.animationsEnabled
        AnimatedBehavior {
            type: "standard"
            size: root.size
        }
    }

    Item {
        id: container
        anchors.fill: parent
        transformOrigin: root.transformOrigin
    }
}
