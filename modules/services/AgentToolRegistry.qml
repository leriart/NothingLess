import QtQuick

QtObject {
    id: root

    // Flat list of tools discovered from all connected agents,
    // formatted for internal use (matches Ai.qml systemTools shape).
    property var tools: []

    // Map of agentId -> { connection, tools[] }
    property var _agentMap: ({})

    signal agentToolsChanged
    signal toolInvokeRequested(string agentId, var tool, var args, var callback)

    function register(agentId, connection, discoveredTools) {
        let map = Object.assign({}, _agentMap);
        let internalTools = [];

        if (discoveredTools && discoveredTools.length > 0) {
            for (let i = 0; i < discoveredTools.length; i++) {
                let t = discoveredTools[i];
                internalTools.push({
                    name: t.name,
                    description: t.description || "",
                    parameters: t.parameters || { type: "object", properties: {} },
                    _agentId: agentId,
                    _source: connection.name || agentId
                });
            }
        }

        map[agentId] = {
            connection: connection,
            tools: internalTools
        };

        _agentMap = map;
        rebuildTools();
    }

    function unregister(agentId) {
        let map = Object.assign({}, _agentMap);
        if (map[agentId] === undefined)
            return;
        delete map[agentId];
        _agentMap = map;
        rebuildTools();
    }

    function updateStatus(agentId, status, message) {
        let map = Object.assign({}, _agentMap);
        if (map[agentId]) {
            map[agentId].connection.status = status;
            map[agentId].connection.statusMessage = message || "";
        }
        _agentMap = map;
    }

    function rebuildTools() {
        let all = [];
        for (let id in _agentMap) {
            let entry = _agentMap[id];
            if (entry && entry.tools) {
                for (let i = 0; i < entry.tools.length; i++) {
                    all.push(entry.tools[i]);
                }
            }
        }
        tools = all;
        agentToolsChanged();
    }

    // Find the owning agent and emit an invocation request.
    // callback(result) receives { content: string, error: string|null, done: bool }.
    function invoke(toolName, args, callback) {
        if (!callback) callback = function() {};

        for (let id in _agentMap) {
            let entry = _agentMap[id];
            if (!entry || !entry.tools) continue;
            for (let i = 0; i < entry.tools.length; i++) {
                if (entry.tools[i].name === toolName) {
                    toolInvokeRequested(id, entry.tools[i], args, callback);
                    return true;
                }
            }
        }
        callback({ content: "", error: "Tool '" + toolName + "' not found in any connected agent.", done: true });
        return false;
    }

    function hasTool(toolName) {
        for (let id in _agentMap) {
            let entry = _agentMap[id];
            if (!entry || !entry.tools) continue;
            for (let i = 0; i < entry.tools.length; i++) {
                if (entry.tools[i].name === toolName)
                    return true;
            }
        }
        return false;
    }
}
