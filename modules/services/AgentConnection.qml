import QtQuick

// Data object describing an external agent connection.
QtObject {
    required property string id
    required property string name
    required property string type // "http-bridge" | "command" | "mcp-sse"
    property bool enabled: true

    // For "command" agents (e.g. OpenClaw CLI, custom scripts)
    property string command: ""
    property list<var> args: []

    // For "http-bridge" / "mcp-sse"
    property string endpoint: ""
    property var headers: ({}) // plain JS object, e.g. { "Authorization": "Bearer x" }

    // HTTP-bridge specific paths (defaults shown)
    property string toolsPath: "/tools"
    property string invokePath: "/invoke"

    // Runtime state (not persisted)
    property string status: "disconnected" // disconnected | connecting | connected | error
    property string statusMessage: ""
    property var discoveredTools: [] // { name, description, parameters }
}
