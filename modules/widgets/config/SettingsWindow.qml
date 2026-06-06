import QtQuick
import Quickshell
import qs.modules.widgets.dashboard.controls
import qs.modules.components
import qs.modules.globals
import qs.modules.theme
import qs.config

FloatingWindow {
    id: settingsWindow

    // Window properties
    implicitWidth: 900
    implicitHeight: 650

    // Animation state — initialized from GlobalStates so the window is never
    // accidentally transparent on first open. Assignments below break the
    // initial binding, which is fine because the Connections handler drives
    // subsequent changes.
    property real popupOpacity: GlobalStates.settingsWindowVisible ? 1.0 : 0.0
    property real popupScale: GlobalStates.settingsWindowVisible ? 1.0 : 0.96

    visible: popupOpacity > 0 || GlobalStates.settingsWindowVisible

    onVisibleChanged: {
        if (!visible && GlobalStates.settingsWindowVisible) {
            GlobalStates.settingsWindowVisible = false;
        }
    }

    // Sync visibility from GlobalStates with animation
    Connections {
        target: GlobalStates
        function onSettingsWindowVisibleChanged() {
            if (GlobalStates.settingsWindowVisible) {
                settingsWindow.popupOpacity = 1.0;
                settingsWindow.popupScale = 1.0;
            } else {
                settingsWindow.popupOpacity = 0.0;
                settingsWindow.popupScale = 0.96;
            }
        }
    }

    Behavior on popupOpacity {
        AnimatedBehavior {
            type: "standard"
            size: "normal"
        }
    }

    Behavior on popupScale {
        AnimatedBehavior {
            type: "emphasized"
            size: "normal"
            useSpring: true
            springName: "snappy"
        }
    }

    color: "transparent"

    // Use a StyledRect for the background and styling
    StyledRect {
        anchors.fill: parent
        variant: "bg"
        radius: 0
        opacity: settingsWindow.popupOpacity
        scale: settingsWindow.popupScale
        transformOrigin: Item.Center

        Behavior on opacity {
            AnimatedBehavior { type: "standard"; size: "normal" }
        }
        Behavior on scale {
            AnimatedBehavior {
                type: "emphasized"
                size: "normal"
                useSpring: true
                springName: "snappy"
            }
        }

        // Settings Tab Content
        SettingsTab {
            id: settingsTab
            anchors.fill: parent
            anchors.margins: 16
            opacity: settingsWindow.popupOpacity
            Behavior on opacity {
                AnimatedBehavior { type: "standard"; size: "normal" }
            }
        }
    }
}
