pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.config

StyledRect {
    id: root
    variant: "pane"
    Layout.fillWidth: true
    Layout.preferredHeight: canvasArea.implicitHeight + 16
    radius: Styling.radius(0)
    enableShadow: true

    property var monitors: []
    property int selectedIndex: 0

    signal monitorMoved(int idx, int newX, int newY)
    signal monitorSelected(int idx)

    // Canvas math (logical pixels based on physical / scale)
    property var viewBounds_: ({ minX: -100, minY: -100, maxX: 100, maxY: 100, spanW: 200, spanH: 200 })
    property real viewScale: 0.1

    function getLogicalWidth(m) {
        if (!m) return 1920;
        var isRot = m.transform === 1 || m.transform === 3 || m.transform === 5 || m.transform === 7;
        return (isRot ? (m.height || 1080) : (m.width || 1920)) / (m.scale || 1.0);
    }

    function getLogicalHeight(m) {
        if (!m) return 1080;
        var isRot = m.transform === 1 || m.transform === 3 || m.transform === 5 || m.transform === 7;
        return (isRot ? (m.width || 1920) : (m.height || 1080)) / (m.scale || 1.0);
    }

    function recalcBounds() {
        var mons = root.monitors;
        if (!mons || mons.length === 0) return;
        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (var i = 0; i < mons.length; i++) {
            var m = mons[i];
            var w = getLogicalWidth(m);
            var h = getLogicalHeight(m);
            var x = m.x || 0, y = m.y || 0;
            if (x < minX) minX = x;
            if (y < minY) minY = y;
            if (x + w > maxX) maxX = x + w;
            if (y + h > maxY) maxY = y + h;
        }
        var margin = 100;
        root.viewBounds_ = {
            minX: minX - margin, minY: minY - margin,
            maxX: maxX + margin, maxY: maxY + margin,
            spanW: Math.max((maxX + margin) - (minX - margin), 1),
            spanH: Math.max((maxY + margin) - (minY - margin), 1)
        };
        recalcScale();
    }
    onMonitorsChanged: recalcBounds()

    function recalcScale() {
        var cw = canvasArea.width, ch = canvasArea.height;
        if (cw <= 0 || ch <= 0) return;
        var vb = root.viewBounds_;
        root.viewScale = Math.min((cw - 20) / vb.spanW, (ch - 20) / vb.spanH);
    }

    function realToCanvasX(rx) { return (rx - root.viewBounds_.minX) * root.viewScale + 10; }
    function realToCanvasY(ry) { return (ry - root.viewBounds_.minY) * root.viewScale + 10; }

    Item {
        id: canvasArea
        anchors.fill: parent; anchors.margins: 8
        implicitHeight: 250
        clip: true
        onWidthChanged: recalcScale(); onHeightChanged: recalcScale()

        StyledRect { anchors.fill: parent; variant: "internalbg"; radius: Styling.radius(-2) }

        Item {
            id: scrollBox
            width: Math.max(parent.width, root.viewBounds_.spanW * root.viewScale + 20)
            height: Math.max(parent.height, root.viewBounds_.spanH * root.viewScale + 20)

            // Grid & origin
            Repeater {
                id: gridWRep
                model: Math.floor(root.viewBounds_.spanW / 500) + 2
                Rectangle { x: root.realToCanvasX(root.viewBounds_.minX + gridWRep.index * 500); y: 0; width: 1; height: scrollBox.height; color: Qt.rgba(Colors.outlineVariant.r, Colors.outlineVariant.g, Colors.outlineVariant.b, 0.06) }
            }
            Repeater {
                id: gridHRep
                model: Math.floor(root.viewBounds_.spanH / 500) + 2
                Rectangle { x: 0; y: root.realToCanvasY(root.viewBounds_.minY + gridHRep.index * 500); width: scrollBox.width; height: 1; color: Qt.rgba(Colors.outlineVariant.r, Colors.outlineVariant.g, Colors.outlineVariant.b, 0.06) }
            }
            StyledRect { x: root.realToCanvasX(0) - 4; y: root.realToCanvasY(0) - 4; width: 8; height: 8; radius: 4; variant: "primary"; opacity: 0.6 }

            // Monitor items
            Repeater {
                model: root.monitors
                delegate: Item {
                    id: monItem
                    required property int index
                    required property var modelData

                    property bool dragging: false
                    property real dragX: modelData.x
                    property real dragY: modelData.y

                    readonly property real rx: dragging ? dragX : modelData.x
                    readonly property real ry: dragging ? dragY : modelData.y
                    readonly property bool isSelected: root.selectedIndex === index

                    readonly property real logicalW: root.getLogicalWidth(modelData)
                    readonly property real logicalH: root.getLogicalHeight(modelData)

                    x: root.realToCanvasX(rx); y: root.realToCanvasY(ry)
                    width: Math.max(50, logicalW * root.viewScale)
                    height: Math.max(35, logicalH * root.viewScale)
                    opacity: modelData.enabled ? 1.0 : 0.45

                    StyledRect {
                        anchors.fill: parent
                        variant: {
                            if (!modelData.enabled) return isSelected ? "focus" : "transparent";
                            return isSelected ? "primary" : "common";
                        }
                        radius: Styling.radius(-2); enableShadow: modelData.enabled
                        border.width: isSelected ? 2 : 1
                        border.color: isSelected ? Styling.srItem("primary") : Colors.outlineVariant
                        opacity: modelData.enabled ? 1.0 : 0.7
                    }

                    // Index badge
                    StyledRect {
                        anchors.top: parent.top; anchors.left: parent.left
                        anchors.margins: 4
                        width: indexBadge.implicitWidth + 8; height: 16
                        radius: 8
                        variant: isSelected ? "primary" : "internalbg"
                        Text {
                            id: indexBadge
                            anchors.centerIn: parent
                            text: (index + 1).toString()
                            font.family: Config.theme.font; font.pixelSize: Math.max(7, Math.min(10, Styling.fontSize(-4)))
                            font.bold: true
                            color: isSelected ? Styling.srItem("primary") : Colors.outline
                        }
                    }

                    Column {
                        anchors.centerIn: parent; spacing: 1
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.name; font.family: Config.theme.font; font.pixelSize: Math.max(8, Math.min(11, Styling.fontSize(-3))); font.bold: true; color: isSelected ? Styling.srItem("primary") : Colors.overBackground }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(logicalW) + "×" + Math.round(logicalH) + " @ " + Math.round(modelData.refreshRate || modelData.refresh_rate || 60) + "Hz"; font.family: Config.theme.font; font.pixelSize: Math.max(7, Math.min(10, Styling.fontSize(-4))); color: Colors.outline }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: rx + "," + ry + " · " + (modelData.scale || 1.0).toFixed(2) + "×"; font.family: Config.theme.font; font.pixelSize: Math.max(7, Math.min(10, Styling.fontSize(-4))); color: Colors.outline }
                    }

                    // Drag handle
                    StyledRect {
                        anchors.right: parent.right; anchors.bottom: parent.bottom
                        anchors.margins: 4
                        width: 18; height: 18; radius: 4
                        variant: isSelected ? "primary" : "internalbg"
                        visible: modelData.enabled
                        Text {
                            anchors.centerIn: parent
                            text: Icons.arrowsOutCardinal
                            font.family: Icons.font; font.pixelSize: 10
                            color: isSelected ? Styling.srItem("primary") : Colors.outline
                        }
                    }

                    MouseArea {
                        id: dragArea; anchors.fill: parent; cursorShape: Qt.SizeAllCursor; hoverEnabled: true
                        enabled: modelData.enabled
                        property real pcx: 0; property real pcy: 0
                        property real srx: 0; property real sry: 0
                        
                        onPressed: mouse => {
                            monItem.z = 100; monItem.dragging = true
                            pcx = mouse.x + monItem.x; pcy = mouse.y + monItem.y
                            srx = modelData.x; sry = modelData.y
                            root.monitorSelected(index)
                        }
                        onPositionChanged: mouse => {
                            if (!monItem.dragging) return
                            var dRX = ((mouse.x + monItem.x) - pcx) / root.viewScale
                            var dRY = ((mouse.y + monItem.y) - pcy) / root.viewScale
                            var newX = Math.round((srx + dRX) / 10) * 10
                            var newY = Math.round((sry + dRY) / 10) * 10
                            var mw = logicalW, mh = logicalH
                            var snapPx = 15 / root.viewScale // 15 screen pixels

                            for (var k = 0; k < root.monitors.length; k++) {
                                if (k === index || !root.monitors[k].enabled) continue
                                var o = root.monitors[k]; if (!o) continue
                                var ox = o.x, oy = o.y, ow = root.getLogicalWidth(o), oh = root.getLogicalHeight(o)
                                if (Math.abs(newX - (ox + ow)) < snapPx) newX = ox + ow
                                if (Math.abs((newX + mw) - ox) < snapPx) newX = ox - mw
                                if (Math.abs(newY - (oy + oh)) < snapPx) newY = oy + oh
                                if (Math.abs((newY + mh) - oy) < snapPx) newY = oy - mh
                                if (Math.abs(newX - ox) < snapPx) newX = ox
                                if (Math.abs(newY - oy) < snapPx) newY = oy
                            }
                            monItem.dragX = newX; monItem.dragY = newY
                        }
                        onReleased: {
                            if (!monItem.dragging) return; monItem.dragging = false; monItem.z = 1
                            var rx = monItem.dragX, ry = monItem.dragY
                            var mw = logicalW, mh = logicalH
                            var snapPx = 25 / root.viewScale // stronger snap on release

                            for (var k = 0; k < root.monitors.length; k++) {
                                if (k === index || !root.monitors[k].enabled) continue
                                var o = root.monitors[k]; if (!o) continue
                                var ox = o.x, oy = o.y, ow = root.getLogicalWidth(o), oh = root.getLogicalHeight(o)
                                if (Math.abs(rx - (ox + ow)) < snapPx) rx = ox + ow
                                if (Math.abs((rx + mw) - ox) < snapPx) rx = ox - mw
                                if (Math.abs(ry - (oy + oh)) < snapPx) ry = oy + oh
                                if (Math.abs((ry + mh) - oy) < snapPx) ry = oy - mh
                                if (Math.abs(rx - ox) < snapPx) rx = ox
                                if (Math.abs(ry - oy) < snapPx) ry = oy
                            }
                            // Prevent overlap
                            for (var j = 0; j < root.monitors.length; j++) {
                                if (j === index || !root.monitors[j].enabled) continue
                                var o2 = root.monitors[j]; if (!o2) continue
                                var o2w = root.getLogicalWidth(o2), o2h = root.getLogicalHeight(o2)
                                if (rx < o2.x + o2w && rx + mw > o2.x && ry < o2.y + o2h && ry + mh > o2.y) {
                                    var dL = rx + mw - o2.x, dR = o2.x + o2w - rx, dU = ry + mh - o2.y, dD = o2.y + o2h - ry
                                    var d = Math.min(dL, dR, dU, dD)
                                    if (d === dL) rx = o2.x - mw
                                    else if (d === dR) rx = o2.x + o2w
                                    else if (d === dU) ry = o2.y - mh
                                    else ry = o2.y + o2h
                                }
                            }
                            rx = Math.round(rx / 10) * 10; ry = Math.round(ry / 10) * 10
                            root.monitorMoved(index, rx, ry)
                        }
                    }
                }
            }
        }
    }
}
