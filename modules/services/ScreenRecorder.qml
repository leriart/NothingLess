pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property bool isRecording: false
    property string duration: ""
    property string lastError: ""
    property bool canRecordDirectly: true // Optimistic default

    // Multi-monitor support
    property var monitors: []                // [{name, description, resolution}]
    property string selectedMonitor: ""      // Monitor name to record ("" = all/screen)
    property bool recordAllMonitors: true    // Default: capture all monitors

    property bool _initialized: false

    function initialize() {
        if (_initialized) return;
        _initialized = true;
        checkCapabilitiesProcess.running = true;
        xdgVideosProcess.running = true;
        checkProcess.running = true;
        listMonitorsProcess.running = true;
    }

    // List available monitors
    property Process listMonitorsProcess: Process {
        id: listMonitorsProcess
        command: ["gpu-screen-recorder", "--list-monitors"]
        running: false
        stdout: StdioCollector {
            onTextChanged: {
                var lines = text.trim().split("\n");
                var result = [];
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim();
                    if (line === "") continue;
                    // Format: "name|1920x1080" or "name: desc (WxH)"
                    var match = line.match(/^([^|]+)\|(\d+)x(\d+)\s*$/);
                    if (!match) {
                        match = line.match(/^([^:]+):\s*(.+?)\s*\((\d+)x(\d+)\)\s*$/);
                        if (match) {
                            result.push({
                                name: match[1].trim(),
                                description: match[2].trim(),
                                width: parseInt(match[3]),
                                height: parseInt(match[4])
                            });
                            continue;
                        }
                    } else {
                        result.push({
                            name: match[1].trim(),
                            description: "",
                            width: parseInt(match[2]),
                            height: parseInt(match[3])
                        });
                        continue;
                    }
                    // Fallback: use the whole line as name
                    result.push({
                        name: line,
                        description: "",
                        width: 0,
                        height: 0
                    });
                }
                if (result.length > 0) {
                    root.monitors = result;
                }
            }
        }
    }

    property Process checkCapabilitiesProcess: Process {
        id: checkCapabilitiesProcess
        command: ["bash", "-c", "if [ -f /run/current-system/sw/bin/nixos-version ]; then if [[ \"$(type -p gpu-screen-recorder)\" == *\"/run/wrappers/bin/\"* ]]; then echo true; else echo false; fi; else echo true; fi"]
        running: false
        stdout: StdioCollector {
            onTextChanged: {
                root.canRecordDirectly = (text.trim() === "true");
            }
        }
    }

    property string videosDir: ""

    // Resolve Videos dir
    property Process xdgVideosProcess: Process {
        id: xdgVideosProcess
        command: ["bash", "-c", "xdg-user-dir VIDEOS"]
        running: false
        stdout: StdioCollector {
            onTextChanged: {
                // Handled in onExited
            }
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                var dir = xdgVideosProcess.stdout.text.trim();
                if (dir === "") {
                    dir = Quickshell.env("HOME") + "/Videos";
                }
                root.videosDir = dir + "/Recordings";
            } else {
                root.videosDir = Quickshell.env("HOME") + "/Videos/Recordings";
            }
        }
    }

    // Poll — only when actively recording
    property Timer statusTimer: Timer {
        interval: 1000
        repeat: true
        running: root.isRecording && !SuspendManager.isSuspending
        onTriggered: {
            checkProcess.running = true;
        }
    }

    property Process checkProcess: Process {
        id: checkProcess
        command: ["bash", "-c", "pgrep -f 'gpu-screen-recorder' | grep -v $$ > /dev/null"]
        onExited: exitCode => {
            var wasRecording = root.isRecording;
            root.isRecording = (exitCode === 0);

            if (root.isRecording && !wasRecording) {
                console.log("[ScreenRecorder] Detected running instance.");
            }

            if (root.isRecording) {
                timeProcess.running = true;
            } else {
                root.duration = "";
            }
        }
    }

    property Process timeProcess: Process {
        id: timeProcess
        command: ["bash", "-c", "pid=$(pgrep -f 'gpu-screen-recorder' | head -n 1); if [ -n \"$pid\" ]; then ps -o etime= -p \"$pid\"; fi"]
        stdout: StdioCollector {
            onTextChanged: {
                root.duration = text.trim();
            }
        }
    }

    function toggleRecording() {
        if (isRecording) {
            stopProcess.running = true;
        } else {
            // Default: Portal, no audio
            startRecording(false, false, "portal", "");
        }
    }

    // Convenience: record a specific monitor by name
    function recordMonitor(monitorName, recordAudioOutput, recordAudioInput) {
        root.selectedMonitor = monitorName;
        root.recordAllMonitors = false;
        startRecording(recordAudioOutput || false, recordAudioInput || false, "monitor", "");
    }

    // Convenience: record all monitors
    function recordAllScreens(recordAudioOutput, recordAudioInput) {
        root.recordAllMonitors = true;
        startRecording(recordAudioOutput || false, recordAudioInput || false, "screen", "");
    }

    function startRecording(recordAudioOutput, recordAudioInput, mode, regionStr) {
        if (isRecording)
            return;

        var outputFile = root.videosDir + "/" + new Date().toISOString().replace(/[:.]/g, "-") + ".mp4";
        var cmd = "gpu-screen-recorder -f 60";

        // Window mode
        if (mode === "portal") {
            cmd += " -w portal";
        } else if (mode === "screen") {
            // Full desktop (all monitors) or specific monitor
            if (root.selectedMonitor && !root.recordAllMonitors) {
                cmd += " -w " + root.selectedMonitor;
            } else {
                cmd += " -w screen";
            }
        } else if (mode === "monitor") {
            // Specific monitor by name
            if (root.selectedMonitor) {
                cmd += " -w " + root.selectedMonitor;
            } else {
                cmd += " -w screen";
            }
        } else if (mode === "region") {
            cmd += " -w region";
            if (regionStr) {
                cmd += " -region " + regionStr;
            }
        }

        // Audio sources
        var audioSources = [];
        if (recordAudioOutput)
            audioSources.push("default_output");
        if (recordAudioInput)
            audioSources.push("default_input");

        if (audioSources.length === 1) {
            cmd += " -a " + audioSources[0];
        } else if (audioSources.length > 1) {
            cmd += " -a \"" + audioSources.join("|") + "\"";
        }

        cmd += " -o \"" + outputFile + "\"";

        console.log("[ScreenRecorder] Starting with command: " + cmd);
        startProcess.command = ["bash", "-c", cmd];

        prepareProcess.running = true;
    }

    // 1. Create dir
    property Process prepareProcess: Process {
        id: prepareProcess
        command: ["mkdir", "-p", root.videosDir]
        onExited: exitCode => {
            notifyStartProcess.running = true;
            startProcess.running = true;
            root.isRecording = true;
        }
    }

    // 2. Notify
    property Process notifyStartProcess: Process {
        id: notifyStartProcess
        command: ["notify-send", "Screen Recorder", "Starting recording..."]
    }

    // 3. Start
    property Process startProcess: Process {
        id: startProcess
        command: ["bash", "-c", "echo 'Error: Command not set'"]

        stdout: StdioCollector {
            onTextChanged: console.log("[ScreenRecorder] OUT: " + text)
        }
        stderr: StdioCollector {
            id: stderrCollector
            onTextChanged: {
                console.warn("[ScreenRecorder] ERR: " + text);
                // root.lastError = text // verbose
            }
        }

        onExited: exitCode => {
            console.log("[ScreenRecorder] Exited with code: " + exitCode);
            if (exitCode !== 0 && exitCode !== 130 && exitCode !== 2) { // 2 = SIGINT
                root.isRecording = false;
                notifyErrorProcess.running = true;
            } else {
                notifySavedProcess.running = true;
            }
        }
    }

    property Process notifyErrorProcess: Process {
        id: notifyErrorProcess
        command: ["notify-send", "-u", "critical", "Screen Recorder Error", "Failed to start. Check logs."]
    }

    property Process notifySavedProcess: Process {
        id: notifySavedProcess
        command: ["notify-send", "Screen Recorder", "Recording saved to " + root.videosDir]
    }

    property Process openVideosProcess: Process {
        id: openVideosProcess
        command: ["xdg-open", root.videosDir]
    }

    function openRecordingsFolder() {
        openVideosProcess.running = true;
    }

    property Process stopProcess: Process {
        id: stopProcess
        command: ["pkill", "-SIGINT", "-f", "gpu-screen-recorder"]
    }

    Component.onDestruction: {
        statusTimer.stop();
        checkProcess.running = false;
        timeProcess.running = false;
        prepareProcess.running = false;
        notifyStartProcess.running = false;
        startProcess.running = false;
        notifyErrorProcess.running = false;
        notifySavedProcess.running = false;
        openVideosProcess.running = false;
        stopProcess.running = false;
        checkCapabilitiesProcess.running = false;
    }
}
