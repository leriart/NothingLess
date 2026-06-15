pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.services

/*!
    ScreenSharingService — Unified wireless display manager for NothingLess

    Supports multiple protocols:
      • AirPlay  (UxPlay)    — iOS/iPadOS/macOS clients, audio+mirror
      • Miracast (miraclecast / gnome-network-displays) — Windows, Android, many smart TVs
      • Chromecast sender (gnome-network-displays)      — cast this desktop to Chromecast targets

    The service starts the appropriate backend depending on the active mode and
    whether the user wants to receive (sink) or send (source) the screen.

    Settings are persisted via StateService under the "screenSharing" namespace.
*/
Singleton {
    id: root

    // ── Public state ──
    property bool available: false
    property bool running: false
    property string state: "stopped" // stopped, starting, running, error
    property string statusMessage: ""
    property string lastError: ""
    property string clientName: ""
    property int connectionCount: 0

    // ── Protocol / mode selection ──
    property string protocol: "auto" // "auto", "airplay", "miracast", "chromecast"
    property string mode: "sink"     // "sink" = receive, "source" = send

    // ── Common settings ──
    property string serverName: "NothingLess"
    property bool autoStart: false
    property bool pinAuth: false
    property string password: ""
    property bool fullscreen: false
    property bool debug: false

    // ── AirPlay-specific settings ──
    property bool audioOnly: false
    property bool vsync: true
    property int fps: 60
    property string videoSink: "waylandsink"
    property string audioSink: ""
    property bool noHold: false
    property int port: 0
    property int portRange: 0

    // ── Miracast-specific settings ──
    property string miracastBackend: "auto" // "auto", "miraclecast", "gnd"
    property string miracastInterface: ""   // empty = auto
    property bool miracastUibc: false       // User Input Back Channel

    // ── Chromecast source settings ──
    property string chromecastTarget: ""    // friendly name or IP
    property var chromecastTargets: []

    signal clientConnected(string name)
    signal clientDisconnected()
    signal logLine(string line)
    signal targetListUpdated(var targets)

    property bool _stateLoaded: false

    Component.onCompleted: root.initialize()

    function initialize() {
        root.checkAvailability();
        if (StateService.initialized) root.loadState();
    }

    Connections {
        target: StateService
        function onStateLoaded() { root.loadState(); }
    }

    function loadState() {
        if (root._stateLoaded) return;
        root._stateLoaded = true;
        var s = StateService.state || {};
        var c = s.screenSharing || {};

        var simpleBools = ["autoStart", "pinAuth", "fullscreen", "debug", "audioOnly", "vsync", "noHold", "miracastUibc"];
        var simpleStrings = ["protocol", "mode", "serverName", "password", "videoSink", "audioSink", "miracastBackend", "miracastInterface", "chromecastTarget"];
        var simpleInts = ["fps", "port", "portRange"];

        for (var i = 0; i < simpleBools.length; i++) {
            var k = simpleBools[i];
            if (c[k] !== undefined) root[k] = c[k];
        }
        for (var j = 0; j < simpleStrings.length; j++) {
            var sk = simpleStrings[j];
            if (c[sk] !== undefined) root[sk] = c[sk];
        }
        for (var m = 0; m < simpleInts.length; m++) {
            var ik = simpleInts[m];
            if (c[ik] !== undefined) root[ik] = c[ik];
        }

        // Migrate legacy UxPlay-only state
        var legacy = s.uxplay || {};
        if (!s.screenSharing && Object.keys(legacy).length > 0) {
            root.serverName = legacy.serverName || root.serverName;
            root.autoStart = legacy.autoStart || root.autoStart;
            root.audioOnly = legacy.audioOnly || root.audioOnly;
            root.vsync = legacy.vsync !== undefined ? legacy.vsync : root.vsync;
            root.pinAuth = legacy.pinAuth || root.pinAuth;
            root.password = legacy.password || root.password;
            root.fps = legacy.fps || root.fps;
            root.videoSink = legacy.videoSink || root.videoSink;
            root.audioSink = legacy.audioSink || root.audioSink;
            root.fullscreen = legacy.fullscreen || root.fullscreen;
            root.debug = legacy.debug || root.debug;
            root.noHold = legacy.noHold || root.noHold;
            root.port = legacy.port || root.port;
            root.portRange = legacy.portRange || root.portRange;
            root.saveState();
        }
    }

    function saveState() {
        if (!StateService.initialized) return;
        var s = StateService.state || {};
        s.screenSharing = {
            protocol: root.protocol,
            mode: root.mode,
            serverName: root.serverName,
            autoStart: root.autoStart,
            pinAuth: root.pinAuth,
            password: root.password,
            fullscreen: root.fullscreen,
            debug: root.debug,
            audioOnly: root.audioOnly,
            vsync: root.vsync,
            fps: root.fps,
            videoSink: root.videoSink,
            audioSink: root.audioSink,
            noHold: root.noHold,
            port: root.port,
            portRange: root.portRange,
            miracastBackend: root.miracastBackend,
            miracastInterface: root.miracastInterface,
            miracastUibc: root.miracastUibc,
            chromecastTarget: root.chromecastTarget
        };
        StateService.state = s;
        StateService.save();
    }

    function setSetting(key, value) {
        root[key] = value;
        root.saveState();
    }

    // ── Availability checks ──
    property var _avail: { "uxplay": false, "miraclecast": false, "gnd": false, "gstLaunch": false }

    function checkAvailability() {
        availCheckProcess.running = true;
    }

    property Process availCheckProcess: Process {
        command: ["bash", "-c",
            "echo uxplay=$(command -v uxplay >/dev/null 2>&1 && echo 1 || echo 0); " +
            "echo miracle-wifid=$(command -v miracle-wifid >/dev/null 2>&1 && echo 1 || echo 0); " +
            "echo miracle-sinkctl=$(command -v miracle-sinkctl >/dev/null 2>&1 && echo 1 || echo 0); " +
            "echo gnd=$(command -v gnome-network-displays >/dev/null 2>&1 && echo 1 || echo 0); " +
            "echo gstlaunch=$(command -v gst-launch-1.0 >/dev/null 2>&1 && echo 1 || echo 0)"
        ]
        running: false
        stdout: SplitParser {
            onRead: line => {
                var parts = line.split("=");
                if (parts.length !== 2) return;
                var key = parts[0].trim();
                var val = parts[1].trim() === "1";
                if (key === "uxplay") root._avail.uxplay = val;
                else if (key === "miracle-wifid") root._avail.miraclecast = root._avail.miraclecast || val;
                else if (key === "miracle-sinkctl") root._avail.miraclecast = root._avail.miraclecast || val;
                else if (key === "gnd") root._avail.gnd = val;
                else if (key === "gstlaunch") root._avail.gstLaunch = val;
                root.recalcAvailable();
            }
        }
    }

    function recalcAvailable() {
        var p = root.protocol;
        if (p === "auto") {
            root.available = root._avail.uxplay || root._avail.miraclecast || root._avail.gnd;
        } else if (p === "airplay") {
            root.available = root._avail.uxplay;
        } else if (p === "miracast") {
            root.available = root._avail.miraclecast || root._avail.gnd;
        } else if (p === "chromecast") {
            root.available = root._avail.gnd;
        }
    }

    onProtocolChanged: root.recalcAvailable()

    function effectiveProtocol() {
        if (root.protocol !== "auto") return root.protocol;
        if (root.mode === "sink") {
            if (root._avail.uxplay) return "airplay";
            if (root._avail.miraclecast || root._avail.gnd) return "miracast";
        } else {
            if (root._avail.gnd) return "chromecast";
            if (root._avail.miraclecast) return "miracast";
        }
        return "airplay";
    }

    function hasProtocol(name) {
        if (name === "airplay") return root._avail.uxplay;
        if (name === "miracast") return root._avail.miraclecast || root._avail.gnd;
        if (name === "chromecast") return root._avail.gnd;
        return false;
    }

    // ── Process management ──
    property Process activeProcess: Process {
        command: ["echo", ""]
        running: false
        stdout: SplitParser {
            onRead: line => {
                if (!line) return;
                root.logLine(line);
                root.parseLine(line);
            }
        }
        stderr: SplitParser {
            onRead: line => {
                if (!line) return;
                root.logLine(line);
                root.parseLine(line);
            }
        }
        onExited: exitCode => {
            root.running = false;
            if (root.state !== "stopped") {
                root.state = exitCode === 0 ? "stopped" : "error";
                if (exitCode !== 0) {
                    root.lastError = "Process exited with code " + exitCode;
                    root.statusMessage = "Stopped unexpectedly";
                } else {
                    root.statusMessage = "Stopped";
                }
            }
            root.clientName = "";
        }
    }

    function buildCommand() {
        var prot = root.effectiveProtocol();
        if (prot === "airplay") return root.buildAirPlayCommand();
        if (prot === "miracast") return root.buildMiracastCommand();
        if (prot === "chromecast") return root.buildChromecastCommand();
        return ["echo", "No compatible screen sharing backend available"];
    }

    function buildAirPlayCommand() {
        var cmd = ["uxplay"];
        if (root.serverName && root.serverName !== "") cmd.push("-n", root.serverName);
        if (root.audioOnly) cmd.push("-a");
        if (!root.vsync) cmd.push("-vsync", "no");
        if (root.pinAuth) cmd.push("-pin");
        if (root.password && root.password !== "") cmd.push("-pw", root.password);
        if (root.fps > 0) cmd.push("-fps", root.fps.toString());
        if (root.videoSink && root.videoSink !== "auto") cmd.push("-vs", root.videoSink);
        if (root.audioSink && root.audioSink !== "") cmd.push("-as", root.audioSink);
        if (root.fullscreen) cmd.push("-fs");
        if (root.debug) cmd.push("-d");
        if (root.noHold) cmd.push("-nohold");
        if (root.port > 0) cmd.push("-p", root.port.toString());
        if (root.portRange > 0) cmd.push("-m", root.portRange.toString());
        return cmd;
    }

    function buildMiracastCommand() {
        var backend = root.miracastBackend;
        if (backend === "auto") {
            backend = root._avail.miraclecast ? "miraclecast" : "gnd";
        }
        if (backend === "miraclecast") {
            if (root.mode === "sink") {
                var args = ["sudo", "miracle-sinkctl"];
                if (root.miracastUibc) args.push("--uibc");
                if (root.miracastInterface) args.push("--interface", root.miracastInterface);
                return args;
            } else {
                return ["sudo", "miracle-wifictl"];
            }
        }
        // gnome-network-displays
        return ["gnome-network-displays"];
    }

    function buildChromecastCommand() {
        // gnome-network-displays is the only practical Chromecast sender on Linux
        return ["gnome-network-displays"];
    }

    function start() {
        if (root.running || !root.available) return;
        var prot = root.effectiveProtocol();
        root.state = "starting";
        root.lastError = "";
        root.statusMessage = "Starting " + prot + "...";
        var cmd = root.buildCommand();
        activeProcess.running = false;
        activeProcess.command = cmd;
        activeProcess.running = true;
        root.running = true;
    }

    function stop() {
        if (!root.running) return;
        root.state = "stopped";
        root.statusMessage = "Stopping...";
        activeProcess.running = false;
    }

    function toggle() {
        if (root.running) root.stop();
        else root.start();
    }

    function restart() {
        root.stop();
        restartTimer.start();
    }

    Timer {
        id: restartTimer
        interval: 500
        repeat: false
        onTriggered: root.start()
    }

    function parseLine(line) {
        var l = line.toLowerCase();
        var prot = root.effectiveProtocol();

        if (prot === "airplay") {
            if (l.indexOf("connection") !== -1 && l.indexOf("from") !== -1) {
                var match = line.match(/from\s+["']?([^"']+)["']?/i);
                root.clientName = match ? match[1] : "Unknown";
                root.connectionCount++;
                root.clientConnected(root.clientName);
                root.statusMessage = "Connected: " + root.clientName;
                root.notify("AirPlay connected", root.clientName + " started mirroring.");
                return;
            }
            if (l.indexOf("connection") !== -1 && (l.indexOf("closed") !== -1 || l.indexOf("lost") !== -1)) {
                root.clientDisconnected();
                root.clientName = "";
                root.statusMessage = root.running ? "Waiting for client..." : "Stopped";
                root.notify("AirPlay disconnected", "Client disconnected.");
                return;
            }
        } else if (prot === "miracast") {
            // miraclecast / gnd generic patterns
            if (l.indexOf("connected") !== -1 || l.indexOf("session established") !== -1 || l.indexOf("link: ") !== -1) {
                root.clientName = "Miracast device";
                root.connectionCount++;
                root.clientConnected(root.clientName);
                root.statusMessage = "Miracast connected";
                root.notify("Miracast connected", "A device started mirroring.");
                return;
            }
            if (l.indexOf("disconnected") !== -1 || l.indexOf("session stopped") !== -1 || l.indexOf("stopped") !== -1) {
                root.clientDisconnected();
                root.clientName = "";
                root.statusMessage = root.running ? "Waiting for device..." : "Stopped";
                root.notify("Miracast disconnected", "Device disconnected.");
                return;
            }
        } else if (prot === "chromecast") {
            if (l.indexOf("connecting to") !== -1 || l.indexOf("streaming to") !== -1) {
                var m = line.match(/to\s+["']?([^"']+)["']?/i);
                root.clientName = m ? m[1] : "Chromecast";
                root.clientConnected(root.clientName);
                root.statusMessage = "Casting to " + root.clientName;
                root.notify("Chromecast connected", "Casting to " + root.clientName);
                return;
            }
            if (l.indexOf("stopped") !== -1 || l.indexOf("disconnected") !== -1) {
                root.clientDisconnected();
                root.clientName = "";
                root.statusMessage = root.running ? "Ready to cast" : "Stopped";
                root.notify("Chromecast stopped", "Casting stopped.");
                return;
            }
        }

        if (l.indexOf("error") !== -1 || l.indexOf("failed") !== -1 || l.indexOf("cannot") !== -1) {
            root.lastError = line;
            if (root.state === "starting") root.state = "error";
        } else if (l.indexOf("initialized") !== -1 || l.indexOf("server") !== -1 || l.indexOf("ready") !== -1) {
            if (root.state === "starting") {
                root.state = "running";
                root.statusMessage = root.mode === "sink" ? "Waiting for client..." : "Ready to cast";
            }
        }
    }

    function notify(summary, body) {
        if (typeof Notifications !== "undefined" && Notifications.notifyInternal) {
            Notifications.notifyInternal({ summary: summary, body: body, expireTimeout: 3000, popup: true });
        }
    }

    function scanChromecastTargets() {
        if (!root._avail.gnd) return;
        chromecastScanProcess.running = true;
    }

    property Process chromecastScanProcess: Process {
        command: ["bash", "-c", "timeout 10 gnome-network-displays --list 2>/dev/null || echo '[]'"]
        running: false
        stdout: StdioCollector {
            onTextChanged: {
                try {
                    var data = JSON.parse(text || "[]");
                    root.chromecastTargets = Array.isArray(data) ? data : [];
                    root.targetListUpdated(root.chromecastTargets);
                } catch (e) {
                    root.chromecastTargets = [];
                }
            }
        }
    }
}
