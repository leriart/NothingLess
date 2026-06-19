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

        reloadHistory();
        createNewChat();
    }

    Component.onDestruction: {
        fetchProcessDeepSeek.running = false;
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
        case "custom": return openaiStrategy; // custom endpoints use OpenAI-compatible format by default
        default: return openaiStrategy;
        }
    }

    // ============================================
    // OLLAMA LIFECYCLE
    // ============================================

    property string ollamaStatus: "unknown"
    property string ollamaLastError: ""
    property bool _ollamaFetchPending: false
    property bool _ollamaChatPending: false
    readonly property string ollamaEnsureScript: Qt.resolvedUrl(
        "../../scripts/ollama-ensure.sh").toString().replace("file://", "")

    function ensureOllamaRunning() {
        if (root.ollamaStatus === "starting") return;
        root._ollamaFetchPending = false;
        root._ollamaChatPending = false;
        root.ollamaStatus = "starting";
        root.ollamaLastError = "";
        ollamaEnsureProcess.running = true;
    }

    function _ensureOllamaThenFetch() {
        if (root.ollamaStatus === "starting") {
            root._ollamaFetchPending = true;
            return;
        }
        root._ollamaFetchPending = true;
        root.ollamaStatus = "starting";
        root.ollamaLastError = "";
        ollamaEnsureProcess.running = true;
    }

    function _ensureOllamaThenChat() {
        if (root.ollamaStatus === "starting") {
            root._ollamaChatPending = true;
            return;
        }
        root._ollamaChatPending = true;
        root.ollamaStatus = "starting";
        root.ollamaLastError = "";
        ollamaEnsureProcess.running = true;
    }

    function restartOllama() {
        root._ollamaFetchPending = false;
        root._ollamaChatPending = false;
        root.ollamaStatus = "starting";
        root.ollamaLastError = "";
        ollamaRestartProcess.running = true;
    }

    function updateStrategy() {
        if (currentModel)
            currentStrategy = getStrategyForProvider(currentModel.provider);
        else
            currentStrategy = openaiStrategy;
    }

    // ============================================
    // AGENTS
    // ============================================

    property AgentToolRegistry agentToolRegistry: AgentToolRegistry {}
    property AgentManager agentManager: AgentManager {
        toolRegistry: root.agentToolRegistry
    }

    // ============================================
    // STATE
    // ============================================

    property bool isLoading: false
    property string lastError: ""
    property string responseBuffer: ""
    // Streaming content exposed directly to the sidebar delegate.
    // The delegate binds to this property instead of modelData.content
    // for the last assistant message, so we never need to reassign
    // currentChat during streaming — avoiding full ListView re-layout
    // on every token.  Updated at streamThrottleMs rate.
    property string streamingContent: ""
    // Accumulated tool-call delta from streaming responses.
    // OpenAI-compatible APIs stream tool calls in chunks (each delta
    // carries a partial `function.arguments` string). We merge them
    // here so that, when curl finishes, we can attach a complete
    // functionCall to the assistant message — without this the agent
    // tool path silently disappears and the chat freezes on a half-
    // streamed response (the AI's preface text is shown but no tool
    // card appears, so the user can't approve/reject and any further
    // input stacks on top of a stuck conversation).
    property var pendingToolCall: null
    // Tracks the tool_call_id of the LAST assistant message that
    // proposed a tool call. Both the streaming toolCallId and the
    // post-stream functionCall.tool_call_id are set from the same
    // primary.id, but the AI can stream chunks with different `id`
    // fields across deltas, and some providers (DeepSeek) reassign
    // the id on the second-to-last delta. The cleanest fix is to
    // remember the authoritative id once the tool is approved and
    // force the subsequent tool result to use that exact id — that
    // way the assistant's tool_calls[].id and the tool's tool_call_id
    // are guaranteed to match in the outgoing payload, no matter how
    // non-deterministic the provider's id assignment was.
    property string lastToolCallId: ""
    // Short human-readable description of what is happening right
    // now ("streaming…", "running tool…", "awaiting tool approval…").
    // Drives the status indicator in the sidebar header.
    property string streamingStatus: ""
    // Wall-clock start of the current in-flight chat request. Set to
    // Date.now() in makeRequest before firing curlProcess, reset to 0
    // on every terminal path (curlProcess.onExited, watchdog, deadline).
    // The wall-clock deadline in curlProcess.stdout.onRead uses this
    // to detect streams that trickle bytes and so never trip curl's
    // --max-time (inactivity) watchdog.
    property int requestStartMs: 0

    // Throttle for streaming UI updates. Instead of reassigning
    // `currentChat` (which forces the sidebar ListView to re-layout
    // every delegate), we copy the accumulated token buffer into
    // `streamingContent` at most every `streamThrottleMs` ms.
    // The sidebar delegate binds directly to `streamingContent` for
    // the last streaming message — only that one TextEdit re-renders,
    // no ListView re-layout, no Markdown re-split on other messages.
    property int streamThrottleMs: 100
    property int _streamLastModelUpdate: 0
    property Timer _streamUpdateTimer: Timer {
        interval: root.streamThrottleMs
        repeat: false
        onTriggered: root._flushStreamUpdate()
    }

    // Safety flags to prevent onExited handlers from overwriting
    // state after the user called stopGeneration(). When true,
    // curlProcess.onExited and commandExecutionProc.onExited must
    // clean up silently — no message overwrites, no makeRequest.
    property bool _killedByUser: false

    // Re-entrancy guard for makeRequest. Set true while a curl is
    // actively streaming; cleared in curlProcess.onExited. A second
    // makeRequest call (e.g. from a tool-result follow-up that fires
    // while the previous response is still streaming) sets
    // `requestQueued` instead of spawning a second curl. After the
    // in-flight request finishes we re-run makeRequest once to
    // drain the queue — preventing both parallel curls and lost
    // follow-up requests.
    property bool requestInFlight: false
    property bool requestQueued: false

    // Watchdog: if `requestInFlight` stays true longer than the
    // configured timeout (default 120s, see Config.ai.requestTimeoutSeconds),
    // something is stuck — the curl onExited didn't fire or threw
    // before clearing the flag. Auto-reset so the sidebar isn't
    // permanently frozen. Also runs the queued request if any.
    // Without this watchdog a single missed onExited would hang the
    // AI pipeline forever.
    //
    // Mirrors Odysseus's two-layer timeout design:
    //   - Inactivity: curl --max-time = requestTimeoutSeconds (kills
    //     wedged/silent endpoints that stop sending bytes).
    //   - Wall-clock deadline: max(timeout * 4, 1200) (catches the
    //     rare streams that trickle bytes forever and so never trip
    //     the inactivity timeout). For the default 120s this is
    //     480s, but capped to 1200s on the lower end to cover
    //     multi-round tool chains on slower hardware.
    //
    // The previous 90s default was too tight for small local
    // Ollama models (qwen2.5:3b on CPU can take 60-90s for a
    // single chat response with tools, and the requestWatchdog
    // would fire just as the model finished streaming).
    readonly property int _requestInactivityTimeoutMs:
        Math.max(10000, (Config.ai.requestTimeoutSeconds || 120) * 1000)
    readonly property int _requestWallClockDeadlineMs:
        Math.max(_requestInactivityTimeoutMs * 4, 1200000)
    property Timer requestWatchdog: Timer {
        interval: root._requestInactivityTimeoutMs
        repeat: false
        onTriggered: {
            if (root.requestInFlight) {
                let secs = Math.round(root._requestInactivityTimeoutMs / 1000);
                console.warn("Ai.qml: requestInFlight stuck — resetting ("
                             + secs + "s inactivity watchdog)");
                if (root.curlProcess && root.curlProcess.running) {
                    root.curlProcess.running = false;
                }
                root.requestInFlight = false;
                root.streamingStatus = "request timed out after " + secs + "s";
                root.isLoading = false;
                root.streamingElapsedTimer.stop();
                root.streamingStartedAt = 0;
                // Surface a system message so the user knows the
                // request died, rather than staring at a frozen
                // spinner. Append to the last assistant placeholder
                // if any, otherwise push a new system message.
                let errChat = Array.from(root.currentChat);
                if (errChat.length > 0
                        && errChat[errChat.length - 1].role === "assistant"
                        && (!errChat[errChat.length - 1].content
                            || errChat[errChat.length - 1].content === "")) {
                    errChat[errChat.length - 1].content =
                        "[Request timed out after " + secs + "s. The API may be "
                        + "unresponsive or the conversation may be malformed. "
                        + "Try again, or `/model` to switch. Increase "
                        + "`requestTimeoutSeconds` in AI settings for slow "
                        + "local models.]";
                    errChat[errChat.length - 1].role = "system";
                } else {
                    errChat.push({
                        role: "system",
                        content: "[Request timed out after " + secs + "s.]"
                    });
                }
                root.currentChat = errChat;
                root.saveCurrentChat();
                if (root.requestQueued) {
                    root.requestQueued = false;
                    Qt.callLater(root.makeRequest);
                }
            }
        }
    }

    // Timer that fires when an agent tool invocation takes too long.
