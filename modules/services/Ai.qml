pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.services
import "ai"
import "ai/strategies"

Singleton {
    id: root

    // ============================================
    // PROPERTIES
    // ============================================

    property string chatDir: Quickshell.env("HOME") + "/.local/share/nothingless/chats"
    property string tmpDir: "/tmp/nothingless-ai"

    property list<AiModel> models: []

    property AiModel currentModel: models.length > 0 ? models[0] : null
    property bool persistenceReady: false
    property string savedModelId: ""
    property bool isRestored: false

    onCurrentModelChanged: {
        if (persistenceReady && currentModel && isRestored) {
            StateService.set("lastAiModel", currentModel.model);
        }
        updateStrategy();
    }

    function restoreModel() {
        const lastModelId = StateService.get("lastAiModel", "gemini-2.0-flash");
        savedModelId = lastModelId;
        tryRestore();
        persistenceReady = true;
    }

    function tryRestore() {
        if (isRestored || models.length === 0)
            return;

        let found = false;

        for (let i = 0; i < models.length; i++) {
            if (models[i].model === savedModelId) {
                currentModel = models[i];
                found = true;
                break;
            }
        }

        if (!found && savedModelId) {
            for (let i = 0; i < models.length; i++) {
                if (models[i].model.endsWith(savedModelId) || models[i].model.endsWith("/" + savedModelId)) {
                    currentModel = models[i];
                    found = true;
                    break;
                }
            }
        }

        if (found)
            isRestored = true;
    }

    Connections {
        target: StateService
        function onStateLoaded() {
            restoreModel();
        }
    }

    Connections {
        target: KeyStore
        function onKeysChanged() {
            fetchAvailableModels();
        }
    }

    Component.onCompleted: {
        if (StateService.initialized)
            restoreModel();

        if (models.length === 0)
            fetchAvailableModels();

        loadExtraModels();
        reloadHistory();
        createNewChat();
    }

    // ============================================
    // STRATEGIES
    // ============================================

    property OpenAiApiStrategy openaiStrategy: OpenAiApiStrategy {}
    property GeminiApiStrategy geminiStrategy: GeminiApiStrategy {}
    property AnthropicApiStrategy anthropicStrategy: AnthropicApiStrategy {}
    property MistralApiStrategy mistralStrategy: MistralApiStrategy {}
    property GroqApiStrategy groqStrategy: GroqApiStrategy {}
    property OllamaApiStrategy ollamaStrategy: OllamaApiStrategy {}
    property MiniMaxApiStrategy minimaxStrategy: MiniMaxApiStrategy {}
    property DeepSeekApiStrategy deepseekStrategy: DeepSeekApiStrategy {}

    property AgentToolRegistry agentToolRegistry: AgentToolRegistry {}
    property AgentManager agentManager: AgentManager {
        toolRegistry: root.agentToolRegistry
    }

    property ApiStrategy currentStrategy: openaiStrategy

    function getStrategyForProvider(providerName) {
        switch (providerName) {
        case "openai": return openaiStrategy;
        case "gemini": return geminiStrategy;
        case "anthropic": return anthropicStrategy;
        case "mistral": return mistralStrategy;
        case "groq": return groqStrategy;
        case "ollama": return ollamaStrategy;
        case "minimax": return minimaxStrategy;
        case "deepseek": return deepseekStrategy;
        default: return openaiStrategy;
        }
    }

    function updateStrategy() {
        if (currentModel)
            currentStrategy = getStrategyForProvider(currentModel.provider);
        else
            currentStrategy = openaiStrategy;
    }

    // ============================================
    // STATE
    // ============================================

    property bool isLoading: false
    property string lastError: ""
    property string responseBuffer: ""

    // Current Chat
    property var currentChat: []
    property string currentChatId: ""

    // Chat History List (files)
    property var chatHistory: []

    FileView {
        id: chatFileView
        printErrors: false
    }

    FileView {
        id: bodyFileView
        printErrors: false
    }

    // ============================================
    // TOOLS
    // ============================================

    function regenerateResponse(index) {
        if (index < 0 || index >= currentChat.length)
            return;

        let newChat = currentChat.slice(0, index);
        currentChat = newChat;

        isLoading = true;
        lastError = "";
        makeRequest();
    }

    function updateMessage(index, newContent) {
        if (index < 0 || index >= currentChat.length)
            return;

        let newChat = Array.from(currentChat);
        let msg = newChat[index];
        msg.content = newContent;
        newChat[index] = msg;

        currentChat = newChat;
        saveCurrentChat();
    }

    // Tool definitions
    property var shellTool: ({
        name: "run_shell_command",
        description: "Execute a shell command on the user's system (Linux). Use this to list files, control the system, or run utilities. Output will be returned.",
        parameters: {
            type: "object",
            properties: {
                command: {
                    type: "string",
                    description: "The shell command to run (e.g. 'ls -la', 'ip addr')"
                }
            },
            required: ["command"]
        }
    })

    // Tools currently active = native enabled tools + agent-discovered tools
    property var activeTools: (function() {
        let t = [];
        let enabled = Config.ai.enabledTools || [];
        if (enabled.includes("shell") || Config.ai.tool === "shell") {
            t.push(shellTool);
        }
        t = t.concat(root.agentToolRegistry.tools);
        return t;
    }())

    // Streaming / reasoning / tool-call accumulators
    property string reasoningBuffer: ""
    property var toolCallBuffer: []

    // ============================================
    // CHAT MANAGEMENT
    // ============================================

    function deleteChat(id) {
        if (id === currentChatId)
            createNewChat();

        let filename = chatDir + "/" + id + ".json";
        deleteChatProcess.command = ["rm", filename];
        deleteChatProcess.running = true;
    }

    // ============================================
    // LOGIC
    // ============================================

    function setModel(modelName) {
        for (let i = 0; i < models.length; i++) {
            if (models[i].name === modelName) {
                currentModel = models[i];
                return;
            }
        }
    }

    function getApiKey(model) {
        if (!model || !model.requires_key)
            return "";

        // Try KeyStore first
        let ksKey = KeyStore.getKey(model.provider);
        if (ksKey)
            return ksKey;

        return "";
    }

    function processCommand(text) {
        let cmd = text.trim();
        if (!cmd.startsWith("/"))
            return false;

        let parts = cmd.split(" ");
        let command = parts[0].toLowerCase();
        let args = parts.slice(1).join(" ");

        switch (command) {
        case "/new":
            createNewChat();
            return true;
        case "/model":
            if (args) {
                let found = false;
                for (let i = 0; i < models.length; i++) {
                    if (models[i].name.toLowerCase().includes(args.toLowerCase()) || models[i].model.toLowerCase() === args.toLowerCase()) {
                        setModel(models[i].name);
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    pushSystemMessage("Model '" + args + "' not found.");
                } else {
                    pushSystemMessage("Switched to model: " + currentModel.name);
                }
            } else {
                modelSelectionRequested();
            }
            return true;
        case "/help":
            pushSystemMessage("🤖 **Assistant Commands**\n\n" + "**`/new`**\n" + "Starts a fresh conversation context.\n\n" + "**`/model [name]`**\n" + "Switches the active AI model.\n" + "• **List models:** Type `/model` without arguments.\n" + "• **Switch:** Type `/model gemini` or `/model mistral`.\n\n" + "**`/help`**\n" + "Shows this help message.\n\n" + "💡 **Tips:**\n" + "• **Edit:** Click the pen icon on any message to modify it.\n" + "• **Regenerate:** Click the refresh icon to get a new response.\n" + "• **Copy:** Use the copy button to grab code or text.");
            return true;
        }

        return false;
    }

    function pushSystemMessage(text) {
        let newChat = Array.from(currentChat);
        newChat.push({
            role: "system",
            content: text
        });
        currentChat = newChat;
    }

    // Function Call Handling
    function approveCommand(index) {
        let msg = currentChat[index];
        if (!msg.functionCall)
            return;

        let newChat = Array.from(currentChat);
        newChat[index].functionPending = false;
        newChat[index].functionApproved = true;
        currentChat = newChat;
        saveCurrentChat();

        let args = msg.functionCall.args;
        let toolName = msg.functionCall.name;

        if (toolName === "run_shell_command") {
            if (!_isShellCommandAllowed(args.command)) {
                let err = "Command blocked by allowlist. Allowed commands: " + (Config.ai.toolAllowlist || []).join(", ");
                _pushFunctionResult(toolName, msg.toolCallId || "", err, true);
                return;
            }
            commandExecutionProc.command = ["bash", "-c", args.command];
            commandExecutionProc.targetIndex = index;
            commandExecutionProc.running = true;
        } else if (root.agentToolRegistry.hasTool(toolName)) {
            root.agentToolRegistry.invoke(toolName, args, function(result) {
                _pushFunctionResult(toolName, msg.toolCallId || "", result.error || result.content || "", !!result.error);
            });
        } else {
            _pushFunctionResult(toolName, msg.toolCallId || "", "Unknown tool: " + toolName, true);
        }
    }

    function rejectCommand(index) {
        let newChat = Array.from(currentChat);
        newChat[index].functionPending = false;
        newChat[index].functionApproved = false;

        let toolName = newChat[index].functionCall.name;
        let toolCallId = newChat[index].toolCallId || "";
        newChat.push(_makeFunctionResult(toolName, toolCallId, "User rejected the command execution."));

        currentChat = newChat;
        saveCurrentChat();
        makeRequest();
    }

    function _isShellCommandAllowed(command) {
        let allowlist = Config.ai.toolAllowlist || [];
        if (allowlist.length === 0) return true; // empty = confirmation only
        let base = String(command).trim().split(/\s+/)[0];
        for (let i = 0; i < allowlist.length; i++) {
            if (allowlist[i] === base) return true;
        }
        return false;
    }

    function _makeFunctionResult(name, toolCallId, content, isError) {
        let msg = {
            role: "function",
            name: name,
            content: content
        };
        if (toolCallId) msg.tool_call_id = toolCallId;
        if (isError) msg.is_error = true;
        return msg;
    }

    function _pushFunctionResult(name, toolCallId, content, isError) {
        let newChat = Array.from(currentChat);
        newChat.push(_makeFunctionResult(name, toolCallId, content, isError));
        currentChat = newChat;
        saveCurrentChat();
        makeRequest();
    }

    function sendMessage(text, attachments) {
        if (text.trim() === "" && (!attachments || attachments.length === 0))
            return;
        if (processCommand(text))
            return;
        isLoading = true;
        lastError = "";
        let userMsg = {
            role: "user",
            content: text
        };
        if (attachments && attachments.length > 0)
            userMsg.attachments = attachments;
        let newChat = Array.from(currentChat);
        newChat.push(userMsg);
        currentChat = newChat;
        saveCurrentChat();
        makeRequest();
    }

    function makeRequest() {
        let apiKey = getApiKey(currentModel);
        if (!apiKey && currentModel.requires_key) {
            lastError = "API Key missing for " + currentModel.name + ". Add it in Settings or set " + (currentModel.key_id || "the environment variable") + ".";
            isLoading = false;

            let errChat = Array.from(currentChat);
            errChat.push({
                role: "assistant",
                content: "Error: " + lastError
            });
            currentChat = errChat;
            return;
        }

        // Determine endpoint — Gemini streaming uses a different endpoint
        let endpoint;
        let isGemini = currentModel.provider === "gemini";
        if (isGemini && geminiStrategy._getStreamEndpoint) {
            endpoint = geminiStrategy._getStreamEndpoint(currentModel, apiKey);
        } else {
            endpoint = currentStrategy.getEndpoint(currentModel, apiKey);
        }

        let headers = currentStrategy.getHeaders(apiKey);

        // Build messages array
        let messages = [];
        if (Config.ai.systemPrompt) {
            messages.push({
                role: "system",
                content: Config.ai.systemPrompt
            });
        }

        for (let i = 0; i < currentChat.length; i++) {
            let msg = currentChat[i];
            let apiMsg = {
                role: msg.role,
                content: msg.content
            };
            if (msg.attachments)
                apiMsg.attachments = msg.attachments;
            if (msg.functionCall)
                apiMsg.functionCall = msg.functionCall;
            if (msg.geminiParts)
                apiMsg.geminiParts = msg.geminiParts;
            if (msg.name)
                apiMsg.name = msg.name;
            messages.push(apiMsg);
        }

        // Build body — always use streaming
        let body = currentStrategy.getStreamBody(messages, currentModel, activeTools);

        // Reset streaming buffers
        responseBuffer = "";
        reasoningBuffer = "";
        toolCallBuffer = [];

        // Add placeholder assistant message for streaming
        let streamChat = Array.from(currentChat);
        streamChat.push({
            role: "assistant",
            content: "",
            model: currentModel ? currentModel.name : "Unknown"
        });
        currentChat = streamChat;

        writeTempBody(JSON.stringify(body), headers, endpoint);
    }

    function writeTempBody(jsonBody, headers, endpoint) {
        requestProcess.command = ["/usr/bin/mkdir", "-p", tmpDir];
        requestProcess.step = "mkdir";
        requestProcess.payload = {
            body: jsonBody,
            headers: headers,
            endpoint: endpoint
        };
        requestProcess.running = true;
    }

    function executeRequest(payload) {
        let bodyPath = tmpDir + "/body.json";
        bodyFileView.path = bodyPath;
        bodyFileView.setText(payload.body);
        Qt.callLater(() => runCurl(payload));
    }

    function runCurl(payload) {
        let bodyPath = tmpDir + "/body.json";
        let headerArgs = payload.headers.map(h => "-H \"" + h + "\"").join(" ");

        // Check for custom curl template
        let customCurl = "";
        if (currentModel && currentModel.customCurlTemplate) {
            customCurl = currentModel.customCurlTemplate;
        } else if (currentModel && KeyStore.getCustomCurl(currentModel.provider)) {
            customCurl = KeyStore.getCustomCurl(currentModel.provider);
        }

        let curlCmd;
        if (customCurl) {
            // Replace placeholders in custom curl
            curlCmd = customCurl
                .replace("{{BODY_PATH}}", bodyPath)
                .replace("{{ENDPOINT}}", payload.endpoint)
                .replace("{{API_KEY}}", getApiKey(currentModel));
        } else {
            curlCmd = "curl -s --no-buffer -N -X POST \"" + payload.endpoint + "\" " + headerArgs + " -d @" + bodyPath;
        }

        curlProcess.command = ["/usr/bin/bash", "-c", curlCmd];
        curlProcess.running = true;
    }

    // ============================================
    // PROCESSES
    // ============================================

    Process {
        id: requestProcess
        property string step: ""
        property var payload: ({})

        onExited: exitCode => {
            if (exitCode === 0 && step === "mkdir") {
                executeRequest(payload);
            } else if (exitCode !== 0) {
                root.lastError = "Failed to create temp directory";
                root.isLoading = false;
            }
        }
    }

    Process {
        id: writeBodyProcess
        property var payload: ({})
        stderr: StdioCollector {
            id: writeBodyStderr
        }

        onExited: exitCode => {
            if (exitCode === 0) {
                runCurl(payload);
            } else {
                root.lastError = "Failed to write request body: " + writeBodyStderr.text;
                root.isLoading = false;
            }
        }
    }

    Process {
        id: curlProcess

        // Use SplitParser for streaming — emits onRead per line
        stdout: SplitParser {
            onRead: data => {
                let result = root.currentStrategy.parseStreamChunk(data);

                if (result.error) {
                    root.lastError = result.error;
                    return;
                }

                if (result.content || result.reasoningContent) {
                    if (result.content) root.responseBuffer += result.content;
                    if (result.reasoningContent) root.reasoningBuffer += result.reasoningContent;
                    // Update the last message in currentChat with accumulated text
                    let newChat = Array.from(root.currentChat);
                    if (newChat.length > 0) {
                        newChat[newChat.length - 1].content = root.responseBuffer;
                        if (root.reasoningBuffer)
                            newChat[newChat.length - 1].reasoningContent = root.reasoningBuffer;
                        root.currentChat = newChat;
                    }
                }

                if (result.toolCallDelta && result.toolCallDelta.length > 0) {
                    root._accumulateToolCallDelta(result.toolCallDelta);
                }

                // Note: done is handled in onExited
            }
        }

        stderr: StdioCollector {
            id: curlStderr
        }

        onExited: exitCode => {
            root.isLoading = false;

            if (exitCode === 0) {
                // If tool calls were accumulated, convert the assistant placeholder into a function call message
                if (root.toolCallBuffer.length > 0 && root.currentChat.length > 0) {
                    let firstTc = root._finalizeFirstToolCall();
                    if (firstTc) {
                        let newChat = Array.from(root.currentChat);
                        let lastIdx = newChat.length - 1;
                        newChat[lastIdx].content = root.responseBuffer || "";
                        newChat[lastIdx].reasoningContent = root.reasoningBuffer || undefined;
                        newChat[lastIdx].functionCall = firstTc.functionCall;
                        newChat[lastIdx].toolCallId = firstTc.toolCallId;
                        newChat[lastIdx].functionPending = true;
                        newChat[lastIdx].functionApproved = false;
                        root.currentChat = newChat;
                    }
                } else if (root.responseBuffer === "" && root.currentChat.length > 0) {
                    let lastMsg = root.currentChat[root.currentChat.length - 1];
                    if (!lastMsg.content) {
                        let newChat = Array.from(root.currentChat);
                        newChat[newChat.length - 1].content = "No response received from the API.";
                        root.currentChat = newChat;
                    }
                }

                root.saveCurrentChat();
            } else {
                root.lastError = "Network Request Failed: " + curlStderr.text;

                // Update the placeholder message with error
                let errChat = Array.from(root.currentChat);
                if (errChat.length > 0) {
                    errChat[errChat.length - 1].content = "Error: " + root.lastError;
                }
                root.currentChat = errChat;
            }

            root.responseBuffer = "";
            root.reasoningBuffer = "";
            root.toolCallBuffer = [];
        }
    }

    function _accumulateToolCallDelta(deltaArray) {
        for (let i = 0; i < deltaArray.length; i++) {
            let d = deltaArray[i];
            let idx = d.index !== undefined ? d.index : i;
            if (!toolCallBuffer[idx]) {
                toolCallBuffer[idx] = {
                    id: d.id || "",
                    type: d.type || "function",
                    function: { name: "", arguments: "" }
                };
            }
            if (d.id && !toolCallBuffer[idx].id) toolCallBuffer[idx].id = d.id;
            if (d.function) {
                if (d.function.name) toolCallBuffer[idx].function.name += d.function.name;
                if (d.function.arguments) toolCallBuffer[idx].function.arguments += d.function.arguments;
            }
        }
    }

    function _finalizeFirstToolCall() {
        if (toolCallBuffer.length === 0) return null;
        let tc = toolCallBuffer[0];
        let args = {};
        try {
            args = JSON.parse(tc.function.arguments || "{}");
        } catch (e) {
            args = { raw: tc.function.arguments };
        }
        return {
            functionCall: {
                name: tc.function.name,
                args: args
            },
            toolCallId: tc.id || ""
        };
    }

    Process {
        id: commandExecutionProc
        property int targetIndex: -1

        stdout: StdioCollector {
            id: cmdStdout
        }
        stderr: StdioCollector {
            id: cmdStderr
        }

        onExited: exitCode => {
            let output = cmdStdout.text + "\n" + cmdStderr.text;
            if (output.trim() === "")
                output = "Command executed successfully (no output).";

            let msg = currentChat[targetIndex];
            root._pushFunctionResult(msg.functionCall.name, msg.toolCallId || "", output, exitCode !== 0);
        }
    }

    // ============================================
    // CHAT STORAGE
    // ============================================

    function createNewChat() {
        currentChat = [];
        currentChatId = Date.now().toString();
        chatModelChanged();
    }

    function saveCurrentChat() {
        if (currentChat.length === 0)
            return;

        let filename = chatDir + "/" + currentChatId + ".json";
        let data = JSON.stringify(currentChat, null, 2);

        saveChatProcess.filePath = filename;
        saveChatProcess.data = data;
        saveChatProcess.command = ["/usr/bin/mkdir", "-p", chatDir];
        saveChatProcess.running = true;
    }

    function reloadHistory() {
        let pyScript = `import os, json, glob
chat_dir = "${chatDir}"
os.makedirs(chat_dir, exist_ok=True)
files = sorted(glob.glob(chat_dir + "/*.json"), key=os.path.getmtime, reverse=True)
for f in files:
    id = os.path.basename(f)[:-5]
    title = "New Chat"
    try:
        with open(f, 'r') as fp:
            data = json.load(fp)
            for msg in data:
                if msg.get("role") == "user":
                    title = msg.get("content", "")[:40].replace("\\n", " ").strip()
                    if len(msg.get("content", "")) > 40: title += "..."
                    break
    except: pass
    print(f"{id}|{title}")
`;
        listHistoryProcess.command = ["python3", "-c", pyScript];
        listHistoryProcess.running = true;
    }

    function loadChat(id) {
        let filename = chatDir + "/" + id + ".json";
        loadChatProcess.targetId = id;
        loadChatProcess.command = ["cat", filename];
        loadChatProcess.running = true;
    }

    Process {
        id: saveChatProcess
        property string filePath: ""
        property string data: ""
        onExited: exitCode => {
            if (exitCode === 0) {
                if (filePath.length > 0)
                    chatFileView.path = filePath;
                if (data.length > 0)
                    chatFileView.setText(data);
                reloadHistory();
            } else {
                console.warn("Failed to create chat directory");
            }
        }
    }

    Process {
        id: deleteChatProcess
        onExited: reloadHistory()
    }

    Process {
        id: listHistoryProcess
        stdout: StdioCollector {
            id: listHistoryStdout
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                let lines = listHistoryStdout.text.trim().split("\n");
                let history = [];
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i];
                    if (line === "")
                        continue;
                    let parts = line.split("|");
                    if (parts.length >= 2) {
                        history.push({
                            id: parts[0],
                            title: parts.slice(1).join("|"),
                            path: chatDir + "/" + parts[0] + ".json"
                        });
                    }
                }
                root.chatHistory = history;
                root.historyModelChanged();
            }
        }
    }

    Process {
        id: loadChatProcess
        property string targetId: ""
        stdout: StdioCollector {
            id: loadChatStdout
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    root.currentChat = JSON.parse(loadChatStdout.text);
                    root.currentChatId = targetId;
                    root.chatModelChanged();
                } catch (e) {
                    console.log("Error loading chat: " + e);
                }
            }
        }
    }

    // ============================================
    // DYNAMIC MODEL FETCHING
    // ============================================

    property bool fetchingModels: false
    property int pendingFetches: 0

    function fetchAvailableModels() {
        fetchingModels = false; // Force refresh
        if (fetchingModels)
            return;

        fetchingModels = true;
        pendingFetches = 0;

        // Gemini
        let geminiKey = KeyStore.getKey("gemini");
        if (geminiKey) {
            pendingFetches++;
            fetchProcessGemini.command = ["bash", "-c", "curl -s 'https://generativelanguage.googleapis.com/v1beta/models?key=" + geminiKey + "'"];
            fetchProcessGemini.running = true;
        }

        // OpenAI
        let openaiKey = KeyStore.getKey("openai");
        if (openaiKey) {
            pendingFetches++;
            fetchProcessOpenAI.command = ["bash", "-c", "curl -s https://api.openai.com/v1/models -H 'Authorization: Bearer " + openaiKey + "'"];
            fetchProcessOpenAI.running = true;
        }

        // Anthropic
        let anthropicKey = KeyStore.getKey("anthropic");
        if (anthropicKey) {
            pendingFetches++;
            fetchProcessAnthropic.command = ["bash", "-c", "curl -s https://api.anthropic.com/v1/models -H 'x-api-key: " + anthropicKey + "' -H 'anthropic-version: 2023-06-01'"];
            fetchProcessAnthropic.running = true;
        }

        // Mistral
        let mistralKey = KeyStore.getKey("mistral");
        if (mistralKey) {
            pendingFetches++;
            fetchProcessMistral.command = ["bash", "-c", "curl -s https://api.mistral.ai/v1/models -H 'Authorization: Bearer " + mistralKey + "'"];
            fetchProcessMistral.running = true;
        }

        // Groq
        let groqKey = KeyStore.getKey("groq");
        if (groqKey) {
            pendingFetches++;
            fetchProcessGroq.command = ["bash", "-c", "curl -s https://api.groq.com/openai/v1/models -H 'Authorization: Bearer " + groqKey + "'"];
            fetchProcessGroq.running = true;
        }

        // Ollama (local)
        let ollamaEnabled = KeyStore.hasKey("ollama");
        if (ollamaEnabled) {
            pendingFetches++;
            fetchProcessOllama.command = ["bash", "-c", "curl -s http://127.0.0.1:11434/api/tags"];
            fetchProcessOllama.running = true;
        }

        // MiniMax
        let minimaxKey = KeyStore.getKey("minimax");
        if (minimaxKey) {
            pendingFetches++;
            fetchProcessMiniMax.command = ["bash", "-c", "echo 'done'"];
            fetchProcessMiniMax.running = true;
        }

        // DeepSeek — only fetch when API key is configured (like other providers)
        let deepseekKey = KeyStore.getKey("deepseek");
        if (deepseekKey) {
            pendingFetches++;
            fetchProcessDeepSeek.command = ["bash", "-c", "curl -s https://api.deepseek.com/v1/models -H 'Authorization: Bearer " + deepseekKey + "'"];
            fetchProcessDeepSeek.running = true;
        }

        if (pendingFetches === 0) {
            fetchingModels = false;
        }
    }

    Process {
        id: fetchProcessGemini
        stdout: StdioCollector {
            id: fetchGeminiOut
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    let data = JSON.parse(fetchGeminiOut.text);
                    if (data.models) {
                        let newModels = [];
                        for (let i = 0; i < data.models.length; i++) {
                            let item = data.models[i];
                            let id = item.name.replace("models/", "");
                            if (id.includes("gemini") || id.includes("flash") || id.includes("pro")) {
                                let m = aiModelFactory.createObject(root, {
                                    name: item.displayName || id,
                                    icon: Qt.resolvedUrl("../../../assets/aiproviders/google.svg"),
                                    description: item.description || "Google Gemini Model",
                                    endpoint: "https://generativelanguage.googleapis.com/v1beta",
                                    model: id,
                                    provider: "gemini",
                                    requires_key: true,
                                    key_id: "GEMINI_API_KEY"
                                });
                                if (m) newModels.push(m);
                            }
                        }
                        mergeModels(newModels);
                    }
                } catch (e) {
                    console.log("Gemini fetch error: " + e);
                }
            }
            checkFetchCompletion();
        }
    }

    Process {
        id: fetchProcessOpenAI
        stdout: StdioCollector {
            id: fetchOpenAIOut
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    let data = JSON.parse(fetchOpenAIOut.text);
                    if (data.data) {
                        let newModels = [];
                        let allowed = ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-4", "o1", "o1-mini", "o1-preview", "o3-mini"];
                        for (let i = 0; i < data.data.length; i++) {
                            let item = data.data[i];
                            let id = item.id;
                            let isAllowed = false;
                            for (let j = 0; j < allowed.length; j++) {
                                if (id === allowed[j] || id.startsWith(allowed[j] + "-")) {
                                    isAllowed = true;
                                    break;
                                }
                            }
                            if (isAllowed) {
                                let m = aiModelFactory.createObject(root, {
                                    name: id,
                                    icon: Qt.resolvedUrl("../../../assets/aiproviders/openai.svg"),
                                    description: "OpenAI Model",
                                    endpoint: "https://api.openai.com",
                                    model: id,
                                    provider: "openai",
                                    requires_key: true,
                                    key_id: "OPENAI_API_KEY"
                                });
                                if (m) newModels.push(m);
                            }
                        }
                        mergeModels(newModels);
                    }
                } catch (e) {
                    console.log("OpenAI fetch error: " + e);
                }
            }
            checkFetchCompletion();
        }
    }

    Process {
        id: fetchProcessMistral
        stdout: StdioCollector {
            id: fetchMistralOut
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    let data = JSON.parse(fetchMistralOut.text);
                    if (data.data) {
                        let newModels = [];
                        for (let i = 0; i < data.data.length; i++) {
                            let item = data.data[i];
                            let id = item.id;
                            let m = aiModelFactory.createObject(root, {
                                name: id,
                                icon: Qt.resolvedUrl("../../../assets/aiproviders/mistral.svg"),
                                description: "Mistral Model",
                                endpoint: "https://api.mistral.ai/v1",
                                model: id,
                                provider: "mistral",
                                requires_key: true,
                                key_id: "MISTRAL_API_KEY"
                            });
                            if (m) newModels.push(m);
                        }
                        mergeModels(newModels);
                    }
                } catch (e) {
                    console.log("Mistral fetch error: " + e);
                }
            }
            checkFetchCompletion();
        }
    }

    Process {
        id: fetchProcessGroq
        stdout: StdioCollector {
            id: fetchGroqOut
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    let data = JSON.parse(fetchGroqOut.text);
                    if (data.data) {
                        let newModels = [];
                        for (let i = 0; i < data.data.length; i++) {
                            let item = data.data[i];
                            let id = item.id;
                            let m = aiModelFactory.createObject(root, {
                                name: id,
                                icon: Qt.resolvedUrl("../../../assets/aiproviders/groq.svg"),
                                description: "Groq Model",
                                endpoint: "https://api.groq.com/openai/v1",
                                model: id,
                                provider: "groq",
                                requires_key: true,
                                key_id: "GROQ_API_KEY"
                            });
                            if (m) newModels.push(m);
                        }
                        mergeModels(newModels);
                    }
                } catch (e) {
                    console.log("Groq fetch error: " + e);
                }
            }
            checkFetchCompletion();
        }
    }

    Process {
        id: fetchProcessAnthropic
        stdout: StdioCollector {
            id: fetchAnthropicOut
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    let data = JSON.parse(fetchAnthropicOut.text);
                    if (data.data) {
                        let newModels = [];
                        for (let i = 0; i < data.data.length; i++) {
                            let item = data.data[i];
                            let id = item.id;
                            let m = aiModelFactory.createObject(root, {
                                name: item.display_name || id,
                                icon: Qt.resolvedUrl("../../../assets/aiproviders/anthropic.svg"),
                                description: item.description || "Anthropic Model",
                                endpoint: "https://api.anthropic.com/v1/messages",
                                model: id,
                                provider: "anthropic",
                                requires_key: true,
                                key_id: "ANTHROPIC_API_KEY"
                            });
                            if (m) newModels.push(m);
                        }
                        mergeModels(newModels);
                    }
                } catch (e) {
                    console.log("Anthropic fetch error: " + e);
                }
            }
            checkFetchCompletion();
        }
    }

    Process {
        id: fetchProcessOllama
        stdout: StdioCollector {
            id: fetchOllamaOut
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    let data = JSON.parse(fetchOllamaOut.text);
                    if (data.models) {
                        let newModels = [];
                        for (let i = 0; i < data.models.length; i++) {
                            let item = data.models[i];
                            let m = aiModelFactory.createObject(root, {
                                name: item.name,
                                icon: Qt.resolvedUrl("../../../assets/aiproviders/ollama.svg"),
                                description: "Local Ollama Model",
                                endpoint: "http://127.0.0.1:11434",
                                model: item.name,
                                provider: "ollama",
                                requires_key: false
                            });
                            if (m) newModels.push(m);
                        }
                        mergeModels(newModels);
                    }
                } catch (e) {
                    console.log("Ollama fetch error: " + e);
                }
            }
            checkFetchCompletion();
        }
    }

    Process {
        id: fetchProcessMiniMax
        onExited: exitCode => {
            if (exitCode === 0) {
                let newModels = [];
                
                let models = [
                    { name: "MiniMax-M2.7", model: "MiniMax-M2.7", description: "Latest model with recursive self-improvement, SOTA coding capabilities", endpoint: "https://api.minimax.io" },
                    { name: "MiniMax-M2.7-highspeed", model: "MiniMax-M2.7-highspeed", description: "Same performance as M2.7, faster inference (~100 tps)", endpoint: "https://api.minimax.io" },
                    { name: "MiniMax-M2.5", model: "MiniMax-M2.5", description: "Peak performance, ultimate value, master the complex", endpoint: "https://api.minimax.io" },
                    { name: "MiniMax-M2.5-highspeed", model: "MiniMax-M2.5-highspeed", description: "Same performance as M2.5, faster inference (~100 tps)", endpoint: "https://api.minimax.io" },
                    { name: "MiniMax-M2.1", model: "MiniMax-M2.1", description: "Powerful multi-language programming, enhanced reasoning", endpoint: "https://api.minimax.io" },
                    { name: "MiniMax-M2.1-highspeed", model: "MiniMax-M2.1-highspeed", description: "Same performance as M2.1, faster inference (~100 tps)", endpoint: "https://api.minimax.io" },
                    { name: "MiniMax-M2", model: "MiniMax-M2", description: "Agentic capabilities, advanced reasoning, 200k context", endpoint: "https://api.minimax.io" },
                    { name: "M2-her", model: "M2-her", description: "Role-playing, multi-turn conversations, emotional expression", endpoint: "https://api.minimax.io" }
                ];
                
                for (let i = 0; i < models.length; i++) {
                    let item = models[i];
                    let m = aiModelFactory.createObject(root, {
                        name: item.name,
                        icon: Qt.resolvedUrl("../../../assets/aiproviders/minimax.svg"),
                        description: item.description,
                        endpoint: item.endpoint,
                        model: item.model,
                        provider: "minimax",
                        requires_key: true,
                        key_id: "MINIMAX_API_KEY"
                    });
                    if (m) newModels.push(m);
                }
                
                mergeModels(newModels);
            }
            checkFetchCompletion();
        }
    }

    property Process fetchProcessDeepSeek: Process {
        running: false
        stdout: StdioCollector { id: fetchDeepSeekOut }
        onExited: exitCode => {
            if (exitCode === 0) {
                let newModels = [];
                let hasApiData = false;
                try {
                    let data = JSON.parse(fetchDeepSeekOut.text);
                    if (data.data && data.data.length > 0) {
                        hasApiData = true;
                        for (let i = 0; i < data.data.length; i++) {
                            let item = data.data[i];
                            let id = item.id;
                            let m = aiModelFactory.createObject(root, {
                                name: item.id,
                                icon: Qt.resolvedUrl("../../../assets/aiproviders/deepseek.svg"),
                                description: "DeepSeek model",
                                endpoint: "https://api.deepseek.com",
                                model: id,
                                provider: "deepseek",
                                requires_key: true,
                                key_id: "DEEPSEEK_API_KEY"
                            });
                            if (m) newModels.push(m);
                        }
                    }
                } catch (e) {
                    // Fall back to static list
                }

                if (!hasApiData) {
                    let models = [
                        { name: "DeepSeek-V3", model: "deepseek-chat", description: "Latest DeepSeek model, SOTA reasoning & coding", endpoint: "https://api.deepseek.com" },
                        { name: "DeepSeek-R1", model: "deepseek-reasoner", description: "DeepSeek reasoning model with chain-of-thought", endpoint: "https://api.deepseek.com" }
                    ];
                    for (let i = 0; i < models.length; i++) {
                        let item = models[i];
                        let m = aiModelFactory.createObject(root, {
                            name: item.name,
                            icon: Qt.resolvedUrl("../../../assets/aiproviders/deepseek.svg"),
                            description: item.description,
                            endpoint: item.endpoint,
                            model: item.model,
                            provider: "deepseek",
                            requires_key: true,
                            key_id: "DEEPSEEK_API_KEY"
                        });
                        if (m) newModels.push(m);
                    }
                }

                mergeModels(newModels);
            }
            checkFetchCompletion();
        }
    }


    function checkFetchCompletion() {
        pendingFetches--;
        if (pendingFetches <= 0) {
            fetchingModels = false;
            pendingFetches = 0;

            tryRestore();

            if (!currentModel && models.length > 0) {
                currentModel = models[0];
                isRestored = true;
            } else if (!isRestored && currentModel) {
                isRestored = true;
            }
        }
    }

    function mergeModels(newModels) {
        let updatedList = [];
        for (let i = 0; i < models.length; i++)
            updatedList.push(models[i]);

        for (let i = 0; i < newModels.length; i++) {
            let m = newModels[i];
            let isDuplicate = false;
            for (let j = 0; j < updatedList.length; j++) {
                if (updatedList[j].model === m.model) {
                    isDuplicate = true;
                    break;
                }
            }
            if (!isDuplicate)
                updatedList.push(m);
        }

        models = updatedList;

        if (!isRestored)
            tryRestore();
    }


    function loadExtraModels() {
        let cfg = Config.ai.extraModels || [];
        if (cfg.length === 0) return;
        let newModels = [];
        for (let i = 0; i < cfg.length; i++) {
            let item = cfg[i];
            let m = aiModelFactory.createObject(root, {
                name: item.name || item.model,
                icon: item.icon ? Qt.resolvedUrl(item.icon) : "",
                description: item.description || "Custom model",
                endpoint: item.endpoint || "",
                model: item.model,
                provider: item.provider || "openai",
                requires_key: item.requires_key !== undefined ? item.requires_key : true,
                key_id: item.key_id || ""
            });
            if (m) newModels.push(m);
        }
        mergeModels(newModels);
    }

    // Signals
    signal chatModelChanged
    signal historyModelChanged
    signal modelSelectionRequested

    Component {
        id: aiModelFactory
        AiModel {}
    }
}
