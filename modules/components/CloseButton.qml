import QtQuick
import QtQuick.Controls
import qs.modules.theme
import qs.modules.components
import qs.config

Button {
    id: root

    implicitWidth: 28
    implicitHeight: 28
    flat: true
    hoverEnabled: true

    contentItem: Text {
        text: "\u2715"
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(-1)
        color: parent.hovered ? Styling.srItem("primary") : Colors.outline
        anchors.centerIn: parent
        Behavior on color {
            enabled: Anim.animationsEnabled
            ColorAnimation { duration: Anim.standardSmall }
        }
    }

    background: StyledRect {
        variant: root.hovered ? "focus" : "transparent"
        radius: Styling.radius(-6)
    }
}
