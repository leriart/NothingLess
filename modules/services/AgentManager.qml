import QtQuick
import Quickshell
import qs.config

QtObject {
    id: root

    property var connections: [] // AgentConnection objects
    property var _clients: ({})  // agentId -> client QtObject
    property QtObject toolRegistry: null

    signal statusChanged(string agentId, string status, string message)

    property Component agentConnectionFactory: Component {
        AgentConnection {}
    }

    property Component httpClientFactory: Component {
        HttpAgentClient {}
    }

    property Component commandClientFactory: Component {
        CommandAgentClient {}
    }

    Component.onCompleted: {
        reloadFromConfig();
    }

    property bool _reloading: false

    property Connections configWatcher: Connections {
        target: Config.ai
        function onAgentsChanged() {
            if (!root._reloading) Qt.callLater(root.reloadFromConfig);
        }
    }

    function reloadFromConfig() {
        if (root._reloading) return;
        root._reloading = true;

        // Tear down existing clients safely (may be called multiple times)
        for (let id in _clients) {
            try {
                if (_clients[id]) {
                    _clients[id].stop();
                    _clients[id].destroy();
                }
            } catch (e) {
                // Client already destroyed or invalid — ignore
            }
        }
        _clients = {};

        let cfg = Config.ai.agents;
        let cfgLen = cfg ? (cfg.length || 0) : 0;
        if (!cfg || cfgLen === 0) {
            connections = [];
            root._reloading = false;
            return;
        }

        let newConnections = [];
        for (let i = 0; i < cfgLen; i++) {
            let c = cfg[i];
            if (!c) continue;
            let conn = agentConnectionFactory.createObject(root, {
                id: c.id || ("agent_" + i),
                name: c.name || "Agent " + i,
                type: c.type || "http-bridge",
                enabled: c.enabled !== false,
                command: c.command || "",
                args: c.args || [],
                endpoint: c.endpoint || "",
                headers: c.headers || {},
                toolsPath: c.toolsPath || "/tools",
                invokePath: c.invokePath || "/invoke"
            });
            newConnections.push(conn);

            if (conn.enabled) {
                _connectAgent(conn);
            }
        }
        connections = newConnections;
        root._reloading = false;
    }

    function _connectAgent(conn) {
        conn.status = "connecting";
        conn.statusMessage = "";
        statusChanged(conn.id, "connecting", "");

        let client;
        if (conn.type === "http-bridge" || conn.type === "mcp-sse") {
            client = httpClientFactory.createObject(root, {});
            client.connected.connect(() => {
                conn.status = "connected";
                statusChanged(conn.id, "connected", "");
            });
            client.disconnected.connect(() => {
                conn.status = "disconnected";
                statusChanged(conn.id, "disconnected", "");
            });
            client.error.connect(msg => {
                conn.status = "error";
                conn.statusMessage = msg;
                statusChanged(conn.id, "error", msg);
            });
            client.toolsDiscovered.connect(tools => {
                conn.discoveredTools = tools || [];
                if (root.toolRegistry) root.toolRegistry.register(conn.id, conn, tools);
            });
            client.start(conn.endpoint, conn.headers, conn.toolsPath, conn.invokePath);
        } else if (conn.type === "command") {
            client = commandClientFactory.createObject(root, {});
            client.connected.connect(() => {
                conn.status = "connected";
                statusChanged(conn.id, "connected", "");
            });
            client.disconnected.connect(() => {
                conn.status = "disconnected";
                statusChanged(conn.id, "disconnected", "");
            });
            client.error.connect(msg => {
                conn.status = "error";
                conn.statusMessage = msg;
                statusChanged(conn.id, "error", msg);
            });
            client.toolsDiscovered.connect(tools => {
                conn.discoveredTools = tools || [];
                if (root.toolRegistry) root.toolRegistry.register(conn.id, conn, tools);
            });
            client.start(conn.command, conn.args);
        } else {
            conn.status = "error";
            conn.statusMessage = "Unsupported agent type: " + conn.type;
            statusChanged(conn.id, "error", conn.statusMessage);
            return;
        }

        _clients[conn.id] = client;
    }

    function disconnectAgent(agentId) {
        if (_clients[agentId]) {
            try {
                _clients[agentId].stop();
                _clients[agentId].destroy();
            } catch (e) {
                // Already destroyed
            }
            delete _clients[agentId];
        }
        if (root.toolRegistry) root.toolRegistry.unregister(agentId);
        let connsLen = connections ? connections.length : 0;
        for (let i = 0; i < connsLen; i++) {
            if (connections[i] && connections[i].id === agentId) {
                connections[i].status = "disconnected";
                break;
            }
        }
    }

    function reconnectAgent(agentId) {
        disconnectAgent(agentId);
        let connsLen = connections ? connections.length : 0;
        for (let i = 0; i < connsLen; i++) {
            if (connections[i] && connections[i].id === agentId && connections[i].enabled) {
                _connectAgent(connections[i]);
                break;
            }
        }
    }

    function saveConnections() {
        // Convert connection objects back to plain JSON and persist
        let cfg = [];
        for (let i = 0; i < connections.length; i++) {
            let c = connections[i];
            cfg.push({
                id: c.id,
                name: c.name,
                type: c.type,
                enabled: c.enabled,
                command: c.command,
                args: c.args,
                endpoint: c.endpoint,
                headers: c.headers,
                toolsPath: c.toolsPath,
                invokePath: c.invokePath
            });
        }
        Config.ai.agents = cfg;
    }

    function addConnection(config) {
        if (!config || !config.id) {
            console.warn("AgentManager.addConnection: invalid config, missing id");
            return;
        }
        // Read current agents safely (QML list<var> is not a JS Array)
        let currentAgents = Config.ai.agents;
        let cfg = [];
        let len = currentAgents ? (currentAgents.length || 0) : 0;
        for (let i = 0; i < len; i++) {
            let item = currentAgents[i];
            if (item) cfg.push(item);
        }
        cfg.push(config);
        Config.ai.agents = cfg;
        // configWatcher will trigger reloadFromConfig automatically
    }

    function removeConnection(agentId) {
        disconnectAgent(agentId);
        let currentAgents = Config.ai.agents;
        let cfg = [];
        let len = currentAgents ? (currentAgents.length || 0) : 0;
        for (let i = 0; i < len; i++) {
            let item = currentAgents[i];
            if (item && item.id !== agentId) cfg.push(item);
        }
        Config.ai.agents = cfg;
        // configWatcher will trigger reloadFromConfig automatically
    }

    // Agent tool invocation dispatcher
    property Connections invokeDispatcher: Connections {
        target: root.toolRegistry
        function onToolInvokeRequested(agentId, tool, args, callback) {
            let client = root._clients[agentId];
            if (!client) {
                if (callback) callback({ content: "", error: "Agent not connected", done: true });
                return;
            }
            client.invokeTool(tool.name, args, callback);
        }
    }
}
