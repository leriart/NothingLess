import QtQuick
import Quickshell
import QMLTermWidget 2.0

Item {
    id: root

    signal finished()

    anchors.fill: parent

    QMLTermWidget {
        id: termEmbed
        anchors.fill: parent
        font.family: "Monospace"
        font.pointSize: 12
        colorScheme: "Linux"
        session: QMLTermSession {
            id: termSession
            shellProgram: Quickshell.env("SHELL") || "/bin/bash"
            initialWorkingDirectory: Quickshell.env("HOME") || "/tmp"
            onFinished: root.finished()
        }
        Component.onCompleted: {
            try {
                termSession.startShellProgram();
                termEmbed.forceActiveFocus();
            } catch (e) {
                console.warn("Hax: terminal start failed:", e);
            }
        }
    }
}
