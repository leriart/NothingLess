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

    // Tracks the id of the agent currently being edited (null = create mode)
    property string editingAgentId: ""

    // JSON preview toggle (lives on root so all children can reference it)
    property bool jsonPreviewExpanded: false

    // Per-agent JSON inspector toggle map: { agentId: bool }

    // Resolved absolute path to the bundled NothingClaw bridge
    // server. The preset chips below use this to pre-fill the
    // profile's `process` block so the shell can spawn the bridge
    // directly with no install step.
    readonly property string nothingclawServerPath:
        Qt.resolvedUrl("../../../mcp/nothingclaw/server.py")
            .toString().replace("file://", "")
    readonly property string nothingclawDirPath:
        Qt.resolvedUrl("../../../mcp/nothingclaw/")
            .toString().replace("file://", "")
    property var agentJsonExpanded: ({})

    // ── Helpers ────────────────────────────────────────────────────────

    // Parse a multi-line text area into a JSON-style args array.
    // Accepts: one arg per line, OR a single shell-style line.
    // Quotes (' or ") wrap args containing spaces; backslash escapes work.
    function _parseArgsField(text) {
        if (!text)
            return [];
        // If multi-line: each non-empty line is one arg, surrounding quotes stripped
        if (text.indexOf("\n") !== -1) {
            let out = [];
            let lines = text.split("\n");
            for (let i = 0; i < lines.length; i++) {
                let line = lines[i].trim();
                if (line === "")
                    continue;
                if ((line.startsWith('"') && line.endsWith('"')) || (line.startsWith("'") && line.endsWith("'"))) {
                    line = line.substring(1, line.length - 1);
                }
                out.push(line);
            }
            return out;
        }
        // Otherwise, treat as a single shell-style line and split with quote awareness
        return _splitShellArgs(text);
    }

    // Tokenize a single shell-style command line into args (handles "..." and '...')
    function _splitShellArgs(line) {
        let out = [];
        let cur = "";
        let quote = ""; // active quote char
        let i = 0;
        while (i < line.length) {
            let c = line.charAt(i);
            if (quote) {
                if (c === quote) {
                    quote = "";
                } else if (c === "\\" && i + 1 < line.length) {
                    cur += line.charAt(i + 1);
                    i++;
                } else {
                    cur += c;
                }
            } else {
                if (c === " " || c === "\t") {
                    if (cur.length > 0) {
                        out.push(cur);
                        cur = "";
                    }
                } else if (c === '"' || c === "'") {
                    quote = c;
                } else if (c === "\\" && i + 1 < line.length) {
                    cur += line.charAt(i + 1);
                    i++;
                } else {
                    cur += c;
                }
            }
            i++;
        }
        if (cur.length > 0)
            out.push(cur);
        return out;
    }

    // Build a JSON-serializable preview of the form's current state
    function _buildConfigFromForm() {
        let type = (newAgentType.text || "").trim() || "http-bridge";
        let cfg = {
            id: root.editingAgentId !== "" ? root.editingAgentId : ("agent_" + Date.now()),
            name: (newAgentName.text || "").trim() || "New Agent",
            type: type,
            enabled: true
        };
        if (type === "command" || type === "mcp-stdio") {
            cfg.command = root._expandPath((newAgentCommand.text || "").trim());
            let rawArgs = root._parseArgsField(argsArea.backingText || argsArea.text || "");
            let expanded = [];
            for (let i = 0; i < rawArgs.length; i++) {
                expanded.push(root._expandPath(rawArgs[i]));
            }
            cfg.args = expanded;
        } else {
            cfg.endpoint = (newAgentEndpoint.text || "").trim();
            let hdrs = {};
            let h = (newAgentHeaders.text || "").trim();
            if (h) {
                try { hdrs = JSON.parse(h); } catch (e) { /* keep empty */ }
            }
            cfg.headers = hdrs;
            cfg.toolsPath = "/tools";
            cfg.invokePath = "/invoke";
            // Capability hints for bridges that adapt tool surface to
            // model size (NothingClaw uses these to query Ollama's
            // /api/show and pick a tier). Other agents ignore them.
            let m = (newAgentModel.text || "").trim();
            if (m) cfg.model = m;
            let mh = (newAgentModelHost.text || "").trim();
            if (mh) cfg.modelHost = mh;
        }
        return cfg;
    }

    // Reset the form to a clean state
    function _clearForm() {
        editingAgentId = "";
        newAgentName.text = "";
        newAgentType.text = "http-bridge";
        newAgentEndpoint.text = "";
        newAgentCommand.text = "";
        argsArea.text = "";
        newAgentHeaders.text = "";
        newAgentModel.text = "";
        newAgentModelHost.text = "";
        shellPasteField.text = "";
        shellPasteField.visible = false;
        pasteButton.visible = true;
        newAgentSectionTitle.text = "Manual config";
    }

    // Load an existing connection into the form (for Edit)
    function _loadConnectionIntoForm(conn) {
        if (!conn) return;
        editingAgentId = conn.id || "";
        newAgentName.text = conn.name || "";
        newAgentType.text = conn.type || "http-bridge";
        if (conn.type === "command" || conn.type === "mcp-stdio") {
            newAgentCommand.text = conn.command || "";
            let arr = conn.args || [];
            argsArea.text = arr.join("\n");
        } else {
            newAgentEndpoint.text = conn.endpoint || "";
            try {
                newAgentHeaders.text = conn.headers && Object.keys(conn.headers).length > 0
                    ? JSON.stringify(conn.headers, null, 2) : "";
            } catch (e) {
                newAgentHeaders.text = "";
            }
            newAgentModel.text = conn.model || "";
            newAgentModelHost.text = conn.modelHost || "";
        }
        newAgentSectionTitle.text = "Editing: " + (conn.name || "agent");
    }

    // Resolve ~ and $ENV in a path-like string. Anything not starting with / or ~ is returned as-is
    // (it's a binary name resolved via PATH, like `uv`, `python3`).
    function _expandPath(p) {
        if (!p) return p;
        if (p.startsWith("/") || p.startsWith("~")) {
            if (p === "~") return Quickshell.env("HOME");
            if (p.startsWith("~/")) return Quickshell.env("HOME") + p.substring(1);
        }
        // $VAR expansion
        return p.replace(/\$([A-Z_][A-Z0-9_]*)/g, function(_, name) {
            let v = Quickshell.env(name);
            return v !== undefined ? v : ("$" + name);
        });
    }

    // ── Shell-native toggle row ────────────────────────────────────
    // Mirrors the ToggleRow pattern from ShellPanel.qml so the AI
    // tab uses the same on/off switch widget as the rest of the
    // settings panels. The default QtQuick.Controls Switch renders
    // a platform blue/cyan style that looks out of place against
    // the NothingLess dark theme; this component rebuilds the
    // visual as a 40x20 pill with the primary accent color when
    // on, and Colors.surfaceBright when off. The handle is a
    // circle that animates between the two ends.
    component ToggleRow: RowLayout {
        id: toggleRowRoot
        property string label: ""
        property string description: ""
        property bool checked: false
        signal toggled(bool value)

        // Guard against feedback when we mirror the bound state
        // onto the internal switch on initialization.
        property bool _updating: false

        onCheckedChanged: {
            if (!_updating && toggleSwitch.checked !== checked) {
                _updating = true;
                toggleSwitch.checked = checked;
                _updating = false;
            }
        }

        Layout.fillWidth: true
        spacing: 12

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                text: toggleRowRoot.label
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(0)
                font.weight: Font.Medium
                color: Colors.overBackground
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
            Text {
                visible: toggleRowRoot.description !== ""
                text: toggleRowRoot.description
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.outline
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
        }

        Switch {
            id: toggleSwitch
            checked: toggleRowRoot.checked

            onCheckedChanged: {
                if (!toggleRowRoot._updating && checked !== toggleRowRoot.checked) {
                    toggleRowRoot.toggled(checked);
                }
            }

            // Shell-native pill indicator with primary accent on,
            // surfaceBright off, animated handle.
            indicator: Rectangle {
                implicitWidth: 40
                implicitHeight: 20
                x: toggleSwitch.leftPadding
                y: parent.height / 2 - height / 2
                radius: height / 2
                color: toggleSwitch.checked
                    ? Styling.srItem("overprimary")
                    : Colors.surfaceBright
                border.color: toggleSwitch.checked
                    ? Styling.srItem("overprimary")
                    : Colors.outline
                border.width: 1

                Behavior on color {
                    enabled: Anim.animationsEnabled
                    ColorAnimation {
                        duration: Anim.standardSmall
                        easing.type: Anim.easing("standard").type
                        easing.bezierCurve: Anim.easing("standard").bezierCurve
                    }
                }

                Rectangle {
                    x: toggleSwitch.checked
                        ? parent.width - width - 2
                        : 2
                    y: 2
                    width: parent.height - 6
                    height: width
                    radius: width / 2
                    color: toggleSwitch.checked
                        ? Colors.background
                        : Colors.overSurfaceVariant

                    Behavior on x {
                        enabled: Anim.animationsEnabled
                        NumberAnimation {
                            duration: Anim.standardSmall
                            easing.type: Anim.easing("standard").type
                            easing.bezierCurve: Anim.easing("standard").bezierCurve
                        }
                    }
                }
            }
            background: null
        }
    }

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
                        text: Config.ai.customEndpoint || ""
                        placeholderText: "e.g. https://api.example.com/v1/chat/completions"
                        font.family: Config.theme.font
                        color: Colors.overSurface
                        padding: 6
                        
                        onTextChanged: Config.ai.customEndpoint = text;
                        
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
                        text: Config.ai.customCurlTemplate || ""
                        placeholderText: "curl -X POST {{ENDPOINT}} -H 'Authorization: Bearer {{API_KEY}}' -d @{{BODY_PATH}}"
                        font.family: "Monospace"
                        color: Colors.overSurface
                        padding: 6
                        
                        onTextChanged: Config.ai.customCurlTemplate = text;
                        
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

            // Chat defaults (mode + agent)
            Text {
                text: "Chat defaults"
                font.family: Config.theme.font
                font.pixelSize: 20
                font.weight: Font.Bold
                color: Colors.overSurface
                Layout.fillWidth: true
                Layout.topMargin: 16
                Layout.bottomMargin: 8
            }

            Text {
                text: "Mode and agent applied to new chats (each chat can override these with /mode and /agent, or via the header chip)."
                font.family: Config.theme.font
                font.pixelSize: 12
                color: Colors.outline
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.bottomMargin: 4
            }

            StyledRect {
                Layout.fillWidth: true
                variant: "surface"
                radius: Styling.radius(8)
                implicitHeight: defaultsCol.implicitHeight + 32

                ColumnLayout {
                    id: defaultsCol
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Default mode"
                            font.family: Config.theme.font
                            font.pixelSize: 14
                            color: Colors.overSurface
                            Layout.fillWidth: true
                        }

                        // Two rounded pill buttons side by side
                        Row {
                            spacing: 6
                            Layout.preferredHeight: 28

                            Repeater {
                                model: [
                                    { id: "chat", label: "Chat", icon: Icons.user },
                                    { id: "agent", label: "Agent", icon: Icons.robot }
                                ]
                                delegate: Item {
                                    required property var modelData
                                    width: 96
                                    height: 28
                                    property bool isSelected: (Config.ai.defaultMode || "agent") === modelData.id

                                    StyledRect {
                                        anchors.fill: parent
                                        radius: Styling.radius(0) / 2
                                        variant: parent.isSelected ? "primary" : "common"
                                        enableShadow: parent.isSelected

                                        Behavior on variant {
                                            enabled: Anim.animationsEnabled
                                            ColorAnimation {
                                                duration: Anim.standardSmall
                                                easing.type: Anim.easing("standard").type
                                                easing.bezierCurve: Anim.easing("standard").bezierCurve
                                            }
                                        }
                                    }

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 4

                                        Text {
                                            text: modelData.icon
                                            font.family: Icons.font
                                            font.pixelSize: 12
                                            color: parent.parent.isSelected ? Colors.overPrimary : Colors.overSurface
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Text {
                                            text: modelData.label
                                            font.family: Config.theme.font
                                            font.pixelSize: 12
                                            font.weight: parent.parent.isSelected ? Font.Bold : Font.Normal
                                            color: parent.parent.isSelected ? Colors.overPrimary : Colors.overSurface
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    MouseArea {
                                        id: modeMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            Config.ai.defaultMode = modelData.id;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Default agent"
                            font.family: Config.theme.font
                            font.pixelSize: 14
                            color: Colors.overSurface
                            Layout.fillWidth: true
                        }

                        StyledRect {
                            radius: Styling.radius(4)
                            variant: "common"
                            Layout.preferredWidth: 180
                            Layout.preferredHeight: 28

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.right: parent.right
                                anchors.rightMargin: 32   // leave room for the MouseArea + caret
                                text: {
                                    let id = Config.ai.defaultAgentId || "";
                                    if (id === "") return "All agents";
                                    let conns = Ai.agentManager ? Ai.agentManager.connections : [];
                                    for (let i = 0; i < conns.length; i++) {
                                        if (conns[i] && conns[i].id === id) return conns[i].name;
                                    }
                                    return "All agents";
                                }
                                font.family: Config.theme.font
                                font.pixelSize: 12
                                color: Colors.overSurface
                                elide: Text.ElideRight
                            }

                            MouseArea {
                                id: agentDefaultMenuMouse
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.rightMargin: 8
                                width: 16
                                height: 16
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: agentDefaultMenu.expanded = !agentDefaultMenu.expanded
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.rightMargin: 8
                                text: Icons.caretDown
                                font.family: Icons.font
                                font.pixelSize: 10
                                color: Colors.outline
                            }
                        }

                        Item {
                            id: agentDefaultMenu
                            property bool expanded: false
                            Layout.preferredWidth: 180

                            StyledRect {
                                anchors.fill: dropdownDefaultColumn
                                anchors.margins: -4
                                radius: Styling.radius(4)
                                variant: "popup"
                                enableShadow: true
                                visible: agentDefaultMenu.expanded
                            }

                            Column {
                                id: dropdownDefaultColumn
                                visible: agentDefaultMenu.expanded
                                width: 180
                                spacing: 0

                                Item {
                                    width: parent.width
                                    height: 28
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        spacing: 6
                                        Text {
                                            text: Icons.list
                                            font.family: Icons.font
                                            font.pixelSize: 10
                                            color: (Config.ai.defaultAgentId || "") === "" ? Styling.srItem("overprimary") : Colors.overSurface
                                        }
                                        Text {
                                            text: "All agents"
                                            font.family: Config.theme.font
                                            font.pixelSize: 11
                                            font.weight: (Config.ai.defaultAgentId || "") === "" ? Font.Bold : Font.Normal
                                            color: (Config.ai.defaultAgentId || "") === "" ? Styling.srItem("overprimary") : Colors.overSurface
                                            Layout.fillWidth: true
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            Config.ai.defaultAgentId = "";
                                            agentDefaultMenu.expanded = false;
                                        }
                                    }
                                }

                                Rectangle {
                                    width: parent.width - 16
                                    x: 8
                                    height: 1
                                    color: Colors.outline
                                    opacity: 0.15
                                    visible: Ai.agentManager && Ai.agentManager.connections.length > 0
                                }

                                Repeater {
                                    model: Ai.agentManager ? Ai.agentManager.connections : []
                                    delegate: Item {
                                        required property var modelData
                                        width: parent.width
                                        height: 28
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            spacing: 6
                                            Text {
                                                text: modelData.status === "connected" ? Icons.accept : Icons.circle
                                                font.family: Icons.font
                                                font.pixelSize: 9
                                                color: modelData.status === "connected" ? Colors.success : Colors.outline
                                            }
                                            Text {
                                                text: modelData.name
                                                font.family: Config.theme.font
                                                font.pixelSize: 11
                                                font.weight: modelData.id === (Config.ai.defaultAgentId || "") ? Font.Bold : Font.Normal
                                                color: modelData.id === (Config.ai.defaultAgentId || "") ? Styling.srItem("overprimary") : Colors.overSurface
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                Config.ai.defaultAgentId = modelData.id;
                                                agentDefaultMenu.expanded = false;
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.leftMargin: -2000
                                anchors.rightMargin: -2000
                                z: -1
                                enabled: agentDefaultMenu.expanded
                                onClicked: agentDefaultMenu.expanded = false
                            }
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
                    
                    ToggleRow {
                        label: "Enable shell command tool"
                        description: "Lets the AI propose to run shell commands (e.g. xdg-open, ls, systemctl). You will still see an Approve / Reject card before anything actually executes."
                        checked: (Config.ai.enabledTools || []).includes("shell")
                        onToggled: value => {
                            let tools = Array.from(Config.ai.enabledTools || []);
                            if (value) {
                                if (!tools.includes("shell")) tools.push("shell");
                            } else {
                                tools = tools.filter(t => t !== "shell");
                            }
                            Config.ai.enabledTools = tools;
                        }
                    }

                    ToggleRow {
                        label: "Auto-approve allowlisted commands"
                        description: "When on, commands whose first token matches the allowlist below run without asking. When off, every shell command waits for your explicit approval."
                        checked: Config.ai.toolAutoApprove || false
                        onToggled: value => {
                            Config.ai.toolAutoApprove = value;
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
                            id: agentItem
                            required property var modelData
                            property var conn: modelData
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
                                    spacing: 6

                                    Text {
                                        text: agentItem.conn.status === "connected" ? Icons.accept : (agentItem.conn.status === "error" ? Icons.cancel : Icons.circle)
                                        font.family: Icons.font
                                        font.pixelSize: 12
                                        color: agentItem.conn.status === "connected" ? Colors.success : (agentItem.conn.status === "error" ? Colors.error : Colors.outline)
                                    }

                                    Text {
                                        text: agentItem.conn.name
                                        font.family: Config.theme.font
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        color: Colors.overSurface
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: (agentItem.conn.status || "unknown").toUpperCase()
                                        font.family: Config.theme.font
                                        font.pixelSize: 10
                                        color: agentItem.conn.status === "connected" ? Colors.success : (agentItem.conn.status === "error" ? Colors.error : Colors.outline)
                                    }
                                }

                                Text {
                                    text: {
                                        let md = agentItem.conn;
                                        let type = md.type || "";
                                        if (md.endpoint) return type + " • " + md.endpoint;
                                        if (md.command) {
                                            let args = md.args || [];
                                            let parts = [md.command].concat(args);
                                            return type + " • " + parts.join(" ");
                                        }
                                        return type;
                                    }
                                    font.family: "Monospace"
                                    font.pixelSize: 10
                                    color: Colors.outline
                                    elide: Text.ElideRight
                                    wrapMode: Text.NoWrap
                                    Layout.fillWidth: true
                                }

                                // Shell-managed process indicator. Visible only when
                                // the profile declares an embedded `process` block
                                // (the same condition that makes the Start/Stop buttons
                                // appear below). Reads `procState` / `procMessage` off
                                // the AgentConnection, both written by AgentManager.
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    visible: Ai.agentManager && Ai.agentManager.hasManagedProcess(agentItem.conn.id)

                                    Text {
                                        text: {
                                            let s = agentItem.conn.procState || "stopped";
                                            if (s === "running") return Icons.play;
                                            if (s === "starting" || s === "stopping") return Icons.circle;
                                            if (s === "error") return Icons.cancel;
                                            return Icons.pause;
                                        }
                                        font.family: Icons.font
                                        font.pixelSize: 11
                                        color: {
                                            let s = agentItem.conn.procState || "stopped";
                                            if (s === "running") return Colors.success;
                                            if (s === "error") return Colors.error;
                                            return Colors.outline;
                                        }
                                    }

                                    Text {
                                        text: "Process: " + (agentItem.conn.procState || "stopped")
                                        font.family: Config.theme.font
                                        font.pixelSize: 11
                                        color: Colors.outline
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                }

                                Text {
                                    visible: !!(agentItem.conn.procMessage)
                                    text: "⚠ " + (agentItem.conn.procMessage || "")
                                    font.family: Config.theme.font
                                    font.pixelSize: 11
                                    color: Colors.error
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }

                                Text {
                                    visible: !!(agentItem.conn.statusMessage)
                                    text: "⚠ " + (agentItem.conn.statusMessage || "")
                                    font.family: Config.theme.font
                                    font.pixelSize: 11
                                    color: Colors.error
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    visible: root.agentJsonExpanded[agentItem.conn.id] === true
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: visible ? 90 : 0
                                    color: Colors.surface
                                    radius: Styling.radius(4)
                                    border.width: 1
                                    border.color: Colors.outline

                                    ScrollView {
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        clip: true

                                        TextEdit {
                                            readOnly: true
                                            selectByMouse: true
                                            wrapMode: TextEdit.NoWrap
                                            font.family: "Monospace"
                                            font.pixelSize: 10
                                            color: Colors.overSurface
                                            text: {
                                                try { return JSON.stringify(agentItem.conn, null, 2); }
                                                catch (e) { return "Error: " + e.message; }
                                            }
                                        }
                                    }
                                }

                                Text {
                                    visible: (Ai.agentToolRegistry && agentItem.conn.status === "connected")
                                    text: {
                                        let count = 0;
                                        let tools = Ai.agentToolRegistry.tools || [];
                                        for (let i = 0; i < tools.length; i++) {
                                            if (tools[i] && tools[i]._agentId === agentItem.conn.id) count++;
                                        }
                                        return "🔧 " + count + " tool" + (count === 1 ? "" : "s") + " exposed";
                                    }
                                    font.family: Config.theme.font
                                    font.pixelSize: 11
                                    color: Colors.outline
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Button {
                                        id: connToggleBtn
                                        text: agentItem.conn.enabled ? "Disconnect" : "Connect"
                                        onClicked: {
                                            if (agentItem.conn.enabled) {
                                                Ai.agentManager.disconnectAgent(agentItem.conn.id);
                                            } else {
                                                Ai.agentManager.reconnectAgent(agentItem.conn.id);
                                            }
                                        }
                                        background: StyledRect {
                                            variant: connToggleBtn.down ? "overprimary" : (connToggleBtn.hovered ? "primaryfocus" : "primary")
                                            radius: Styling.radius(4)
                                        }
                                        contentItem: Item {
                                            implicitWidth: connToggleLabel.implicitWidth + connToggleBtn.leftPadding + connToggleBtn.rightPadding
                                            implicitHeight: connToggleLabel.implicitHeight + connToggleBtn.topPadding + connToggleBtn.bottomPadding
                                            Text {
                                                id: connToggleLabel
                                                text: connToggleBtn.text
                                                color: Colors.overPrimary
                                                font.family: Config.theme.font
                                                font.pixelSize: 11
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                anchors.fill: parent
                                                anchors.leftMargin: connToggleBtn.leftPadding
                                                anchors.rightMargin: connToggleBtn.rightPadding
                                                anchors.topMargin: connToggleBtn.topPadding
                                                anchors.bottomMargin: connToggleBtn.bottomPadding
                                            }
                                        }
                                    }

                                    // Manual Start/Stop for shell-managed processes.
                                    // Lets the user run the bridge on demand without
                                    // opening an AI session, and recover cleanly when
                                    // the child process exits unexpectedly.
                                    Button {
                                        id: procStartBtn
                                        visible: Ai.agentManager && Ai.agentManager.hasManagedProcess(agentItem.conn.id)
                                        text: {
                                            let s = agentItem.conn.procState || "stopped";
                                            if (s === "running" || s === "starting") return "Stop";
                                            return "Start";
                                        }
                                        onClicked: {
                                            let s = agentItem.conn.procState || "stopped";
                                            if (s === "running" || s === "starting") {
                                                Ai.agentManager.stopProcess(agentItem.conn.id);
                                            } else {
                                                Ai.agentManager.startProcess(agentItem.conn.id);
                                            }
                                        }
                                        background: StyledRect {
                                            variant: procStartBtn.down
                                                ? "oversecondary"
                                                : (procStartBtn.hovered ? "secondaryfocus" : "secondary")
                                            radius: Styling.radius(4)
                                        }
                                        contentItem: Item {
                                            implicitWidth: procStartLabel.implicitWidth + procStartBtn.leftPadding + procStartBtn.rightPadding
                                            implicitHeight: procStartLabel.implicitHeight + procStartBtn.topPadding + procStartBtn.bottomPadding
                                            Text {
                                                id: procStartLabel
                                                text: procStartBtn.text
                                                color: Colors.overSecondary
                                                font.family: Config.theme.font
                                                font.pixelSize: 11
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                anchors.fill: parent
                                                anchors.leftMargin: procStartBtn.leftPadding
                                                anchors.rightMargin: procStartBtn.rightPadding
                                                anchors.topMargin: procStartBtn.topPadding
                                                anchors.bottomMargin: procStartBtn.bottomPadding
                                            }
                                        }
                                    }

                                    // "Reset" — kill any orphan process holding the
                                    // agent's port and re-spawn. Surfaced when the
                                    // managed process is in `error` (the typical case
                                    // is "Address already in use" from a previous shell
                                    // session that didn't get cleaned up). On
                                    // success the button auto-hides because the new
                                    // process reports `running` instead of `error`.
                                    Button {
                                        id: procResetBtn
                                        visible: {
                                            if (!Ai.agentManager) return false;
                                            if (!Ai.agentManager.hasManagedProcess(agentItem.conn.id)) return false;
                                            let s = agentItem.conn.procState || "stopped";
                                            return s === "error";
                                        }
                                        text: "Reset"
                                        ToolTip.visible: hovered
                                        ToolTip.text: "Kill any orphaned bridge process holding the port, then respawn"
                                        onClicked: Ai.agentManager.resetProcess(agentItem.conn.id)
                                        background: StyledRect {
                                            variant: procResetBtn.down
                                                ? "overerror"
                                                : (procResetBtn.hovered ? "errorfocus" : "error")
                                            radius: Styling.radius(4)
                                        }
                                        contentItem: Item {
                                            implicitWidth: procResetLabel.implicitWidth + procResetBtn.leftPadding + procResetBtn.rightPadding
                                            implicitHeight: procResetLabel.implicitHeight + procResetBtn.topPadding + procResetBtn.bottomPadding
                                            Text {
                                                id: procResetLabel
                                                text: procResetBtn.text
                                                color: Colors.overError
                                                font.family: Config.theme.font
                                                font.pixelSize: 11
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                anchors.fill: parent
                                                anchors.leftMargin: procResetBtn.leftPadding
                                                anchors.rightMargin: procResetBtn.rightPadding
                                                anchors.topMargin: procResetBtn.topPadding
                                                anchors.bottomMargin: procResetBtn.bottomPadding
                                            }
                                        }
                                    }

                                    Button {
                                        id: editBtn
                                        text: "Edit"
                                        onClicked: root._loadConnectionIntoForm(agentItem.conn)
                                        background: StyledRect {
                                            variant: editBtn.hovered ? "primaryfocus" : "primary"
                                            radius: Styling.radius(4)
                                        }
                                        contentItem: Item {
                                            implicitWidth: editLabel.implicitWidth + editBtn.leftPadding + editBtn.rightPadding
                                            implicitHeight: editLabel.implicitHeight + editBtn.topPadding + editBtn.bottomPadding
                                            Text {
                                                id: editLabel
                                                text: editBtn.text
                                                color: Colors.overPrimary
                                                font.family: Config.theme.font
                                                font.pixelSize: 11
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                anchors.fill: parent
                                                anchors.leftMargin: editBtn.leftPadding
                                                anchors.rightMargin: editBtn.rightPadding
                                                anchors.topMargin: editBtn.topPadding
                                                anchors.bottomMargin: editBtn.bottomPadding
                                            }
                                        }
                                    }

                                    Button {
                                        id: jsonBtn
                                        text: root.agentJsonExpanded[agentItem.conn.id] ? "Hide" : "JSON"
                                        onClicked: {
                                            let id = agentItem.conn.id;
                                            let m = Object.assign({}, root.agentJsonExpanded);
                                            m[id] = !m[id];
                                            root.agentJsonExpanded = m;
                                        }
                                        background: StyledRect {
                                            variant: jsonBtn.hovered ? "focus" : "common"
                                            radius: Styling.radius(4)
                                        }
                                        contentItem: Item {
                                            implicitWidth: jsonLabel.implicitWidth + jsonBtn.leftPadding + jsonBtn.rightPadding
                                            implicitHeight: jsonLabel.implicitHeight + jsonBtn.topPadding + jsonBtn.bottomPadding
                                            Text {
                                                id: jsonLabel
                                                text: jsonBtn.text
                                                color: Colors.overSurface
                                                font.family: Config.theme.font
                                                font.pixelSize: 11
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                anchors.fill: parent
                                                anchors.leftMargin: jsonBtn.leftPadding
                                                anchors.rightMargin: jsonBtn.rightPadding
                                                anchors.topMargin: jsonBtn.topPadding
                                                anchors.bottomMargin: jsonBtn.bottomPadding
                                            }
                                        }
                                    }

                                    Button {
                                        id: removeBtn
                                        text: "Remove"
                                        onClicked: Ai.agentManager.removeConnection(agentItem.conn.id)
                                        background: StyledRect {
                                            variant: "error"
                                            radius: Styling.radius(4)
                                        }
                                        contentItem: Item {
                                            implicitWidth: removeLabel.implicitWidth + removeBtn.leftPadding + removeBtn.rightPadding
                                            implicitHeight: removeLabel.implicitHeight + removeBtn.topPadding + removeBtn.bottomPadding
                                            Text {
                                                id: removeLabel
                                                text: removeBtn.text
                                                color: Colors.overError
                                                font.family: Config.theme.font
                                                font.pixelSize: 11
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                anchors.fill: parent
                                                anchors.leftMargin: removeBtn.leftPadding
                                                anchors.rightMargin: removeBtn.rightPadding
                                                anchors.topMargin: removeBtn.topPadding
                                                anchors.bottomMargin: removeBtn.bottomPadding
                                            }
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

                        // NothingClaw — bundled HTTP bridge shipped under mcp/nothingclaw/.
                        // Endpoint matches the default port in server.py; tools/invoke paths
                        // match the stdlib HTTP routes defined there. The
                        // `process` block tells AgentManager to spawn the
                        // bridge itself when the agent is connected, so no
                        // install step is needed.
                        Button {
                            text: "+ NothingClaw"
                            onClicked: {
                                Ai.agentManager.addConnection({
                                    id: "agent_nothingclaw_" + Date.now(),
                                    name: "NothingClaw",
                                    type: "http-bridge",
                                    enabled: true,
                                    endpoint: "http://127.0.0.1:8000",
                                    headers: {},
                                    toolsPath: "/tools",
                                    invokePath: "/tools",
                                    model: "",
                                    modelHost: "http://127.0.0.1:11434",
                                    process: {
                                        command: "python3",
                                        args: [root.nothingclawServerPath],
                                        cwd: root.nothingclawDirPath
                                    }
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
                            text: "+ MCP Stdio"
                            onClicked: {
                                Ai.agentManager.addConnection({
                                    id: "agent_mcp_stdio_" + Date.now(),
                                    name: "MCP Stdio",
                                    type: "mcp-stdio",
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
                            text: "+ MCP Bridge (cmd)"
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
                            onClicked: {
                                root._clearForm();
                                newAgentName.focus = true;
                            }
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
                        id: newAgentSectionTitle
                        text: root.editingAgentId !== "" ? ("Editing: " + (newAgentName.text || "agent")) : "Manual config"
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
                        placeholderText: "Type: http-bridge | command | mcp-stdio | mcp-sse"
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

                    // ── HTTP bridge / SSE fields ───────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: newAgentType.text.trim() === "http-bridge" || newAgentType.text.trim() === "mcp-sse" || newAgentType.text.trim() === ""

                        TextField {
                            id: newAgentEndpoint
                            Layout.fillWidth: true
                            placeholderText: "Endpoint base URL (e.g. http://localhost:8080)"
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

                        TextField {
                            id: newAgentHeaders
                            Layout.fillWidth: true
                            placeholderText: "HTTP headers (JSON object, optional) — e.g. {\"Authorization\": \"Bearer xyz\"}"
                            font.family: Config.theme.font
                            color: Colors.overSurface
                            padding: 6
                            background: StyledRect {
                                variant: "internalbg"
                                radius: Styling.radius(4)
                                border.width: newAgentHeaders.activeFocus ? 2 : 0
                                Behavior on border.width { AnimatedBehavior { type: "standard"; size: "small" } }
                                border.color: Styling.srItem("primary")
                                anchors.fill: parent
                                anchors.leftMargin: -parent.padding
                                anchors.rightMargin: -parent.padding
                                anchors.topMargin: -parent.padding
                                anchors.bottomMargin: -parent.padding
                            }
                        }

                        // Capability hints — sent as X-Model-Name /
                        // X-Model-Host on the tools discovery request.
                        // Bridges that adapt their tool surface to the
                        // model (NothingClaw queries Ollama /api/show
                        // for the real parameter_size) use these to
                        // pick a tier; other agents ignore them.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            TextField {
                                id: newAgentModel
                                Layout.fillWidth: true
                                placeholderText: "Model name (e.g. qwen2.5:3b) — optional, for capability-aware tools"
                                font.family: Config.theme.font
                                color: Colors.overSurface
                                padding: 6
                                background: StyledRect {
                                    variant: "internalbg"
                                    radius: Styling.radius(4)
                                    border.width: newAgentModel.activeFocus ? 2 : 0
                                    border.color: Styling.srItem("primary")
                                    anchors.fill: parent
                                    anchors.leftMargin: -parent.padding
                                    anchors.rightMargin: -parent.padding
                                    anchors.topMargin: -parent.padding
                                    anchors.bottomMargin: -parent.padding
                                }
                            }
                            TextField {
                                id: newAgentModelHost
                                Layout.preferredWidth: 220
                                placeholderText: "Model host (optional)"
                                font.family: Config.theme.font
                                color: Colors.overSurface
                                padding: 6
                                background: StyledRect {
                                    variant: "internalbg"
                                    radius: Styling.radius(4)
                                    border.width: newAgentModelHost.activeFocus ? 2 : 0
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

                    // ── HTTP-bridge protocol reference ─────────────────────
                    // Collapsible docs showing the exact JSON
                    // contract NothingLess expects from a
                    // http-bridge agent. Hidden by default; a
                    // button toggles it.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: newAgentType.text.trim() === "http-bridge" || newAgentType.text.trim() === "mcp-sse" || newAgentType.text.trim() === ""

                        Button {
                            id: protocolInfoToggle
                            text: protocolInfoBox.visible ? "▾ Hide protocol format" : "▸ Show protocol format"
                            flat: true
                            Layout.alignment: Qt.AlignLeft
                            font.pixelSize: 11
                            contentItem: Text {
                                text: parent.text
                                color: Colors.outline
                                font.family: Config.theme.font
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignLeft
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: protocolInfoBox.visible = !protocolInfoBox.visible
                        }

                        ColumnLayout {
                            id: protocolInfoBox
                            visible: false
                            Layout.fillWidth: true
                            spacing: 8
                            Layout.leftMargin: 8
                            Layout.rightMargin: 8

                            Text {
                                text: "NothingLess discovers tools via GET {endpoint}{toolsPath} and invokes them via POST {endpoint}{invokePath}. Both paths default to /tools and /invoke."
                                color: Colors.outline
                                font.family: Config.theme.font
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }

                            Text {
                                text: "Expected /tools response (one of these shapes is accepted):"
                                color: Colors.outline
                                font.family: Config.theme.font
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                Layout.topMargin: 4
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: toolsSchemaText.implicitHeight + 16
                                color: Colors.surface
                                radius: Styling.radius(4)
                                border.width: 1
                                border.color: Colors.outline
                                opacity: 0.6

                                TextEdit {
                                    id: toolsSchemaText
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    readOnly: true
                                    selectByMouse: true
                                    wrapMode: TextEdit.Wrap
                                    font.family: "Monospace"
                                    font.pixelSize: 10
                                    color: Colors.overSurface
                                    text: '// Flat array (simplest)
[
  {
    "name": "verificar_programa",
    "description": "Check if a program is installed",
    "parameters": {
      "type": "object",
      "properties": {
        "nombre_programa": { "type": "string" }
      },
      "required": ["nombre_programa"]
    }
  }
]

// ── IMPORTANT ──
// • Use "parameters" (NOT "inputSchema" — that is the MCP
//   standard, but NothingLess reads "parameters")
// • "name", "description" and "parameters" are required for
//   the tool to be usable by the AI'
                                }
                            }

                            Text {
                                text: "Expected /invoke request and response:"
                                color: Colors.outline
                                font.family: Config.theme.font
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                Layout.topMargin: 4
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: invokeSchemaText.implicitHeight + 16
                                color: Colors.surface
                                radius: Styling.radius(4)
                                border.width: 1
                                border.color: Colors.outline
                                opacity: 0.6

                                TextEdit {
                                    id: invokeSchemaText
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    readOnly: true
                                    selectByMouse: true
                                    wrapMode: TextEdit.Wrap
                                    font.family: "Monospace"
                                    font.pixelSize: 10
                                    color: Colors.overSurface
                                    text: '// Request body (POST /invoke)
{
  "name": "verificar_programa",
  "arguments": {
    "nombre_programa": "firefox"
  }
}

// Response body
{
  "content": "El programa firefox SI esta instalado en: /usr/bin/firefox",
  "error": null
}

// On error
{
  "content": "",
  "error": "permission denied"
}

// ── IMPORTANT ──
// • "content" can also be "result" (both accepted)
// • "error" must be null on success
// • Plain text responses are also accepted'
                                }
                            }
                        }
                    }

                    // ── Command / MCP-stdio fields ────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: newAgentType.text.trim() === "command" || newAgentType.text.trim() === "mcp-stdio"

                        TextField {
                            id: newAgentCommand
                            Layout.fillWidth: true
                            placeholderText: "Command (binary, e.g. uv, python3, /usr/local/bin/mcp-server)"
                            font.family: "Monospace"
                            color: Colors.overSurface
                            padding: 6
                            background: StyledRect {
                                variant: "internalbg"
                                radius: Styling.radius(4)
                                border.width: newAgentCommand.activeFocus ? 2 : 0
                                Behavior on border.width { AnimatedBehavior { type: "standard"; size: "small" } }
                                border.color: Styling.srItem("primary")
                                anchors.fill: parent
                                anchors.leftMargin: -parent.padding
                                anchors.rightMargin: -parent.padding
                                anchors.topMargin: -parent.padding
                                anchors.bottomMargin: -parent.padding
                            }
                        }

                        Text {
                            text: "Arguments (one per line, OR paste a full shell command and use the parser)"
                            font.family: Config.theme.font
                            font.pixelSize: 11
                            color: Colors.outline
                            Layout.topMargin: 2
                        }

                        Rectangle {
                            id: newAgentArgsContainer
                            Layout.fillWidth: true
                            Layout.preferredHeight: 100
                            color: Colors.surface
                            radius: Styling.radius(4)
                            border.width: argsArea.activeFocus ? 2 : 1
                            border.color: argsArea.activeFocus ? Styling.srItem("primary") : Colors.outline
                            Behavior on border.width { AnimatedBehavior { type: "standard"; size: "small" } }

                            ScrollView {
                                anchors.fill: parent
                                anchors.margins: 2
                                clip: true

                                TextArea {
                                    id: argsArea
                                    placeholderText: "run\n--with\nmcp\nmcp\nrun\n/path/to/server.py"
                                    font.family: "Monospace"
                                    font.pixelSize: 12
                                    color: Colors.overSurface
                                    wrapMode: TextEdit.NoWrap
                                    selectByMouse: true
                                    background: null
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Button {
                                text: "Paste shell command"
                                Layout.fillWidth: true
                                onClicked: {
                                    let s = (shellPasteField.text || "").trim();
                                    if (!s) return;
                                    // First token is the command, rest are args
                                    let tokens = root._splitShellArgs(s);
                                    if (tokens.length > 0) {
                                        newAgentCommand.text = tokens[0];
                                        let argLines = [];
                                        for (let i = 1; i < tokens.length; i++)
                                            argLines.push(tokens[i]);
                                        argsArea.text = argLines.join("\n");
                                    }
                                    shellPasteField.text = "";
                                    shellPasteField.visible = false;
                                    pasteButton.visible = true;
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
                                id: pasteButton
                                text: "Show paste box"
                                onClicked: {
                                    shellPasteField.visible = !shellPasteField.visible;
                                    if (shellPasteField.visible) shellPasteField.forceActiveFocus();
                                }
                                background: StyledRect {
                                    variant: parent.hovered ? "focus" : "common"
                                    radius: Styling.radius(4)
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: Colors.overSurface
                                    font.family: Config.theme.font
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }

                        TextField {
                            id: shellPasteField
                            visible: false
                            Layout.fillWidth: true
                            placeholderText: "uv run --with mcp mcp run /path/to/server.py"
                            font.family: "Monospace"
                            color: Colors.overSurface
                            padding: 6
                            background: StyledRect {
                                variant: "internalbg"
                                radius: Styling.radius(4)
                                border.width: shellPasteField.activeFocus ? 2 : 0
                                Behavior on border.width { AnimatedBehavior { type: "standard"; size: "small" } }
                                border.color: Styling.srItem("primary")
                                anchors.fill: parent
                                anchors.leftMargin: -parent.padding
                                anchors.rightMargin: -parent.padding
                                anchors.topMargin: -parent.padding
                                anchors.bottomMargin: -parent.padding
                            }
                            onAccepted: {
                                let s = text.trim();
                                if (!s) return;
                                let tokens = root._splitShellArgs(s);
                                if (tokens.length > 0) {
                                    newAgentCommand.text = tokens[0];
                                    let argLines = [];
                                    for (let i = 1; i < tokens.length; i++)
                                        argLines.push(tokens[i]);
                                    argsArea.text = argLines.join("\n");
                                }
                                text = "";
                                visible = false;
                                pasteButton.visible = true;
                            }
                        }
                    }

                    // ── JSON preview ───────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: "JSON preview"
                                font.family: Config.theme.font
                                font.pixelSize: 11
                                color: Colors.outline
                                Layout.fillWidth: true
                            }

                            Button {
                                text: root.jsonPreviewExpanded ? "Hide" : "Show"
                                flat: true
                                onClicked: root.jsonPreviewExpanded = !root.jsonPreviewExpanded
                                contentItem: Text {
                                    text: parent.text
                                    color: Styling.srItem("overprimary")
                                    font.family: Config.theme.font
                                    font.pixelSize: 11
                                }
                            }

                            Button {
                                text: "Copy"
                                flat: true
                                onClicked: {
                                    let cfg = root._buildConfigFromForm();
                                    let json = JSON.stringify(cfg, null, 2);
                                    let p = Qt.createQmlObject('import Quickshell; import Quickshell.Io; Process { command: ["wl-copy"] }', parent);
                                    p.stdin = json;
                                    p.running = true;
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: Styling.srItem("overprimary")
                                    font.family: Config.theme.font
                                    font.pixelSize: 11
                                }
                            }
                        }

                        Rectangle {
                            visible: root.jsonPreviewExpanded
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.jsonPreviewExpanded ? 120 : 0
                            color: Colors.surface
                            radius: Styling.radius(4)
                            border.width: 1
                            border.color: Colors.outline

                            ScrollView {
                                anchors.fill: parent
                                anchors.margins: 4
                                clip: true

                                TextEdit {
                                    readOnly: true
                                    selectByMouse: true
                                    wrapMode: TextEdit.NoWrap
                                    font.family: "Monospace"
                                    font.pixelSize: 11
                                    color: Colors.overSurface
                                    text: {
                                        try {
                                            return JSON.stringify(root._buildConfigFromForm(), null, 2);
                                        } catch (e) { return "Error: " + e.message; }
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Button {
                            text: root.editingAgentId !== "" ? "Save" : "Add Agent"
                            Layout.fillWidth: true
                            onClicked: {
                                let cfg = root._buildConfigFromForm();
                                if (root.editingAgentId !== "") {
                                    Ai.agentManager.removeConnection(root.editingAgentId);
                                    root.editingAgentId = "";
                                }
                                Ai.agentManager.addConnection(cfg);
                                root._clearForm();
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
                            visible: root.editingAgentId !== ""
                            text: "Cancel"
                            Layout.preferredWidth: 100
                            onClicked: {
                                root.editingAgentId = "";
                                root._clearForm();
                            }
                            background: StyledRect {
                                variant: parent.hovered ? "focus" : "common"
                                radius: Styling.radius(4)
                            }
                            contentItem: Text {
                                text: parent.text
                                color: Colors.overSurface
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
}
