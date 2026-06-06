import QtQuick
import Quickshell
import Quickshell.Io

// Minimal MCP client over stdio (JSON-RPC 2.0), using a Python bridge
// because QML Process cannot easily write to child stdin repeatedly.
QtObject {
    id: root

    signal connected
    signal disconnected
    signal toolsDiscovered(var tools)
    signal error(string message)

    property bool isConnected: false
    property string _requestIdPrefix: "nl_"
    property int _requestCounter: 1
    property var _pendingCallbacks: ({})

    property string _bridgePath: Qt.resolvedUrl("../../../scripts/mcp_stdio_bridge.py").toString().replace("file://", "")

    function start(command, args) {
        if (!command) {
            error("No command specified for MCP stdio client");
            return;
        }
        isConnected = false;
        let bridgeCmd = ["python3", _bridgePath, "--", command];
        if (args && args.length > 0) {
            for (let i = 0; i < args.length; i++) bridgeCmd.push(args[i]);
        }
        mcpProcess.command = bridgeCmd;
        mcpProcess.running = true;
    }

    function stop() {
        mcpProcess.running = false;
        isConnected = false;
        disconnected();
    }

    function sendRequest(method, params, callback) {
        let id = _requestIdPrefix + (_requestCounter++);
        let msg = JSON.stringify({ jsonrpc: "2.0", id: id, method: method, params: params || {} });
        if (callback) _pendingCallbacks[id] = callback;

        // Write via a small helper process: echo 'msg' >> /dev/null is wrong.
        // Instead we kill/restart? No. We use a dedicated write process that
        // echoes into the bridge's stdin through a fifo? That's complex.
        // Simpler: since we launched the bridge with bash -c, we can write
        // to a fifo if we created one. But we want minimal code.
        // Best approach for now: send the message by appending to a file that
        // the bridge tails? Not reliable.
        //
        // OK, QML Process in Qt 6 actually CAN receive stdin writes if we
        // set it up with a custom file descriptor, but QML bindings don't
        // expose it.
        //
        // Workaround: write the message into a temp file and use a second
        // process to send it to the bridge via a named pipe (FIFO).
        // We'll create the FIFO in start().
        _sendLine(msg);
    }

    function sendNotification(method, params) {
        let msg = JSON.stringify({ jsonrpc: "2.0", method: method, params: params || {} });
        _sendLine(msg);
    }

    property string _fifoPath: ""

    function _sendLine(line) {
        if (!_fifoPath) {
            console.warn("McpStdioClient: FIFO not ready");
            return;
        }
        // Use a one-shot Process to write the line into the FIFO.
        writeProcess.command = ["bash", "-c", "echo " + _bashEscape(line) + " > " + _fifoPath];
        writeProcess.running = true;
    }

    function _bashEscape(s) {
        // Very basic escaping for echo -n via $'...'
        return "$'" + s.replace(/\\/g, "\\\\").replace(/'/g, "\\'") + "'";
    }

    function _handleLine(line) {
        let trimmed = line.trim();
        if (!trimmed) return;
        try {
            let msg = JSON.parse(trimmed);
            if (msg.jsonrpc !== "2.0") return;

            if (msg.id !== undefined) {
                let cb = _pendingCallbacks[msg.id];
                if (cb) {
                    delete _pendingCallbacks[msg.id];
                    cb(msg.error || null, msg.result);
                }
                if (msg.result && msg.result.protocolVersion) {
                    isConnected = true;
                    connected();
                    sendNotification("notifications/initialized", {});
                }
                return;
            }

            if (msg.method === "notifications/tools/list_changed") {
                sendRequest("tools/list", {}, function(err, result) {
                    if (!err && result && result.tools) {
                        toolsDiscovered(result.tools);
                    }
                });
            }
        } catch (e) {
            console.warn("McpStdioClient parse error:", e, "line:", trimmed);
        }
    }

    property Process setupFifoProcess: Process {
        property var _payload: ({})
        onExited: exitCode => {
            if (exitCode === 0) {
                root._fifoPath = _payload.fifoPath;
                // Now start the bridge reading from the FIFO
                let cmd = root.mcpProcess.command;
                // Replace the bridge command to read stdin from FIFO
                // We use bash to redirect the FIFO into the bridge
                let redirectCmd = ["bash", "-c", cmd.map(c => "'" + c.replace(/'/g, "'\\''") + "'").join(" ") + " < " + root._fifoPath];
                root.mcpProcess.command = redirectCmd;
                root.mcpProcess.running = true;
            } else {
                root.error("Failed to create FIFO for MCP bridge");
            }
        }
    }

    property Process mcpProcess: Process {
        running: false

        stdout: SplitParser {
            onRead: data => root._handleLine(data)
        }

        stderr: StdioCollector {
            id: mcpStderr
        }

        onExited: exitCode => {
            root.isConnected = false;
            if (exitCode !== 0 && exitCode !== -1) {
                root.error("MCP process exited: " + mcpStderr.text);
            }
            root.disconnected();
        }
    }

    property Process writeProcess: Process {
        running: false
    }

    Component.onCompleted: {
        // Create a FIFO in /tmp for this session
        let fifo = "/tmp/nl-mcp-" + Qt.application.pid + "-" + Date.now();
        setupFifoProcess._payload = { fifoPath: fifo };
        setupFifoProcess.command = ["bash", "-c", "mkfifo " + fifo + " && chmod 600 " + fifo];
        setupFifoProcess.running = true;
    }

    Component.onDestruction: {
        stop();
        if (_fifoPath) {
            cleanupProcess.command = ["rm", "-f", _fifoPath];
            cleanupProcess.running = true;
        }
    }

    property Process cleanupProcess: Process {
        running: false
    }
}
