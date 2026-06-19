import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

/*!
    QuickAddAgentPopup — lightweight modal that lets the user spin up
    a new agent profile without opening the full Settings → AI panel.

    Each preset captures a typical agent topology (HTTP bridge, MCP
    stdio, generic webhook…). Choosing a preset pre-fills the form;
    pressing "Add" hands the config to `AgentManager.addConnection`,
    which persists it via `AgentStore` and immediately spawns the
    client.
*/
Popup {
    id: root
    modal: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0
    width: 460
    height: 520

    background: StyledRect {
        variant: "popup"
        radius: Styling.radius(8)
        enableShadow: true
    }

    // Resolved path to the bundled NothingClaw bridge — used by the
    // preset below to declare a shell-managed `process` block so the
    // shell spawns the bridge on demand (no install step).
    readonly property string nothingclawServerPath:
        Qt.resolvedUrl("../../mcp/nothingclaw/server.py")
            .toString().replace("file://", "")
    readonly property string nothingclawDirPath:
        Qt.resolvedUrl("../../mcp/nothingclaw/")
            .toString().replace("file://", "")

    property var presets: [
        {
            id: "preset-nothingclaw",
            label: "NothingClaw",
            description: "Bundled HTTP bridge — shell-managed, no install needed",
            icon: Icons.robot,
            type: "http-bridge",
            endpoint: "http://127.0.0.1:8000",
            toolsPath: "/tools",
            invokePath: "/tools",
            process: {
                command: "python3",
                args: [root.nothingclawServerPath],
                cwd: root.nothingclawDirPath
            }
        },
        {
            id: "preset-odysseus",
            label: "Odysseus",
            description: "Local LLM gateway with codex tools",
            icon: Icons.robot,
            type: "http-bridge",
            endpoint: "http://localhost:7000",
            toolsPath: "/api/codex/capabilities",
            invokePath: "/api/codex/invoke"
        },
        {
            id: "preset-openclaw",
            label: "OpenClaw",
            description: "OpenClaw agent gateway",
            icon: Icons.toolbox,
            type: "http-bridge",
            endpoint: "http://localhost:8080",
            toolsPath: "/tools",
            invokePath: "/invoke"
        },
        {
            id: "preset-mcp-stdio",
            label: "MCP server (stdio)",
            description: "Local MCP server over stdio (Anthropic standard)",
            icon: Icons.terminalWindow,
            type: "mcp-stdio",
            command: "uvx",
            args: ["mcp-server-filesystem", Quickshell.env("HOME")]
        },
        {
            id: "preset-mcp-sse",
            label: "MCP server (SSE)",
            description: "Remote MCP server over Server-Sent Events",
            icon: Icons.link,
            type: "mcp-sse",
            endpoint: "http://localhost:9000",
            toolsPath: "/sse/tools",
            invokePath: "/sse/invoke"
        },
        {
            id: "preset-webhook",
            label: "Webhook",
            description: "Simple POST endpoint returning JSON tool",
            icon: Icons.at,
            type: "http-bridge",
            endpoint: "http://localhost:8000",
            toolsPath: "/tools",
            invokePath: "/invoke"
        },
        {
            id: "preset-command",
            label: "Custom command",
            description: "Stateless CLI that takes a JSON arg",
            icon: Icons.terminal,
            type: "command",
            command: "",
            args: []
        }
    ]

    property string selectedPresetId: "preset-mcp-stdio"
    property string formName: ""
    property string formEndpoint: ""
    property string formCommand: ""
    property string formArgs: ""
    property string formToolsPath: "/tools"
    property string formInvokePath: "/invoke"
    property string formHeaders: ""
    property string lastErr: ""

    function _getPreset(id) {
        for (let i = 0; i < presets.length; i++) {
            if (presets[i].id === id) return presets[i];
        }
        return null;
    }

    function _applyPreset(presetId) {
        selectedPresetId = presetId;
        let p = _getPreset(presetId);
        if (!p) return;
        formName = p.label || "";
        formEndpoint = p.endpoint || "";
        formCommand = p.command || "";
        formArgs = Array.isArray(p.args) ? p.args.join("\n") : "";
        formToolsPath = p.toolsPath || "/tools";
        formInvokePath = p.invokePath || "/invoke";
        formHeaders = "";
        lastErr = "";
    }

    function _selectedType() {
        let p = _getPreset(selectedPresetId);
        return p ? p.type : "http-bridge";
    }

    function _buildConfig() {
        let p = _getPreset(selectedPresetId);
        if (!p) return null;
        let parsedHeaders = {};
        if (formHeaders.trim() !== "") {
            try { parsedHeaders = JSON.parse(formHeaders); }
            catch (e) {
                lastErr = "Headers must be a JSON object: " + e.toString();
                return null;
            }
        }
        let args = formArgs.split("\n").map(s => s.trim()).filter(s => s.length > 0);
        return {
            id: "agent_" + (formName || "custom").toLowerCase().replace(/[^a-z0-9]+/g, "_") + "_" + Date.now(),
            name: formName || p.label,
            type: p.type,
            enabled: true,
            command: formCommand,
            args: args,
            endpoint: formEndpoint,
            headers: parsedHeaders,
            toolsPath: formToolsPath,
            invokePath: formInvokePath,
            process: (p.process && typeof p.process === "object") ? p.process : ({})
        };
    }

    onAboutToShow: {
        if (selectedPresetId)
            _applyPreset(selectedPresetId);
    }

    contentItem: ColumnLayout {
        spacing: 12

        // Header
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 14
            Layout.rightMargin: 8
            Layout.topMargin: 12
            spacing: 8

            Text {
                text: Icons.robot
                font.family: Icons.font
                font.pixelSize: 18
                color: Styling.srItem("overprimary")
            }
            Text {
                text: "Add an agent"
                color: Colors.overSurface
                font.family: Config.theme.font
                font.pixelSize: 16
                font.weight: Font.Bold
                Layout.fillWidth: true
            }
            Button {
                flat: true
                width: 28
                height: 28
                contentItem: Text {
                    text: Icons.cancel
                    font.family: Icons.font
                    color: Colors.overSurface
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: StyledRect {
                    radius: Styling.radius(4)
                    variant: parent.hovered ? "focus" : "transparent"
                }
                onClicked: root.close()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            height: 1
            color: Colors.outline
            opacity: 0.15
        }

        // Preset selector
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            spacing: 6

            Repeater {
                model: root.presets

                delegate: Item {
                    required property var modelData
                    width: presetLabel.implicitWidth + 24
                    height: 26

                    property bool isSelected: root.selectedPresetId === modelData.id

                    StyledRect {
                        anchors.fill: parent
                        radius: Styling.radius(4)
                        variant: parent.isSelected ? "primary" : (presetMa.containsMouse ? "focus" : "common")
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 4

                        Text {
                            text: modelData.icon
                            font.family: Icons.font
                            font.pixelSize: 11
                            color: parent.parent.isSelected ? Colors.overPrimary : Colors.overSurface
                        }
                        Text {
                            id: presetLabel
                            text: modelData.label
                            color: parent.parent.isSelected ? Colors.overPrimary : Colors.overSurface
                            font.family: Config.theme.font
                            font.pixelSize: 11
                            font.weight: parent.parent.isSelected ? Font.Bold : Font.Normal
                        }
                    }

                    MouseArea {
                        id: presetMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root._applyPreset(modelData.id)
                    }
                }
            }
        }

        Text {
            text: {
                let p = root._getPreset(root.selectedPresetId);
                return p ? p.description : "";
            }
            color: Colors.outline
            font.family: Config.theme.font
            font.pixelSize: 11
            font.italic: true
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        // Form fields (scrollable in case of long content)
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            clip: true

            ColumnLayout {
                width: parent.parent.width - 16
                spacing: 8

                // Name
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        text: "Name"
                        color: Colors.outline
                        font.family: Config.theme.font
                        font.pixelSize: 11
                    }
                    TextField {
                        Layout.fillWidth: true
                        text: root.formName
                        onTextChanged: root.formName = text
                        font.family: Config.theme.font
                        color: Colors.overSurface
                        padding: 8
                        background: StyledRect {
                            anchors.fill: parent
                            variant: "internalbg"
                            radius: Styling.radius(4)
                        }
                    }
                }

                // HTTP-bridge / mcp-sse fields
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    visible: {
                        let t = root._selectedType();
                        return t === "http-bridge" || t === "mcp-sse";
                    }
                    Text {
                        text: "Endpoint"
                        color: Colors.outline
                        font.family: Config.theme.font
                        font.pixelSize: 11
                    }
                    TextField {
                        Layout.fillWidth: true
                        text: root.formEndpoint
                        onTextChanged: root.formEndpoint = text
                        placeholderText: "http://localhost:8080"
                        color: Colors.overSurface
                        padding: 8
                        background: StyledRect {
                            anchors.fill: parent
                            variant: "internalbg"
                            radius: Styling.radius(4)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text {
                                text: "Tools path"
                                color: Colors.outline
                                font.family: Config.theme.font
                                font.pixelSize: 11
                            }
                            TextField {
                                Layout.fillWidth: true
                                text: root.formToolsPath
                                onTextChanged: root.formToolsPath = text
                                color: Colors.overSurface
                                padding: 8
                                background: StyledRect {
                                    anchors.fill: parent
                                    variant: "internalbg"
                                    radius: Styling.radius(4)
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text {
                                text: "Invoke path"
                                color: Colors.outline
                                font.family: Config.theme.font
                                font.pixelSize: 11
                            }
                            TextField {
                                Layout.fillWidth: true
                                text: root.formInvokePath
                                onTextChanged: root.formInvokePath = text
                                color: Colors.overSurface
                                padding: 8
                                background: StyledRect {
                                    anchors.fill: parent
                                    variant: "internalbg"
                                    radius: Styling.radius(4)
                                }
                            }
                        }
                    }

                    Text {
                        text: "Headers (optional JSON)"
                        color: Colors.outline
                        font.family: Config.theme.font
                        font.pixelSize: 11
                    }
                    TextField {
                        Layout.fillWidth: true
                        text: root.formHeaders
                        onTextChanged: root.formHeaders = text
                        placeholderText: "{\"Authorization\": \"Bearer xyz\"}"
                        color: Colors.overSurface
                        padding: 8
                        background: StyledRect {
                            anchors.fill: parent
                            variant: "internalbg"
                            radius: Styling.radius(4)
                        }
                    }
                }

                // Command / mcp-stdio fields
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    visible: {
                        let t = root._selectedType();
                        return t === "command" || t === "mcp-stdio";
                    }
                    Text {
                        text: "Command"
                        color: Colors.outline
                        font.family: Config.theme.font
                        font.pixelSize: 11
                    }
                    TextField {
                        Layout.fillWidth: true
                        text: root.formCommand
                        onTextChanged: root.formCommand = text
                        placeholderText: "uvx | python3 | /usr/local/bin/server"
                        color: Colors.overSurface
                        padding: 8
                        font.family: "Monospace"
                        background: StyledRect {
                            anchors.fill: parent
                            variant: "internalbg"
                            radius: Styling.radius(4)
                        }
                    }

                    Text {
                        text: "Arguments (one per line)"
                        color: Colors.outline
                        font.family: Config.theme.font
                        font.pixelSize: 11
                    }
                    StyledRect {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 80
                        variant: "internalbg"
                        radius: Styling.radius(4)

                        ScrollView {
                            anchors.fill: parent
                            anchors.margins: 4
                            clip: true

                            TextArea {
                                text: root.formArgs
                                onTextChanged: root.formArgs = text
                                placeholderText: "mcp-server-filesystem\n/home/user"
                                color: Colors.overSurface
                                font.family: "Monospace"
                                background: null
                            }
                        }
                    }
                }
            }
        }

        // Error / footer
        Text {
            visible: root.lastErr !== ""
            text: root.lastErr
            color: Colors.error
            font.family: Config.theme.font
            font.pixelSize: 11
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            Layout.bottomMargin: 12
            spacing: 8

            Item { Layout.fillWidth: true }

            Button {
                text: "Cancel"
                flat: true
                onClicked: root.close()
                background: StyledRect {
                    radius: Styling.radius(4)
                    variant: parent.hovered ? "focus" : "common"
                }
                contentItem: Text {
                    text: parent.text
                    color: Colors.overSurface
                    font.family: Config.theme.font
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                padding: 8
            }

            Button {
                text: "Add agent"
                highlighted: true
                onClicked: {
                    let cfg = root._buildConfig();
                    if (!cfg) return;
                    if (!cfg.endpoint && (cfg.type === "http-bridge" || cfg.type === "mcp-sse")) {
                        root.lastErr = cfg.type + " requires an endpoint URL.";
                        return;
                    }
                    if (!cfg.command && (cfg.type === "command" || cfg.type === "mcp-stdio")) {
                        root.lastErr = cfg.type + " requires a command.";
                        return;
                    }
                    root.lastErr = "";
                    Ai.agentManager.addConnection(cfg);
                    Ai.setAgent(cfg.id);
                    Qt.callLater(root.close);
                }
                background: StyledRect {
                    radius: Styling.radius(4)
                    variant: parent.hovered ? "primaryfocus" : "primary"
                }
                contentItem: Text {
                    text: parent.text
                    color: Colors.overPrimary
                    font.family: Config.theme.font
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                padding: 8
            }
        }
    }
}
