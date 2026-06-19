import QtQuick
import Quickshell
import Quickshell.Io

// Generic HTTP bridge for external agents (OpenClaw, Odysseus, custom APIs).
// Discovers tools via GET <endpoint><toolsPath> and invokes via POST <endpoint><invokePath>.
QtObject {
    id: root

    signal connected
    signal disconnected
    signal toolsDiscovered(var tools)
    signal error(string message)
    signal invokeResult(var requestId, var result)

    property bool isConnected: false
    property var _pendingInvokes: ({})
    property int _invokeCounter: 1

    property string endpoint: ""
    property var headers: ({})
    property string toolsPath: "/tools"
    property string invokePath: "/invoke"
    // Optional. When set, the client sends X-Model-Name / X-Model-Host
    // headers on the tools discovery request so the bridge can pick a
    // capability-aware tool subset (see _detect_capability in the
    // NothingClaw server). Most useful for local Ollama — the bridge
    // queries Ollama's /api/show for the real parameter_size instead
    // of guessing from the model name. Has no effect on agents that
    // don't understand the header.
    property string model: ""
    property string modelHost: ""

    function start(baseEndpoint, hdrs, tPath, iPath) {
        if (baseEndpoint) endpoint = baseEndpoint;
        if (hdrs) headers = hdrs;
        if (tPath) toolsPath = tPath;
        if (iPath) invokePath = iPath;

        if (!endpoint) {
            error("No endpoint configured for HTTP agent");
            return;
        }
        _discoverTools();
    }

    function setModel(modelName, host) {
        if (modelName !== undefined) root.model = modelName || "";
        if (host !== undefined) root.modelHost = host || "";
    }

    function stop() {
        isConnected = false;
        disconnected();
    }

    function invokeTool(toolName, args, callback) {
        let id = "invoke_" + (_invokeCounter++);
        if (callback) _pendingInvokes[id] = callback;

        let url = endpoint.replace(/\/+$/, "") + "/" + invokePath.replace(/^\/+/, "");
        let body = JSON.stringify({ name: toolName, arguments: args || {} });
        let hdrArgs = _buildHeaderArgs(headers);

        // Write body to temp file because curl -d @path is safer for quoting
        let bodyPath = "/tmp/nl-agent-invoke-" + Date.now() + "-" + id + ".json";
        invokeBodyFile.path = bodyPath;
        invokeBodyFile.setText(body);

        invokeProcess.property_payload = { id: id, bodyPath: bodyPath };
        invokeProcess.command = [
            "bash", "-c",
            // --connect-timeout: stop trying to connect after 5s
            // --max-time:        bound the whole transfer at 25s
            // The Ai.qml agentToolInvokeTimeout still adds an
            // outer 10s safety net, so the user always sees
            // feedback within ~10s even if curl stalls.
            "curl -s --connect-timeout 5 --max-time 25 -X POST "
            + _shQuote(url) + " " + hdrArgs
            + " -H 'Content-Type: application/json' -d @" + bodyPath
            + "; rm -f " + bodyPath
        ];
        invokeProcess.running = true;
    }

    function _discoverTools() {
        let url = endpoint.replace(/\/+$/, "") + "/" + toolsPath.replace(/^\/+/, "");
        let hdrArgs = _buildHeaderArgs(headers);
        // Send the model identifier if the user configured one on the
        // agent profile. The bridge uses it to pick a tool subset sized
        // to the model's capability tier — small local models get 4-8
        // tools, large cloud models get all 23. Bridges that don't
        // understand the header ignore it, so this is safe even for
        // non-NothingClaw HTTP agents.
        let modelArgs = "";
        if (root.model) modelArgs += " -H " + _shQuote("X-Model-Name: " + root.model);
        if (root.modelHost) modelArgs += " -H " + _shQuote("X-Model-Host: " + root.modelHost);
        // Same timeouts as invokeTool: 5s to connect, 15s total.
        // Without these, an unreachable Odysseus / OpenClaw /
        // custom MCP endpoint would freeze the agent connection at
        // boot — the discovery curl would block the bash
        // subshell forever and the agent's status would never
        // resolve past "connecting".
        discoveryProcess.command = ["bash", "-c",
            "curl -s --connect-timeout 5 --max-time 15 "
            + _shQuote(url) + " " + hdrArgs + modelArgs];
        discoveryProcess.running = true;
    }

    function _buildHeaderArgs(hdrs) {
        let s = "";
        for (let k in hdrs) {
            s += " -H " + _shQuote(k + ": " + hdrs[k]);
        }
        return s;
    }

    function _shQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    property FileView invokeBodyFile: FileView {
        printErrors: false
    }

    property Process discoveryProcess: Process {
        stdout: StdioCollector { id: discoveryOut }
        stderr: StdioCollector { id: discoveryErr }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.isConnected = false;
                root.error("Discovery failed: " + discoveryErr.text);
                return;
            }
            try {
                let data = JSON.parse(discoveryOut.text);

                // Support multiple response formats:
                // 1. Flat array: [{name, description, parameters}, ...]
                // 2. OpenAI-style: {tools: [{...}, ...]}
                // 3. Odysseus capabilities: {tools: {category: {actions: [...], ...}, ...}}
                let tools = [];
                if (Array.isArray(data)) {
                    tools = data;
                } else if (data.tools) {
                    if (Array.isArray(data.tools)) {
                        tools = data.tools;
                    } else if (typeof data.tools === "object") {
                        // Odysseus format: nested category -> actions
                        for (let category in data.tools) {
                            let cat = data.tools[category];
                            if (cat && typeof cat === "object") {
                                let actions = cat.actions || [];
                                for (let j = 0; j < actions.length; j++) {
                                    tools.push({
                                        name: category + "_" + actions[j],
                                        description: (cat.read ? "📖 " : "") + (cat.write ? "✏️ " : "") + category + " — " + actions[j],
                                        parameters: { type: "object", properties: {} }
                                    });
                                }
                            }
                        }
                    }
                }

                root.isConnected = true;
                root.connected();
                root.toolsDiscovered(tools);
            } catch (e) {
                root.isConnected = false;
                root.error("Invalid discovery JSON: " + e.message);
            }
        }
    }

    property Process invokeProcess: Process {
        property var property_payload: ({})
        stdout: StdioCollector { id: invokeOut }
        stderr: StdioCollector { id: invokeErr }
        onExited: exitCode => {
            let id = property_payload.id;
            let cb = root._pendingInvokes[id];
            if (cb) delete root._pendingInvokes[id];

            if (exitCode !== 0) {
                if (cb) cb({ content: "", error: "Invoke failed: " + invokeErr.text, done: true });
                return;
            }
            try {
                let data = JSON.parse(invokeOut.text);
                if (cb) cb({ content: data.content || data.result || "", error: data.error || null, done: true });
            } catch (e) {
                if (cb) cb({ content: invokeOut.text, error: null, done: true });
            }
        }
    }
}
