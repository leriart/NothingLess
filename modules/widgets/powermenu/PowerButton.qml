import QtQuick
import qs.modules.components
import qs.modules.theme
import qs.modules.services

ToggleButton {
    id: powerButton
    buttonIcon: Icons.shutdown
    tooltipText: "Power Menu"
    onToggle: function () {
        if (Visibilities.currentActiveModule === "powermenu") {
            Visibilities.setActiveModule("");
        } else {
            Visibilities.setActiveModule("powermenu");
        }
    }

    // Press animation: scale pulse
    transform: Scale {
        id: powerScale
        origin.x: powerButton.width / 2
        origin.y: powerButton.height / 2
        xScale: powerButton.pressed ? 0.85 : 1.0
        yScale: powerButton.pressed ? 0.85 : 1.0
        Behavior on xScale {
            enabled: Anim.animationsEnabled
            NumberAnimation { duration: Anim.emphasizedNormal; easing.type: Anim.springSnappy().type; easing.bezierCurve: Anim.springSnappy().bezierCurve }
        }
        Behavior on yScale {
            enabled: Anim.animationsEnabled
            NumberAnimation { duration: Anim.emphasizedNormal; easing.type: Anim.springSnappy().type; easing.bezierCurve: Anim.springSnappy().bezierCurve }
        }
    }
}
