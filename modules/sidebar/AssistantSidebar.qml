import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Widgets
import qs.modules.theme
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.globals
import Quickshell
import Quickshell.Io

Item {
    id: root
    anchors.fill: parent

    required property var targetScreen

    readonly property bool active: GlobalStates.assistantVisible && targetScreen.name === GlobalStates.assistantScreenName
    property alias hitbox: sidebarContainer
    property alias hasActiveFocus: inputField.activeFocus

    readonly property bool frameEnabled: (Config.bar?.frameEnabled ?? false)
    readonly property bool frameWrapped: frameEnabled && GlobalStates.assistantPinned
    readonly property int sidebarMargin: frameWrapped ? 0 : 4
    property bool wantsFocus: false
    property bool menuExpanded: false
    property real menuWidth: 250
    property var slashCommands: [
        {
            name: "model",
            description: "Switch AI model"
        },
        {
            name: "help",
            description: "Show help"
        },
        {
            name: "new",
            description: "Start new chat"
        },
        {
            name: "key",
            description: "Set API key"
        },
        {
            name: "prompt",
            description: "Set system prompt"
        },
        {
            name: "mode",
            description: "Switch chat/agent mode"
        },
        {
            name: "agent",
            description: "Pick which agent to use"
        },
        {
            name: "agents",
            description: "List connected agents"
        },
        {
            name: "tools",
            description: "List available tools"
        }
    ]


    function focusSearchInput() {
        inputField.forceActiveFocus();
    }

    Connections {
        target: GlobalStates
        function onAssistantFocusRequested(wasAlreadyOpen) {
            if (targetScreen.name === GlobalStates.assistantScreenName) {
                Qt.callLater(() => {
                    if (wasAlreadyOpen) {
                        // It was already open. If it currently has focus, close it. Otherwise, regain focus.
                        if (root.active && root.wantsFocus && inputField.activeFocus) {
                            GlobalStates.hideAssistant();
                        } else {
                            root.wantsFocus = true;
                            focusSearchInput();
                        }
                    } else {
                        // It just opened. Just ensure it has focus.
                        root.wantsFocus = true;
                        focusSearchInput();
                    }
                });
            }
        }
    }

    onActiveChanged: {
        if (active) {
            root.wantsFocus = true;
            // Pre-warm the active Ollama model when the sidebar
            // first opens. Fires once per session (the Ai.qml side
            // dedupes via the ollama status). The user's first
            // message lands on a hot model instead of waiting
            // 5-30s for the weights to load.
            if (Ai.currentModel
                    && Ai.currentModel.provider === "ollama"
                    && Ai.ollamaStatus !== "running") {
                Ai.prewarmOllamaModel(Ai.currentModel, 30);
            }
            Qt.callLater(() => {
                focusSearchInput();
            });
        } else {
            root.wantsFocus = false;
        }
    }

    MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mouse => {
            if (!root.wantsFocus)
                root.wantsFocus = true;
            mouse.accepted = false;
        }
    }

    MouseArea {
        id: resizeHandle
        width: 8
        height: sidebarContainer.height
        y: sidebarContainer.y
        visible: sidebarContainer.visible && root.active
        cursorShape: Qt.SplitHCursor
        preventStealing: true

        x: {
            if (GlobalStates.assistantPosition === "left")
                return sidebarContainer.x + sidebarContainer.width;
            return sidebarContainer.x - width;
        }

        property real pressMouseX: 0
        property int pressWidth: 0

        onPressed: {
            let mapped = mapToItem(root, mouseX, 0);
            pressMouseX = mapped.x;
            pressWidth = GlobalStates.assistantWidth;
        }

        onMouseXChanged: {
            if (!pressed)
                return;
            let mapped = mapToItem(root, mouseX, 0);
            let delta;
            if (GlobalStates.assistantPosition === "right")
                delta = pressMouseX - mapped.x;
            else
                delta = mapped.x - pressMouseX;
            GlobalStates.assistantWidth = Math.max(300, Math.min(800, pressWidth + delta));
        }

        onReleased: {
            Config.ai.sidebarWidth = GlobalStates.assistantWidth;
        }
                        }

                        Item {
        id: sidebarContainer
        width: GlobalStates.assistantWidth + root.sidebarMargin
        height: parent.height

        x: {
            if (GlobalStates.assistantPosition === "left")
                return root.active ? 0 : -(width);
            return root.active ? parent.width - width : parent.width;
        }

        visible: root.active || slideAnimation.running

        Behavior on x {
            // Use the spatial animation profile so the sidebar slide
            // matches the rest of the shell (e.g. bar/notch flyouts).
            // AnimatedBehaviour honours Anim.animationsEnabled + the
            // active animation style — bypassing the raw Easing.OutCubic
            // ensures game mode / "disabled" styles correctly snap the
            // panel in place.
            AnimatedBehavior {
                id: slideAnimation
                type: "spatial"
                size: "default"
            }
        }

        StyledRect {
            anchors.fill: parent
            anchors.topMargin: root.sidebarMargin
            anchors.bottomMargin: root.sidebarMargin
            anchors.leftMargin: GlobalStates.assistantPosition === "left" ? root.sidebarMargin : 0
            anchors.rightMargin: GlobalStates.assistantPosition === "right" ? root.sidebarMargin : 0
            variant: root.frameWrapped ? "transparent" : "bg"

            radius: root.frameWrapped ? 0 : (variantConfig.radius !== undefined ? variantConfig.radius : Styling.radius(0))
            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8

                        Button {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            flat: true
                            padding: 0
                            contentItem: Text {
                                text: Icons.list
                                font.family: Icons.font
                                font.pixelSize: 16
                                color: root.menuExpanded ? Styling.srItem("overprimary") : Colors.overSurface
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: StyledRect {
                                variant: parent.hovered ? "focus" : "common"
                                radius: Styling.radius(4)
                                opacity: parent.hovered ? 1 : 0
                                Behavior on opacity {
                                    AnimatedBehavior { type: "standard"; size: "fast" }
                                }
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: root.menuExpanded ? "Hide chat history" : "Show chat history"
                            onClicked: root.menuExpanded = !root.menuExpanded
                        }

                        Button {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            flat: true
                            padding: 0
                            contentItem: Text {
                                text: Icons.edit
                                font.family: Icons.font
                                font.pixelSize: 16
                                color: Colors.overSurface
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: StyledRect {
                                variant: parent.hovered ? "focus" : "common"
                                radius: Styling.radius(4)
                                opacity: parent.hovered ? 1 : 0
                                Behavior on opacity {
                                    AnimatedBehavior { type: "standard"; size: "fast" }
                                }
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Start new chat"
                            onClicked: {
                                Ai.createNewChat();
                                root.menuExpanded = false;
                            }
                        }

                        Button {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            flat: true
                            padding: 0

                            contentItem: Text {
                                text: Icons.pin
                                font.family: Icons.font
                                font.pixelSize: 16
                                color: GlobalStates.assistantPinned ? Styling.srItem("overprimary") : Colors.overSurface
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            background: StyledRect {
                                variant: parent.hovered ? "focus" : "common"
                                radius: Styling.radius(4)
                                opacity: parent.hovered ? 1 : 0

                                Behavior on opacity {
                                    AnimatedBehavior { type: "standard"; size: "fast" }
                                }
                            }

                            Accessible.role: Accessible.Button
                            Accessible.name: GlobalStates.assistantPinned ? "Unpin sidebar" : "Pin sidebar"

                            onClicked: {
                                GlobalStates.assistantPinned = !GlobalStates.assistantPinned;
                                Config.ai.sidebarPinnedOnStartup = GlobalStates.assistantPinned;
                            }
                        }

                        // Chat / Agent mode selector. Click cycles
                        // between chat (no tools) and agent (tools
                        // enabled, can drive shell commands and
                        // connected agents). Long-press / right-
                        // click clears the current agent selection
                        // (sets currentAgentId back to "").
                        Button {
                            id: modeToggle
                            Layout.preferredHeight: 32
                            Layout.preferredWidth: modeRow.implicitWidth + 16
                            flat: true
                            padding: 0

                            readonly property int connectedAgents: {
                                let mgr = Ai.agentManager;
                                if (!mgr || !mgr.connections) return 0;
                                let n = 0;
                                for (let i = 0; i < mgr.connections.length; i++) {
                                    let c = mgr.connections[i];
                                    if (c && c.enabled && c.status === "connected") n++;
                                }
                                return n;
                            }

                            contentItem: RowLayout {
                                id: modeRow
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: Ai.currentMode === "agent" ? Icons.robot : Icons.chatCenteredDots
                                    font.family: Icons.font
                                    font.pixelSize: 16
                                    color: Ai.currentMode === "agent"
                                        ? (modeToggle.connectedAgents > 0 ? Styling.srItem("overprimary") : Colors.overSurface)
                                        : Colors.overSurface
                                }
                                Text {
                                    text: Ai.currentMode === "agent" ? "Agent" : "Chat"
                                    color: Ai.currentMode === "agent"
                                        ? (modeToggle.connectedAgents > 0 ? Styling.srItem("overprimary") : Colors.overSurface)
                                        : Colors.overSurface
                                    font.family: Config.theme.font
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }
                                Text {
                                    visible: Ai.currentMode === "agent" && modeToggle.connectedAgents > 0
                                    text: "· " + modeToggle.connectedAgents
                                    color: Styling.srItem("overprimary")
                                    font.family: Config.theme.font
                                    font.pixelSize: 11
                                }
                            }

                            background: StyledRect {
                                variant: parent.hovered ? "focus" : "common"
                                radius: Styling.radius(4)
                                opacity: parent.hovered ? 1 : 0

                                Behavior on opacity {
                                    AnimatedBehavior { type: "standard"; size: "fast" }
                                }
                            }

                            ToolTip.visible: hovered
                            ToolTip.delay: 400
                            ToolTip.text: Ai.currentMode === "agent"
                                ? "Agent mode: tools enabled" + (modeToggle.connectedAgents > 0 ? " (" + modeToggle.connectedAgents + " connected)" : " (no agents connected — using system tools only)") + "\nClick to switch to chat mode"
                                : "Chat mode: no tools available\nClick to switch to agent mode"

                            Accessible.role: Accessible.Button
                            Accessible.name: Ai.currentMode === "agent" ? "Switch to chat mode" : "Switch to agent mode"

                            onClicked: {
                                Ai.setMode(Ai.currentMode === "agent" ? "chat" : "agent");
                            }
                        }

                        // Agent selector — visible only in agent
                        // mode. Shows the currently-selected agent
                        // name (or "All" / "No agents" depending on
                        // state) and pops a dropdown on click. The
                        // dropdown lists every agent with its
                        // connection status dot and a check mark on
                        // the active one; picking an entry calls
                        // `Ai.setAgent(id)` which already persists
                        // the choice and rebuilds the active tool
                        // list.
                        Item {
                            id: agentSelector
                            Layout.preferredHeight: 32
                            Layout.preferredWidth: agentSelectorRow.implicitWidth + 16
                            visible: Ai.currentMode === "agent"

                            // Pre-compute agent list + count of
                            // enabled/connected. Re-evaluates when
                            // `Ai.agentManager.connections` changes
                            // (an agent connects, disconnects, is
                            // added or removed) — cheap, O(n) over
                            // the small connections array.
                            readonly property var allAgents: {
                                let mgr = Ai.agentManager;
                                if (!mgr || !mgr.connections) return [];
                                return mgr.connections;
                            }
                            readonly property int totalAgents: allAgents.length
                            readonly property int connectedAgents: {
                                let n = 0;
                                for (let i = 0; i < allAgents.length; i++) {
                                    let c = allAgents[i];
                                    if (c && c.enabled && c.status === "connected") n++;
                                }
                                return n;
                            }
                            readonly property string currentAgentName: {
                                if (Ai.currentAgentId === "") return "All";
                                for (let i = 0; i < allAgents.length; i++) {
                                    let c = allAgents[i];
                                    if (c && c.id === Ai.currentAgentId) return c.name || c.id;
                                }
                                return "All";
                            }

                            MouseArea {
                                id: agentSelectorClick
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton
                                Accessible.role: Accessible.Button
                                Accessible.name: agentSelector.totalAgents === 0
                                    ? "No agents configured"
                                    : "Active agent: " + agentSelector.currentAgentName
                                onClicked: agentSelectorMenu.popup()
                            }

                            RowLayout {
                                id: agentSelectorRow
                                anchors.centerIn: parent
                                spacing: 6

                                // Status dot — green if any agent
                                // connected, gray otherwise. Avoids
                                // the spinning icon that previously
                                // caused UI thread pressure.
                                Rectangle {
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: {
                                        if (agentSelector.totalAgents === 0)
                                            return Colors.outline;
                                        if (agentSelector.connectedAgents > 0)
                                            return Colors.primary;
                                        if (Ai.currentAgentId !== ""
                                            && agentSelector.totalAgents > 0)
                                            return Colors.error;
                                        return Colors.outline;
                                    }
                                }
                                Text {
                                    visible: agentSelector.totalAgents > 0
                                    text: agentSelector.currentAgentName
                                    color: agentSelector.connectedAgents > 0
                                        ? Styling.srItem("overprimary") : Colors.overSurface
                                    font.family: Config.theme.font
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 110
                                }
                                Text {
                                    visible: agentSelector.totalAgents === 0
                                    text: "No agents"
                                    color: Colors.outline
                                    font.family: Config.theme.font
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    font.italic: true
                                }
                                Text {
                                    text: Icons.caretDown
                                    font.family: Icons.font
                                    font.pixelSize: 10
                                    color: Colors.overSurface
                                }
                            }

                            StyledRect {
                                anchors.fill: parent
                                variant: agentSelectorClick.containsMouse ? "focus" : "common"
                                radius: Styling.radius(4)
                                opacity: agentSelectorClick.containsMouse ? 1 : 0

                                Behavior on opacity {
                                    AnimatedBehavior { type: "standard"; size: "fast" }
                                }
                            }

                            ToolTip.visible: agentSelectorClick.containsMouse
                            ToolTip.delay: 600
                            ToolTip.text: agentSelector.totalAgents === 0
                                ? "No agents configured. Add one in Settings → AI → Agents."
                                : (Ai.currentAgentId === ""
                                    ? "All agents (" + agentSelector.connectedAgents + " connected)"
                                    : "Active: " + agentSelector.currentAgentName
                                        + " (" + agentSelector.connectedAgents + " of "
                                        + agentSelector.totalAgents + " connected)")

                            // Dropdown menu. Built fresh each
                            // popup so connection status / count
                            // are always current. "All agents" is
                            // always offered; the rest come from
                            // `Ai.agentManager.connections`. Each
                            // item carries its own `onTriggered`
                            // callback because OptionsMenu delegates
                            // item clicks through that per-item
                            // property rather than a global signal.
                            OptionsMenu {
                                id: agentSelectorMenu

                                function buildItems() {
                                    let items = [];
                                    let closeFn = () => agentSelectorMenu.close();
                                    items.push({
                                        text: "All agents",
                                        icon: Ai.currentAgentId === "" ? Icons.checkCircle : "",
                                        highlightColor: Colors.overPrimary,
                                        onTriggered: () => {
                                            Ai.setAgent("");
                                            closeFn();
                                        }
                                    });
                                    items.push({ isSeparator: true });
                                    let conns = agentSelector.allAgents;
                                    for (let i = 0; i < conns.length; i++) {
                                        let c = conns[i];
                                        if (!c) continue;
                                        let capturedId = c.id;
                                        let label = c.name || c.id;
                                        if (c.status && c.status !== "connected")
                                            label += "  ·  " + c.status;
                                        items.push({
                                            text: label,
                                            icon: Ai.currentAgentId === c.id ? Icons.checkCircle : "",
                                            highlightColor: Colors.overPrimary,
                                            onTriggered: () => {
                                                Ai.setAgent(capturedId);
                                                closeFn();
                                            }
                                        });
                                    }
                                    return items;
                                }

                                items: buildItems()

                                onAboutToShow: items = buildItems()
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        Button {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            flat: true
                            padding: 0

                            contentItem: Text {
                                text: GlobalStates.assistantPosition === "right" ? Icons.caretRight : Icons.caretLeft
                                font.family: Icons.font
                                font.pixelSize: 16
                                color: Colors.overSurface
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            background: StyledRect {
                                variant: parent.hovered ? "focus" : "common"
                                radius: Styling.radius(4)
                                opacity: parent.hovered ? 1 : 0

                                Behavior on opacity {
                                    AnimatedBehavior { type: "standard"; size: "fast" }
                                }
                            }

                            Accessible.role: Accessible.Button
                            Accessible.name: "Close sidebar"

                            onClicked: GlobalStates.hideAssistant()
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Colors.outline
                        opacity: 0.15
                    }
                }

                // Status strip — disabled by default. Showing it
                // caused visible UI stalls during streaming because
                // each `streamingStatus` change re-evaluated the
                // layout (chat area shrinking/growing by 22px) and
                // cascaded ListView delegate re-layouts. The Stop
                // button in the input bar already gives the user a
                // visible signal that the AI is busy; that's enough.
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 0
                    visible: false
                    clip: true
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Item {
                        id: mainChatArea
                        anchors.fill: parent

                        property var pendingAttachments: []

                        function addAttachment(mimeType, base64Data, fileName) {
                            let list = pendingAttachments.slice();
                            list.push({
                                type: "image",
                                mimeType: mimeType,
                                base64: base64Data,
                                name: fileName
                            });
                            pendingAttachments = list;
                        }

                        function normalizeFilePath(path) {
                            let p = path ? path.trim() : "";
                            if (p.startsWith("file://"))
                                p = p.substring(7);
                            try {
                                p = decodeURIComponent(p);
                            } catch (e) {
                            }
                            return p;
                        }

                        function fileMimeForPath(path) {
                            let ext = path.split(".").pop().toLowerCase();
                            let mimeMap = {
                                png: "image/png",
                                jpg: "image/jpeg",
                                jpeg: "image/jpeg",
                                gif: "image/gif",
                                webp: "image/webp",
                                bmp: "image/bmp"
                            };
                            return mimeMap[ext] || "";
                        }

                        function addAttachmentFromFile(path) {
                            let filePath = normalizeFilePath(path);
                            if (!filePath)
                                return;
                            let mimeType = fileMimeForPath(filePath);
                            if (!mimeType) {
                                Ai.pushSystemMessage("Only image files are supported for attachments.");
                                return;
                            }
                            attachmentReadProcess.filePath = filePath;
                            attachmentReadProcess.mimeType = mimeType;
                            attachmentReadProcess.fileName = filePath.split("/").pop();
                            attachmentReadProcess.running = true;
                        }

                        function addAttachmentsFromUriList(text) {
                            let lines = text.split("\n");
                            for (let i = 0; i < lines.length; i++) {
                                let line = lines[i].trim();
                                if (line === "" || line.startsWith("#"))
                                    continue;
                                addAttachmentFromFile(line);
                            }
                        }

                        function removeAttachment(index) {
                            let list = pendingAttachments.slice();
                            list.splice(index, 1);
                            pendingAttachments = list;
                        }

                        function clearAttachments() {
                            pendingAttachments = [];
                        }
                        StyledRect {
                            id: historyPage
                            anchors.fill: parent
                            variant: "bg"
                            visible: root.menuExpanded
                            opacity: root.menuExpanded ? 1 : 0
                            z: 10

                            Behavior on opacity {
                                AnimatedBehavior { type: "standard"; size: "normal" }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 8

                                Text {
                                    text: "Chat History"
                                    color: Colors.overSurface
                                    font.family: Config.theme.font
                                    font.pixelSize: 18
                                    font.weight: Font.Bold
                                }

                                ListView {
                                    id: historyList
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    model: Ai.chatHistory
                                    spacing: 4

                                    delegate: Item {
                                        id: chatRow
                                        width: historyList.width
                                        height: 52

                                        // Per-row pending-delete state. When
                                        // the user clicks the trash button
                                        // once, the row swaps to a confirm
                                        // pair ("Delete" + "Cancel") with a
                                        // 5-second auto-reset timer so an
                                        // accidental click doesn't wipe a
                                        // chat.
                                        property bool confirmingDelete: false
                                        Timer {
                                            id: confirmTimer
                                            interval: 5000
                                            onTriggered: chatRow.confirmingDelete = false
                                        }
                                        function startConfirmDelete() {
                                            confirmingDelete = true;
                                            confirmTimer.restart();
                                        }

                                        // Animated enter / exit for the
                                        // confirm row. The confirm swap
                                        // animates opacity + a subtle slide
                                        // so it doesn't feel like a hard cut.
                                        property real confirmOpacity: confirmingDelete ? 1 : 0

                                        Behavior on confirmOpacity {
                                            AnimatedBehavior { type: "emphasized"; size: "normal"; variant: "enter" }
                                        }

                                        // ── Row body (default state) ──
                                        // We keep the row body free of colour
                                        // tricks. The trick to hide the title
                                        // and date behind the "Delete this chat?"
                                        // overlay is to fade the text itself to 0
                                        // — opacity is bound to chatRow.confirmOpacity
                                        // so the text fades out together with
                                        // the overlay fading in. Simpler than any
                                        // post-process effect, renders at every
                                        // DPI, and matches the rest of the
                                        // shell's animation style.
                                        Button {
                                            id: rowBtn
                                            anchors.fill: parent
                                            flat: true

                                            Accessible.role: Accessible.Button
                                            Accessible.name: "Open chat: " + (modelData.title || "New chat")

                                            contentItem: RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: 8

                                                Column {
                                                    Layout.fillWidth: true
                                                    Layout.alignment: Qt.AlignVCenter

                                                    Text {
                                                        id: titleText
                                                        text: modelData.title || "New Chat"
                                                        color: Ai.currentChatId === modelData.id
                                                            ? Styling.srItem("primary") : Colors.overSurface
                                                        font.family: Config.theme.font
                                                        font.pixelSize: 14
                                                        font.weight: Font.Medium
                                                        elide: Text.ElideRight
                                                        width: parent.width
                                                        opacity: 1.0
                                                            - chatRow.confirmOpacity
                                                        Behavior on opacity {
                                                            AnimatedBehavior { type: "emphasized"; size: "normal"; variant: "exit" }
                                                        }
                                                    }

                                                    Text {
                                                        id: dateText
                                                        text: {
                                                            let date = new Date(parseInt(modelData.id));
                                                            return date.toLocaleString(Qt.locale(), "MMM dd, hh:mm a");
                                                        }
                                                        color: Ai.currentChatId === modelData.id
                                                            ? Styling.srItem("primary") : Colors.outline
                                                        font.family: Config.theme.font
                                                        font.pixelSize: 11
                                                        elide: Text.ElideRight
                                                        width: parent.width
                                                        opacity: 1.0
                                                            - chatRow.confirmOpacity
                                                        Behavior on opacity {
                                                            AnimatedBehavior { type: "emphasized"; size: "normal"; variant: "exit" }
                                                        }
                                                    }
                                                }

                                                Button {
                                                    visible: rowBtn.hovered
                                                            && !chatRow.confirmingDelete
                                                    flat: true
                                                    Layout.preferredWidth: 28
                                                    Layout.preferredHeight: 28

                                                    Accessible.role: Accessible.Button
                                                    Accessible.name: "Delete chat"

                                                    contentItem: Text {
                                                        text: Icons.trash
                                                        font.family: Icons.font
                                                        color: parent.hovered ? Colors.error : Colors.outline
                                                        font.pixelSize: 14
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                        Behavior on color {
                                                            AnimatedBehavior { type: "standard"; size: "fast" }
                                                        }
                                                    }

                                                    background: null
                                                    onClicked: chatRow.startConfirmDelete()
                                                }
                                            }

                                            background: StyledRect {
                                                variant: Ai.currentChatId === modelData.id
                                                    ? "focus"
                                                    : (parent.hovered ? "surfaceVariant" : "transparent")
                                                radius: Styling.radius(6)
                                            }

                                            onClicked: {
                                                if (chatRow.confirmingDelete) return;
                                                Ai.loadChat(modelData.id);
                                                root.menuExpanded = false;
                                            }
                                        }

                                        // ── Confirm-delete overlay ──
                                        // Absolute-positioned so it overlays
                                        // the row body. The row body beneath
                                        // is blurred via MultiEffect on its
                                        // own layer (see `rowBody` above), so
                                        // the title/date text becomes illegible
                                        // while the user is making the delete
                                        // decision. On top of that blur we
                                        // paint a tinted error backdrop so the
                                        // overlay reads as a destructive action
                                        // even when the blur is small.
                                        Rectangle {
                                            id: confirmOverlay
                                            anchors.fill: parent
                                            radius: Styling.radius(6)
                                            color: Colors.error
                                            opacity: chatRow.confirmOpacity * 0.22

                                            Behavior on opacity {
                                                AnimatedBehavior { type: "emphasized"; size: "normal"; variant: "enter" }
                                            }
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 8
                                            opacity: chatRow.confirmOpacity
                                            visible: chatRow.confirmOpacity > 0.01

                                            Text {
                                                Layout.fillWidth: true
                                                Layout.leftMargin: 8
                                                text: "Delete this chat?"
                                                color: Colors.overError
                                                font.family: Config.theme.font
                                                font.pixelSize: 12
                                                font.weight: Font.Medium
                                                verticalAlignment: Text.AlignVCenter
                                            }

                                            Button {
                                                text: "Cancel"
                                                flat: true
                                                Accessible.role: Accessible.Button
                                                Accessible.name: "Cancel delete"

                                                background: StyledRect {
                                                    variant: "transparent"
                                                    radius: Styling.radius(4)
                                                    border.width: 1
                                                    border.color: Colors.outline
                                                }

                                                contentItem: Text {
                                                    text: parent.text
                                                    color: Colors.overSurface
                                                    font.family: Config.theme.font
                                                    font.pixelSize: 11
                                                    font.weight: Font.Medium
                                                    horizontalAlignment: Text.AlignHCenter
                                                    verticalAlignment: Text.AlignVCenter
                                                }

                                                onClicked: {
                                                    chatRow.confirmingDelete = false;
                                                    confirmTimer.stop();
                                                }
                                            }

                                            Button {
                                                text: "Delete"
                                                flat: true
                                                Accessible.role: Accessible.Button
                                                Accessible.name: "Confirm delete chat"

                                                background: StyledRect {
                                                    variant: "error"
                                                    radius: Styling.radius(4)
                                                }

                                                contentItem: Text {
                                                    text: parent.text
                                                    color: Colors.overError
                                                    font.family: Config.theme.font
                                                    font.pixelSize: 11
                                                    font.weight: Font.Medium
                                                    horizontalAlignment: Text.AlignHCenter
                                                    verticalAlignment: Text.AlignVCenter
                                                }

                                                onClicked: {
                                                    Ai.deleteChat(modelData.id);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        property int retryIndex: -1
                        property string username: ""

                        Process {
                            running: true
                            command: ["whoami"]
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    let user = text.trim();
                                    if (user) {
                                        mainChatArea.username = user.charAt(0).toUpperCase() + user.slice(1);
                                    }
                                }
                            }
                        }

                        Process {
                            id: zenityProcess
                            command: ["zenity", "--file-selection", "--file-filter=Images | *.png *.jpg *.jpeg *.gif *.webp *.bmp", "--file-filter=All files | *"]
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    let filePath = text.trim();
                                    if (filePath.length > 0)
                                        mainChatArea.addAttachmentFromFile(filePath);
                                }
                            }
                        }

                        Process {
                            id: attachmentReadProcess
                            property string filePath: ""
                            property string mimeType: ""
                            property string fileName: ""
                            command: ["bash", "-c", "/usr/bin/base64 -w 0 '" + filePath.replace(/'/g, "'\\''") + "'"]
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    let data = text.trim();
                                    if (data.length > 0)
                                        mainChatArea.addAttachment(attachmentReadProcess.mimeType, data, attachmentReadProcess.fileName);
                                    else if (attachmentReadProcess.filePath.length > 0)
                                        Ai.pushSystemMessage("Failed to read attachment data.");
                                }
                            }
                            stderr: StdioCollector {
                                id: attachmentReadStderr
                            }
                            onExited: exitCode => {
                                if (exitCode !== 0) {
                                    let errorText = attachmentReadStderr.text.trim();
                                    Ai.pushSystemMessage("Failed to read attachment: " + (errorText.length > 0 ? errorText : "unknown error"));
                                }
                            }
                        }

                        Process {
                            id: clipboardTypesProcess
                            command: ["wl-paste", "--list-types"]
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    let types = text.trim().split("\n");
                                    let imageType = "";
                                    for (let i = 0; i < types.length; i++) {
                                        if (types[i].startsWith("image/")) {
                                            imageType = types[i].trim();
                                            break;
                                        }
                                    }
                                    if (imageType.length > 0) {
                                        clipboardImageProcess.mimeType = imageType;
                                        clipboardImageProcess.running = true;
                                        return;
                                    }
                                    if (types.indexOf("text/uri-list") !== -1) {
                                        clipboardUrisProcess.running = true;
                                        return;
                                    }
                                    Ai.pushSystemMessage("Clipboard does not contain an image or file.");
                                }
                            }
                            stderr: StdioCollector {
                                id: clipboardTypesStderr
                            }
                            onExited: exitCode => {
                                if (exitCode !== 0) {
                                    let err = clipboardTypesStderr.text.trim();
                                    Ai.pushSystemMessage("Clipboard read failed: " + (err.length > 0 ? err : "unknown error"));
                                }
                            }
                        }

                        Process {
                            id: clipboardImageProcess
                            property string mimeType: ""
                            command: ["bash", "-c", "wl-paste --type \"" + mimeType + "\" 2>/dev/null | /usr/bin/base64 -w 0" ]
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    let data = text.trim();
                                    if (data.length > 0) {
                                        let ext = clipboardImageProcess.mimeType.split("/")[1] || "png";
                                        mainChatArea.addAttachment(clipboardImageProcess.mimeType, data, "clipboard." + ext);
                                    } else {
                                        Ai.pushSystemMessage("Clipboard image read returned no data.");
                                    }
                                }
                            }
                            stderr: StdioCollector {
                                id: clipboardImageStderr
                            }
                            onExited: exitCode => {
                                if (exitCode !== 0) {
                                    let err = clipboardImageStderr.text.trim();
                                    Ai.pushSystemMessage("Clipboard image read failed: " + (err.length > 0 ? err : "unknown error"));
                                }
                            }
                        }

                        Process {
                            id: clipboardUrisProcess
                            command: ["wl-paste", "--type", "text/uri-list"]
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    let data = text.trim();
                                    if (data.length > 0)
                                        mainChatArea.addAttachmentsFromUriList(data);
                                    else
                                        Ai.pushSystemMessage("Clipboard file list is empty.");
                                }
                            }
                            stderr: StdioCollector {
                                id: clipboardUrisStderr
                            }
                            onExited: exitCode => {
                                if (exitCode !== 0) {
                                    let err = clipboardUrisStderr.text.trim();
                                    Ai.pushSystemMessage("Clipboard file read failed: " + (err.length > 0 ? err : "unknown error"));
                                }
                            }
                        }
                        property bool isWelcome: Ai.currentChat.length === 0

                        // ── Status banner ─────────────────────────────────
                        // Sits between the chat list and the input bar so it
                        // can grow/shrink without affecting chatView's layout.
                        // Shows four distinct states:
                        //   • thinking    — pre-stream warmup (DeepSeek R1, etc.)
                        //   • streaming   — tokens arriving
                        //   • runningTool — agent tool invoked (e.g. list_windows)
                        //   • awaitingApproval — tool call needs user OK
                        // The banner animates in/out with a single opacity +
                        // height pair so we don't get a layout-stall cascade
                        // (the original status strip was disabled for that
                        // reason). The icon + label swap inside it without
                        // touching the parent's height.
                        // ── Text-only-mode pill ─────────────────────────
                        // Persistent indicator shown when the active
                        // model has been flagged `forceTextOnly` by
                        // the capability probe. The streaming status
                        // banner above handles the "what's happening
                        // right now" feedback; this handles "what mode
                        // are we in" feedback. Two separate concerns,
                        // two separate pills.
                        Item {
                            id: textOnlyPill
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: inputContainer.top
                            anchors.bottomMargin: statusBanner.visible
                                ? statusBanner.height + 12 : 6
                            width: pillRow.implicitWidth + 24
                            height: visible ? 24 : 0
                            visible: statusBanner.textOnlyMode
                            opacity: visible ? 1 : 0
                            clip: true
                            z: 4

                            Behavior on opacity {
                                AnimatedBehavior { type: "standard"; size: "fast" }
                            }
                            Behavior on height {
                                AnimatedBehavior { type: "spatial"; size: "fast" }
                            }
                            Behavior on anchors.bottomMargin {
                                AnimatedBehavior { type: "spatial"; size: "fast" }
                            }

                            StyledRect {
                                anchors.fill: parent
                                variant: "internalbg"
                                radius: Styling.radius(12)

                                RowLayout {
                                    id: pillRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        text: Icons.textAa
                                        font.family: Icons.font
                                        font.pixelSize: 11
                                        color: Colors.outline
                                    }
                                    Text {
                                        text: "Text-only mode · model too small for tools"
                                        color: Colors.outline
                                        font.family: Config.theme.font
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                    }
                                }
                            }
                        }

                        Item {
                            id: statusBanner
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: textOnlyPill.visible
                                ? textOnlyPill.top : inputContainer.top
                            anchors.bottomMargin: 6
                            width: Math.min(parent.width - 24, inputContainer.width)
                            height: visible ? 32 : 0
                            visible: _aiState !== "idle"
                            opacity: visible ? 1 : 0
                            clip: true
                            z: 5

                            Behavior on opacity {
                                AnimatedBehavior { type: "standard"; size: "fast" }
                            }
                            Behavior on height {
                                AnimatedBehavior { type: "spatial"; size: "fast" }
                            }

                            // Map (isLoading, streamingStatus, pendingToolCall)
                            // to a single state enum. Avoids brittle string
                            // matching at every call site below.
                            readonly property string _aiState: {
                                if (!Ai.isLoading) return "idle";
                                let s = Ai.streamingStatus || "";
                                if (s.indexOf("awaiting") === 0) return "awaitingApproval";
                                if (s.indexOf("running tool") === 0) return "runningTool";
                                if (s.indexOf("launched") === 0) return "launched";
                                if (s.indexOf("timed out") >= 0
                                        || s.indexOf("exceeded") >= 0
                                        || s.indexOf("Network") >= 0
                                        || s.indexOf("Error") >= 0) return "error";
                                if (s.indexOf("streaming") === 0) return "streaming";
                                // isLoading=true with no recognised status =
                                // pre-stream warmup (model is preparing its
                                // first token). Show a "thinking" affordance.
                                return "thinking";
                            }

                            // True when the active model has been flagged
                            // `forceTextOnly` by the capability probe —
                            // either because Ollama reports a tiny parameter
                            // count (≤2B, e.g. Gemma2:2b / qwen2.5:0.5b)
                            // or because recordOutcome() saw an empty
                            // response with tools in the request body. The
                            // sidebar shows a persistent text-only pill so
                            // the user understands why their agent-mode
                            // commands run without tool calls.
                            readonly property bool textOnlyMode:
                                Ai.activeCapabilities
                                    && Ai.activeCapabilities.supportsTools === false

                            // Tool name when running a tool — pulled from
                            // pendingToolCall.functionCall.name first (more
                            // reliable than parsing the streamingStatus text).
                            readonly property string _toolName: {
                                if (Ai.pendingToolCall && Ai.pendingToolCall._calls
                                        && Ai.pendingToolCall._calls.length > 0) {
                                    let c = Ai.pendingToolCall._calls[0];
                                    if (c && c.function && c.function.name)
                                        return c.function.name;
                                }
                                let s = Ai.streamingStatus || "";
                                let m = s.match(/running tool:\s*(.+)/);
                                return m ? m[1] : "";
                            }

                            StyledRect {
                                anchors.fill: parent
                                variant: statusBanner._aiState === "error"
                                    ? "error"
                                    : (statusBanner._aiState === "awaitingApproval"
                                        ? "primary"
                                        : "internalbg")
                                radius: Styling.radius(6)
                                enableShadow: statusBanner._aiState === "error"
                                    || statusBanner._aiState === "awaitingApproval"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 8

                                    // ── Leading icon ──
                                    //
                                    // Each state has its own visual: animated
                                    // dot for streaming, spinner for tool
                                    // run, pulsing outline for approval,
                                    // warning for error. Animations respect
                                    // Anim.animationsEnabled (game mode).
                                    Item {
                                        Layout.preferredWidth: 16
                                        Layout.preferredHeight: 16

                                        // Spinner (runningTool / thinking).
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 12
                                            height: 12
                                            radius: 6
                                            visible: statusBanner._aiState === "runningTool"
                                                    || statusBanner._aiState === "thinking"
                                            color: "transparent"
                                            border.width: 2
                                            border.color: statusBanner._aiState === "error"
                                                ? Colors.error : Colors.primary
                                            RotationAnimation on rotation {
                                                from: 0; to: 360
                                                loops: Animation.Infinite
                                                duration: 900
                                                running: parent.visible && Anim.animationsEnabled
                                            }
                                        }

                                        // Pulsing dot (streaming).
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 8
                                            height: 8
                                            radius: 4
                                            visible: statusBanner._aiState === "streaming"
                                                    || statusBanner._aiState === "launched"
                                            color: Colors.primary
                                            SequentialAnimation on opacity {
                                                loops: Animation.Infinite
                                                running: parent.visible && Anim.animationsEnabled
                                                NumberAnimation { to: 1.0; duration: 500; easing.type: Easing.InOutQuad }
                                                NumberAnimation { to: 0.4; duration: 500; easing.type: Easing.InOutQuad }
                                            }
                                        }

                                        // Warning glyph (error).
                                        Text {
                                            anchors.centerIn: parent
                                            visible: statusBanner._aiState === "error"
                                            text: Icons.warningCircle
                                            font.family: Icons.font
                                            font.pixelSize: 14
                                            color: Colors.overError
                                        }

                                        // Hand glyph (awaitingApproval).
                                        Text {
                                            anchors.centerIn: parent
                                            visible: statusBanner._aiState === "awaitingApproval"
                                            text: Icons.hand
                                            font.family: Icons.font
                                            font.pixelSize: 13
                                            color: Colors.overPrimary

                                            SequentialAnimation on scale {
                                                loops: Animation.Infinite
                                                running: parent.visible && Anim.animationsEnabled
                                                NumberAnimation {
                                                    from: 1.0; to: 1.18
                                                    duration: 700
                                                    easing.type: Easing.InOutQuad
                                                }
                                                NumberAnimation {
                                                    from: 1.18; to: 1.0
                                                    duration: 700
                                                    easing.type: Easing.InOutQuad
                                                }
                                            }
                                        }
                                    }

                                    // ── Status text ──
                                    Text {
                                        Layout.fillWidth: true
                                        text: {
                                            switch (statusBanner._aiState) {
                                            case "streaming":
                                                return "Streaming"
                                                    + (Ai.streamingContent
                                                        ? "  ·  " + Ai.streamingContent.length + " chars"
                                                        : "");
                                            case "thinking":
                                                return "Thinking…";
                                            case "runningTool":
                                                return "Running tool"
                                                    + (statusBanner._toolName
                                                        ? "  ·  " + statusBanner._toolName : "");
                                            case "awaitingApproval":
                                                return "Awaiting your approval"
                                                    + (statusBanner._toolName
                                                        ? "  ·  " + statusBanner._toolName : "");
                                            case "launched":
                                                return "Launched"
                                                    + (statusBanner._toolName
                                                        ? "  ·  " + statusBanner._toolName : "");
                                            case "error":
                                                return "Error — click Stop to cancel";
                                            default:
                                                return "";
                                            }
                                        }
                                        color: statusBanner._aiState === "error"
                                            ? Colors.overError
                                            : (statusBanner._aiState === "awaitingApproval"
                                                ? Colors.overPrimary
                                                : Colors.overSurface)
                                        font.family: Config.theme.font
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }

                                    // Elapsed-seconds badge (only for long
                                    // streaming / tool runs — surfaces
                                    // stalls without nagging on quick replies).
                                    Text {
                                        visible: {
                                            let s = Ai.streamingStatus || "";
                                            let m = s.match(/(\d+)s/);
                                            return m && parseInt(m[1]) >= 8;
                                        }
                                        text: {
                                            let s = Ai.streamingStatus || "";
                                            let m = s.match(/(\d+)s/);
                                            return m ? m[1] + "s" : "";
                                        }
                                        color: statusBanner._aiState === "error"
                                            ? Colors.overError : Colors.outline
                                        font.family: "Monospace"
                                        font.pixelSize: 11
                                        font.weight: Font.Medium
                                    }
                                }
                            }
                        }

                        // ── Welcome screen ─────────────────────────────────
                        // Welcome screen — minimal centered greeting.
                        // Shown only while the current chat is empty.
                        ColumnLayout {
                            anchors.bottom: inputContainer.top
                            anchors.bottomMargin: 24
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: mainChatArea.isWelcome
                            spacing: 8

                            Text {
                                text: "Hello, <font color='" + Styling.srItem("overprimary") + "'>" + mainChatArea.username + "</font>."
                                font.family: Config.theme.font
                                font.pixelSize: 32
                                font.weight: Font.Bold
                                textFormat: Text.StyledText
                                Layout.alignment: Qt.AlignHCenter
                                color: Colors.overBackground
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                height: 40

                                Text {
                                    text: Ai.currentModel ? Ai.currentModel.name : ""
                                    color: Colors.overBackground
                                    font.family: Config.theme.font
                                    font.pixelSize: 16
                                    font.weight: Font.Bold
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                visible: false
                            }

                            ListView {
                                id: chatView
                                visible: !mainChatArea.isWelcome
                                cacheBuffer: 1000
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                model: Ai.currentChat
                                spacing: 16
                                displayMarginBeginning: 40
                                displayMarginEnd: 40
                                // reuseItems disabled: QML anchor bindings are
                                // evaluated only at component creation, so
                                // reused delegates keep the anchors of the
                                // first model item they showed.  Recreating
                                // delegates is slightly slower during streaming
                                // but the positioning stays correct.
                                reuseItems: false
                                pixelAligned: true

                                bottomMargin: mainChatArea.isWelcome
                                    ? 0
                                    : inputContainer.height
                                          + (statusBanner.visible ? statusBanner.height + 6 : 0)
                                          + (textOnlyPill.visible ? textOnlyPill.height + 6 : 0)

                                // ── "Stick to bottom" behaviour ─────────────────
                                // The chat follows new messages by default. When the
                                // user scrolls up to read history we honour that and
                                // stop yanking them down on every token; a small
                                // "↓ Latest" button lets them re-anchor when ready.
                                property bool _stickToBottom: true
                                property bool _userScrolledUp: false
                                readonly property real _maxContentY: Math.max(0, contentHeight - height)
                                readonly property real _distanceFromBottom: _maxContentY - contentY
                                readonly property bool _atBottom: _distanceFromBottom < 4

                                // Smooth scroll animation. We don't bind it via
                                // `Behavior on contentY` because that would also
                                // fire on every WheelHandler tick from the user —
                                // which would feel laggy. Instead we explicitly
                                // start it from `_animateToBottom`.
                                NumberAnimation {
                                    id: contentYAnim
                                    target: chatView
                                    property: "contentY"
                                    duration: Anim.standardNormal
                                    easing.type: Easing.OutCubic
                                    easing.bezierCurve: Anim.easing("standard").bezierCurve
                                    // If the user grabs the scrollbar / wheel mid-
                                    // animation, kill it so the gesture feels direct.
                                    onStarted: chatView._userScrolledUp = false
                                }

                                function _animateToBottom(immediate) {
                                    if (!visible || height <= 0 || count === 0) return;
                                    const target = chatView._maxContentY;
                                    if (Math.abs(contentY - target) < 1) {
                                        contentY = target;
                                        return;
                                    }
                                    if (immediate || !Anim.animationsEnabled) {
                                        contentYAnim.stop();
                                        contentY = target;
                                        return;
                                    }
                                    contentYAnim.stop();
                                    contentYAnim.from = contentY;
                                    contentYAnim.to = target;
                                    contentYAnim.start();
                                }

                                // Detect the user scrolling away from the bottom.
                                // We only flip _stickToBottom to false once the
                                // gesture is settled (movementEnded) so a tiny
                                // jitter at the bottom doesn't disable the
                                // auto-follow.
                                onMovementEnded: {
                                    if (!_atBottom) {
                                        _userScrolledUp = true;
                                        _stickToBottom = false;
                                    } else if (_userScrolledUp) {
                                        // User scrolled back to the bottom manually
                                        // — re-engage stickiness.
                                        _stickToBottom = true;
                                        _userScrolledUp = false;
                                    }
                                }

                                // New messages arrive. SNAP to the bottom — don't animate.
                                //
                                // Rationale: when the AI message finalises or a new user message
                                // lands, contentHeight usually jumps by hundreds of pixels (markdown
                                // re-render, code block collapse, etc.). Animating across that much
                                // distance feels like the chat is fighting against the user; a clean
                                // snap matches the expected behaviour of ChatGPT / Claude / Gemini
                                // and removes the "se va hacia arriba de golpe" jolt. Streaming
                                // tokens still animate smoothly via the streaming follower below.
                                onCountChanged: {
                                    if (_stickToBottom && visible && height > 0 && count > 0) {
                                        // callLater so the new delegate is laid
                                        // out before the centering read its
                                        // position. Centering (not End) is
                                        // the user's preferred behaviour: the
                                        // new message lands in the middle of
                                        // the viewport, not glued to the
                                        // bottom edge.
                                        Qt.callLater(function() {
                                            positionViewAtIndex(count - 1, ListView.Center);
                                        });
                                    }
                                }

                                // Streaming follower — centers the last
                                // delegate at ~30 fps while the AI is
                                // streaming. Using positionViewAtIndex(idx,
                                // ListView.Center) keeps the message being
                                // typed in the middle of the viewport instead
                                // of pinned to the bottom edge, which the
                                // user finds easier to read while tokens
                                // are arriving.
                                Timer {
                                    id: streamFollower
                                    interval: 32
                                    repeat: true
                                    running: chatView._stickToBottom
                                            && !chatView._userScrolledUp
                                            && Ai.isLoading
                                            && chatView.visible
                                            && chatView.count > 0
                                    onTriggered: chatView.positionViewAtIndex(
                                        chatView.count - 1, ListView.Center)
                                }

                                // Final-snap on stream completion. When the
                                // AI finishes, isLoading goes true→false and
                                // the streaming follower above stops. But the
                                // last message is typically re-rendered at
                                // that moment — raw text collapses into
                                // Markdown, code blocks fold/unfold, tool
                                // result cards lay out — which can grow the
                                // delegate by hundreds of px after the
                                // follower has already stopped. Without this
                                // catch the chat ends up parked mid-content
                                // and the message can drift away from the
                                // viewport center.
                                Connections {
                                    target: Ai
                                    function onIsLoadingChanged() {
                                        if (!Ai.isLoading
                                                && chatView._stickToBottom
                                                && !chatView._userScrolledUp
                                                && chatView.visible
                                                && chatView.count > 0) {
                                            // Two snaps, ~32 ms apart, so we
                                            // catch both the first layout pass
                                            // (Markdown expansion) and any
                                            // follow-up relayout (code-block
                                            // syntax highlighting).
                                            Qt.callLater(function() {
                                                chatView.positionViewAtIndex(
                                                    chatView.count - 1,
                                                    ListView.Center);
                                                Qt.callLater(function() {
                                                    chatView.positionViewAtIndex(
                                                        chatView.count - 1,
                                                        ListView.Center);
                                                });
                                            });
                                        }
                                    }
                                }

                                // Reset stickiness when the user switches chats
                                // — new chat should anchor to the bottom.
                                Connections {
                                    target: Ai
                                    function onCurrentChatIdChanged() {
                                        chatView._stickToBottom = true;
                                        chatView._userScrolledUp = false;
                                        // Center the last message of the new
                                        // chat (matches the rest of the chat
                                        // behaviour) instead of pinning to
                                        // the bottom.
                                        Qt.callLater(function() {
                                            if (chatView.count > 0)
                                                chatView.positionViewAtIndex(
                                                    chatView.count - 1,
                                                    ListView.Center);
                                        });
                                    }
                                }

                                // Initial layout pass: center the last
                                // message (no animation — avoids a 240 ms
                                // slide on chat reopen).
                                Component.onCompleted: Qt.callLater(function() {
                                    if (count > 0)
                                        positionViewAtIndex(count - 1, ListView.Center);
                                })

                                // (jump-to-bottom button is hoisted out of
                                // chatView below — anchoring inside the
                                // ListView made it clip against the view's
                                // own bounds and sometimes disappear off-
                                // screen entirely.)

                                delegate: Item {
                                    id: messageDelegate
                                    required property var modelData
                                    required property int index

                                    property bool isUser: modelData.role === "user"
                                    property bool isSystem: modelData.role === "system" || modelData.role === "function"
                                    property bool isFunctionResult: modelData.role === "function"
                                    property bool isEditing: false
                                    property bool retryMode: false

                                    // Tool results collapse by default to avoid
                                    // saturating the screen with long command output.
                                    // Click the header to expand/collapse.
                                    property bool toolResultCollapsed: isFunctionResult

                                    // True for the last assistant message while tokens are
                                    // still arriving. In that state we render plain text
                                    // instead of the full Markdown/CodeBlock pipeline to
                                    // avoid re-creating Repeater/Loader/CodeBlock instances
                                    // on every streaming update.
                                    readonly property bool isStreamingLast: index === ListView.view.count - 1
                                        && modelData.role === "assistant"
                                        && Ai.isLoading
                                        && (Ai.streamingStatus === "" || Ai.streamingStatus.indexOf("streaming") === 0)

                                    // Cached markdown split so the regex is not re-run on
                                    // every ListView re-layout while streaming. While the
                                    // message is still streaming we keep the parts empty —
                                    // the plain-text TextEdit is shown instead.
                                    property var _contentParts: messageDelegate.isStreamingLast ? [] : _splitContent(modelData.content || "")
                                    function _splitContent(txt) {
                                        let parts = [];
                                        if (!txt) return parts;
                                        let regex = /```(\w*)\n([\s\S]*?)```/g;
                                        let lastIndex = 0;
                                        let match;
                                        while ((match = regex.exec(txt)) !== null) {
                                            if (match.index > lastIndex) {
                                                parts.push({ type: "text", content: txt.substring(lastIndex, match.index), language: "" });
                                            }
                                            parts.push({ type: "code", content: match[2].trim(), language: match[1] || "text" });
                                            lastIndex = regex.lastIndex;
                                        }
                                        if (lastIndex < txt.length) {
                                            parts.push({ type: "text", content: txt.substring(lastIndex), language: "" });
                                        }
                                        if (parts.length === 0) parts.push({ type: "text", content: txt, language: "" });
                                        return parts;
                                    }

                                    width: ListView.view.width
                                    height: bubbleArea.height + 8

                                    Row {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.margins: 10
                                        layoutDirection: (isUser && !isSystem) ? Qt.RightToLeft : Qt.LeftToRight
                                        spacing: 12
                                        clip: true

                                        Item {
                                            width: 32
                                            height: 32
                                            visible: !isSystem

                                            StyledRect {
                                                anchors.fill: parent
                                                radius: Styling.radius(16)
                                                variant: "primary"
                                                visible: !isUser

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: Icons.robot
                                                    font.family: Icons.font
                                                    color: Colors.overPrimary
                                                    font.pixelSize: 20
                                                }
                                            }

                                            ClippingRectangle {
                                                anchors.fill: parent
                                                radius: Styling.radius(16)
                                                color: Colors.surfaceDim
                                                visible: isUser

                                                Image {
                                                    mipmap: true
                                                    anchors.fill: parent
                                                    source: "file://" + Quickshell.env("HOME") + "/.face.icon"
                                                    fillMode: Image.PreserveAspectCrop

                                                    onStatusChanged: {
                                                        if (status === Image.Error) {
                                                            source = "";
                                                        }
                                                    }

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: Icons.user
                                                        font.family: Icons.font
                                                        color: Colors.overPrimary
                                                        visible: parent.status !== Image.Ready
                                                    }
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: bubbleArea
                                            width: parent.width
                                            height: Math.max(bubble.height, 32) + (modelIndicator.visible ? modelIndicator.implicitHeight + 4 : 0)
                                            hoverEnabled: true
                                            acceptedButtons: Qt.NoButton

                                            Row {
                                                anchors.verticalCenter: bubble.verticalCenter
                                                anchors.left: isUser ? undefined : bubble.right
                                                anchors.right: isUser ? bubble.left : undefined
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 4
                                                visible: bubbleArea.containsMouse || messageDelegate.isEditing

                                                Button {
                                                    width: 24
                                                    height: 24
                                                    flat: true
                                                    padding: 0
                                                    visible: !isSystem

                                                    property bool isHovered: hovered

                                                    contentItem: Text {
                                                        text: messageDelegate.isEditing ? Icons.accept : Icons.edit
                                                        font.family: Icons.font
                                                        color: parent.down ? Colors.overPrimary : (parent.isHovered ? Colors.overSurface : Colors.overSurface)
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }

                                                    background: StyledRect {
                                                        variant: parent.down ? "primary" : (parent.isHovered ? "focus" : "common")
                                                        radius: Styling.radius(4)
                                                    }

                                                    onClicked: {
                                                        if (messageDelegate.isEditing) {
                                                            Ai.updateMessage(index, bubbleContentText.text);
                                                            messageDelegate.isEditing = false;
                                                        } else {
                                                            messageDelegate.isEditing = true;
                                                            bubbleContentText.forceActiveFocus();
                                                            bubbleContentText.cursorPosition = bubbleContentText.text.length;
                                                        }
                                                    }
                                                }

                                                Button {
                                                    width: 24
                                                    height: 24
                                                    flat: true
                                                    padding: 0
                                                    visible: !messageDelegate.isEditing

                                                    property bool isHovered: hovered

                                                    contentItem: Text {
                                                        text: Icons.copy
                                                        font.family: Icons.font
                                                        color: parent.down ? Colors.overPrimary : (parent.isHovered ? Colors.overSurface : Colors.overSurface)
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }

                                                    background: StyledRect {
                                                        variant: parent.down ? "primary" : (parent.isHovered ? "focus" : "common")
                                                        radius: Styling.radius(4)
                                                    }

                                                    onClicked: {
                                                        let p = Qt.createQmlObject('import Quickshell; import Quickshell.Io; Process { command: ["wl-copy", "' + modelData.content.replace(/"/g, '\\"') + '"] }', parent);
                                                        p.running = true;
                                                    }
                                                }

                                                Button {
                                                    visible: !isUser && !isSystem && !messageDelegate.isEditing
                                                    width: 24
                                                    height: 24
                                                    flat: true
                                                    padding: 0

                                                    property bool isHovered: hovered

                                                    contentItem: Text {
                                                        text: Icons.arrowCounterClockwise
                                                        font.family: Icons.font
                                                        color: parent.down ? Colors.overPrimary : (parent.isHovered ? Colors.overSurface : Colors.overSurface)
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }

                                                    background: StyledRect {
                                                        variant: parent.down ? "primary" : (parent.isHovered ? "focus" : "common")
                                                        radius: Styling.radius(4)
                                                    }

                                                    onClicked: Ai.regenerateResponse(index)
                                                }
                                            }

                                            StyledRect {
                                                id: bubble
                                                // Let the Row layout determine
                                                // positioning — anchors and Row
                                                // layoutDirection can conflict.
                                                width: Math.min(
                                                    Math.max(bubbleContent.implicitWidth + 32, 100),
                                                    chatView.width * (isSystem ? 0.9 : 0.7))
                                                height: bubbleContent.implicitHeight + 24
                                                clip: true

                                                // QML anchor bindings are NOT re-evaluated
                                                // when their source changes (a known QML
                                                // limitation).  We solved this by disabling
                                                // reuseItems on the chat ListView so each
                                                // delegate is created fresh with the right
                                                // isUser value at construction time.
                                                anchors.right: isUser ? parent.right : undefined
                                                anchors.left: isUser ? undefined : parent.left

                                                variant: isSystem ? "surface" : (isUser ? "primary" : "secondary")
                                                radius: Styling.radius(4)
                                                border.width: isSystem || messageDelegate.isEditing ? 1 : 0
                                                border.color: messageDelegate.isEditing ? Styling.srItem("overprimary") : Colors.surfaceDim

                                                ColumnLayout {
                                                    id: bubbleContent
                                                    anchors.centerIn: parent
                                                    width: parent.width - 32
                                                    spacing: 8

                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 8
                                                        visible: modelData.role === "function"

                                                        Text {
                                                            text: messageDelegate.toolResultCollapsed ? Icons.caretRight : Icons.caretDown
                                                            font.family: Icons.font
                                                            font.pixelSize: 10
                                                            color: Colors.outline
                                                            visible: messageDelegate.isFunctionResult
                                                        }

                                                        Text {
                                                            text: modelData.is_error ? Icons.xCircle + " Tool Error" : Icons.checkCircle + " Tool Result"
                                                            color: modelData.is_error ? Colors.error : Colors.success
                                                            font.family: Icons.font
                                                            font.pixelSize: 12
                                                            font.weight: Font.Bold
                                                        }
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: modelData.name ? "· " + modelData.name : ""
                                                            color: modelData.is_error ? Colors.error : Colors.outline
                                                            font.family: Config.theme.font
                                                            font.pixelSize: 11
                                                            elide: Text.ElideRight
                                                        }

                                                        MouseArea {
                                                            anchors.fill: parent
                                                            visible: messageDelegate.isFunctionResult
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                messageDelegate.toolResultCollapsed = !messageDelegate.toolResultCollapsed
                                                            }
                                                        }
                                                    }

                                                    TextEdit {
                                                        Layout.fillWidth: true
                                                        visible: !messageDelegate.isEditing && messageDelegate.isStreamingLast
                                                        text: Ai.streamingContent
                                                        textFormat: Text.PlainText
                                                        color: isSystem ? Colors.outline : (isUser ? Styling.srItem("primary") : Styling.srItem("secondary"))
                                                        font.family: Config.theme.font
                                                        font.pixelSize: 14
                                                        wrapMode: Text.Wrap
                                                        readOnly: true
                                                        selectByMouse: true
                                                    }

                                                    // ── Thinking card (collapsible) ──
                                                    // Shown when the model emitted
                                                    // reasoning content for this
                                                    // turn (DeepSeek R1's
                                                    // reasoning_content, qwen3's
                                                    // inline  blocks,
                                                    // gemma thinking mode). The
                                                    // thinking is hidden by
                                                    // default — clicking the
                                                    // header expands it. This
                                                    // keeps the chat surface
                                                    // clean for the common
                                                    // case (no reasoning) while
                                                    // making it inspectable
                                                    // when the user wants to
                                                    // debug what the model did.
                                                    ColumnLayout {
                                                        visible: !messageDelegate.isEditing
                                                                && !messageDelegate.isStreamingLast
                                                                && (modelData.reasoningContent || Ai.reasoningBuffer)
                                                                && !isUser
                                                                && !isSystem
                                                        Layout.fillWidth: true
                                                        Layout.topMargin: 6
                                                        spacing: 4

                                                        property bool expanded: false

                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 6

                                                            StyledRect {
                                                                radius: Styling.radius(4)
                                                                variant: "internalbg"
                                                                opacity: 0.6
                                                                Layout.fillWidth: true
                                                                Layout.preferredHeight: thinkingHeader.implicitHeight + 8

                                                                RowLayout {
                                                                    id: thinkingHeader
                                                                    anchors.fill: parent
                                                                    anchors.leftMargin: 10
                                                                    anchors.rightMargin: 10
                                                                    spacing: 6

                                                                    Text {
                                                                        text: parent.parent.parent.expanded
                                                                            ? Icons.caretDown : Icons.caretRight
                                                                        font.family: Icons.font
                                                                        font.pixelSize: 10
                                                                        color: Colors.outline
                                                                        Layout.alignment: Qt.AlignVCenter
                                                                    }
                                                                    Text {
                                                                        text: "Thinking"
                                                                        color: Colors.outline
                                                                        font.family: Config.theme.font
                                                                        font.pixelSize: 11
                                                                        font.weight: Font.Medium
                                                                        Layout.alignment: Qt.AlignVCenter
                                                                    }
                                                                    Text {
                                                                        text: {
                                                                            let rc = modelData.reasoningContent
                                                                                || Ai.reasoningBuffer || "";
                                                                            let words = rc.split(/\s+/).filter(s => s).length;
                                                                            return words > 0 ? words + " words" : "";
                                                                        }
                                                                        color: Colors.outline
                                                                        font.family: "Monospace"
                                                                        font.pixelSize: 10
                                                                        opacity: 0.7
                                                                        Layout.alignment: Qt.AlignVCenter
                                                                    }
                                                                    Item { Layout.fillWidth: true }
                                                                }

                                                                MouseArea {
                                                                    anchors.fill: parent
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    onClicked: parent.parent.parent.expanded
                                                                        = !parent.parent.parent.expanded
                                                                }
                                                            }
                                                        }

                                                        TextEdit {
                                                            visible: expanded
                                                            Layout.fillWidth: true
                                                            text: modelData.reasoningContent
                                                                || Ai.reasoningBuffer || ""
                                                            textFormat: Text.PlainText
                                                            color: Colors.outline
                                                            font.family: "Monospace"
                                                            font.pixelSize: 11
                                                            wrapMode: Text.Wrap
                                                            readOnly: true
                                                            selectByMouse: true
                                                            opacity: 0.85
                                                            Layout.topMargin: 4
                                                            Behavior on opacity {
                                                                AnimatedBehavior { type: "standard"; size: "normal" }
                                                            }
                                                        }
                                                    }

                                                    // ── Collapsed summary for tool results ──
                                                    Text {
                                                        Layout.fillWidth: true
                                                        visible: messageDelegate.isFunctionResult
                                                              && messageDelegate.toolResultCollapsed
                                                              && !messageDelegate.isEditing
                                                        text: {
                                                            let txt = (modelData.content || "").trim();
                                                            let firstLine = txt.split("\n")[0] || "";
                                                            if (firstLine.length > 150)
                                                                return firstLine.substring(0, 150) + "…";
                                                            return firstLine;
                                                        }
                                                        textFormat: Text.PlainText
                                                        color: Colors.outline
                                                        font.family: Config.theme.font
                                                        font.pixelSize: 12
                                                        wrapMode: Text.WrapAnywhere
                                                        maximumLineCount: 1
                                                        elide: Text.ElideRight
                                                    }

                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        visible: (!messageDelegate.isFunctionResult
                                                                  || !messageDelegate.toolResultCollapsed)
                                                              && !messageDelegate.isEditing
                                                              && !bubbleContentText.visible
                                                              && !messageDelegate.isStreamingLast
                                                        spacing: 8

                                                        Repeater {
                                                            model: messageDelegate._contentParts

                                                            delegate: Loader {
                                                                Layout.fillWidth: true
                                                                sourceComponent: modelData.type === 'code' ? codeComponent : textComponent
                                                                asynchronous: true

                                                                property var segment: modelData

                                                                 Component {
                                                                     id: textComponent
                                                                     TextEdit {
                                                                         Layout.fillWidth: true
                                                                         Layout.maximumWidth: bubbleContent.width
                                                                         text: segment.content
                                                                         textFormat: Text.MarkdownText
                                                                         color: isSystem ? Colors.outline : (isUser ? Styling.srItem("primary") : Styling.srItem("secondary"))
                                                                         font.family: Config.theme.font
                                                                         font.pixelSize: 14
                                                                         wrapMode: Text.Wrap
                                                                         readOnly: true
                                                                         selectByMouse: true

                                                                         onLinkActivated: link => Qt.openUrlExternally(link)
                                                                     }
                                                                 }

                                                                 Component {
                                                                     id: codeComponent
                                                                     CodeBlock {
                                                                         Layout.fillWidth: true
                                                                         Layout.maximumWidth: bubbleContent.width
                                                                         code: segment.content
                                                                         language: segment.language
                                                                     }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    TextEdit {
                                                        id: bubbleContentText
                                                        Layout.fillWidth: true
                                                        text: modelData.content || ""
                                                        textFormat: Text.PlainText
                                                        color: isSystem ? Colors.outline : (isUser ? Styling.srItem("primary") : Styling.srItem("secondary"))
                                                        font.family: Config.theme.font
                                                        font.pixelSize: 14
                                                        wrapMode: Text.Wrap
                                                        readOnly: !messageDelegate.isEditing
                                                        selectByMouse: true
                                                        visible: messageDelegate.isEditing
                                                    }

                                                    ColumnLayout {
                                                        visible: modelData.functionCall !== undefined
                                                        Layout.fillWidth: true
                                                        spacing: 4

                                                        Rectangle {
                                                            Layout.fillWidth: true
                                                            height: 1
                                                            color: Colors.outline
                                                            opacity: 0.2
                                                        }

                                                        Text {
                                                            text: {
                                                                if (!modelData.functionCall)
                                                                    return "";
                                                                let n = modelData.functionCall.name || "";
                                                                if (n === "run_shell_command")
                                                                    return "Run Command";
                                                                if (n === "agent_invoke" && modelData.functionCall.args && modelData.functionCall.args.tool)
                                                                    return "Agent Tool · " + modelData.functionCall.args.tool;
                                                                return "Tool · " + n;
                                                            }
                                                            color: Styling.srItem("overprimary")
                                                            font.family: Config.theme.font
                                                            font.weight: Font.Bold
                                                            font.pixelSize: 12
                                                        }

                                                        StyledRect {
                                                            Layout.fillWidth: true
                                                            variant: "surface"
                                                            color: Colors.surface
                                                            radius: Styling.radius(4)

                                                            TextEdit {
                                                                padding: 8
                                                                width: parent.width
                                                                text: {
                                                                    if (!modelData.functionCall)
                                                                        return "";
                                                                    let fc = modelData.functionCall;
                                                                    let n = fc.name || "";
                                                                    let args = fc.args || {};
                                                                    if (n === "run_shell_command" && args.command)
                                                                        return args.command;
                                                                    try {
                                                                        return JSON.stringify(args, null, 2);
                                                                    } catch (e) {
                                                                        return String(args);
                                                                    }
                                                                }
                                                                font.family: "Monospace"
                                                                font.pixelSize: 12
                                                                color: Colors.overSurface
                                                                readOnly: true
                                                                wrapMode: Text.WrapAnywhere
                                                            }
                                                        }

                                                        // Animated approval card. Three buttons
                                                        // with consistent layout — Cancel (skip
                                                        // entirely), Reject (tell AI no), Approve
                                                        // (let it run). The whole row fades in
                                                        // when `functionPending` flips true so the
                                                        // approval moment feels deliberate, not
                                                        // abrupt.
                                                        RowLayout {
                                                            visible: modelData.functionPending === true
                                                            opacity: visible ? 1 : 0
                                                            Layout.alignment: Qt.AlignRight
                                                            spacing: 8
                                                            Layout.topMargin: 4

                                                            Behavior on opacity {
                                                                AnimatedBehavior { type: "standard"; size: "normal" }
                                                            }

                                                            Button {
                                                                id: cancelBtn
                                                                text: "Cancel"
                                                                highlighted: true
                                                                flat: true
                                                                // Cancel discards the tool call
                                                                // entirely — no follow-up to the
                                                                // AI, just a clean state. Use
                                                                // Reject if you want the AI to
                                                                // know the tool was declined.
                                                                Accessible.role: Accessible.Button
                                                                Accessible.name: "Cancel tool call"
                                                                onClicked: Ai.cancelTool(index)

                                                                background: StyledRect {
                                                                    variant: "transparent"
                                                                    opacity: parent.hovered ? 1 : 0.7
                                                                    radius: Styling.radius(4)
                                                                    border.width: 1
                                                                    border.color: Colors.outline
                                                                    Behavior on opacity {
                                                                        AnimatedBehavior { type: "standard"; size: "fast" }
                                                                    }
                                                                }

                                                                contentItem: RowLayout {
                                                                    anchors.centerIn: parent
                                                                    spacing: 4
                                                                    Text {
                                                                        text: Icons.x
                                                                        font.family: Icons.font
                                                                        font.pixelSize: 12
                                                                        color: Colors.outline
                                                                        Layout.alignment: Qt.AlignVCenter
                                                                    }
                                                                    Text {
                                                                        text: cancelBtn.text
                                                                        color: Colors.outline
                                                                        font.family: Config.theme.font
                                                                        font.pixelSize: 12
                                                                        font.weight: Font.Medium
                                                                    }
                                                                }
                                                            }

                                                            Button {
                                                                id: rejectBtn
                                                                text: "Reject"
                                                                highlighted: true
                                                                flat: true
                                                                Accessible.role: Accessible.Button
                                                                Accessible.name: "Reject tool call"
                                                                onClicked: Ai.rejectCommand(index)

                                                                background: StyledRect {
                                                                    variant: "error"
                                                                    opacity: parent.hovered ? 0.95 : 0.55
                                                                    radius: Styling.radius(4)
                                                                    Behavior on opacity {
                                                                        AnimatedBehavior { type: "standard"; size: "fast" }
                                                                    }
                                                                }

                                                                contentItem: RowLayout {
                                                                    anchors.centerIn: parent
                                                                    spacing: 4
                                                                    Text {
                                                                        text: Icons.prohibit
                                                                        font.family: Icons.font
                                                                        font.pixelSize: 12
                                                                        color: Colors.overError
                                                                        Layout.alignment: Qt.AlignVCenter
                                                                    }
                                                                    Text {
                                                                        text: rejectBtn.text
                                                                        color: Colors.overError
                                                                        font.family: Config.theme.font
                                                                        font.pixelSize: 12
                                                                        font.weight: Font.Medium
                                                                    }
                                                                }
                                                            }

                                                            Button {
                                                                id: approveBtn
                                                                text: "Approve"
                                                                highlighted: true
                                                                flat: true
                                                                Accessible.role: Accessible.Button
                                                                Accessible.name: "Approve tool call"
                                                                onClicked: Ai.approveCommand(index)

                                                                background: StyledRect {
                                                                    variant: "primary"
                                                                    opacity: parent.hovered ? 1 : 0.85
                                                                    radius: Styling.radius(4)
                                                                    Behavior on opacity {
                                                                        AnimatedBehavior { type: "standard"; size: "fast" }
                                                                    }
                                                                }

                                                                contentItem: RowLayout {
                                                                    anchors.centerIn: parent
                                                                    spacing: 4
                                                                    Text {
                                                                        text: Icons.check
                                                                        font.family: Icons.font
                                                                        font.pixelSize: 12
                                                                        color: Colors.overPrimary
                                                                        Layout.alignment: Qt.AlignVCenter
                                                                    }
                                                                    Text {
                                                                        text: approveBtn.text
                                                                        color: Colors.overPrimary
                                                                        font.family: Config.theme.font
                                                                        font.pixelSize: 12
                                                                        font.weight: Font.Medium
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        // Status row shown after the user
                                                        // approved or rejected a tool call.
                                                        // Replaces the previous plain-text
                                                        // "Tool Approved · xxx" with an icon +
                                                        // text row that fades in.
                                                        RowLayout {
                                                            visible: modelData.functionApproved === true
                                                            opacity: visible ? 1 : 0
                                                            Layout.topMargin: 4
                                                            spacing: 6
                                                            Behavior on opacity {
                                                                AnimatedBehavior { type: "standard"; size: "normal" }
                                                            }
                                                            Text {
                                                                text: Icons.checkCircle
                                                                font.family: Icons.font
                                                                font.pixelSize: 12
                                                                color: Colors.success
                                                                Layout.alignment: Qt.AlignVCenter
                                                            }
                                                            Text {
                                                                text: {
                                                                    let n = (modelData.functionCall && modelData.functionCall.name) || "";
                                                                    if (n === "run_shell_command")
                                                                        return "Command approved";
                                                                    if (n === "agent_invoke" && modelData.functionCall.args && modelData.functionCall.args.tool)
                                                                        return "Tool approved · " + modelData.functionCall.args.tool;
                                                                    return "Tool approved · " + n;
                                                                }
                                                                color: Colors.success
                                                                font.family: Config.theme.font
                                                                font.pixelSize: 12
                                                                font.weight: Font.Medium
                                                            }
                                                        }

                                                        RowLayout {
                                                            visible: modelData.functionApproved === false && !modelData.functionPending
                                                            opacity: visible ? 1 : 0
                                                            Layout.topMargin: 4
                                                            spacing: 6
                                                            Behavior on opacity {
                                                                AnimatedBehavior { type: "standard"; size: "normal" }
                                                            }
                                                            Text {
                                                                text: Icons.xCircle
                                                                font.family: Icons.font
                                                                font.pixelSize: 12
                                                                color: Colors.error
                                                                Layout.alignment: Qt.AlignVCenter
                                                            }
                                                            Text {
                                                                text: {
                                                                    let n = (modelData.functionCall && modelData.functionCall.name) || "";
                                                                    if (n === "run_shell_command")
                                                                        return "Command rejected";
                                                                    if (n === "agent_invoke" && modelData.functionCall.args && modelData.functionCall.args.tool)
                                                                        return "Tool rejected · " + modelData.functionCall.args.tool;
                                                                    return "Tool rejected · " + n;
                                                                }
                                                                color: Colors.error
                                                                font.family: Config.theme.font
                                                                font.pixelSize: 12
                                                                font.weight: Font.Medium
                                                            }
                                                        }

                                                        // Resend button — only appears on the
                                                        // system "*(empty response)* — …"
                                                        // placeholder Ai.qml emits when the
                                                        // AI returns an empty completion. One
                                                        // click drops the placeholder + the
                                                        // hint and re-runs makeRequest with
                                                        // the same history. Saves the user
                                                        // from retyping their question after
                                                        // every flaky AI response.
                                                        RowLayout {
                                                            visible: isSystem
                                                                && !Ai.isLoading
                                                                && Ai.streamingStatus === ""
                                                                && (modelData.content || "").indexOf("*(empty response)*") === 0
                                                            Layout.topMargin: 6
                                                            spacing: 8

                                                            Button {
                                                                text: "Resend"
                                                                flat: true
                                                                onClicked: Ai.resendLast()

                                                                background: StyledRect {
                                                                    variant: resendMa.containsMouse ? "primary" : "common"
                                                                    opacity: resendMa.containsMouse ? 1 : 0.85
                                                                    radius: Styling.radius(4)
                                                                }
                                                                contentItem: Text {
                                                                    text: parent.text
                                                                    color: resendMa.containsMouse ? Colors.overPrimary : Colors.overBackground
                                                                    font.family: Config.theme.font
                                                                    font.pixelSize: 11
                                                                    font.weight: Font.Medium
                                                                    horizontalAlignment: Text.AlignHCenter
                                                                    verticalAlignment: Text.AlignVCenter
                                                                }
                                                                MouseArea {
                                                                    id: resendMa
                                                                    anchors.fill: parent
                                                                    hoverEnabled: true
                                                                    cursorShape: Qt.PointingHandCursor
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            Text {
                                                id: modelIndicator
                                                visible: !isUser && !isSystem && (modelData.model ? true : false)
                                                text: retryMode ? "Retry with another model " + Icons.caretRight : (modelData.model || "")
                                                color: Colors.outline
                                                font.family: Config.theme.font
                                                font.pixelSize: Styling.fontSize(-2)
                                                font.weight: Font.Medium

                                                anchors.top: bubble.bottom
                                                anchors.topMargin: 4
                                                anchors.left: bubble.left
                                                anchors.leftMargin: 4

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor

                                                    onClicked: {
                                                        if (retryMode) {
                                                            mainChatArea.retryIndex = index;
                                                            modelSelector.open();
                                                            retryMode = false;
                                                        } else {
                                                            retryMode = true;
                                                            retryTimer.start();
                                                        }
                                                    }
                                                }

                                                Timer {
                                                    id: retryTimer
                                                    interval: 5000
                                                    onTriggered: retryMode = false
                                                }
                                            }
                                        }
                                    }
                                }

                                footer: Item {
                                    width: chatView.width
                                    height: 40
                                    visible: Ai.isLoading

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 4

                                        Repeater {
                                            model: 3

                                            Rectangle {
                                                width: 8
                                                height: 8
                                                radius: 4
                                                color: Styling.srItem("overprimary")
                                                opacity: 0.5

                                                // Animated typing indicator.
                                                // Wraps the SequentialAnimation in
                                                // `enabled: Anim.animationsEnabled`
                                                // so the dots freeze in place when
                                                // game mode is on or the user picked
                                                // an "instant" animation style —
                                                // otherwise the animation runs even
                                                // when the rest of the shell is
                                                // paused, drawing GPU/CPU for no
                                                // visual benefit.
                                                SequentialAnimation on opacity {
                                                    loops: Animation.Infinite
                                                    running: Anim.animationsEnabled && Ai.isLoading

                                                    PauseAnimation {
                                                        duration: index * 200
                                                    }

                                                    PropertyAnimation {
                                                        to: 1
                                                        duration: 400
                                                    }

                                                    PropertyAnimation {
                                                        to: 0.5
                                                        duration: 400
                                                    }

                                                    PauseAnimation {
                                                        duration: 400 - (index * 200)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ── Jump-to-bottom button ─────────────────────
                        // Sibling of the chat ColumnLayout + inputContainer
                        // inside mainChatArea. Anchoring inside chatView
                        // (the ListView) clipped it against the view's
                        // own bounds — chatView has clip: true and the
                        // button would silently disappear when the input
                        // bar grew. Hoisted to mainChatArea so the anchor
                        // resolves cleanly against inputContainer.top
                        // and z is well above the chat ColumnLayout fill.
                        Item {
                            id: jumpToBottomAnchor
                            width: jumpToBottomBtn.implicitWidth
                            height: jumpToBottomBtn.implicitHeight
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: inputContainer.top
                            anchors.bottomMargin: 12
                            z: 50

                            readonly property bool _shouldShow:
                                chatView._userScrolledUp
                                && chatView.count > 0
                                && chatView.visible
                                && !mainChatArea.isWelcome

                            // Both opacity and scale ride a single
                            // `popupOpacity` so the fade and the pop-in
                            // animate in lockstep. `visible` only flips
                            // off when opacity has finished draining —
                            // otherwise QML tears the item down the
                            // instant the condition stops being true and
                            // the fade-out never plays.
                            property real popupOpacity: _shouldShow ? 1 : 0
                            opacity: popupOpacity
                            scale: 0.92 + 0.08 * popupOpacity
                            visible: popupOpacity > 0.01
                            transformOrigin: Item.Bottom

                            Behavior on popupOpacity {
                                enabled: Anim.animationsEnabled
                                NumberAnimation {
                                    duration: Anim.standardSmall
                                    easing.type: Easing.OutCubic
                                    easing.bezierCurve: Anim.easing("standard").bezierCurve
                                }
                            }

                            StyledRect {
                                anchors.fill: parent
                                variant: "popup"
                                radius: Styling.radius(8)
                                enableShadow: true
                            }

                            Button {
                                id: jumpToBottomBtn
                                anchors.fill: parent
                                flat: true
                                padding: 0
                                leftPadding: 12
                                rightPadding: 12
                                topPadding: 6
                                bottomPadding: 6
                                hoverEnabled: true

                                contentItem: RowLayout {
                                    spacing: 4
                                    anchors.centerIn: parent
                                    Text {
                                        text: Icons.caretDown
                                        font.family: Icons.font
                                        font.pixelSize: 11
                                        color: Styling.srItem("overprimary")
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    Text {
                                        text: "Latest"
                                        font.family: Config.theme.font
                                        font.pixelSize: 11
                                        font.weight: Font.Medium
                                        color: Colors.overSurface
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }

                                background: null

                                onClicked: {
                                    chatView._stickToBottom = true;
                                    chatView._userScrolledUp = false;
                                    chatView._animateToBottom(false);
                                }
                            }
                        }

                        // Keep the last message glued to the bottom of
                        // the visible chat area while the input bar
                        // grows (user typing multi-line) or shrinks
                        // (attachments toggled). Without this the
                        // bottomMargin bound to inputContainer.height
                        // makes the view's effective bottom shrink but
                        // contentY stays put — so the latest message
                        // visibly scrolls upward while the user types.
                        Connections {
                            target: inputContainer
                            function onHeightChanged() {
                                if (chatView._stickToBottom
                                        && !chatView._userScrolledUp) {
                                    chatView._animateToBottom(false);
                                }
                            }
                        }
                        // Re-anchor when the status banner grows /
                        // shrinks too (model starts streaming, etc.) so
                        // the last message stays visible.
                        Connections {
                            target: statusBanner
                            function onHeightChanged() {
                                if (chatView._stickToBottom
                                        && !chatView._userScrolledUp) {
                                    chatView._animateToBottom(false);
                                }
                            }
                            function onVisibleChanged() {
                                if (statusBanner.visible
                                        && chatView._stickToBottom
                                        && !chatView._userScrolledUp) {
                                    chatView._animateToBottom(false);
                                }
                            }
                        }

                        ModelSelectorPopup {
                            id: modelSelector
                            parent: mainChatArea

                            onModelSelected: {
                                if (mainChatArea.retryIndex > -1) {
                                    Ai.regenerateResponse(mainChatArea.retryIndex);
                                    mainChatArea.retryIndex = -1;
                                }
                            }
                        }

                        Connections {
                            target: Ai

                            function onModelSelectionRequested() {
                                modelSelector.open();
                            }
                        }

                        Item {
                            id: inputContainer
                            property int attachmentPreviewHeight: attachmentPreview.visible ? Math.min(attachmentPreview.contentHeight, 120) + 8 : 0
                            height: attachmentPreviewHeight + Math.min(150, Math.max(48, inputField.contentHeight + 24))

                            anchors.bottom: parent.bottom
                            property real centerMargin: (parent.height / 2) - (height / 2)
                            anchors.bottomMargin: mainChatArea.isWelcome ? centerMargin : 20
                            anchors.horizontalCenter: parent.horizontalCenter

                            width: Math.min(600, parent.width - 40)

                            Behavior on anchors.bottomMargin {
                                AnimatedBehavior { type: "spatial"; size: "default" }
                            }

                            StyledRect {
                                id: inputStyledRect
                                anchors.fill: parent
                                variant: "pane"
                                radius: Styling.radius(4)
                                enableShadow: true

                                DropArea {
                                    anchors.fill: parent
                                    onDropped: drop => {
                                        if (drop.urls && drop.urls.length > 0) {
                                            for (let i = 0; i < drop.urls.length; i++)
                                                mainChatArea.addAttachmentFromFile(drop.urls[i]);
                                            drop.accepted = true;
                                            return;
                                        }
                                        if (drop.text && drop.text.length > 0) {
                                            mainChatArea.addAttachmentsFromUriList(drop.text);
                                            drop.accepted = true;
                                        }
                                    }
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: 6

                                    Flickable {
                                        id: attachmentPreview
                                        height: visible ? Math.min(contentHeight, 120) : 0
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 12
                                        Layout.rightMargin: 12
                                        Layout.topMargin: 8
                                        Layout.preferredHeight: height
                                        visible: mainChatArea.pendingAttachments.length > 0
                                        clip: true
                                        boundsBehavior: Flickable.StopAtBounds
                                        interactive: contentHeight > height

                                        contentWidth: width
                                        contentHeight: attachmentsFlow.height

                                        Flow {
                                            id: attachmentsFlow
                                            width: attachmentPreview.width
                                            spacing: 6

                                            Repeater {
                                                model: mainChatArea.pendingAttachments

                                                Item {
                                                    width: 48
                                                    height: 48

                                                    StyledRect {
                                                        anchors.fill: parent
                                                        variant: "surface"
                                                        radius: Styling.radius(6)

                                                        Image {
                                                            anchors.fill: parent
                                                            anchors.margins: 2
                                                            source: "data:" + modelData.mimeType + ";base64," + modelData.base64
                                                            fillMode: Image.PreserveAspectCrop
                                                            sourceSize.width: 48
                                                            sourceSize.height: 48
                                                        }
                                                    }

                                                    Button {
                                                        anchors.right: parent.right
                                                        anchors.top: parent.top
                                                        anchors.rightMargin: -4
                                                        anchors.topMargin: -4
                                                        width: 16
                                                        height: 16
                                                        flat: true
                                                        z: 1

                                                        contentItem: Text {
                                                            text: Icons.cancel
                                                            font.family: Icons.font
                                                            font.pixelSize: 10
                                                            color: Colors.overSurface
                                                            horizontalAlignment: Text.AlignHCenter
                                                            verticalAlignment: Text.AlignVCenter
                                                        }

                                                        background: Rectangle {
                                                            color: Colors.surfaceBright
                                                            radius: 8
                                                        }

                                                        onClicked: mainChatArea.removeAttachment(index)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                Popup {
                                    id: suggestionsPopup
                                    parent: inputContainer
                                    y: -height - 8
                                    x: 0
                                    width: parent.width
                                    height: Math.min(suggestionsList.contentHeight, mainChatArea.isWelcome ? 120 : 200)
                                    padding: 0
                                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                                    visible: inputField.text.startsWith("/") && suggestionsModel.count > 0

                                    background: StyledRect {
                                        variant: "popup"
                                        radius: Styling.radius(8)
                                        enableShadow: true
                                    }

                                    function selectNext() {
                                        suggestionsList.currentIndex = (suggestionsList.currentIndex + 1) % suggestionsModel.count;
                                    }

                                    function selectPrevious() {
                                        suggestionsList.currentIndex = (suggestionsList.currentIndex - 1 + suggestionsModel.count) % suggestionsModel.count;
                                    }

                                    function executeSelection() {
                                        if (suggestionsList.currentIndex >= 0 && suggestionsList.currentIndex < suggestionsModel.count) {
                                            let item = suggestionsModel.get(suggestionsList.currentIndex);
                                            inputField.text = "/" + item.name + " ";
                                            inputField.cursorPosition = inputField.text.length;
                                            inputField.forceActiveFocus();
                                        }
                                    }

                                    ListView {
                                        id: suggestionsList
                                        anchors.fill: parent
                                        clip: true

                                        model: ListModel {
                                            id: suggestionsModel
                                        }

                                        highlight: Rectangle {
                                            color: Colors.surface
                                            opacity: 0.5
                                        }
                                        highlightMoveDuration: 0

                                        delegate: Button {
                                            width: suggestionsList.width
                                            height: 40
                                            flat: true
                                            highlighted: ListView.isCurrentItem

                                            contentItem: RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: 8

                                                Text {
                                                    text: "/" + model.name
                                                    font.family: Config.theme.font
                                                    font.weight: Font.Bold
                                                    color: highlighted ? Styling.srItem("overprimary") : Colors.overSurface
                                                }

                                                Text {
                                                    text: model.description
                                                    font.family: Config.theme.font
                                                    color: highlighted ? Colors.overSurface : Colors.surfaceDim
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            background: Rectangle {
                                                color: (parent.highlighted || parent.hovered) ? Colors.surfaceBright : "transparent"
                                            }

                                            onClicked: {
                                                suggestionsList.currentIndex = index;
                                                suggestionsPopup.executeSelection();
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.leftMargin: 16
                                    Layout.rightMargin: 16
                                    Layout.topMargin: attachmentPreview.visible ? 0 : 8
                                    Layout.bottomMargin: 8

                                    ScrollView {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        TextArea {
                                            id: inputField
                                            focus: true
                                            activeFocusOnTab: true
                                            placeholderText: mainChatArea.isWelcome ? "Ask AI or type /help..." : "Message AI..."
                                            placeholderTextColor: Colors.outline
                                            font.pixelSize: 14
                                            color: Colors.overBackground
                                            wrapMode: TextEdit.Wrap

                                            // Screen reader: identify this as the
                                            // chat composer. The placeholder is
                                            // already a useful hint but screen
                                            // readers don't always announce it.
                                            Accessible.role: Accessible.EditableText
                                            Accessible.name: "Chat message"
                                            Accessible.description: "Type your message and press Enter to send. Shift+Enter adds a new line."

                                            onTextChanged: {
                                                if (text.startsWith("/")) {
                                                    const query = text.substring(1).toLowerCase();
                                                    suggestionsModel.clear();
                                                    root.slashCommands.forEach(cmd => {
                                                        if (cmd.name.startsWith(query)) {
                                                            suggestionsModel.append(cmd);
                                                        }
                                                    });
                                                } else {
                                                    suggestionsModel.clear();
                                                }
                                            }

                                            background: null

                                            Keys.onPressed: event => {
                                                if (suggestionsPopup.visible) {
                                                    if (event.key === Qt.Key_Up) {
                                                        suggestionsPopup.selectPrevious();
                                                        event.accepted = true;
                                                        return;
                                                    } else if (event.key === Qt.Key_Down) {
                                                        suggestionsPopup.selectNext();
                                                        event.accepted = true;
                                                        return;
                                                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) {
                                                        suggestionsPopup.executeSelection();
                                                        event.accepted = true;
                                                        return;
                                                    }
                                                }
                                                if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                                                    clipboardTypesProcess.running = true;
                                                    return;
                                                }
                                                if (event.key === Qt.Key_Escape) {
                                                    if (root.menuExpanded) {
                                                        root.menuExpanded = false;
                                                    } else {
                                                        root.wantsFocus = false;
                                                    }
                                                    event.accepted = true;
                                                    return;
                                                }
                                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                                    if (text.trim().length > 0 || mainChatArea.pendingAttachments.length > 0) {
                                                        Ai.sendMessage(text.trim(), mainChatArea.pendingAttachments.length > 0 ? mainChatArea.pendingAttachments : undefined);
                                                        text = "";
                                                        mainChatArea.clearAttachments();
                                                    }
                                                    event.accepted = true;
                                                }
                                            }
                                            Component.onCompleted: {
                                                if (root.active)
                                                    forceActiveFocus();
                                            }
                                        }
                                    }

                                    // ── Auto-approve toggle ──
                                    // Only visible in agent mode.
                                    Button {
                                        id: autoToggle
                                        visible: Ai.currentMode === "agent"
                                        Layout.preferredWidth: 44
                                        Layout.preferredHeight: 32
                                        flat: true
                                        padding: 0

                                        readonly property bool active: Config.ai.toolAutoApprove || false

                                        Text {
                                            anchors.centerIn: parent
                                            text: Icons.lightning
                                            font.family: Icons.font
                                            font.pixelSize: 14
                                            color: autoToggle.active
                                                ? Styling.srItem("overprimary") : Colors.outline
                                        }

                                        background: Rectangle {
                                            color: autoToggle.active
                                                ? Colors.primary : "transparent"
                                            radius: Styling.radius(4)
                                            opacity: autoToggle.active ? 0.3 : 1
                                            border.width: autoToggle.active ? 0 : 0
                                        }

                                        ToolTip.visible: hovered
                                        ToolTip.delay: 400
                                        ToolTip.text: "Auto-approve shell commands"

                                        onClicked: {
                                            Config.ai.toolAutoApprove = !Config.ai.toolAutoApprove
                                        }
                                    }

                                    Button {
                                        Layout.preferredWidth: 32
                                        Layout.preferredHeight: 32
                                        flat: true

                                        contentItem: Text {
                                            text: Icons.plus
                                            font.family: Icons.font
                                            font.pixelSize: 20
                                            color: Colors.outline
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        background: Rectangle {
                                            color: parent.hovered ? Colors.surfaceBright : "transparent"
                                            radius: 16
                                        }

                                        onClicked: zenityProcess.running = true
                                    }
                                    Button {
                                        id: sendOrStopButton
                                        Layout.preferredWidth: 36
                                        Layout.preferredHeight: 32
                                        flat: true
                                        // When the AI is mid-stream, running a
                                        // tool, or just waiting for tool
                                        // approval, this button morphs into
                                        // a Stop button with an animated
                                        // colour transition. Otherwise it
                                        // shows the paper-plane send icon.
                                        readonly property bool aiBusy: Ai.isLoading || Ai.streamingStatus !== ""
                                        visible: aiBusy
                                            || inputField.text.length > 0
                                            || mainChatArea.pendingAttachments.length > 0

                                        // Cross-fade the two icons by stacking
                                        // both and animating their opacity.
                                        // A plain `text:` swap is a hard cut;
                                        // a cross-fade feels like the button
                                        // is gently morphing between states.
                                        contentItem: Item {
                                            Text {
                                                anchors.centerIn: parent
                                                text: Icons.paperPlane
                                                font.family: Icons.font
                                                font.pixelSize: 20
                                                color: Styling.srItem("overprimary")
                                                opacity: sendOrStopButton.aiBusy ? 0 : 1
                                                scale: sendOrStopButton.aiBusy ? 0.6 : 1.0
                                                Behavior on opacity {
                                                    AnimatedBehavior { type: "emphasized"; size: "normal" }
                                                }
                                                Behavior on scale {
                                                    AnimatedBehavior { type: "emphasized"; size: "normal" }
                                                }
                                            }
                                            Text {
                                                anchors.centerIn: parent
                                                text: Icons.stop
                                                font.family: Icons.font
                                                font.pixelSize: 18
                                                color: parent.hovered ? Colors.overError : Colors.error
                                                opacity: sendOrStopButton.aiBusy ? 1 : 0
                                                scale: sendOrStopButton.aiBusy ? 1.0 : 0.6
                                                Behavior on opacity {
                                                    AnimatedBehavior { type: "emphasized"; size: "normal" }
                                                }
                                                Behavior on scale {
                                                    AnimatedBehavior { type: "emphasized"; size: "normal" }
                                                }
                                            }
                                        }

                                        background: Rectangle {
                                            radius: 16
                                            color: sendOrStopButton.aiBusy
                                                ? (parent.hovered ? Colors.surfaceBright : Qt.darker(Colors.surfaceBright, 1.4))
                                                : (parent.hovered ? Colors.surfaceBright : "transparent")
                                            Behavior on color {
                                                AnimatedBehavior { type: "standard"; size: "fast" }
                                            }
                                        }

                                        Accessible.role: Accessible.Button
                                        Accessible.name: sendOrStopButton.aiBusy ? "Stop generation" : "Send message"

                                        onClicked: {
                                            if (sendOrStopButton.aiBusy) {
                                                Ai.stopGeneration();
                                                return;
                                            }
                                            if (inputField.text.trim().length > 0 || mainChatArea.pendingAttachments.length > 0) {
                                                Ai.sendMessage(inputField.text.trim(), mainChatArea.pendingAttachments.length > 0 ? mainChatArea.pendingAttachments : undefined);
                                                inputField.text = "";
                                                mainChatArea.clearAttachments();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Text {
                            anchors.top: inputContainer.bottom
                            anchors.topMargin: 8
                            anchors.horizontalCenter: inputContainer.horizontalCenter

                            text: Ai.currentModel ? Ai.currentModel.name : ""
                            color: Colors.outline
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            font.weight: Font.Medium

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: modelSelector.open()
                            }

                            visible: mainChatArea.isWelcome

                            Behavior on opacity {
                                AnimatedBehavior { type: "standard"; size: "fast" }
                            }

                            opacity: visible ? 1 : 0
                        }
                    }
                }
            }
        }
    }
}
