pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

/*!
    AgentProfilesTab — Per-file JSON editor for AI agent profiles.

    Each agent lives in its own file under
    `~/.local/share/nothingless/agents/<id>.json`. The left column
    lists every profile (filename + name). The right column is a raw
    JSON editor with live validation: edits turn the border red on
    parse error and disable the Save button.

    Buttons:
      - Save: validate (JSON.parse + AgentStore.validateProfile), then
        AgentStore.saveProfile. On success, the file is rewritten
        atomically and the AgentManager rebuilds the live connection.
      - Discard: revert the editor to the last-saved content.
      - New: create a blank profile, save it, select it.
      - Delete: ask for confirmation, then remove the file. The
        AgentManager drops the live connection.
*/
Item {
    id: root

    property int maxContentWidth: 920
    readonly property int contentWidth: Math.min(width, maxContentWidth)
    readonly property real sideMargin: (width - contentWidth) / 2

    // Currently selected profile id. Empty string = "no selection".
    property string selectedId: ""

    // The text in the editor. Mirrors the file content when the
    // selected profile changes; user edits update it live.
    property string editorText: ""

    // The last-saved content of the selected profile (used for
    // "Discard" and to detect dirty state).
    property string savedText: ""

    // Result of JSON.parse(editorText). null = valid (parsed
    // successfully) or empty editor. A string = parse error message.
    property string parseError: ""

    Component.onCompleted: {
        // Auto-select the first profile (or defaultAgentId if set).
        let first = Config.ai.defaultAgentId || "";
        let profiles = AgentStore.listProfiles();
        if (!first && profiles.length > 0) {
            first = profiles[0].id;
        }
        if (first) selectedId = first;
    }

    // React to AgentStore: keep selection valid when profiles change.
    property Connections storeWatcher: Connections {
        target: AgentStore
        function onProfilesChanged() {
            let profiles = AgentStore.listProfiles();
            if (selectedId === "" && profiles.length > 0) {
                selectedId = profiles[0].id;
            } else if (selectedId !== "" && !AgentStore.getProfile(selectedId)) {
                // Selection was deleted — fall back to first.
                selectedId = profiles.length > 0 ? profiles[0].id : "";
            }
        }
    }

    // When the selection changes, refresh the editor content.
    onSelectedIdChanged: {
        let p = AgentStore.getProfile(selectedId);
        if (p) {
            savedText = JSON.stringify(p, null, 2);
            editorText = savedText;
        } else {
            savedText = "";
            editorText = "";
        }
        parseError = "";
    }

    function _selectedProfile() {
        return AgentStore.getProfile(selectedId);
    }

    function _tryParse() {
        if (editorText.trim() === "") {
            parseError = "Empty editor";
            return null;
        }
        try {
            const obj = JSON.parse(editorText);
            parseError = "";
            return obj;
        } catch (e) {
            parseError = String(e.message || e);
            return null;
        }
    }

    function _save() {
        const obj = _tryParse();
        if (!obj) return;
        const err = AgentStore.validateProfile(obj);
        if (err) {
            parseError = err;
            return;
        }
        // If the id changed, the file name would change too — delete
        // the old file to avoid leaving a stale <oldId>.json around.
        if (obj.id !== selectedId) {
            AgentStore.deleteProfile(selectedId);
        }
        if (AgentStore.saveProfile(obj)) {
            // Update selection to the (possibly new) id and reload
            // the editor with the freshly-normalized JSON.
            Qt.callLater(function() {
                selectedId = obj.id;
            });
        }
    }

    function _discard() {
        editorText = savedText;
        parseError = "";
    }

    function _newProfile() {
        let p = AgentStore.createBlankProfile();
        if (AgentStore.saveProfile(p)) {
            Qt.callLater(function() {
                selectedId = p.id;
            });
        }
    }

    function _delete() {
        if (!selectedId) return;
        confirmPopup.open();
    }

    Flickable {
        anchors.fill: parent
        contentHeight: mainRow.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        RowLayout {
            id: mainRow
            x: root.sideMargin
            width: root.contentWidth
            spacing: 16

            // ── Left: profile list ─────────────────────────────────────
            StyledRect {
                variant: "pane"
                Layout.preferredWidth: 240
                Layout.preferredHeight: 500
                radius: Styling.radius(0)
                enableShadow: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                            text: Icons.user + "  Agent profiles"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            font.weight: Font.Medium
                            color: Colors.overBackground
                            Layout.fillWidth: true
                        }
                        StyledRect {
                            radius: Styling.radius(-3)
                            Layout.preferredHeight: 26
                            Layout.preferredWidth: 26
                            enabled: AgentStore.listProfiles().length < 256
                            variant: newMa.containsMouse ? "primary" : "common"
                            Text {
                                anchors.centerIn: parent
                                text: Icons.plus
                                font.family: Icons.font
                                font.pixelSize: Styling.fontSize(0)
                                font.weight: Font.Medium
                                color: newMa.containsMouse ? Colors.overPrimary : Colors.overBackground
                            }
                            MouseArea {
                                id: newMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root._newProfile()
                            }
                        }
                    }

                    Text {
                        text: "Each profile lives in its own JSON file under\n~/.local/share/nothingless/agents/<id>.json. Edit and Save to apply."
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-3)
                        color: Colors.outline
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    ListView {
                        id: profileList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 2
                        clip: true
                        model: AgentStore.listProfiles()
                        delegate: Item {
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            height: 36

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 2
                                radius: Styling.radius(-3)
                                color: {
                                    if (modelData.id === root.selectedId)
                                        return Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.20);
                                    if (rowMa.containsMouse)
                                        return Qt.rgba(Colors.outline.r, Colors.outline.g, Colors.outline.b, 0.10);
                                    return "transparent";
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 6

                                Text {
                                    text: modelData.status === "connected" ? Icons.accept : Icons.circle
                                    font.family: Icons.font
                                    font.pixelSize: 9
                                    color: modelData.status === "connected" ? Colors.success : Colors.outline
                                    Layout.preferredWidth: 12
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Text {
                                        text: modelData.name || "(unnamed)"
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-1)
                                        font.weight: modelData.id === root.selectedId ? Font.Bold : Font.Normal
                                        color: modelData.id === root.selectedId ? Styling.srItem("overprimary") : Colors.overBackground
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: modelData.type
                                        font.family: "Monospace"
                                        font.pixelSize: Styling.fontSize(-3)
                                        color: Colors.outline
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                            MouseArea {
                                id: rowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedId = modelData.id
                            }
                        }
                    }
                }
            }

            // ── Right: editor ──────────────────────────────────────────
            StyledRect {
                variant: "pane"
                Layout.fillWidth: true
                Layout.preferredHeight: 500
                radius: Styling.radius(0)
                enableShadow: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    // Header row: name + action buttons
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: root._selectedProfile()
                                ? (root._selectedProfile().name + "  ·  " + root._selectedProfile().type)
                                : "No profile selected"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            font.weight: Font.Medium
                            color: Colors.overBackground
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        StyledRect {
                            visible: root.selectedId !== ""
                            radius: Styling.radius(-3)
                            Layout.preferredHeight: 28
                            Layout.preferredWidth: 28
                            enabled: root.selectedId !== ""
                            variant: delMa.containsMouse ? "error" : "common"
                            Text {
                                anchors.centerIn: parent
                                text: Icons.trash
                                font.family: Icons.font
                                font.pixelSize: Styling.fontSize(-1)
                                color: delMa.containsMouse ? Colors.overError : Colors.error
                            }
                            MouseArea {
                                id: delMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root._delete()
                            }
                        }
                    }

                    Text {
                        visible: root.selectedId === ""
                        text: "Pick a profile on the left, or click + to create one."
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.outline
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    // File path hint
                    Text {
                        visible: root.selectedId !== ""
                        text: AgentStore.agentsDir + "/" + AgentStore._safeFilename(root.selectedId) + ".json"
                        font.family: "Monospace"
                        font.pixelSize: Styling.fontSize(-3)
                        color: Colors.outline
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }

                    // Editor
                    Rectangle {
                        visible: root.selectedId !== ""
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Styling.radius(-2)
                        color: Styling.srItem ? Styling.srItem("internalbg") : Colors.internalbg
                        border.color: root.parseError !== "" ? Colors.error : Colors.outlineVariant
                        border.width: 1

                        ScrollView {
                            anchors.fill: parent
                            anchors.margins: 4
                            clip: true

                            TextArea {
                                id: editor
                                text: root.editorText
                                wrapMode: TextEdit.NoWrap
                                font.family: Config.theme.monoFont
                                font.pixelSize: Styling.fontSize(-1)
                                color: Colors.overBackground
                                selectByMouse: true
                                background: null
                                onTextChanged: {
                                    if (text === root.editorText) return;
                                    root.editorText = text;
                                    // Live-parse to surface errors.
                                    if (text.trim() === "") {
                                        root.parseError = "Empty editor";
                                    } else {
                                        try {
                                            JSON.parse(text);
                                            root.parseError = "";
                                        } catch (e) {
                                            root.parseError = String(e.message || e);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Error / hint row
                    Text {
                        visible: root.parseError !== ""
                        text: Icons.alert + "  " + root.parseError
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.error
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: root.selectedId !== "" && root.parseError === ""
                        text: Icons.info + "  Schema: id, name, type (http-bridge | mcp-sse | command | mcp-stdio), enabled, command, args[], endpoint, headers{}, toolsPath, invokePath, process{command, args[], cwd, env{}}"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-3)
                        color: Colors.outline
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    // Action row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Item { Layout.fillWidth: true }

                        StyledRect {
                            visible: root.selectedId !== ""
                            radius: Styling.radius(-3)
                            Layout.preferredHeight: 30
                            Layout.preferredWidth: 90
                            enabled: root.editorText !== root.savedText && root.parseError === ""
                            variant: enabled ? (discardMa.containsMouse ? "focus" : "common") : "common"
                            Text {
                                anchors.centerIn: parent
                                text: "Discard"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                color: enabled ? Colors.overBackground : Colors.outline
                            }
                            MouseArea {
                                id: discardMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root._discard()
                            }
                        }
                        StyledRect {
                            visible: root.selectedId !== ""
                            radius: Styling.radius(-3)
                            Layout.preferredHeight: 30
                            Layout.preferredWidth: 90
                            enabled: root.editorText !== root.savedText && root.parseError === ""
                            variant: enabled ? (saveMa.containsMouse ? "primary" : "common") : "common"
                            Text {
                                anchors.centerIn: parent
                                text: "Save"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Medium
                                color: enabled ? Colors.overPrimary : Colors.outline
                            }
                            MouseArea {
                                id: saveMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root._save()
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Confirm delete popup ────────────────────────────────────────
    Popup {
        id: confirmPopup
        anchors.centerIn: Overlay.overlay
        modal: true
        focus: true
        width: 340
        height: 160
        padding: 16
        background: StyledRect {
            variant: "popup"
            radius: Styling.radius(0)
            enableShadow: true
        }
        ColumnLayout {
            anchors.fill: parent
            spacing: 12
            Text {
                text: "Delete this agent profile?"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(0)
                font.weight: Font.Medium
                color: Colors.overBackground
            }
            Text {
                text: "The file ~/.local/share/nothingless/agents/" +
                      AgentStore._safeFilename(root.selectedId) +
                      ".json will be removed. The agent will stop working immediately. This cannot be undone."
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.outline
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }
                StyledRect {
                    radius: Styling.radius(-3)
                    Layout.preferredHeight: 32
                    Layout.preferredWidth: 80
                    variant: "common"
                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        color: Colors.overBackground
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: confirmPopup.close()
                    }
                }
                StyledRect {
                    radius: Styling.radius(-3)
                    Layout.preferredHeight: 32
                    Layout.preferredWidth: 100
                    variant: confirmDelMa.containsMouse ? "error" : "common"
                    Text {
                        anchors.centerIn: parent
                        text: "Delete"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        font.weight: Font.Medium
                        color: confirmDelMa.containsMouse ? Colors.overError : Colors.error
                    }
                    MouseArea {
                        id: confirmDelMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            confirmPopup.close();
                            AgentStore.deleteProfile(root.selectedId);
                            root.selectedId = "";
                        }
                    }
                }
            }
        }
    }
}
