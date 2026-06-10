import QtQuick
import QtQuick.Layouts
import qs.modules.components
import qs.modules.theme
import qs.config

Item {
    id: root

    required property var bar

    property bool vertical: bar.orientation === "vertical"
    property bool isHovered: false
    property bool externalChange: false
    property bool isExpanded: false
    property bool layerEnabled: true

    property string icon
    property real iconRotation: 0
    property real iconScale: 1
    property color progressColor
    property var onValueChangedCallback
    property var onIconClickedCallback
    property string iconPos: "start"
    property bool scroll: false
    property bool iconClickable: false

    property alias slider: _slider

    Behavior on iconRotation {
        enabled: Anim.animationsEnabled
        AnimatedBehavior { type: "standard"; size: "normal" }
    }
    Behavior on iconScale {
        enabled: Anim.animationsEnabled
        AnimatedBehavior { type: "standard"; size: "normal" }
    }

    HoverHandler {
        onHoveredChanged: {
            root.isHovered = hovered;
            if (!hovered && root.isExpanded && !_slider.isDragging) {
                root.isExpanded = false;
            }
        }
    }

    Layout.preferredWidth: root.vertical ? 36 : 36
    Layout.preferredHeight: root.vertical ? 36 : 36

    states: [
        State {
            name: "expanded"
            when: root.isExpanded || _slider.isDragging || root.externalChange
            PropertyChanges {
                target: root
                Layout.preferredWidth: root.vertical ? 36 : 150
                Layout.preferredHeight: root.vertical ? 150 : 36
            }
        }
    ]

    transitions: Transition {
        NumberAnimation {
            properties: "implicitWidth,implicitHeight,Layout.preferredWidth,Layout.preferredHeight"
            duration: Anim.standardNormal
            easing.type: Anim.easing("standard").type
            easing.bezierCurve: Anim.easing("standard").bezierCurve
        }
    }

    Layout.fillWidth: root.vertical
    Layout.fillHeight: !root.vertical

    StyledRect {
        variant: "bg"
        anchors.fill: parent
        enableShadow: root.layerEnabled

        Rectangle {
            anchors.fill: parent
            color: Styling.srItem("overprimary")
            opacity: root.isHovered && !root.isExpanded ? 0.25 : 0
            radius: parent.radius ?? 0

            Behavior on opacity {
                enabled: Anim.animationsEnabled
                NumberAnimation {
                    duration: Anim.standardSmall
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: false
            onClicked: {
                root.isExpanded = !root.isExpanded;
            }
            onWheel: wheel => {
                if (root.isExpanded) {
                    if (wheel.angleDelta.y > 0) {
                        _slider.value = Math.min(1, _slider.value + 0.1);
                    } else {
                        _slider.value = Math.max(0, _slider.value - 0.1);
                    }
                }
            }
        }

        StyledSlider {
            id: _slider
            anchors.fill: parent
            anchors.margins: 8
            anchors.rightMargin: root.vertical ? 8 : 16
            anchors.topMargin: root.vertical ? 16 : 8
            vertical: root.vertical
            smoothDrag: true
            value: 0
            resizeParent: false
            wavy: false
            scroll: root.scroll
            iconClickable: root.iconClickable
            sliderVisible: root.isExpanded || _slider.isDragging || root.externalChange
            wavyAmplitude: 0
            wavyFrequency: 0
            iconPos: root.iconPos
            icon: root.icon
            iconRotation: root.iconRotation
            iconScale: root.iconScale
            progressColor: root.progressColor

            onValueChanged: {
                if (root.onValueChangedCallback) root.onValueChangedCallback(value);
            }
            onIconClicked: {
                if (root.onIconClickedCallback) root.onIconClickedCallback();
            }
        }

        Timer {
            id: externalChangeTimer
            interval: 1000
            onTriggered: root.externalChange = false
        }
    }

    function notifyExternalChange(): void {
        root.externalChange = true;
        externalChangeTimer.restart();
    }

    Component.onDestruction: {
        externalChangeTimer.stop ? externalChangeTimer.stop() : undefined;
        externalChangeTimer.running !== undefined ? externalChangeTimer.running = false : undefined;
        externalChangeTimer.destroy !== undefined ? externalChangeTimer.destroy() : undefined;
    }
}