// If the HTTP call or command agent doesn't respond within this
// window, we synthesise a timeout error so the chat doesn't hang
// forever on "running tool: …".
//
// Must be LONGER than the bridge's curl --max-time (25s in
// HttpAgentClient.qml) and the server-side subprocess timeout
// (up to 30s for open_url which spawns xdg-open and waits for
// Wayland portal activation). 35s gives a 5s margin over the
// longest server-side path so the model sees the real result
// instead of a synthetic timeout error while the URL is still
// being dispatched in the background.
    property Timer agentToolInvokeTimeout: Timer {
        interval: 35000
        repeat: false
        property var onFire: null
        onTriggered: {
            if (onFire) onFire();
            onFire = null;
        }
    }

    // Ticks every 5s while a request is in flight. Updates the
    // streamingStatus string to show how long the AI has been
    // streaming (e.g. "streaming… 15s"). When the AI provider is
    // slow the user sees that something is happening, instead of
    // the sidebar just sitting there with a frozen feel. The
    // counter is reset in makeRequest() and stopped in
    // curlProcess.onExited / stopGeneration.
    property int streamingStartedAt: 0
    property Timer streamingElapsedTimer: Timer {
        interval: 5000
        repeat: true
        onTriggered: {
            if (root.streamingStartedAt <= 0) return;
            let secs = Math.floor((Date.now() - root.streamingStartedAt) / 1000);
            // Only update status when it's still in the streaming
            // prefix; if the AI produced a tool call meanwhile the
            // status will have moved on (e.g. "tool call: ...").
            if (root.streamingStatus && root.streamingStatus.indexOf("streaming") === 0) {
                root.streamingStatus = "streaming… " + secs + "s";
            }
        }
    }

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

    property var systemTools: [
        {
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
        }
    ]

    property string currentMode: "agent"
    property string currentAgentId: ""
    property var activeTools: []

    function _rebuildActiveTools() {
        let t = [];
        if (root.currentMode === "agent") {
            t = Array.from(systemTools);
            let registry = root.agentToolRegistry;
            if (registry && registry.tools) {
                for (let i = 0; i < registry.tools.length; i++) {
                    let tool = registry.tools[i];
                    if (!tool) continue;
                    if (root.currentAgentId !== "" && tool._agentId !== root.currentAgentId)
                        continue;
                    t.push(tool);
                }
            }
        }
        root.activeTools = t;
    }

    function setMode(mode) {
        if (mode !== "chat" && mode !== "agent") return;
        if (root.currentMode === mode) return;
        root.currentMode = mode;
    }

    function setAgent(agentId) {
        let normalized = agentId || "";
        if (root.currentAgentId === normalized) return;
        root.currentAgentId = normalized;
        if (Config && Config.ai && Config.ai.defaultAgentId !== normalized) {
            Config.ai.defaultAgentId = normalized;
        }
    }

    function _detectTextToolCall(text) {
        if (!text) return null

        // Pattern 1: JSON block with "name" and "arguments"
        // e.g. {"name": "run_shell_command", "arguments": {"command": "ls -la"}}
        let re = /\{[^{}]*"name"\s*:\s*"([^"]+)"[^{}]*"arguments"\s*:\s*(\{[^}]+\})[^{}]*\}/
        let m = text.match(re)
        if (m) {
            try { let args = JSON.parse(m[2]); return { name: m[1], args: args } } catch (e) {}
        }

        // Pattern 2: structured "tool:" / "parameters:" format
        re = /tool\s*:\s*(\S+)\s*\n\s*(?:parameters|args?)\s*:\s*(\{[^}]+\})/i
        m = text.match(re)
        if (m) {
            try { let args = JSON.parse(m[2]); return { name: m[1], args: args } } catch (e) {}
        }

        // Pattern 3: inline shell: / run: / command: prefix
        re = /(?:^|\n)\s*(?:shell|run|command)\s*:\s*(.+?)(?:\n|$)/i
        m = text.match(re)
        if (m) return { name: "run_shell_command", args: { command: m[1].trim() } }

        // Pattern 4: <tool_call> JSON </tool_call>
        re = /<tool_call>\s*(\{[^}]+\})\s*<\/tool_call>/
        m = text.match(re)
        if (m) {
            try {
                let json = JSON.parse(m[1])
                if (json.name && (json.arguments || json.args))
                    return { name: json.name, args: json.arguments || json.args }
            } catch (e) {}
        }

        // Pattern 5: ```tool_call ... ``` code block
        re = /```(?:tool_call|tool)?\s*\n?\s*(\{[^}]+\})\s*\n?\s*```/
        m = text.match(re)
        if (m) {
            try {
                let json = JSON.parse(m[1])
                if (json.name && (json.arguments || json.args))
                    return { name: json.name, args: json.arguments || json.args }
            } catch (e) {}
        }

        // Pattern 6: {"function_call": {"name": "...", "arguments": {...}}}
        re = /\{[^{}]*"function_call"\s*:\s*(\{[^}]+\})[^{}]*\}/
        m = text.match(re)
        if (m) {
            try {
                let fc = JSON.parse(m[1])
                if (fc.name && fc.arguments)
                    return { name: fc.name, args: fc.arguments }
            } catch (e) {}
        }

        // Pattern 7: tiny-model prose descriptions. Small local LLMs
        // (granite-2b, qwen-0.5b, phi-1.5, etc.) often fail to emit
        // proper tool_calls deltas and instead narrate a multi-step
        // plan in plain text:
        //   "1. Execute shell command: xdg-open https://youtube.com
        //    2. Create a file /tmp/youtube.desktop ...
        //    3. Launch the browser to open YouTube using: xdg-open ..."
        // If we don't catch this, the user sees a verbose recipe
        // instead of an executed action. We look for the first
        // runnable command in the text — anywhere in the response,
        // not just after a verb — and route it through
        // run_shell_command. We anchor on (^|\n|:\s) so we don't
        // match mid-word. Skip lines that are obviously explanatory
        // ("use xdg-open to open...") by requiring a real command
        // shape: binary followed by an argument that isn't a
        // conjunction.
        let runnables = text.match(/(?:^|[\n:]\s*)(xdg-open\s+\S+|setsid\s+\S+|nohup\s+\S+|bash\s+-c\s+\S+|firefox\s+\S+|chromium\s+\S+|google-chrome\s+\S+|code\s+\S+|notify-send\s+\S+|systemctl\s+\S+)/i);
        if (runnables) {
            let cmd = runnables[1].trim();
            // Only treat as tool call if the command is actually a
            // recognized opener — avoid false positives on mentions
            // like "you can use xdg-open".
            let openerRe = /^(xdg-open|setsid|nohup|bash\s+-c|firefox|chromium|google-chrome|code|notify-send|systemctl)/i;
            if (openerRe.test(cmd)) {
                return { name: "run_shell_command", args: { command: cmd } };
            }
        }

        // Pattern 8: 'open <url> in browser' / 'go to <url>' style. Tiny
        // models often narrate this as "I would open https://...
        // in the default browser using xdg-open" without ever
        // calling a tool. We catch the explicit URL mention and
        // route it through the agent's open_url tool (which has
        // alias expansion and a clean error path).
        let urlRe = /(?:open|go to|browse to|visit|navigate to|abre|abrir)\s+(https?:\/\/\S+|(?:www\.)?[a-z0-9-]+(?:\.[a-z]{2,})(?:\/\S*)?|youtube|github|gmail|google|reddit|twitter|stackoverflow)/i;
        let urlMatch = text.match(urlRe);
        if (urlMatch) {
            let raw = urlMatch[1];
            // Skip obvious non-URL fragments
            if (!/^(the|a|my|this|that)$/i.test(raw)) {
                return { name: "open_url", args: { url: raw } };
            }
        }

        return null
    }

    // Normalize tool-call arguments so that minor cosmetic
    // variations from the model (extra spaces, stray quotes,
    // different key ordering) don't bypass duplicate detection.
    // Returns a stable string fingerprint of the args.
    function _normalizeToolArgs(args) {
        if (args === null || args === undefined) return "";
        if (typeof args === "string") {
            return args.trim().replace(/\s+/g, " ");
        }
        if (typeof args === "object") {
            let normalized = {};
            let keys = Object.keys(args).sort();
            for (let i = 0; i < keys.length; i++) {
                let k = keys[i];
                let v = args[k];
                if (typeof v === "string") {
                    normalized[k] = v.trim().replace(/\s+/g, " ");
                } else {
                    normalized[k] = v;
                }
            }
            return JSON.stringify(normalized);
        }
        return String(args);
    }

    // Decide whether the incoming tool call should be auto-rejected.
    // Returns one of:
    //   ""             — not a duplicate, allow the call
    //   "duplicate"    — exact same tool + args already executed this turn
    //   "rate-limit"   — same tool already called MAX times this turn
    //
    // We use a two-pronged check:
    //   1. Normalized args fingerprint — catches "xdg-open https://..."
    //      vs "xdg-open  https://..." (extra spaces), or any other
    //      cosmetic variation the small model might emit.
    //   2. Rate limit by tool name — if the same tool has been
    //      called MAX_TOOL_CALLS_PER_TURN times regardless of args,
    //      reject.  This prevents loops where the model keeps varying
    //      the args slightly to evade detection.
    //
    // Scoped to the current user turn (walks backwards from end
    // until it hits a user message).  This way a later, different
    // user request can legitimately re-use the same tool.
    //
    // Set to 5 (was 1): the "duplicate" check (normalized args
    // fingerprint) already catches identical tool+args calls.  The
    // rate limit is a safety net for models that vary args slightly
    // to dodge the fingerprint — 5 different calls in one turn is
    // almost certainly a loop, while 2-3 different commands (e.g.
    // "ls /home" then "ls /etc") are legitimate multi-action prompts.
    readonly property int _maxToolCallsPerTurn: 5

    // Read-only / idempotent tools. Their result reflects current
    // system state (window list, workspace list, installed apps) and
    // always changes between calls — re-invoking them is the model's
    // normal way of refreshing its view between user actions, NOT a
    // loop. They bypass the duplicate-fingerprint check entirely; the
    // rate-limit still applies as a runaway-loop safety net.
    readonly property var _idempotentReadTools: [
        "list_windows",
        "list_workspaces",
        "list_monitors",
        "list_installed_apps"
    ]

    function _shouldAutoRejectToolCall(toolName, args) {
        if (!toolName) return "";

        let argsFp = root._normalizeToolArgs(args);
        let callCount = 0;
        let isIdempotent = root._idempotentReadTools.indexOf(toolName) !== -1;

        for (let i = root.currentChat.length - 1; i >= 0; i--) {
            let m = root.currentChat[i];
            if (m.role === "user") break;
            if (m.role === "assistant" && m.functionCall
                    && m.functionCall.name === toolName) {
                // Skip the current message (no functionPending yet
                // because we're checking before attachment).  Only
                // count previously-seen calls.
                if (m.functionPending === true) continue;

                callCount++;
                // Exact (normalized) duplicate of a previous call.
                // Skipped for read-only tools — see _idempotentReadTools.
                if (!isIdempotent && m.functionPending === false) {
                    let prevFp = root._normalizeToolArgs(m.functionCall.args);
                    if (prevFp === argsFp) {
                        return "duplicate";
                    }
                }
            }
        }

        // Rate limit: if this tool was already called the max
        // number of times in the current turn, reject — regardless
        // of whether the args match.  The model is looping.
        if (callCount >= root._maxToolCallsPerTurn) {
            return "rate-limit";
        }

        return "";
    }

    // Strip a pending function call from the last assistant message
    // and push a synthetic function result that tells the model the
    // call was auto-rejected.  This is the single source of truth
    // for what an auto-rejection looks like — both the native
    // streaming path and the text-fallback path route through here
    // so the model gets a consistent protocol regardless of how
    // the tool call was detected.
    //
    // `reason` is one of: "duplicate", "rate-limit".
    function _autoRejectToolCall(toolName, toolCallId, reason) {
        let dupChat = Array.from(root.currentChat);
        let dupLast = dupChat[dupChat.length - 1];
        dupLast.functionCall = undefined;
        dupLast.functionPending = false;
        dupLast.functionApproved = false;
        dupLast.toolCallId = "";
        dupChat[dupChat.length - 1] = dupLast;

        let msg;
        if (reason === "duplicate") {
            msg = "[Auto-rejected: this exact tool call (same name and "
                + "arguments) was already executed earlier in this "
                + "conversation. Do NOT re-invoke the same tool with the "
                + "same arguments. Respond with a brief text "
                + "confirmation of what was done, or wait for the user's "
                + "next request.]";
        } else if (reason === "rate-limit") {
            msg = "[Auto-rejected: the tool '" + toolName + "' has already "
                + "been called " + root._maxToolCallsPerTurn + " times in "
                + "this turn. The system detected a loop. Do NOT call this "
                + "tool again in this turn. Respond with a brief text "
                + "summary of what was already done, or ask the user for "
                + "clarification.]";
        } else {
            msg = "[Auto-rejected: tool call not allowed (" + reason + "). "
                + "Respond with text instead.]";
        }

        dupChat.push({
            role: "function",
            name: toolName,
            content: msg,
            tool_call_id: toolCallId
        });
        root.currentChat = dupChat;

        // Queue a follow-up request so the model is asked to
        // respond with text instead of looping again.  The
        // re-entrancy guard in makeRequest sees requestInFlight is
        // still true, so it sets requestQueued = true; the existing
        // drainPending logic at the end of onExited then runs the
        // queued makeRequest once the guard is cleared.
        root.isLoading = true;
        root.streamingStatus = "streaming…";
        root.lastError = "";
        root.makeRequest();
    }

    onCurrentModeChanged: { _rebuildActiveTools(); saveCurrentChat(); }
    onCurrentAgentIdChanged: { _rebuildActiveTools(); saveCurrentChat(); }

    Connections {
        target: root.agentToolRegistry
        function onAgentToolsChanged() { root._rebuildActiveTools(); }
    }
    Connections {
        target: Config.ai
        function onEnabledToolsChanged() { root._rebuildActiveTools(); }
        function onToolChanged() { root._rebuildActiveTools(); }
    }

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

    function loadChat(id) {
        if (!id) return;
        let filename = chatDir + "/" + id + ".json";
        loadChatProcess.targetId = id;
        loadChatProcess.command = ["cat", "--", filename];
        loadChatProcess.running = true;
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
        case "/mode":
            setMode(args === "chat" || args === "agent" ? args : (currentMode === "agent" ? "chat" : "agent"));
            pushSystemMessage("Mode: " + currentMode);
            return true;
        case "/agent":
            if (!args) { pushSystemMessage("Current agent: " + (currentAgentId === "" ? "all" : currentAgentId)); return true; }
            if (args === "all" || args === "none") { setAgent(""); pushSystemMessage("Agent: all"); return true; }
            let conns = root.agentManager ? root.agentManager.connections : [];
            let found = null;
            for (let i = 0; i < conns.length; i++) { if (conns[i] && conns[i].name && conns[i].name.toLowerCase().includes(args.toLowerCase())) { found = conns[i]; break; } }
            if (found) { setAgent(found.id); pushSystemMessage("Agent: " + found.name); }
            else { pushSystemMessage("Agent not found. Use /agents."); }
            return true;
        case "/agents": listAgents(); return true;
        case "/tools": listTools(); return true;
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

    function _onToolFinished(toolName, toolCallId, result, isError) {
        let newChat = Array.from(currentChat);
        // Prefer the id captured at approval time (lastToolCallId)
        // over the one passed in — same rationale as the
        // commandExecutionProc.onExited fix.
        let id = root.lastToolCallId || toolCallId || "";
        let toolMsg = { role: "function", name: toolName, content: result || "" };
        if (id) toolMsg.tool_call_id = id;
        if (isError) toolMsg.is_error = true;
        newChat.push(toolMsg);
        root.lastToolCallId = "";
        currentChat = newChat;
        saveCurrentChat();
        isLoading = true;
        lastError = "";
        streamingStatus = "";
        makeRequest();
    }

    // Function Call Handling
    function approveCommand(index) {
        let msg = currentChat[index];
        if (!msg.functionCall)
            return;

        let newChat = Array.from(currentChat);
        newChat[index].functionPending = false;
        newChat[index].functionApproved = true;
        // Lock in the tool call id at approval time. The provider's
        // streaming deltas may emit different `id` values across
        // chunks, and the assistant's stored toolCallId is whatever
        // the LAST delta happened to contain. By capturing the id
        // that the UI was actually showing to the user when they
        // approved, we guarantee the tool result uses the same id
        // that the assistant message carries forward.
        root.lastToolCallId = msg.toolCallId || msg.functionCall.tool_call_id || "";
        currentChat = newChat;
        saveCurrentChat();

        let args = msg.functionCall.args;
        let toolName = msg.functionCall.name;
        let toolCallId = msg.functionCall.tool_call_id || "";
        if (msg.functionCall.name === "run_shell_command") {
            // Wrap with `timeout N` so a hung GUI launch (e.g.
            // `firefox URL` which only returns when the user
            // closes the browser) can't freeze the chat forever.
            // For commands that obviously spawn a GUI window
            // (xdg-open, firefox, mpv, …) we also detach with
            // setsid+nohup+& so the shell returns immediately
            // and the AI gets a fast "launched" acknowledgement.
            commandExecutionProc.originalCommand = args.command || "";
            commandExecutionProc.detached = root._shouldDetach(args.command || "");
            let cmd;
            if (commandExecutionProc.detached) {
                // Detached launch: redirect output, run in new
                // session, return immediately. We send the
                // backgrounded process output to /tmp/null so we
                // don't fill up the home directory with stray
                // logs.
                cmd = "setsid nohup bash -c "
                    + "'" + (args.command || "").replace(/'/g, "'\\''") + "'"
                    + " </dev/null >/tmp/null 2>&1 &";
            } else {
                // Foreground with timeout. We don't use timeout's
                // --foreground flag because we want to capture
                // stdout/stderr as the command runs.
                cmd = "timeout " + root.shellCommandTimeoutSeconds + " bash -c "
                    + "'" + (args.command || "").replace(/'/g, "'\\''") + "'";
            }
            commandExecutionProc.command = ["bash", "-c", cmd];
            commandExecutionProc.targetIndex = index;
            commandExecutionProc.running = true;
            root.streamingStatus = commandExecutionProc.detached
                ? "launched: " + toolName
                : "running tool: " + toolName;
        } else if (root.agentToolRegistry && root.agentToolRegistry.hasTool(toolName)) {
            root.streamingStatus = "running tool: " + toolName;

            // Gate: if the agent is unreachable or the HTTP
            // endpoint never responds, the invoke callback will
            // never fire. The timeout timer below (default 35s,
            // see agentToolInvokeTimeout.interval) synthesises a
            // failure so the chat doesn't hang. 35s leaves room
            // for the bridge's 25s curl --max-time plus a 5s
            // buffer for xdg-open on cold-launch Wayland.
            var finished = false;
            root.agentToolInvokeTimeout.stop();
            root.agentToolInvokeTimeout.onFire = function() {
                if (!finished) {
                    finished = true;
                    let secs = Math.round(root.agentToolInvokeTimeout.interval / 1000);
                    _onToolFinished(toolName, toolCallId,
                        "Tool invocation timed out after " + secs
                        + "s — the agent may be unreachable or the tool "
                        + "is taking too long. The action may still have "
                        + "happened in the background.",
                        true);
                }
            };
            root.agentToolInvokeTimeout.restart();

            root.agentToolRegistry.invoke(toolName, args, function(result) {
                if (finished) return;
                finished = true;
                root.agentToolInvokeTimeout.stop();
                root.agentToolInvokeTimeout.onFire = null;

                let output = result.error || result.content || "";
                if (result.error && !result.content) {
                    output = "Error: " + result.error;
                } else if (result.error && result.content) {
                    output = result.content + "\n\n[Error: " + result.error + "]";
                }
                _onToolFinished(toolName, toolCallId, output, !!result.error && !result.content);
            });
        } else {
            // Tool name not in registry (e.g. stale chat, registry
            // disconnected mid-flight). Don't leave the user
            // staring at a frozen approval card.
            let newChat = Array.from(currentChat);
            newChat[index].functionPending = false;
            newChat[index].functionApproved = false;
            // Propagate tool_call_id so the outgoing tool message
            // pairs with the assistant's tool_calls[].id. Same fix
            // as in _onToolFinished — without it the conversation
            // is malformed and the model returns empty on the next
            // turn.
            newChat.push({
                role: "function",
                name: toolName,
                content: "Tool unavailable: no agent is currently exposing '" + toolName + "'.",
                tool_call_id: root.lastToolCallId || toolCallId
            });
            root.lastToolCallId = "";
            root.currentChat = newChat;
            root.saveCurrentChat();
            root.streamingStatus = "";
            root.makeRequest();
        }
    }

    function rejectCommand(index) {
        let newChat = Array.from(currentChat);
        newChat[index].functionPending = false;
        newChat[index].functionApproved = false;

        // Prefer lastToolCallId (captured at approval time) for the
        // same reason as the other tool-result sites: the persisted
        // functionCall.tool_call_id can drift from the id the user
        // actually saw and approved, and the assistant's outgoing
        // tool_calls[].id is the one that matters for pairing.
        let rejectedToolCallId = root.lastToolCallId
            || (newChat[index].functionCall
                ? newChat[index].functionCall.tool_call_id
                : "")
            || "";
        root.lastToolCallId = "";

        newChat.push({
            role: "function",
            name: newChat[index].functionCall.name,
            content: "User rejected the command execution.",
            tool_call_id: rejectedToolCallId
        });

        currentChat = newChat;
        saveCurrentChat();
        streamingStatus = "";
        makeRequest();
    }

    function sendMessage(text, attachments) {
        if (text.trim() === "" && (!attachments || attachments.length === 0))
            return;
        if (processCommand(text))
            return;
        // Clear any lingering stop/kill state from a previous
        // stopGeneration() call. This is the only place where
        // _killedByUser should transition from true→false — the
        // onExited handlers intentionally leave it set so a
        // second onExited (e.g. from a concurrently-killed shell
        // command) also sees the flag and bails out instead of
        // corrupting the chat.
        _killedByUser = false;
        shellCmdWasCancelled = false;
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
        // Re-entrancy guard. If a curl is already in flight and
        // something else (a tool-result follow-up, a re-send after
        // an error, an agent tool completion) calls makeRequest
        // again, queue the second call so it runs after the
        // current one finishes — instead of spawning a second
        // curl in parallel that would race for the responseBuffer
        // and the streaming placeholder. Without this guard the
        // sidebar visibly freezes when the AI chains several tool
        // calls quickly (one finishes, another starts, the user
        // sees two interleaved ghost placeholders).
        if (root.requestInFlight) {
            root.requestQueued = true;
            return;
        }
        root.requestInFlight = true;
        // 90s watchdog — fires if curl takes longer than its own
        // --max-time 90s (e.g. bodyFileView stuck), reset the
        // flag and bail so the sidebar isn't permanently hung.
        root.requestWatchdog.restart();

        // Ollama lifecycle: before sending the chat request, ensure
        // the local daemon is actually up. The model fetch already
        // does this (via _ensureOllamaThenFetch) but Ollama can fall
        // over between the fetch and the user's first message, or
        // the user can kill it mid-session. Without this gate the
        // curl would fail with "Network error" after the 90s watchdog
        // (matching the [GIN] 500 + 1m30s the user saw). We keep the
        // requestInFlight flag set so the re-entrancy guard does not
        // queue a second makeRequest while we wait for the ensure
        // script — it will be cleared and the request resumed in
        // ollamaEnsureProcess.onExited via _ollamaChatPending.
        if (currentModel && currentModel.provider === "ollama"
                && root.ollamaStatus !== "running"
                && root.ollamaStatus !== "starting") {
            isLoading = true;
            streamingStatus = "starting Ollama…";
            root._ensureOllamaThenChat();
            return;
        }

        let apiKey = getApiKey(currentModel);
        if (!currentModel) {
            isLoading = false;
            streamingStatus = "";
            let errChat = Array.from(currentChat);
            errChat.push({
                role: "system",
                content: "No AI model selected. Pick one in Settings or with `/model`."
            });
            currentChat = errChat;
            root.requestInFlight = false;
            return;
        }
        if (!apiKey && currentModel.requires_key) {
            // KeyStore may still be loading its keys.db at startup.
            // The user sees this only on the very first send attempt;
            // the KeyStore finishes loading ~1s later and onKeysChanged
            // triggers a model re-fetch. Show a friendlier message
            // than the old "API key missing" so the user knows to wait.
            if (!KeyStore.initialized) {
                let waitChat = Array.from(currentChat);
                waitChat.push({
                    role: "system",
                    content: "Loading API keys, please wait a moment and try again..."
                });
                currentChat = waitChat;
                isLoading = false;
                streamingStatus = "";
                root.requestInFlight = false;
                return;
            }
            lastError = "API Key missing for " + currentModel.name + ". Add it in Settings or set " + (currentModel.key_id || "the environment variable") + ".";
            isLoading = false;

            let errChat = Array.from(currentChat);
            errChat.push({
                role: "assistant",
                content: "Error: " + lastError
            });
            currentChat = errChat;
            streamingStatus = "";
            root.requestInFlight = false;
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

        // ── Sanitise the chat before serialising ──────────────────
        // Minimal sweep: only remove messages that are clearly
        // orphaned or that would confuse the AI. The heavy tool-
        // call-id validation was replaced by `lastToolCallId`
        // (captured in approveCommand), which guarantees the tool
        // result's tool_call_id always matches the assistant's
        // tool_calls[].id without mutating the chat array at all.
        let chatTouched = false;
        for (let i = 0; i < currentChat.length; i++) {
            let m = currentChat[i];
            // Orphaned tool invocation — the user never accepted
            // or rejected it. Drop it entirely so the AI doesn't
            // see a dangling function call.
            if (m && m.functionCall && m.functionPending === true) {
                if (!chatTouched) {
                    currentChat = Array.from(currentChat);
                    chatTouched = true;
                }
                currentChat.splice(i, 1);
                i--;
                continue;
            }
            // Strip empty assistant placeholders — messages that have
            // no content AND no functionCall at all.  These are the
            // ghosts of a previous makeRequest() that never completed
            // streaming.  We MUST NOT remove messages that hold an
            // already-executed tool call (functionCall present,
            // functionPending === false) because:
            //   (a) the model needs to see its own tool_calls in the
            //       history so it doesn't re-invoke the same tool,
            //   (b) the duplicate/rate-limit detection walks the chat
            //       history to find previous calls of the same tool.
            // The previous condition (!m.functionCall || !m.functionPending)
            // was BROKEN: for an approved call functionPending is false,
            // so !m.functionPending is true, and the entire approved
            // message was deleted every makeRequest — hence the
            // "xdg-open x4" loop that no rate-limit could stop.
            if (m && m.role === "assistant"
                     && (!m.content || m.content === "")
                     && !m.functionCall) {
                if (!chatTouched) {
                    currentChat = Array.from(currentChat);
                    chatTouched = true;
                }
                currentChat.splice(i, 1);
                i--;
                continue;
            }
        }

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
            if (msg.functionCall) {
                apiMsg.functionCall = msg.functionCall;
                // Propagate the tool call id so OpenAI-compatible
                // strategies can pair assistant.tool_calls[].id with
                // the matching tool/tool_call_id result message.
                if (msg.toolCallId)
                    apiMsg.toolCallId = msg.toolCallId;
            }
            if (msg.geminiParts)
                apiMsg.geminiParts = msg.geminiParts;
            // CRITICAL: copy `tool_call_id` (snake_case) from the
            // internal tool-result message to the outgoing message.
            // Without this the OpenAI/DeeSeek/etc. API sees:
            //   assistant → tool_calls: [{id: "call_xxx", ...}]
            //   tool      → {content: "..."}      ← no id
            // which is an unpaired tool result. The provider either
            // rejects the request outright or, more commonly, treats
            // the tool result as orphaned context and returns empty
            // content on the next assistant turn. This was THE root
            // cause of the "1 system tool available but AI doesn't
            // use it" symptom: the conversation was malformed from
            // the provider's perspective, so the model lost track of
            // what tool it had just invoked and refused to invoke it
            // again. `name` is intentionally skipped (Fix B) — the
            // tool-message spec only accepts tool_call_id + content.
            if (msg.tool_call_id)
                apiMsg.tool_call_id = msg.tool_call_id;
            if (msg.name && msg.role !== "function" && msg.role !== "tool")
                apiMsg.name = msg.name;
            messages.push(apiMsg);
        }

        // Build body — always use streaming
        let body = currentStrategy.getStreamBody(messages, currentModel, activeTools);

        // Reset streaming buffer
        responseBuffer = "";
        streamingContent = "";
        pendingToolCall = null;
        streamingStatus = "streaming…";
        root._streamLastModelUpdate = 0;
        root._streamUpdateTimer.stop();

        // Reset the elapsed-time indicator. The timer fires every
        // 5s and rewrites `streamingStatus` to "streaming… Ns"
        // so the user sees the AI is still working even when the
        // provider stalls (no tokens arrive for a while).
        streamingStartedAt = Date.now();
        streamingElapsedTimer.restart();

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
            // Timeouts:
            //   --connect-timeout 5   → fail fast on TCP refusal
            //   --max-time <inactivity> → bound the transfer at the
            //     configured inactivity timeout (default 120s, see
            //     Config.ai.requestTimeoutSeconds). Kills wedged /
            //     silent streams. Mirrors Odysseus's per-read
            //     inactivity cap.
            //   Wall-clock deadline = max(timeout * 4, 1200s) is
            //     enforced separately inside curlProcess.stdout
            //     .onRead — it catches the rare "one byte every 5s"
            //     runaway that --max-time alone would not.
            // The 120s default is generous enough for small Ollama
            // models (qwen2.5:3b on CPU) on long tool-using
            // conversations without freezing the sidebar if the
            // model is genuinely stuck.
            let timeoutSecs = Config.ai.requestTimeoutSeconds || 120;
            curlCmd = "curl -s --no-buffer -N -X POST"
                    + " --connect-timeout 5"
                    + " --max-time " + timeoutSecs
                    + " \"" + payload.endpoint + "\" "
                    + headerArgs + " -d @" + bodyPath;
        }

        // Stamp the wall-clock start so curlProcess.stdout.onRead can
        // apply the deadline cap. Cleared in every terminal path
        // (onExited, watchdog, deadline hit) below.
        root.requestStartMs = Date.now();

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
                // Wall-clock deadline — Odysseus's complementary cap
                // for streams that trickle bytes forever and so never
                // trip the inactivity timeout (curl --max-time).
                // Computed at request start (root.requestStartMs) and
                // re-checked on every chunk. The inactivity watchdog
                // above kills truly silent streams; this kills the
                // rare "one byte every 5s" runaway that would otherwise
                // burn the wall-clock budget for many minutes.
                if (root.requestStartMs > 0
                        && Date.now() - root.requestStartMs
                                > root._requestWallClockDeadlineMs) {
                    let totalSecs = Math.round(
                        root._requestWallClockDeadlineMs / 1000);
                    console.warn("Ai.qml: stream exceeded wall-clock deadline ("
                                 + totalSecs + "s) — cutting off");
                    if (root.curlProcess && root.curlProcess.running) {
                        root.curlProcess.running = false;
                    }
                    root.requestInFlight = false;
                    root.streamingStatus = "request exceeded " + totalSecs
                                            + "s wall-clock limit";
                    root.isLoading = false;
                    root.streamingElapsedTimer.stop();
                    root.requestStartMs = 0;
                    let errChat = Array.from(root.currentChat);
                    if (errChat.length > 0
                            && errChat[errChat.length - 1].role === "assistant"
                            && (!errChat[errChat.length - 1].content
                                || errChat[errChat.length - 1].content === "")) {
                        errChat[errChat.length - 1].content =
                            "[Stream exceeded the " + totalSecs
                            + "s wall-clock limit. The model may be in a "
                            + "runaway generation loop. Try a different "
                            + "model or split the request into smaller pieces.]";
                        errChat[errChat.length - 1].role = "system";
                    } else {
                        errChat.push({
                            role: "system",
                            content: "[Stream exceeded " + totalSecs
                                     + "s wall-clock limit.]"
                        });
                    }
                    root.currentChat = errChat;
                    root.saveCurrentChat();
                    if (root.requestQueued) {
                        root.requestQueued = false;
                        Qt.callLater(root.makeRequest);
                    }
                    return;
                }
                let result = root.currentStrategy.parseStreamChunk(data);

                if (result.error) {
                    root.lastError = result.error;
                    return;
                }

                if (result.content) {
                    root.responseBuffer += result.content;
                    root._updateStreamingMessage();
                }

                // Accumulate tool-call deltas. OpenAI-compatible APIs
                // emit one chunk per tool-call index; each chunk may
                // carry partial arguments (a JSON string built up over
                // several `data:` lines). We merge them by index so
                // the final call has the complete name + arguments.
                // No QML-bound properties are touched here — only the
                // internal `pendingToolCall` var, so no sidebar binding
                // re-evaluation cascades during streaming.
                if (result.toolCallDelta && result.toolCallDelta.length > 0) {
                    let acc = root.pendingToolCall;
                    if (!acc || !acc._calls) {
                        acc = { _calls: [], _id: "" };
                    }
                    for (let i = 0; i < result.toolCallDelta.length; i++) {
                        let d = result.toolCallDelta[i];
                        if (!d) continue;
                        let idx = (d.index !== undefined) ? d.index : 0;
                        while (acc._calls.length <= idx) acc._calls.push({});
                        let slot = acc._calls[idx];
                        if (d.id) slot.id = d.id;
                        if (d.type) slot.type = d.type;
                        if (d.function) {
                            if (!slot.function) slot.function = { name: "", arguments: "" };
                            if (d.function.name) slot.function.name += d.function.name;
                            if (d.function.arguments) slot.function.arguments += d.function.arguments;
                        }
                        if (d.id && !acc._id) acc._id = d.id;
                    }
                    root.pendingToolCall = acc;
                }

                // Note: done is handled in onExited
            }
        }

        stderr: StdioCollector {
            id: curlStderr
        }

         onExited: exitCode => {
            // If the user called stopGeneration(), we set
            // curlProcess.running=false ourselves. The onExited
            // callback still fires because the OS cleaned up the
            // process, but we must NOT overwrite the placeholder
            // message (already marked "Stopped by user" in
            // stopGeneration) and must NOT call saveCurrentChat
            // (which would re-write the pre-fix state).
            // NOTE: we intentionally do NOT reset _killedByUser
            // here. If both curl and a shell command were running,
            // resetting on the first onExited would let the second
            // handler proceed normally and corrupt the chat.
            // _killedByUser is reset only in sendMessage() — when
            // the user explicitly sends the next message.
            if (root._killedByUser) {
                root.responseBuffer = "";
                root.streamingContent = "";
                root.pendingToolCall = null;
                root.streamingStatus = "";
                root.streamingElapsedTimer.stop();
                root.streamingStartedAt = 0;
                root.requestStartMs = 0;
                root.requestInFlight = false;
                root.requestQueued = false;
                root.requestWatchdog.stop();
                return;
            }

            root.isLoading = false;
            root._streamUpdateTimer.stop();
            root._flushStreamUpdate();

            if (exitCode === 0) {
                // If a tool call was streamed, attach it to the last
                // assistant message FIRST, before checking for the
                // "no response" fallback. Otherwise a tool-only
                // response (no preface text — common when the AI
                // just goes straight to a tool call) would be
                // overwritten with "No response received from the
                // API." even though the response *is* the tool
                // call.
                let toolAttached = false;
                if (root.pendingToolCall && root.pendingToolCall._calls && root.pendingToolCall._calls.length > 0 && root.currentChat.length > 0) {
                    let calls = root.pendingToolCall._calls;
                    let primary = calls[0];
                    if (primary && primary.function && primary.function.name) {
                        let argsStr = primary.function.arguments || "{}";
                        let parsed = {};
                        try { parsed = JSON.parse(argsStr); } catch (e) { parsed = { _raw: argsStr }; }
                        let callToolId = primary.id || root.pendingToolCall._id || "";

                        // ── Auto-reject duplicate / looping tool calls ──
                        // Small local models get stuck in loops where
                        // they re-invoke the same tool (or slightly
                        // varied args) every turn — especially for
                        // detached commands like xdg-open that return
                        // immediately.  Instead of asking the user to
                        // approve the same launch 3+ times, detect the
                        // loop and auto-reject with a clear directive
                        // to respond with text.
                        let rejectReason = root._shouldAutoRejectToolCall(
                            primary.function.name, parsed);
                        if (rejectReason !== "") {
                            root._autoRejectToolCall(
                                primary.function.name, callToolId, rejectReason);
                            toolAttached = true;
                        } else if (Config.ai.toolAutoApprove) {
                            // ── Auto-approve any tool ──
                            // The user enabled auto-approve. Attach
                            // the functionCall and immediately approve
                            // it — the tool runs without showing an
                            // approval card, regardless of tool name.
                            let autoChat = Array.from(root.currentChat);
                            let autoLast = autoChat[autoChat.length - 1];
                            autoLast.functionCall = {
                                name: primary.function.name,
                                args: parsed,
                                tool_call_id: callToolId
                            };
                            autoLast.toolCallId = callToolId;
                            autoLast.functionPending = true;
                            autoChat[autoChat.length - 1] = autoLast;
                            root.currentChat = autoChat;
                            toolAttached = true;
                            root.approveCommand(autoChat.length - 1);
                        } else {
                            let newChat = Array.from(root.currentChat);
                            let last = newChat[newChat.length - 1];
                            last.functionCall = {
                                name: primary.function.name,
                                args: parsed,
                                tool_call_id: callToolId
                            };
                            last.toolCallId = callToolId;
                            last.functionPending = true;
                            newChat[newChat.length - 1] = last;
                            root.currentChat = newChat;
                            root.streamingStatus = "awaiting tool approval…";
                            toolAttached = true;
                        }
                    }
                }

                // ── Text-based tool-call fallback for local / small models ──
                // Many small models (Ollama quantised models, local CPU
                // models) cannot properly emit the OpenAI tool_calls
                // streaming delta, but they DO describe what tool they
                // want to call in their text output using structured
                // markers.  Without this fallback the model's intent
                // stays invisible and the sidebar shows "empty response".
                if (!toolAttached && root.responseBuffer) {
                    let detected = _detectTextToolCall(root.responseBuffer);
                    if (detected && root.currentChat.length > 0) {
                        // Same robust auto-reject for text-detected
                        // tool calls — a small model that can't emit
                        // proper tool_calls deltas will sometimes
                        // still loop on its detected intent.
                        let rejectReason = root._shouldAutoRejectToolCall(
                            detected.name, detected.args || {});
                        if (rejectReason !== "") {
                            let callId = "call_" + Math.random().toString(36).slice(2);
                            root._autoRejectToolCall(
                                detected.name, callId, rejectReason);
                            toolAttached = true;
                        } else {
                            let callId = "call_" + Math.random().toString(36).slice(2);
                            let newChat = Array.from(root.currentChat);
                            let last = newChat[newChat.length - 1];
                            last.functionCall = {
                                name: detected.name,
                                args: detected.args || {},
                                tool_call_id: callId
                            };
                            last.toolCallId = callId;
                            last.functionPending = true;
                            newChat[newChat.length - 1] = last;
                            root.currentChat = newChat;
                            root.streamingStatus = "awaiting tool approval…";
                            toolAttached = true;
                        }
                    }
                }

                // ── Finalize streaming content into the model ──
                // During streaming the sidebar delegate reads from
                // `streamingContent` directly, so we never reassigned
                // currentChat on every token.  Now that streaming is
                // done, write the accumulated text into the real model
                // message so the delegate switches from plain-text to
                // Markdown rendering.  This is the ONLY currentChat
                // reassignment during the whole stream.
                //
                // Note: when a duplicate tool call was auto-rejected
                // above, the LAST message is now a function result, not
                // the assistant message.  Find the last assistant
                // message and write content to it (creating one if
                // necessary) so the next makeRequest doesn't strip it
                // as an empty placeholder.
                if (root.responseBuffer && root.currentChat.length > 0) {
                    let finalChat = Array.from(root.currentChat);
                    let lastAssistantIdx = -1;
                    for (let i = finalChat.length - 1; i >= 0; i--) {
                        if (finalChat[i].role === "assistant") {
                            lastAssistantIdx = i;
                            break;
                        }
                    }
                    if (lastAssistantIdx >= 0) {
                        let lastAssistant = finalChat[lastAssistantIdx];
                        if (!lastAssistant.content) {
                            lastAssistant.content = root.responseBuffer;
                            root.currentChat = finalChat;
                        }
                    } else {
                        // No assistant message found at all (rare
                        // — happens when tool attachment and text
                        // fallback both pushed a function result and
                        // we somehow lost the assistant placeholder).
                        // Add one so the model has somewhere to write
                        // its next response.
                        finalChat.push({
                            role: "assistant",
                            content: root.responseBuffer,
                            model: currentModel ? currentModel.name : "Unknown"
                        });
                        root.currentChat = finalChat;
                    }
                }

                // Handle the empty-response case. Three distinct
                // situations to distinguish:
                //
                //   (a) Tool call was attached — that's the model's
                //       response. Don't overwrite it with anything.
                //   (b) Empty response AND the immediately previous
                //       message is a `function` tool result — the
                //       model produced an empty completion after
                //       running the tool. This is normal (DeepSeek
                //       and others sometimes return finish_reason=stop
                //       with no content). Show a small, neutral
                //       acknowledgement rather than an alarming
                //       "no response" error.
                //   (c) Empty response with no tool in context — the
                //       model genuinely produced nothing. Show a
                //       brief note so the user knows.
                if (!toolAttached && root.responseBuffer === "" && root.currentChat.length > 0) {
                    let lastMsg = root.currentChat[root.currentChat.length - 1];
                    if (!lastMsg.content) {
                        // Look at the previous message. If it's a
                        // tool result, this is the post-tool
                        // empty-completion case (b) — the user
                        // already got their action, the model just
                        // stayed quiet. Keep it subtle.
                        let prev = root.currentChat.length >= 2
                            ? root.currentChat[root.currentChat.length - 2]
                            : null;
                        let followupToTool = prev
                            && prev.role === "function"
                            && !prev.is_error;

                        let newChat = Array.from(root.currentChat);
                        if (followupToTool) {
                            // Empty completion after a successful
                            // tool run. Don't surface an alarming
                            // error — the tool already did the work.
                            // Just remove the empty placeholder so
                            // the chat doesn't render a confusing
                            // empty bubble.
                            newChat.pop();
                        } else {
                            // Genuinely empty response (no tool call
                            // was attached). The API did respond, it
                            // just produced no content. Surface a
                            // context-aware hint so the user can tell
                            // whether the AI genuinely couldn't help
                            // (no internet-search tool available) vs
                            // just chose to stay silent.
                            let hint;
                            if (root.currentMode === "agent") {
                                let conns = root.agentManager
                                    ? root.agentManager.connections
                                    : [];
                                let connected = 0;
                                for (let i = 0; i < conns.length; i++) {
                                    let c = conns[i];
                                    if (c && c.enabled && c.status === "connected") connected++;
                                }
                                // Count BOTH system tools (always
                                // present in agent mode — currently
                                // just run_shell_command) and tools
                                // exposed by connected agents. The
                                // AI can call either; the previous
                                // version only counted agent tools,
                                // which falsely claimed "none exposes
                                // any tools" even when run_shell_command
                                // was clearly usable (the AI used it
                                // for the previous turn!).
                                let sysCount = root.systemTools
                                    ? root.systemTools.length : 0;
                                let agentCount = 0;
                                if (root.agentToolRegistry
                                        && root.agentToolRegistry.tools) {
                                    agentCount = root.agentToolRegistry.tools.length;
                                }
                                let totalTools = sysCount + agentCount;
                                if (connected === 0) {
                                    hint = "Agent mode is on but no agent is "
                                         + "connected. Add one in Settings → AI → "
                                         + "Agents, or `/mode chat` to disable tools.";
                                } else if (totalTools === 0) {
                                    hint = connected + " agent" + (connected === 1 ? "" : "s")
                                         + " connected but none exposes any tools yet. "
                                         + "The model has nothing to call — try a "
                                         + "different model or check the agent config.";
                                } else if (agentCount === 0) {
                                    hint = connected + " agent" + (connected === 1 ? "" : "s")
                                         + " connected but not exposing tools yet. "
                                         + "The model can still use the "
                                         + root.systemTools.length + " system tool"
                                         + (root.systemTools.length === 1 ? "" : "s")
                                         + " (e.g. `run_shell_command`). "
                                         + "If the AI didn't use them, rephrase or `/model`.";
                                } else {
                                    hint = "The model produced no content (it may have "
                                         + "tried to call a tool that doesn't exist). "
                                         + "Try `/model` to switch, or rephrase your request.";
                                }
                            } else {
                                hint = "The model returned no response. "
                                     + "Try `/model` to switch, or resend with a shorter prompt.";
                            }
                            newChat[newChat.length - 1].content =
                                "*(empty response)* — " + hint;
                            newChat[newChat.length - 1].role = "system";
                        }
                        root.currentChat = newChat;
                    }
                }

                root.saveCurrentChat();
            } else {
                root.lastError = "Network Request Failed: " + curlStderr.text;

                let errChat = Array.from(root.currentChat);
                if (errChat.length > 0) {
                    let last = errChat[errChat.length - 1];
                    if (last.role === "assistant") {
                        last.content = "Error: " + root.lastError;
                        errChat[errChat.length - 1] = last;
                    } else {
                        errChat.push({
                            role: "system",
                            content: "Network error: " + root.lastError
                        });
                    }
                }
                root.currentChat = errChat;
            }

            root.responseBuffer = "";
            root.streamingContent = "";
            root.pendingToolCall = null;
            root.streamingStatus = "";
            root.streamingElapsedTimer.stop();
            root.streamingStartedAt = 0;
            root.requestWatchdog.stop();

            // Clear the in-flight guard and, if a second
            // makeRequest was queued during this response (e.g. a
            // tool-result callback fired while the AI was still
            // streaming), re-run it now. drainPending runs at most
            // once per curl — concurrent queued calls collapse to a
            // single follow-up.
            root.requestInFlight = false;
            if (root.requestQueued) {
                root.requestQueued = false;
                Qt.callLater(root.makeRequest);
            }
        }
    }

    // Heuristic: commands that spawn GUI windows (browsers, video
    // players, file managers) and would otherwise block the bash
    // subshell until the user closes the spawned window — which is
    // the original cause of the "running tool: run_shell_command"
    // stuck status. For those we wrap with `setsid nohup ... &` so
    // the command returns immediately and the GUI process is fully
    // detached from our process group.
    readonly property var _detachPrefixes: [
        "xdg-open ", "xdg-open\t", "xdg-open\"", "xdg-open'",
        "firefox ", "firefox\t",
        "chromium ", "chromium\t", "google-chrome ",
        "brave ", "brave-browser ",
        "mpv ", "vlc ", "feh ", "sxiv ", "imv ",
        "nautilus ", "dolphin ", "thunar ", "pcmanfm ",
        "code ", "code-insiders ", "subl ", "gedit ", "kate ",
        "spotify ", "steam "
    ]
    function _shouldDetach(command) {
        if (!command) return false;
        let lc = command.toLowerCase().trim();
        for (let i = 0; i < _detachPrefixes.length; i++) {
            if (lc.startsWith(_detachPrefixes[i])) return true;
        }
        // Catch calls anywhere in a pipeline too: `nohup xdg-open ...`
        if (/\bxdg-open\s/.test(lc)) return true;
        if (/\bfirefox\s/.test(lc)) return true;
        if (/\bchromium\s/.test(lc)) return true;
        return false;
    }

    // Number of seconds to wait before killing a shell command.
    // 60s is generous enough for slow commands (`find /`, `du -sh`)
    // but short enough that a hung GUI launch can't lock the chat
    // for an unbounded time.
    readonly property int shellCommandTimeoutSeconds: 60

    Process {
        id: commandExecutionProc
        property int targetIndex: -1
        property string originalCommand: ""
        // Did we run this command in detached (background) mode?
        // When true, the shell returns immediately so the "tool
        // result" we send back to the model is just an acknowledgement
        // that the command was launched — there is no actual stdout to
        // capture.
        property bool detached: false

        stdout: StdioCollector {
            id: cmdStdout
        }
        stderr: StdioCollector {
            id: cmdStderr
        }

         onExited: exitCode => {
            // If the user called stopGeneration() while the command
            // was running, this handler is being called because WE
            // set running=false above. Don't push a tool result or
            // call makeRequest() — the chat state was already
            // fixed in stopGeneration() and we'd just be putting it
            // back into an inconsistent state.
            if (root._killedByUser) {
                root.agentToolInvokeTimeout.stop();
                root.agentToolInvokeTimeout.onFire = null;
                return;
            }

            let output = cmdStdout.text + "\n" + cmdStderr.text;

            // Exit code 124 is `timeout`'s "command timed out" code.
            if (exitCode === 124) {
                output = (output.trim() ? output + "\n" : "")
                       + "[Command killed after "
                       + root.shellCommandTimeoutSeconds
                       + "s — likely a GUI launch that didn't detach, "
                       + "or a long-running process. Use the Stop button "
                       + "to cancel earlier.]";
            } else if (detached) {
                // The previous wording ("no output captured") made
                // models interpret the launch as a possible failure and
                // refuse to re-use the tool on follow-up turns. Be
                // explicit that detached = success, and that GUI
                // launchers (xdg-open, firefox, mpv, ...) intentionally
                // produce no output.
                output = "[✓ Launched successfully in background.]\n"
                       + "Detached processes (e.g. xdg-open, firefox, mpv) "
                       + "spawn a GUI window and return immediately — the "
                       + "absence of output is normal and does not indicate "
                       + "failure. Re-use this tool for similar requests.\n"
                       + "$ " + originalCommand;
            } else if (output.trim() === "") {
                output = "Command executed successfully (no output).";
            }

            // If the user clicked Stop while the command was running
            // we want to surface that in the tool result rather than
            // pretend the command completed normally.
            if (root.shellCmdWasCancelled) {
                output = "[Stopped by user]\n" + output;
                root.shellCmdWasCancelled = false;
            }

            let msg = currentChat[targetIndex];
            let newChat = Array.from(currentChat);

            if (msg && msg.functionCall) {
                // Use the id captured at approval time, not whatever
                // is currently in functionCall.tool_call_id. The two
                // SHOULD be identical, but in practice the provider
                // can return different ids across streaming deltas
                // and the persisted value can drift. Using
                // lastToolCallId (set in approveCommand) makes the
                // tool result's id guaranteed-equal to the assistant
                // message that proposed the call — eliminating the
                // "1 agent connected but not exposing tools" empty-
                // response bug for good.
                let toolCallId = root.lastToolCallId
                    || msg.functionCall.tool_call_id
                    || msg.toolCallId
                    || "";
                newChat.push({
                    role: "function",
                    name: msg.functionCall.name,
                    content: output,
                    tool_call_id: toolCallId
                });
                // Clear the captured id once consumed so it can't
                // accidentally leak into a different tool call.
                root.lastToolCallId = "";
            } else {
                // Edge case: the assistant message that held the
                // functionCall vanished (history cleared, model
                // changed mid-flight, etc.). Skip the function
                // result instead of crashing.
                newChat.push({
                    role: "system",
                    content: "Tool execution skipped: original message no longer in chat."
                });
            }

            root.currentChat = newChat;
            root.saveCurrentChat();
            root.streamingStatus = "";
            root.makeRequest();
        }
    }

    // Streaming update throttle. Called on every token; copies the
    // accumulated responseBuffer into streamingContent at a rate
    // that avoids overloading the sidebar TextEdit.  The sidebar
    // delegate binds to streamingContent directly — no currentChat
    // reassignment needed during the stream.
    function _updateStreamingMessage() {
        if (root.currentChat.length === 0) return;
        let last = root.currentChat[root.currentChat.length - 1];
        if (!last || last.role !== "assistant") return;

        let now = Date.now();
        if (now - root._streamLastModelUpdate >= root.streamThrottleMs) {
            root._flushStreamUpdate();
        } else if (!root._streamUpdateTimer.running) {
            root._streamUpdateTimer.start();
        }
    }

    function _flushStreamUpdate() {
        root.streamingContent = root.responseBuffer;
        root._streamLastModelUpdate = Date.now();
    }

    // Hard-cancel the currently-running tool or AI stream. Safe to
    // call when nothing is running. After this returns, the chat is
    // in a consistent state: the half-streamed AI message (if any)
    // is marked as stopped, any orphaned functionCall is cleared,
    // the shell command is killed if one was running, and
    // streamingStatus is cleared.
    //
    // Sets _killedByUser = true so the two Process.onExited handlers
    // (curlProcess, commandExecutionProc) know to clean up silently
    // instead of overwriting the placeholder message or triggering
    // a spurious makeRequest.
    function stopGeneration() {
        root._killedByUser = true;
        root._streamUpdateTimer.stop();
        agentToolInvokeTimeout.stop();
        agentToolInvokeTimeout.onFire = null;
        streamingElapsedTimer.stop();
        streamingStartedAt = 0;
        requestWatchdog.stop();

        if (curlProcess.running) {
            curlProcess.running = false;
        }

        if (commandExecutionProc.running) {
            commandExecutionProc.running = false;
        }

        // Clean EVERY message that still has a pending tool call.
        // Without this sweep, the next sendMessage() would include
        // the orphaned functionCall in the serialised messages array,
        // confusing the AI and breaking the conversation context.
        let cleaned = Array.from(currentChat);
        let touched = false;
        for (let i = 0; i < cleaned.length; i++) {
            let m = cleaned[i];
            if (m && m.functionCall && m.functionPending === true) {
                m.functionCall = undefined;
                m.functionPending = false;
                m.functionApproved = undefined;
                m.toolCallId = "";
                if (!m.content) {
                    m.content = "[Tool call cancelled: "
                        + ((m.functionCall && m.functionCall.name) || "unknown")
                        + "]";
                }
                cleaned[i] = m;
                touched = true;
            }
        }
        // Also mark the last assistant placeholder (if any) as stopped
        if (cleaned.length > 0) {
            let last = cleaned[cleaned.length - 1];
            if (last && last.role === "assistant" && (!last.functionCall || !last.functionPending)) {
                if (!last.content) last.content = "";
                last.content += (last.content ? "\n\n" : "") + "⏹ Stopped by user";
                cleaned[cleaned.length - 1] = last;
                touched = true;
            }
        }
        if (touched) root.currentChat = cleaned;

        root.shellCmdWasCancelled = true;
        root.isLoading = false;
        root.streamingStatus = "";
        root.saveCurrentChat();
    }

    // Set by stopGeneration(). commandExecutionProc.onExited checks
    // this to write "[Stopped by user]" into the tool result instead
    // of pretending the command completed normally.
    property bool shellCmdWasCancelled: false

    // Cancel a pending tool approval without running the tool and
    // without sending a follow-up request to the AI. Removes the
    // functionCall from the assistant message entirely so the chat
    // returns to a clean state.
    //
    // Creates a new message object via Object.assign so the QML
    // ListView detects the change — modifying the object in-place
    // (e.g. msg.functionCall = undefined) doesn't reliably trigger
    // delegate re-evaluation with reuseItems:true.
    function cancelTool(index) {
        if (index < 0 || index >= currentChat.length) return;
        let msg = currentChat[index];
        if (!msg || !msg.functionCall) return;

        let newChat = Array.from(currentChat);
        let newMsg = Object.assign({}, msg);
        newMsg.functionCall = undefined;
        newMsg.functionPending = false;
        newMsg.functionApproved = false;
        newMsg.toolCallId = "";
        if (!newMsg.content) {
            newMsg.content = "[Tool call cancelled: " + (msg.functionCall.name || "unknown") + "]";
        }
        newChat[index] = newMsg;
        root.currentChat = newChat;
        root.saveCurrentChat();
        root.streamingStatus = "";
    }

    // Resend the most recent user message after an empty/error
    // response. Drops the empty placeholder (and any trailing
    // system "empty response" hint) so the AI sees the same
    // history plus the user message again. The sidebar's empty-
    // response bubble calls this via Ai.resendLast() to give the
    // user a one-click retry.
    function resendLast() {
        if (isLoading) return;
        if (streamingStatus !== "") return;
        // Find the most recent user message, working backwards and
        // skipping any trailing system placeholders / empty bubbles.
        let userIdx = -1;
        for (let i = currentChat.length - 1; i >= 0; i--) {
            let m = currentChat[i];
            if (m && m.role === "user") {
                userIdx = i;
                break;
            }
        }
        if (userIdx < 0) return;

        // Trim everything AFTER the user message (assistant
        // placeholder, system hint) — the AI will regenerate from
        // the user message up.
        let trimmed = currentChat.slice(0, userIdx + 1);

        // Re-sanitise: drop any pending functionCall / empty
        // placeholders in the remaining history (defensive — should
        // already be clean).
        let cleaned = [];
        for (let i = 0; i < trimmed.length; i++) {
            let m = trimmed[i];
            if (m && m.functionCall && m.functionPending === true) continue;
            if (m && m.role === "assistant" && (!m.content || m.content === "")
                    && (!m.functionCall || !m.functionPending)) continue;
            cleaned.push(m);
        }

        currentChat = cleaned;
        isLoading = true;
        lastError = "";
        makeRequest();
    }

    // ============================================
    // CHAT STORAGE
    // ============================================

    function createNewChat() {
        currentChat = [];
        currentChatId = Date.now().toString();
        currentMode = (Config.ai.defaultMode === "chat" || Config.ai.defaultMode === "agent") ? Config.ai.defaultMode : "agent";
        currentAgentId = Config.ai.defaultAgentId || "";
        _rebuildActiveTools();
        chatModelChanged();
    }

    // Debouncer: multiple rapid `saveCurrentChat()` calls (from
    // per-token streaming, tool follow-ups, mode toggles, etc.)
    // are coalesced into a single disk write 300ms after the
    // last one. Combined with the fresh-process-per-write pattern
    // below, this prevents the saveChatProcess reuse collision
    // that was a likely cause of intermittent freezes during
    // heavy streaming.
    property Timer saveDebouncer: Timer {
        interval: 1000
        repeat: false
        onTriggered: root._saveCurrentChatNow()
    }
    // Same debouncer for history reloads (file watcher events,
    // load / delete / save all trigger reloads).
    property Timer historyReloadDebouncer: Timer {
        interval: 400
        repeat: false
        onTriggered: root._reloadHistoryNow()
    }

    function saveCurrentChat() {
        if (currentChat.length === 0)
            return;
        saveDebouncer.restart();
    }

    function _saveCurrentChatNow() {
        if (currentChat.length === 0)
            return;
        let filename = chatDir + "/" + currentChatId + ".json";
        let data = JSON.stringify(currentChat, null, 2);

        // Spawn a fresh process per save. Setting `running=true`
        // on an already-running Process is unreliable in Quickshell
        // 0.3.0 — the second save would overwrite the first's
        // filePath/data mid-flight, and only the last save's
        // content would ever reach disk. With a dedicated
        // component factory every save is independent.
        let proc = saveProcFactory.createObject(root, {});
        proc._pendingPath = filename;
        proc._pendingData = data;
        proc.command = ["bash", "-c",
            "mkdir -p '" + chatDir + "' && printf '%s' '"
            + data.replace(/'/g, "'\\''") + "' > '" + filename + "'"
        ];
        proc.running = true;
    }

    Component {
        id: saveProcFactory
        Process {
            id: saveProcInstance
            property string _pendingPath: ""
            property string _pendingData: ""
            running: false
            onExited: exitCode => {
                if (exitCode === 0) {
                    // CRITICAL: `root` inside this Process component
                    // refers to saveProcInstance, NOT the Ai singleton.
                    // The previous code did `root.chatFileView.path = …`
                    // which threw a TypeError because saveProcInstance
                    // has no `chatFileView` property. The error was
                    // silently logged and the file writeback never
                    // registered with the FileView, so subsequent
                    // saves kept racing each other (the original
                    // motivation for the factory pattern). Reference
                    // the FileView and the Ai singleton's functions
                    // by their IDs instead.
                    if (_pendingPath.length > 0)
                        chatFileView.path = _pendingPath;
                    if (_pendingData.length > 0)
                        chatFileView.setText(_pendingData);
                    if (typeof reloadHistory === "function")
                        reloadHistory();
                } else {
                    console.warn("Ai.qml: chat save failed (exit", exitCode, ")");
                }
                Qt.callLater(() => { try { saveProcInstance.destroy(); } catch (e) {} });
            }
        }
    }

    function reloadHistory() {
        historyReloadDebouncer.restart();
    }

    function _reloadHistoryNow() {
        // Single reused listHistoryProcess. Setting running=true
        // while it's already running is unreliable in Quickshell
        // 0.3.0, but the debouncer (400ms) collapses most bursts so
        // collisions are rare in practice.
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

    Process {
        id: listHistoryProcess
        stdout: StdioCollector {
            id: listHistoryStdout
        }
        running: false
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
                            path: root.chatDir + "/" + parts[0] + ".json"
                        });
                    }
                }
                root.chatHistory = history;
                root.historyModelChanged();
            }
        }
    }

    Process {
        id: deleteChatProcess
        running: false
        onExited: exitCode => {
            if (exitCode === 0) {
                reloadHistory();
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

        // Ollama (local). Unlike the cloud providers, Ollama
        // doesn't need an API key — we just probe its HTTP API.
        // The curl has a short timeout (2s connect, 3s max) so a
        // missing Ollama daemon doesn't slow down the whole model
        // fetch. Previously this branch was guarded by
        // KeyStore.hasKey("ollama"), which required an explicit
        // key entry and silently skipped Ollama entirely.
        //
        // We first ensure the daemon is actually up (via the
        // ollama-ensure.sh helper which probes + tries systemctl
        // + falls back to `ollama serve`) — this avoids the silent
        // miss where the user has Ollama installed but not running.
        pendingFetches++;
        root._ensureOllamaThenFetch();

        // MiniMax
        let minimaxKey = KeyStore.getKey("minimax");
        if (minimaxKey) {
            pendingFetches++;
            fetchProcessMiniMax.command = ["bash", "-c", "echo 'done'"];
            fetchProcessMiniMax.running = true;
        }

        // DeepSeek
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
        id: ollamaEnsureProcess
        command: ["bash", root.ollamaEnsureScript]
        onExited: exitCode => {
            if (exitCode === 0) {
                root.ollamaStatus = "running";
                if (root._ollamaFetchPending) {
                    root._ollamaFetchPending = false;
                    fetchProcessOllama.command = ["bash", "-c",
                        "curl -s --connect-timeout 2 --max-time 3 http://127.0.0.1:11434/api/tags"];
                    fetchProcessOllama.running = true;
                }
                if (root._ollamaChatPending) {
                    root._ollamaChatPending = false;
                    Qt.callLater(root.makeRequest);
                }
            } else {
                root.ollamaStatus = "failed";
                root.ollamaLastError = "ollama-ensure.sh exited " + exitCode;
                console.warn("[Ai] Ollama failed to start (exit "
                             + exitCode + ") — check ollama-ensure.sh log");
                if (root._ollamaFetchPending) {
                    root._ollamaFetchPending = false;
                    checkFetchCompletion();
                }
                if (root._ollamaChatPending) {
                    root._ollamaChatPending = false;
                    root.lastError = "Ollama failed to start: "
                                     + root.ollamaLastError;
                    root.streamingStatus = "";
                    root.isLoading = false;
                    root.requestInFlight = false;
                }
            }
        }
    }

    Process {
        id: ollamaRestartProcess
        command: ["bash", "-c",
            "pkill -f 'ollama serve' 2>/dev/null; " +
            "systemctl --user stop ollama 2>/dev/null; " +
            "systemctl stop ollama 2>/dev/null; " +
            "true"]
        onExited: exitCode => {
            ollamaRestartDelayTimer.restart();
        }
    }

    Timer {
        id: ollamaRestartDelayTimer
        interval: 1500
        repeat: false
        onTriggered: root.ensureOllamaRunning()
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

    Process {
        id: fetchProcessDeepSeek
        stdout: StdioCollector { id: fetchDeepSeekOut }
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    let data = JSON.parse(fetchDeepSeekOut.text);
                    if (data.data && data.data.length > 0) {
                        let newModels = [];
                        for (let i = 0; i < data.data.length; i++) {
                            let item = data.data[i];
                            let id = item.id;
                            let m = aiModelFactory.createObject(root, {
                                name: item.id,
                                icon: Qt.resolvedUrl("../../../assets/aiproviders/deepseek.svg"),
                                description: "DeepSeek model",
                                endpoint: "https://api.deepseek.com/v1",
                                model: id,
                                provider: "deepseek",
                                requires_key: true,
                                key_id: "DEEPSEEK_API_KEY"
                            });
                            if (m) newModels.push(m);
                        }
                        mergeModels(newModels);
                    }
                } catch (e) { console.log("DeepSeek fetch error: " + e); }
            }
            pendingFetches--;
            if (pendingFetches <= 0) _finishFetching();
        }
    }

    function checkFetchCompletion() {
        pendingFetches--;
        if (pendingFetches <= 0) _finishFetching();
    }

    function _finishFetching() {
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

    function listAgents() {
        let conns = root.agentManager ? root.agentManager.connections : [];
        if (conns.length === 0) {
            pushSystemMessage("No agents configured. Add agents in Settings.");
            return;
        }
        let msg = "**Available Agents**\n\n";
        for (let i = 0; i < conns.length; i++) {
            let c = conns[i];
            if (!c) continue;
            msg += "• **" + c.name + "** — " + (c.description || "No description") + "\n";
        }
        pushSystemMessage(msg);
    }

    function listTools() {
        let tools = activeTools;
        if (tools.length === 0) {
            pushSystemMessage("No tools available.");
            return;
        }
        let msg = "**Active Tools**\n\n";
        for (let i = 0; i < tools.length; i++) {
            let t = tools[i];
            if (!t) continue;
            msg += "• **" + (t.name || "unknown") + "** — " + (t.description || "No description") + "\n";
        }
        pushSystemMessage(msg);
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
