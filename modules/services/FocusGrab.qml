import QtQuick

// Compositor-agnostic FocusGrab replacement.
// Registers with FocusGrabManager when active, providing click-outside-to-close
// behavior via the manager's backdrop mechanism.
Item {
    id: root

    property var windows: []
    property bool active: false
    signal cleared()

    // Unique grab ID per instance
    readonly property string _grabId: `grab_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`

    onActiveChanged: {
        if (active) {
            FocusGrabManager.requestGrab(_grabId, () => {
                root.cleared();
            });
        } else {
            FocusGrabManager.releaseGrab(_grabId);
        }
    }

    Component.onDestruction: {
        // Always release — during destruction the active binding has already
        // broken and reverted to false, so checking active here would skip
        // the release and leave a permanent orphan grab in FocusGrabManager.
        FocusGrabManager.releaseGrab(_grabId);
    }
}
