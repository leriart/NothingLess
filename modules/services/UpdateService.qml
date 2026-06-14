pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.config

Singleton {
    id: root

    readonly property string installPath: Quickshell.env("HOME") + "/.local/src/nothingless"
    readonly property string cliPath: installPath + "/cli.sh"
    readonly property string repoApi: "https://api.github.com/repos/Leriart/NothingLess/commits/main"
    readonly property string changelogUrl: "https://github.com/Leriart/NothingLess/releases"
    readonly property string cacheFile: Quickshell.env("HOME") + "/.cache/nothingless/update_check.json"

    property string lastDetectedHash: ""
    property string currentLocalHash: ""
    property double lastCheckTime: 0
    property double nextCheckTime: 0

    property bool updateAvailable: false
    property string remoteCommitHash: ""
    property string remoteCommitMessage: ""
    property bool checking: false

    readonly property int checkIntervalMs: Config.system.updateService ? Config.system.updateService.checkIntervalMs : 3600000

    function saveCache() {
        const data = {
            lastCheckTime: root.lastCheckTime,
            nextCheckTime: root.nextCheckTime,
            lastDetectedHash: root.lastDetectedHash
        };
        cacheFileView.setText(JSON.stringify(data));
    }

    FileView {
        id: cacheFileView
        path: root.cacheFile
        onLoaded: {
            try {
                const content = text();
                if (content && content.trim() !== "") {
                    const data = JSON.parse(content);
                    root.lastCheckTime = data.lastCheckTime || 0;
                    root.nextCheckTime = data.nextCheckTime || 0;
                    root.lastDetectedHash = data.lastDetectedHash || "";
                } else {
                    root.nextCheckTime = Date.now();
                }
            } catch (e) {
                console.log("[UpdateService] Error loading cache:", e);
                root.nextCheckTime = Date.now();
            }
        }
    }

    Timer {
        id: startupDelay
        interval: 2000
        running: true
        onTriggered: {
            checkTimer.running = true;
        }
    }

    Timer {
        id: checkTimer
        interval: 30000
        running: false
        repeat: true
        onTriggered: {
            if (!(Config.system.updateService && Config.system.updateService.enabled)) return;
            if (root.checking) return;
            const now = Date.now();
            if (now >= root.nextCheckTime) {
                checkUpdates();
            }
        }
    }

    Timer {
        id: safetyTimeout
        interval: 15000
        repeat: false
        onTriggered: {
            if (root.checking) {
                root.checking = false;
            }
        }
    }

    function checkUpdates() {
        if (!(Config.system.updateService && Config.system.updateService.enabled)) return;
        if (root.checking) return;

        root.checking = true;
        root.updateAvailable = false;
        safetyTimeout.restart();
        gitProcess.command = ["git", "-C", root.installPath, "rev-parse", "HEAD"];
        gitProcess.running = true;
    }

    function checkNow() {
        if (root.checking) return;

        root.checking = true;
        root.updateAvailable = false;
        safetyTimeout.restart();
        gitProcess.command = ["git", "-C", root.installPath, "rev-parse", "HEAD"];
        gitProcess.running = true;
    }

    property Process gitProcess: Process {
        command: []
        stdout: StdioCollector {
            id: gitCollector
        }
        stderr: StdioCollector {}
        onExited: exitCode => {
            if (exitCode !== 0 || !gitCollector.text().trim()) {
                root.checking = false;
                safetyTimeout.stop();
                return;
            }
            root.currentLocalHash = gitCollector.text().trim();
            fetchRemoteCommit();
        }
    }

    function fetchRemoteCommit() {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", root.repoApi);
        xhr.timeout = 10000;
        xhr.ontimeout = function() {
            root.checking = false;
            safetyTimeout.stop();
        };
        xhr.onerror = function() {
            root.checking = false;
            safetyTimeout.stop();
        };
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            safetyTimeout.stop();

            if (xhr.status === 200) {
                try {
                    const data = JSON.parse(xhr.responseText);
                    const remoteHash = data.sha;
                    const commitMessage = data.commit ? data.commit.message : "";
                    if (remoteHash && remoteHash.length === 40 && remoteHash !== root.currentLocalHash) {
                        root.updateAvailable = true;
                        root.remoteCommitHash = remoteHash;
                        root.remoteCommitMessage = commitMessage;
                        if (remoteHash !== root.lastDetectedHash || !isNotificationActive()) {
                            lastDetectedHash = remoteHash;
                            saveCache();
                            sendUpdateNotification(remoteHash, commitMessage);
                        }
                    } else {
                        root.updateAvailable = false;
                        root.remoteCommitHash = "";
                        root.remoteCommitMessage = "";
                    }
                } catch (e) {
                    console.log("[UpdateService] Error parsing API response:", e);
                }
            }

            root.checking = false;
            root.lastCheckTime = Date.now();
            if (root.nextCheckTime <= Date.now()) {
                root.nextCheckTime = Date.now() + root.checkIntervalMs;
            }
            root.saveCache();
        };
        xhr.send();
    }

    function isNotificationActive() {
        if (typeof Notifications === "undefined" || !Notifications.list) return false;
        for (let i = 0; i < Notifications.list.length; i++) {
            const notif = Notifications.list[i];
            if (notif && notif.appName === "NothingLess Update") {
                return true;
            }
        }
        return false;
    }

    function sendUpdateNotification(remoteHash, commitMessage) {
        const shortLocal = root.currentLocalHash.substring(0, 7);
        const shortRemote = remoteHash.substring(0, 7);

        const bodyText = commitMessage.length > 280
            ? commitMessage.substring(0, 280) + "..."
            : commitMessage;

        try {
            Notifications.notifyInternal({
                "appName": "NothingLess Update",
                "summary": "Update Available  " + shortLocal + " → " + shortRemote,
                "body": bodyText,
                "urgency": NotificationUrgency.Normal,
                "historyPriority": 90,
                "replaceKey": "nothingless-update",
                "expireTimeout": 0,
                "actions": [
                    {"identifier": "update-now", "text": "Update Now"},
                    {"identifier": "changelog", "text": "Changelog"},
                    {"identifier": "later", "text": "Later"}
                ],
                "actionHandlers": {
                    "update-now": function() { root.performUpdate(); },
                    "changelog": function() { Quickshell.execDetached(["xdg-open", root.changelogUrl]); },
                    "later": function(id) {
                        Notifications.discardNotification(id);
                        root.nextCheckTime = Date.now() + 8 * 3600000;
                        root.saveCache();
                    }
                }
            });
        } catch (e) {
            console.log("[UpdateService] Error sending notification:", e);
        }
    }

    function performUpdate() {
        Quickshell.execDetached(["bash", "-c", "nohup " + root.cliPath + " update >/dev/null 2>&1 &"]);
    }

    Component.onDestruction: {
        if (gitProcess.stop !== undefined) gitProcess.stop();
        gitProcess.running = false;
    }
}
