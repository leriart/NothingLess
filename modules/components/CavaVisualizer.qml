import QtQuick
import QtQuick.Controls
import qs.modules.theme
import qs.modules.services
import qs.config

Item {
    id: root

    property int barCount: 32
    property real barWidth: 4
    property real maxHeight: 32
    property real spacing: 1
    property color accentColor: Config.resolveColor("primary")
    property bool active: CavaService.active
    property bool demoMode: false
    property bool fillWidth: false  // when true, bars stretch to fill available width

    implicitHeight: maxHeight
    implicitWidth: fillWidth ? 0 : barCount * (barWidth + spacing) - spacing

    // Effective bar width — calculated when fillWidth is enabled
    readonly property real effectiveBarWidth: fillWidth && width > 0
        ? Math.max(1, (width - spacing * (barCount - 1)) / barCount)
        : barWidth

    onVisibleChanged: { if (visible) CavaService.start() }

    Timer {
        id: demoTimer
        running: root.visible && !root.active && root.demoMode
        interval: 80
        repeat: true
        property int tick: 0
        onTriggered: {
            tick++
            var arr = []
            for (var i = 0; i < root.barCount; i++) {
                var phase = (i / root.barCount) * Math.PI * 4
                var val = Math.sin((tick * 0.08) + phase) * 0.5 + 0.5
                val += Math.sin(tick * 0.3 + i * 0.7) * 0.15
                arr.push(Math.max(0, Math.min(100, Math.round(val * 100))))
            }
            root._demoBars = arr
        }
    }

    property var _demoBars: []

    function _effectiveBars() {
        if (root.active) return CavaService.bars
        if (root.demoMode) return root._demoBars
        return []
    }

    Row {
        anchors.fill: parent
        spacing: root.spacing
        Repeater {
            model: root.barCount
            delegate: Item {
                property int idx: index
                width: root.effectiveBarWidth
                height: root.maxHeight
                readonly property real amp: {
                    var bars = root._effectiveBars()
                    if (!bars || bars.length === 0 || idx >= bars.length) return 0
                    var v = bars[idx]
                    return isNaN(v) ? 0 : Math.max(0, Math.min(1, v / 100))
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.effectiveBarWidth
                    height: Math.max(2, amp * root.maxHeight)
                    radius: width / 2
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25 + amp * 0.65)
                    Behavior on height { NumberAnimation { duration: 50; easing.type: Easing.OutCubic } }
                }
            }
        }
    }
}
