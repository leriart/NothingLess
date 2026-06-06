import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root

    property int maxContentWidth: 480
    readonly property int contentWidth: Math.min(width, maxContentWidth)
    readonly property real sideMargin: Math.max(0, (width - contentWidth) / 2)

    Flickable {
        anchors.fill: parent
        contentHeight: contentColumn.implicitHeight + 40
        clip: true
        bottomMargin: 40

        ColumnLayout {
            id: contentColumn
            width: root.contentWidth
            x: root.sideMargin
            y: 20
            spacing: 24

            Text {
                text: "AI & API Keys"
                font.family: Config.theme.font
                font.pixelSize: 24
                font.weight: Font.Bold
                color: Colors.overSurface
                Layout.fillWidth: true
                Layout.bottomMargin: 8
            }

            // Providers
            Repeater {
                model: ["gemini", "openai", "anthropic", "mistral", "groq", "ollama", "minimax", "deepseek"]
                delegate: StyledRect {
                    required property string modelData
                    Layout.fillWidth: true
                    variant: "surface"
                    radius: Styling.radius(8)
                    
                    // We need a wrapper to give it a height based on content
                    implicitHeight: providerCol.implicitHeight + 32

                    ColumnLayout {
                        id: providerCol
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                font.family: Config.theme.font
                                font.pixelSize: 16
                                font.weight: Font.Bold
                                color: Colors.overSurface
                                Layout.fillWidth: true
                            }
                            Text {
                                text: KeyStore.hasKey(modelData) ? "Key Configured" : "Not Configured"
                                font.family: Config.theme.font
                                font.pixelSize: 12
                                color: KeyStore.hasKey(modelData) ? Colors.success : Colors.outline
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            TextField {
                                visible: modelData !== "ollama"
                                id: keyInput
                                Layout.fillWidth: true
                                placeholderText: "Enter API Key..."
                                echoMode: TextInput.Password
                                font.family: Config.theme.font
                                color: Colors.overSurface
                                padding: 6
                                
                                background: StyledRect {
                                    variant: "internalbg"
                                    radius: Styling.radius(4)
                                    border.width: keyInput.activeFocus ? 2 : 0
                                    border.color: Styling.srItem("primary")
                                    anchors.fill: parent
                                    anchors.leftMargin: -parent.padding
                                    anchors.rightMargin: -parent.padding
                                    anchors.topMargin: -parent.padding
                                    anchors.bottomMargin: -parent.padding
                                }
                            }
                            Button {
                                id: saveButton
                                text: modelData === "ollama" ? (KeyStore.hasKey("ollama") ? "Configured" : "Enable") : "Save"
                                visible: modelData === "ollama" ? !KeyStore.hasKey("ollama") : true
                                hoverEnabled: true
                                leftPadding: 6
                                rightPadding: 6
                                topPadding: 4
                                bottomPadding: 4
                                onClicked: {
                                    if (modelData === "ollama") {
                                        KeyStore.setKey("ollama", "enabled")
                                    } else if (keyInput.text !== "") {
                                        KeyStore.setKey(modelData, keyInput.text)
                                        keyInput.text = ""
                                    }
                                }
                                background: StyledRect {
                                    variant: saveButton.down ? "overprimary" : (saveButton.hovered ? "primaryfocus" : "primary")
                                    radius: Styling.radius(4)
                                }
                                contentItem: Item {
                                    implicitWidth: saveButtonLabel.implicitWidth + saveButton.leftPadding + saveButton.rightPadding
                                    implicitHeight: saveButtonLabel.implicitHeight + saveButton.topPadding + saveButton.bottomPadding

                                    Text {
                                        id: saveButtonLabel
                                        text: saveButton.text
                                        color: Colors.overPrimary
                                        font.family: Config.theme.font
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        anchors.fill: parent
                                        anchors.leftMargin: saveButton.leftPadding
                                        anchors.rightMargin: saveButton.rightPadding
                                        anchors.topMargin: saveButton.topPadding
                                        anchors.bottomMargin: saveButton.bottomPadding
                                    }
                                }
                            }
                            Button {
                                id: clearButton
                                visible: KeyStore.hasKey(modelData)
                                text: modelData === "ollama" ? "Disable" : "Clear"
                                leftPadding: 6
                                rightPadding: 6
                                topPadding: 4
                                bottomPadding: 4
                                onClicked: KeyStore.deleteKey(modelData)
                                background: StyledRect {
                                    variant: "error"
                                    radius: Styling.radius(4)
                                }
                                contentItem: Item {
                                    implicitWidth: clearButtonLabel.implicitWidth + clearButton.leftPadding + clearButton.rightPadding
                                    implicitHeight: clearButtonLabel.implicitHeight + clearButton.topPadding + clearButton.bottomPadding

                                    Text {
                                        id: clearButtonLabel
                                        text: clearButton.text
                                        color: Colors.overError
                                        font.family: Config.theme.font
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        anchors.fill: parent
                                        anchors.leftMargin: clearButton.leftPadding
                                        anchors.rightMargin: clearButton.rightPadding
                                        anchors.topMargin: clearButton.topPadding
                                        anchors.bottomMargin: clearButton.bottomPadding
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Custom Provider
            Text {
                text: "Custom Provider"
                font.family: Config.theme.font
                font.pixelSize: 20
                font.weight: Font.Bold
                color: Colors.overSurface
                Layout.fillWidth: true
                Layout.topMargin: 16
                Layout.bottomMargin: 8
            }
            
            StyledRect {
                Layout.fillWidth: true
                variant: "surface"
                radius: Styling.radius(8)
                implicitHeight: customCol.implicitHeight + 32

                ColumnLayout {
                    id: customCol
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Custom Provider API Key"
                            font.family: Config.theme.font
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            color: Colors.overSurface
                            Layout.fillWidth: true
                        }
                        Text {
                            text: KeyStore.hasKey("custom") ? "Key Configured" : "Not Configured"
                            font.family: Config.theme.font
                            font.pixelSize: 12
                            color: KeyStore.hasKey("custom") ? Colors.success : Colors.outline
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        TextField {
                            id: customKeyInput
                            Layout.fillWidth: true
                            placeholderText: "Enter API Key..."
                            echoMode: TextInput.Password
                            font.family: Config.theme.font
                            color: Colors.overSurface
                            padding: 6
                            
                            background: StyledRect {
                                variant: "internalbg"
                                radius: Styling.radius(4)
                                border.width: customKeyInput.activeFocus ? 2 : 0
                                border.color: Styling.srItem("primary")
                                anchors.fill: parent
                                anchors.leftMargin: -parent.padding
                                anchors.rightMargin: -parent.padding
                                anchors.topMargin: -parent.padding
                                anchors.bottomMargin: -parent.padding
                            }
                        }
                        Button {
                            id: customSaveButton
                            text: "Save"
                            hoverEnabled: true
                            leftPadding: 6
                            rightPadding: 6
                            topPadding: 4
                            bottomPadding: 4
                            onClicked: {
                                if (customKeyInput.text !== "") {
                                    KeyStore.setKey("custom", customKeyInput.text)
                                    customKeyInput.text = ""
                                }
                            }
                            background: StyledRect {
                                variant: customSaveButton.down ? "overprimary" : (customSaveButton.hovered ? "primaryfocus" : "primary")
                                radius: Styling.radius(4)
                            }
                            contentItem: Item {
                                implicitWidth: customSaveButtonLabel.implicitWidth + customSaveButton.leftPadding + customSaveButton.rightPadding
                                implicitHeight: customSaveButtonLabel.implicitHeight + customSaveButton.topPadding + customSaveButton.bottomPadding

                                Text {
                                    id: customSaveButtonLabel
                                    text: customSaveButton.text
                                    color: Colors.overPrimary
                                    font.family: Config.theme.font
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    anchors.fill: parent
                                    anchors.leftMargin: customSaveButton.leftPadding
                                    anchors.rightMargin: customSaveButton.rightPadding
                                    anchors.topMargin: customSaveButton.topPadding
                                    anchors.bottomMargin: customSaveButton.bottomPadding
                                }
                            }
                        }
                        Button {
                            id: customClearButton
                            visible: KeyStore.hasKey("custom")
                            text: "Clear"
                            leftPadding: 6
                            rightPadding: 6
                            topPadding: 4
                            bottomPadding: 4
                            onClicked: KeyStore.deleteKey("custom")
                            background: StyledRect {
                                variant: "error"
                                radius: Styling.radius(4)
                            }
                            contentItem: Item {
                                implicitWidth: customClearButtonLabel.implicitWidth + customClearButton.leftPadding + customClearButton.rightPadding
                                implicitHeight: customClearButtonLabel.implicitHeight + customClearButton.topPadding + customClearButton.bottomPadding

                                Text {
                                    id: customClearButtonLabel
                                    text: customClearButton.text
                                    color: Colors.overError
                                    font.family: Config.theme.font
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    anchors.fill: parent
                                    anchors.leftMargin: customClearButton.leftPadding
                                    anchors.rightMargin: customClearButton.rightPadding
                                    anchors.topMargin: customClearButton.topPadding
                                    anchors.bottomMargin: customClearButton.bottomPadding
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Colors.outline
                        opacity: 0.2
                        Layout.topMargin: 8
                        Layout.bottomMargin: 8
                    }

                    Text {
                        text: "Custom Endpoint"
                        font.family: Config.theme.font
                        font.pixelSize: 14
                        color: Colors.overSurface
                    }
                    
                    TextField {
                        id: endpointInput
                        Layout.fillWidth: true
                        text: Config.ai.customEndpoint !== undefined ? Config.ai.customEndpoint : ""
                        placeholderText: "e.g. https://api.example.com/v1/chat/completions"
                        font.family: Config.theme.font
                        color: Colors.overSurface
                        padding: 6
                        
                        onTextChanged: {
                            if (Config.ai.customEndpoint !== undefined) {
                                Config.ai.customEndpoint = text;
                            }
                        }
                        
                        background: StyledRect {
                            variant: "internalbg"
                            radius: Styling.radius(4)
                            border.width: endpointInput.activeFocus ? 2 : 0
                            border.color: Styling.srItem("primary")
                            anchors.fill: parent
                            anchors.leftMargin: -parent.padding
                            anchors.rightMargin: -parent.padding
                            anchors.topMargin: -parent.padding
                            anchors.bottomMargin: -parent.padding
                        }
                    }

                    Text {
                        text: "Custom cURL Template"
                        font.family: Config.theme.font
                        font.pixelSize: 14
                        color: Colors.overSurface
                        Layout.topMargin: 8
                    }
                    
                    Text {
                        text: "Placeholders: {{ENDPOINT}}, {{API_KEY}}, {{BODY_PATH}}"
                        font.family: Config.theme.font
                        font.pixelSize: 12
                        color: Colors.outline
                    }
                    
                    TextField {
                        id: curlInput
                        Layout.fillWidth: true
                        text: Config.ai.customCurlTemplate !== undefined ? Config.ai.customCurlTemplate : ""
                        placeholderText: "curl -X POST {{ENDPOINT}} -H 'Authorization: Bearer {{API_KEY}}' -d @{{BODY_PATH}}"
                        font.family: "Monospace"
                        color: Colors.overSurface
                        padding: 6
                        
                        onTextChanged: {
                            if (Config.ai.customCurlTemplate !== undefined) {
                                Config.ai.customCurlTemplate = text;
                            }
                        }
                        
                        background: StyledRect {
                            variant: "internalbg"
                            radius: Styling.radius(4)
                            border.width: curlInput.activeFocus ? 2 : 0
                            border.color: Styling.srItem("primary")
                            anchors.fill: parent
                            anchors.leftMargin: -parent.padding
                            anchors.rightMargin: -parent.padding
                            anchors.topMargin: -parent.padding
                            anchors.bottomMargin: -parent.padding
                        }
                    }
                }
            }

            // Tools Section
            Text {
                text: "Tools & Safety"
                font.family: Config.theme.font
                font.pixelSize: 20
                font.weight: Font.Bold
                color: Colors.overSurface
                Layout.fillWidth: true
                Layout.topMargin: 16
                Layout.bottomMargin: 8
            }
            
            StyledRect {
                Layout.fillWidth: true
                variant: "surface"
                radius: Styling.radius(8)
                implicitHeight: toolsCol.implicitHeight + 32
                
                ColumnLayout {
                    id: toolsCol
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12
                    
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Enable shell command tool"
                            font.family: Config.theme.font
                            font.pixelSize: 14
                            color: Colors.overSurface
                            Layout.fillWidth: true
                        }
                        Switch {
                            checked: (Config.ai.enabledTools || []).includes("shell")
                            onClicked: {
                                let tools = Array.from(Config.ai.enabledTools || []);
                                if (checked) {
                                    if (!tools.includes("shell")) tools.push("shell");
                                } else {
                                    tools = tools.filter(t => t !== "shell");
                                }
                                Config.ai.enabledTools = tools;
                            }
                        }
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Auto-approve allowlisted commands"
                            font.family: Config.theme.font
                            font.pixelSize: 14
                            color: Colors.overSurface
                            Layout.fillWidth: true
                        }
                        Switch {
                            checked: Config.ai.toolAutoApprove || false
                            onClicked: Config.ai.toolAutoApprove = checked
                        }
                    }
                    
                    Text {
                        text: "Allowed commands (comma separated). Empty = require confirmation for all."
                        font.family: Config.theme.font
                        font.pixelSize: 12
                        color: Colors.outline
                    }
                    
                    TextField {
                        id: allowlistInput
                        Layout.fillWidth: true
                        text: (Config.ai.toolAllowlist || []).join(", ")
                        placeholderText: "e.g. ls, cat, pwd, systemctl"
                        font.family: Config.theme.font
                        color: Colors.overSurface
                        padding: 6
                        
                        onEditingFinished: {
                            let parts = text.split(",").map(s => s.trim()).filter(s => s !== "");
                            Config.ai.toolAllowlist = parts;
                        }
                        
                        background: StyledRect {
                            variant: "internalbg"
                            radius: Styling.radius(4)
                            border.width: allowlistInput.activeFocus ? 2 : 0
                            Behavior on border.width {
                                AnimatedBehavior { type: "standard"; size: "small" }
                            }
                            border.color: Styling.srItem("primary")
                            anchors.fill: parent
                            anchors.leftMargin: -parent.padding
                            anchors.rightMargin: -parent.padding
                            anchors.topMargin: -parent.padding
                            anchors.bottomMargin: -parent.padding
                        }
                    }
                }
            }
            
            // Agent Connections Section
            Text {
                text: "Agent Connections"
                font.family: Config.theme.font
                font.pixelSize: 20
                font.weight: Font.Bold
                color: Colors.overSurface
                Layout.fillWidth: true
                Layout.topMargin: 16
                Layout.bottomMargin: 8
            }
            
            StyledRect {
                Layout.fillWidth: true
                variant: "surface"
                radius: Styling.radius(8)
                implicitHeight: agentsCol.implicitHeight + 32
                
                ColumnLayout {
                    id: agentsCol
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12
                    
                    Text {
                        text: "Add external tools via HTTP bridge or CLI wrappers."
                        font.family: Config.theme.font
                        font.pixelSize: 12
                        color: Colors.outline
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    
                    Repeater {
                        model: Ai.agentManager ? Ai.agentManager.connections : []
                        delegate: StyledRect {
                            required property var modelData
                            Layout.fillWidth: true
                            variant: "internalbg"
                            radius: Styling.radius(6)
                            implicitHeight: agentItemCol.implicitHeight + 20
                            
                            ColumnLayout {
                                id: agentItemCol
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 6
                                
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: modelData.name
                                        font.family: Config.theme.font
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        color: Colors.overSurface
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: modelData.status.toUpperCase()
                                        font.family: Config.theme.font
                                        font.pixelSize: 11
                                        color: modelData.status === "connected" ? Colors.success : (modelData.status === "error" ? Colors.error : Colors.outline)
                                    }
                                }
                                
                                Text {
                                    text: (modelData.type || "") + (modelData.endpoint ? " • " + modelData.endpoint : modelData.command ? " • " + modelData.command : "")
                                    font.family: Config.theme.font
                                    font.pixelSize: 11
                                    color: Colors.outline
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    
                                    Button {
                                        text: modelData.enabled ? "Disconnect" : "Connect"
                                        onClicked: {
                                            if (modelData.enabled) {
                                                Ai.agentManager.disconnectAgent(modelData.id);
                                            } else {
                                                Ai.agentManager.reconnectAgent(modelData.id);
                                            }
                                        }
                                        background: StyledRect {
                                            variant: parent.down ? "overprimary" : (parent.hovered ? "primaryfocus" : "primary")
                                            radius: Styling.radius(4)
                                        }
                                        contentItem: Text {
                                            text: parent.text
                                            color: Colors.overPrimary
                                            font.family: Config.theme.font
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                    
                                    Button {
                                        text: "Remove"
                                        onClicked: Ai.agentManager.removeConnection(modelData.id)
                                        background: StyledRect {
                                            variant: "error"
                                            radius: Styling.radius(4)
                                        }
                                        contentItem: Text {
                                            text: parent.text
                                            color: Colors.overError
                                            font.family: Config.theme.font
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Quick-preset buttons
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        
                        Button {
                            text: "+ Odysseus"
                            onClicked: {
                                Ai.agentManager.addConnection({
                                    id: "agent_odysseus_" + Date.now(),
                                    name: "Odysseus",
                                    type: "http-bridge",
                                    enabled: true,
                                    endpoint: "http://localhost:7000",
                                    headers: {},
                                    toolsPath: "/api/codex/capabilities",
                                    invokePath: "/api/codex/invoke"
                                });
                            }
                            background: StyledRect {
                                variant: parent.hovered ? "primaryfocus" : "primary"
                                radius: Styling.radius(4)
                            }
                            contentItem: Text {
                                text: parent.text
                                color: Colors.overPrimary
                                font.family: Config.theme.font
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        
                        Button {
                            text: "+ OpenClaw"
                            onClicked: {
                                Ai.agentManager.addConnection({
                                    id: "agent_openclaw_" + Date.now(),
                                    name: "OpenClaw",
                                    type: "http-bridge",
                                    enabled: true,
                                    endpoint: "http://localhost:8080",
                                    headers: {},
                                    toolsPath: "/tools",
                                    invokePath: "/invoke"
                                });
                            }
                            background: StyledRect {
                                variant: parent.hovered ? "primaryfocus" : "primary"
                                radius: Styling.radius(4)
                            }
                            contentItem: Text {
                                text: parent.text
                                color: Colors.overPrimary
                                font.family: Config.theme.font
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        
                        Button {
                            text: "+ MCP Bridge"
                            onClicked: {
                                Ai.agentManager.addConnection({
                                    id: "agent_mcp_" + Date.now(),
                                    name: "MCP Bridge",
                                    type: "command",
                                    enabled: true,
                                    command: "python3",
                                    args: [Quickshell.env("HOME") + "/.local/src/nothingless/scripts/mcp_stdio_bridge.py"]
                                });
                            }
                            background: StyledRect {
                                variant: parent.hovered ? "primaryfocus" : "primary"
                                radius: Styling.radius(4)
                            }
                            contentItem: Text {
                                text: parent.text
                                color: Colors.overPrimary
                                font.family: Config.theme.font
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        
                        Button {
                            text: "+ Custom"
                            onClicked: { newAgentName.focus = true; }
                            background: StyledRect {
                                variant: parent.hovered ? "secondaryfocus" : "secondary"
                                radius: Styling.radius(4)
                            }
                            contentItem: Text {
                                text: parent.text
                                color: Colors.overSecondary
                                font.family: Config.theme.font
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                    
                    // Simple add-agent form
                    Text {
                        text: "Manual config"
                        font.family: Config.theme.font
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        color: Colors.overSurface
                        Layout.topMargin: 8
                    }
                    
                    TextField {
                        id: newAgentName
                        Layout.fillWidth: true
                        placeholderText: "Name (e.g. OpenClaw Local)"
                        font.family: Config.theme.font
                        color: Colors.overSurface
                        padding: 6
                        background: StyledRect {
                            variant: "internalbg"
                            radius: Styling.radius(4)
                            border.width: newAgentName.activeFocus ? 2 : 0
                            Behavior on border.width { AnimatedBehavior { type: "standard"; size: "small" } }
                            border.color: Styling.srItem("primary")
                            anchors.fill: parent
                            anchors.leftMargin: -parent.padding
                            anchors.rightMargin: -parent.padding
                            anchors.topMargin: -parent.padding
                            anchors.bottomMargin: -parent.padding
                        }
                    }
                    
                    TextField {
                        id: newAgentType
                        Layout.fillWidth: true
                        text: "http-bridge"
                        placeholderText: "Type: http-bridge | command"
                        font.family: Config.theme.font
                        color: Colors.overSurface
                        padding: 6
                        background: StyledRect {
                            variant: "internalbg"
                            radius: Styling.radius(4)
                            border.width: newAgentType.activeFocus ? 2 : 0
                            Behavior on border.width { AnimatedBehavior { type: "standard"; size: "small" } }
                            border.color: Styling.srItem("primary")
                            anchors.fill: parent
                            anchors.leftMargin: -parent.padding
                            anchors.rightMargin: -parent.padding
                            anchors.topMargin: -parent.padding
                            anchors.bottomMargin: -parent.padding
                        }
                    }
                    
                    TextField {
                        id: newAgentEndpoint
                        Layout.fillWidth: true
                        placeholderText: "Endpoint or command (e.g. http://localhost:8080 or /usr/bin/my-agent)"
                        font.family: Config.theme.font
                        color: Colors.overSurface
                        padding: 6
                        background: StyledRect {
                            variant: "internalbg"
                            radius: Styling.radius(4)
                            border.width: newAgentEndpoint.activeFocus ? 2 : 0
                            Behavior on border.width { AnimatedBehavior { type: "standard"; size: "small" } }
                            border.color: Styling.srItem("primary")
                            anchors.fill: parent
                            anchors.leftMargin: -parent.padding
                            anchors.rightMargin: -parent.padding
                            anchors.topMargin: -parent.padding
                            anchors.bottomMargin: -parent.padding
                        }
                    }
                    
                    Button {
                        text: "Add Agent"
                        onClicked: {
                            let type = newAgentType.text.trim() || "http-bridge";
                            let config = {
                                id: "agent_" + Date.now(),
                                name: newAgentName.text.trim() || "New Agent",
                                type: type,
                                enabled: true
                            };
                            if (type === "command") {
                                config.command = newAgentEndpoint.text.trim();
                                config.args = [];
                            } else {
                                config.endpoint = newAgentEndpoint.text.trim();
                                config.headers = {};
                                config.toolsPath = "/tools";
                                config.invokePath = "/invoke";
                            }
                            Ai.agentManager.addConnection(config);
                            newAgentName.text = "";
                            newAgentEndpoint.text = "";
                        }
                        background: StyledRect {
                            variant: parent.down ? "overprimary" : (parent.hovered ? "primaryfocus" : "primary")
                            radius: Styling.radius(4)
                        }
                        contentItem: Text {
                            text: parent.text
                            color: Colors.overPrimary
                            font.family: Config.theme.font
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }
}
