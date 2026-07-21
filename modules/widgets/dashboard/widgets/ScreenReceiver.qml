import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.modules.theme
import qs.modules.components
import qs.modules.services

/*!
    ScreenReceiver — Status overlay for an active Mirai session.

    In the previous incarnation, this window fetched MJPEG frames from
    the local `nothingless-screen-share.py` sender and rendered them as
    a window. With the move to Mirai, the actual video is rendered by
    the mirai daemon itself (via GStreamer or mpv) in its own window.
    This component is now a compact overlay that:

      - Confirms a session is active and to/from which sink.
      - Exposes Stop / Disconnect / Mode buttons for quick control.
      - Offers a "Hide for 5 s" affordance so the user can see the
        underlying stream window briefly.

    Modes:
      - window:  floats in the top-right corner, ~320 × 96 px.
      - fullscreen: covers a chosen output with the overlay centered.

    Keyboard:
      F     → toggle fullscreen
      ESC   → hide overlay (does not stop the session)
*/
FloatingWindow {
    id: receiver

    required property string streamUrl        // unused with Mirai, kept for API compat
    required property int streamFps           // unused with Mirai, kept for API compat
    property string streamPin: ""             // unused with Mirai, kept for API compat
    property string sourceName: ""            // e.g. "TV-Living-Room"
    property bool fullscreenMode: false
    property bool showControls: true
    property int windowWidth: 320
    property int windowHeight: 96
    property int fullscreenOutputIndex: -1

    visible: true
    color: "transparent"
    aboveWindows: true
    screen: Quickshell.screens[Math.max(0, fullscreenOutputIndex >= 0 ? fullscreenOutputIndex : 0)]

    Component.onCompleted: {
        if (screen) {
            x = screen.width - width - 24;
            y = 24;
        }
    }

    onFullscreenModeChanged: {
        if (fullscreenMode && screen) {
            x = 0; y = 0;
            width = screen.width;
            height = screen.height;
        } else if (screen) {
            width = windowWidth;
            height = windowHeight;
            x = screen.width - width - 24;
            y = 24;
        }
    }

    // Pull state from MiraiService so the overlay always reflects the truth
    readonly property bool _active: MiraiService.streaming || MiraiService.receiving
    readonly property string _peerName: {
        if (MiraiService.streaming) return MiraiService.activeSinkName || MiraiService.activeSinkId || "sink";
        if (MiraiService.receiving) return sourceName || "phone / tablet";
        return "";
    }
    readonly property string _direction: MiraiService.streaming ? "→ Casting to" : "← Receiving from"

    // Track time hidden to auto-show again
    property bool _hidden: false
    Timer {
        id: unHideTimer
        interval: 5000
        repeat: false
        onTriggered: receiver._hidden = false
    }
    function hideBriefly() {
        receiver._hidden = true;
        unHideTimer.restart();
    }

    // Center the overlay in fullscreen, otherwise it's anchored top-right
    // by Component.onCompleted above.
    Item {
        id: overlayRoot
        anchors.fill: parent
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        visible: !receiver._hidden
        width: receiver.fullscreenMode ? Math.min(420, parent.width - 48) : receiver.windowWidth
        height: receiver.fullscreenMode ? receiver.windowHeight + 24 : receiver.windowHeight
        x: receiver.fullscreenMode ? (parent.width - width) / 2 : 0
        y: receiver.fullscreenMode ? (parent.height - height) / 2 : 0

        StyledRect {
            anchors.fill: parent
            variant: "popup"
            radius: Styling.radius(0)
            enableShadow: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 6

                RowLayout {
                    spacing: 8
                    Layout.fillWidth: true

                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: receiver._active ? Colors.primary : Colors.outline
                        SequentialAnimation on opacity {
                            running: receiver._active
                            loops: Animation.Infinite
                            NumberAnimation { from: 1.0; to: 0.35; duration: Anim.standardLarge; easing.type: Anim.easing("standard").type; easing.bezierCurve: Anim.easing("standard").bezierCurve || [] }
                            NumberAnimation { from: 0.35; to: 1.0; duration: Anim.standardLarge; easing.type: Anim.easing("standard").type; easing.bezierCurve: Anim.easing("standard").bezierCurve || [] }
                        }
                    }

                    Text {
                        text: receiver._direction + " " + receiver._peerName
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        font.weight: Font.Medium
                        color: Colors.overBackground
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                Text {
                    text: {
                        if (MiraiService.streaming && MiraiService.activeDisplay)
                            return "Display: " + MiraiService.activeDisplay;
                        if (MiraiService.receiving)
                            return "Mode: " + MiraiService.sinkMode;
                        return "Idle";
                    }
                    font.family: "Monospace"
                    font.pixelSize: Styling.fontSize(-3)
                    color: Colors.outline
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                RowLayout {
                    spacing: 6
                    Layout.fillWidth: true
                    Layout.topMargin: 4

                    StyledRect {
                        radius: Styling.radius(-3)
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: 64
                        variant: hover1.containsMouse ? "focus" : "common"
                        Text {
                            anchors.centerIn: parent
                            text: "Hide"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-3)
                            color: Colors.overBackground
                        }
                        MouseArea {
                            id: hover1
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: receiver.hideBriefly()
                        }
                    }
                    StyledRect {
                        radius: Styling.radius(-3)
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: 64
                        visible: MiraiService.streaming
                        variant: hover2.containsMouse ? "error" : "common"
                        Text {
                            anchors.centerIn: parent
                            text: "Stop"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-3)
                            color: hover2.containsMouse ? Colors.overError : Colors.error
                        }
                        MouseArea {
                            id: hover2
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: MiraiService.disconnect()
                        }
                    }
                    StyledRect {
                        radius: Styling.radius(-3)
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: 64
                        visible: MiraiService.receiving
                        variant: hover3.containsMouse ? "error" : "common"
                        Text {
                            anchors.centerIn: parent
                            text: "Stop"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-3)
                            color: hover3.containsMouse ? Colors.overError : Colors.error
                        }
                        MouseArea {
                            id: hover3
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: MiraiService.stopSink()
                        }
                    }
                    Item { Layout.fillWidth: true }
                    StyledRect {
                        radius: Styling.radius(-3)
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: 56
                        variant: "common"
                        Text {
                            anchors.centerIn: parent
                            text: receiver.fullscreenMode ? "Restore" : "Full"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-3)
                            color: Colors.overBackground
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: receiver.fullscreenMode = !receiver.fullscreenMode
                        }
                    }
                }
            }
        }
    }

    // Keyboard shortcuts (only when the window is focused / hover-active)
    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_F) {
                receiver.fullscreenMode = !receiver.fullscreenMode;
                event.accepted = true;
            } else if (event.key === Qt.Key_Escape) {
                receiver.hideBriefly();
                event.accepted = true;
            }
        }
    }
}
