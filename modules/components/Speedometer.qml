import QtQuick
import QtQuick.Controls
import qs.modules.theme
import qs.config

// Arc gauge component — displays a value as a circular progress arc.
// Inspired by Brain_Shell's Speedometer, adapted for NothingLess.
//
// Properties:
//   label       — name displayed above the arc
//   percent     — 0.0–100.0, the fill level
//   centerText  — large text in the center (e.g. "45%")
//   bottomText  — smaller text below center (e.g. "2.4 / 16 GB")
//   active      — when false, arc is greyed and "Off" overlays center
//   accentColor — fill color of the arc (defaults to primary)
//   size        — scale factor, 1.0 = full (120×140), 0.7 = mini

Item {
    id: root

    property string label: ""
    property real percent: 0.0
    property string centerText: "0%"
    property string bottomText: ""
    property bool active: true
    property color accentColor: Config.resolveColor("primary")
    property real size: 1.0

    implicitWidth: Math.round(120 * size)
    implicitHeight: Math.round(140 * size)

    // ── Name label ─────────────────────────────────────────────────────────
    Text {
        id: nameLabel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        text: root.label
        font.pixelSize: Math.max(7, Math.round(11 * root.size))
        font.weight: Font.Medium
        font.family: Styling.defaultFont
        color: root.active
            ? Qt.rgba(1, 1, 1, 0.55)
            : Qt.rgba(1, 1, 1, 0.2)
        Behavior on color {
            AnimatedBehavior { type: "standard"; size: "small" }
        }
    }

    // ── Arc canvas ─────────────────────────────────────────────────────────
    Canvas {
        id: arc
        anchors {
            top: nameLabel.bottom
            topMargin: Math.round(6 * root.size)
            horizontalCenter: parent.horizontalCenter
        }
        width: parent.width
        height: parent.width

        readonly property real cx: width / 2
        readonly property real cy: height / 2
        readonly property real _radius: width / 2 - Math.round(10 * root.size)
        readonly property real thickness: Math.max(3, Math.round(8 * root.size))
        readonly property real startAngle: 150 * Math.PI / 180
        readonly property real sweepAngle: 245 * Math.PI / 180

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            var sa = startAngle
            var sw = sweepAngle

            // Track (background arc)
            ctx.beginPath()
            ctx.arc(cx, cy, _radius, sa, sa + sw, false)
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.08)
            ctx.lineWidth = thickness
            ctx.lineCap = "round"
            ctx.stroke()

            // Fill arc
            var fillPct = root.active ? Math.max(0, Math.min(1, root.percent / 100)) : 0
            if (fillPct > 0) {
                ctx.beginPath()
                ctx.arc(cx, cy, _radius, sa, sa + sw * fillPct, false)
                ctx.strokeStyle = root.active
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 1)
                    : Qt.rgba(1, 1, 1, 0.15)
                ctx.lineWidth = thickness
                ctx.lineCap = "round"
                ctx.stroke()
            }
        }

        Connections {
            target: root
            function onPercentChanged() { arc.requestPaint() }
            function onActiveChanged() { arc.requestPaint() }
            function onAccentColorChanged() { arc.requestPaint() }
            function onSizeChanged() { arc.requestPaint() }
        }
    }

    // ── Center text ────────────────────────────────────────────────────────
    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: arc.top
        width: arc.width
        height: arc.height

        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: Math.round(6 * root.size)
            spacing: Math.round(2 * root.size)
            opacity: root.active ? 1 : 0
            Behavior on opacity {
                AnimatedBehavior { type: "standard"; size: "small" }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.centerText
                font.pixelSize: Math.max(10, Math.round(18 * root.size))
                font.weight: Font.Bold
                font.family: Styling.defaultFont
                color: Config.resolveColor("overBackground")
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.bottomText
                font.pixelSize: Math.max(6, Math.round(9 * root.size))
                font.family: Config.theme.monoFont
                color: Qt.rgba(1, 1, 1, 0.4)
                visible: root.bottomText !== ""
            }
        }

        // Deactivated overlay
        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: Math.round(6 * root.size)
            text: "Off"
            font.pixelSize: Math.max(8, Math.round(13 * root.size))
            font.weight: Font.Medium
            color: Qt.rgba(1, 1, 1, 0.25)
            opacity: root.active ? 0 : 1
            Behavior on opacity {
                AnimatedBehavior { type: "standard"; size: "small" }
            }
        }
    }

    // Helper: dynamic accent color based on temperature thresholds
    function tempColor(temp) {
        if (temp >= 90) return "#f38ba8"
        if (temp >= 75) return "#f5c47a"
        if (temp >= 60) return "#fab387"
        return root.accentColor
    }

    // Helper: dynamic accent color based on usage percentage
    function usageColor(pct) {
        if (pct >= 90) return "#f38ba8"
        if (pct >= 75) return "#f5c47a"
        return root.accentColor
    }
}
