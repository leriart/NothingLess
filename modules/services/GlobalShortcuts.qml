pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.globals
import qs.modules.services
import qs.config

QtObject {
    id: root

    readonly property string appId: "nothingless"
    readonly property string ipcPipe: "/tmp/nothingless_ipc.pipe"

    property Process toggleMetricProcess: Process {
        command: ["sh", "-c", Quickshell.shellDir + "/scripts/toggle-metrics.sh"]
        running: false
    }

    // High-performance Pipe Listener (Daemon mode)
    property Process pipeListener: Process {
        // Use a small wrapper script that:
        //  1. Removes any stale FIFO left behind by a previous shell.
        //  2. Creates a fresh FIFO (mkfifo -m 0600 for tighter perms).
        //  3. Uses `cat` instead of `tail -f` — tail reopens the file on
        //     truncation which can drop messages on hot-restart; cat blocks
        //     on the open FIFO and reads every line that comes through.
        //  4. Auto-restarts itself if the FIFO is closed (handles the case
        //     where the shell is reloaded while the old tail is still alive).
        command: ["bash", "-c",
            "PIPE='" + root.ipcPipe + "'; " +
            "while true; do " +
            "  rm -f \"$PIPE\" 2>/dev/null; " +
            "  if mkfifo -m 0600 \"$PIPE\" 2>/dev/null; then " +
            "    cat \"$PIPE\"; " +
            "  fi; " +
            "  sleep 0.2; " +
            "done"
        ]
        running: true

        stdout: SplitParser {
            onRead: data => {
                const cmd = data.trim();
                if (cmd !== "") {
                    root.run(cmd);
                }
            }
        }

        onExited: code => {
            // The wrapper should never exit on its own, but if it does
            // (e.g. bash crashed), restart it after a short delay so we
            // don't permanently lose IPC signal reception.
            if (code !== 0) {
                console.warn("GlobalShortcuts: pipeListener exited with code " + code + ", restarting");
                Qt.callLater(() => { root.pipeListener.running = true; });
            }
        }
    }

    Component.onDestruction: {
        // Best-effort cleanup. On normal exit this just removes the FIFO;
        // the next shell startup will recreate it. If the destructor is
        // running because the shell is being reloaded, the new shell will
        // immediately create a fresh FIFO with the same name.
        try {
            Qt.callLater(function() {
                let p = Qt.createQmlObject(
                    'import Quickshell.Io; Process { command: ["rm", "-f", "' + root.ipcPipe + '"] }',
                    root
                );
                p.running = true;
            });
        } catch (e) {
            // Ignore — best-effort cleanup only
        }
    }


    function toggleMetrics() {
        // Toggle the notch metrics overlay
        if (Config.notch) {
            Config.notch.showMetrics = !Config.notch.showMetrics;
            console.log("Metrics overlay toggled:", Config.notch.showMetrics);
        }
    }

    function run(command) {
        console.log("IPC run command received:", command);
        switch (command) {
            // Launcher (Standalone Notch Module)
            case "launcher": toggleLauncher(); break;
            case "clipboard": toggleLauncherWithPrefix(1, Config.prefix.clipboard + " "); break;
            case "emoji": toggleLauncherWithPrefix(2, Config.prefix.emoji + " "); break;
            case "tmux": toggleLauncherWithPrefix(3, Config.prefix.tmux + " "); break;
            case "notes": toggleLauncherWithPrefix(4, Config.prefix.notes + " "); break;

            // Dashboard
            case "dashboard": toggleDashboardTab(0); break;
            case "wallpapers": toggleDashboardTab(1); break;
            case "todo": toggleDashboardTab(3); break;
            case "assistant": toggleAssistant(); break;
            case "dashboard-widgets": toggleDashboardTab(0); break;
            case "dashboard-wallpapers": toggleDashboardTab(1); break;
            case "dashboard-todo": toggleDashboardTab(3); break;
            case "dashboard-assistant": toggleAssistant(); break;
            case "dashboard-controls": toggleSettings(); break;

            // System
            case "overview": toggleSimpleModule("overview"); break;
            case "powermenu": toggleSimpleModule("powermenu"); break;
            case "tools": toggleSimpleModule("tools"); break;
            case "toggle-metrics":
                root.toggleMetrics();
                console.log("Metrics toggled");
                break;
            case "config": toggleSettings(); break;
            case "screenshot": Screenshot.initialize(); GlobalStates.screenshotToolVisible = true; break;
            case "screenrecord": ScreenRecorder.initialize(); GlobalStates.screenRecordToolVisible = true; break;
            case "lens": 
                Screenshot.initialize();
                Screenshot.captureMode = "lens";
                GlobalStates.screenshotToolVisible = true;
                break;
            case "lockscreen": GlobalStates.lockscreenVisible = true; break;
            case "share-scan":
                // Super+K (Win+K equivalent): open the settings window on the
                // Screen Sharing tab and ask MiraiService to scan for sinks.
                // Tab indices for SettingsTab: see modules/widgets/dashboard/controls/SettingsTab.qml
                // 0: Network, 1: Bluetooth, 2: Mixer, 3: AI, 4: Effects, 5: Theme,
                // 6: Binds, 7: System, 8: Compositor, 9: Shell, 10: Screen Sharing.
                GlobalStates.settingsCurrentTab = 10;
                GlobalStates.settingsWindowVisible = true;
                MiraiService.refreshStatus();
                MiraiService.scanSinks(10);
                break;
            
            // Media
            case "media-seek-backward": seekActivePlayer(-mediaSeekStepMs); break;
            case "media-seek-forward": seekActivePlayer(mediaSeekStepMs); break;
            case "media-play-pause": 
                if (MprisController.canTogglePlaying) MprisController.togglePlaying();
                break;
            case "media-next": MprisController.next(); break;
            case "media-prev": MprisController.previous(); break;
                
            // System toggles
            case "caffeine": CaffeineService.toggleInhibit(); break;
            case "gamemode": GameModeService.toggle(); break;
            case "focusmode": FocusModeService.toggle(); break;
            case "dnd": GlobalStates.notificationsDnd = !GlobalStates.notificationsDnd; break;
            case "nightlight": NightLightService.toggle(); break;

            // Power profile
            case "powerprofile-saver": PowerProfile.setProfile("power-saver"); break;
            case "powerprofile-balanced": PowerProfile.setProfile("balanced"); break;
            case "powerprofile-performance": PowerProfile.setProfile("performance"); break;
            case "cycle-powerprofile": PowerProfile.cycle(); break;

            // Charge limit
            case "charge-limit-status":
                console.log("ChargeLimit: enabled=" + ChargeLimitService.enabled +
                            " limit=" + ChargeLimitService.limit +
                            " backend=" + ChargeLimitService.backendType +
                            " available=" + ChargeLimitService.isAvailable);
                break;
            case "charge-limit-on":
                if (ChargeLimitService.isAvailable) ChargeLimitService.setEnabled(true);
                else console.warn("ChargeLimit: no backend available");
                break;
            case "charge-limit-off":
                ChargeLimitService.setEnabled(false);
                break;
            default:
                // Pattern: "charge-limit-set <percent>"
                if (command.indexOf("charge-limit-set ") === 0) {
                    const pct = parseInt(command.substring("charge-limit-set ".length).trim(), 10);
                    if (!isNaN(pct) && pct >= 50 && pct <= 100) {
                        ChargeLimitService.setLimit(pct);
                    } else {
                        console.warn("ChargeLimit: invalid percent (must be 50-100)");
                    }
                } else {
                    console.warn("Unknown IPC command:", command);
                }
                break;

            // Audio
            case "volume-up": Audio.incrementVolume(); break;
            case "volume-down": Audio.decrementVolume(); break;
            case "volume-mute": Audio.toggleMute(); break;
            case "mic-mute": Audio.toggleMicMute(); break;

            // Diagnostic / repair
            case "reload-binds": CompositorKeybinds.forceReloadBinds(); break;
        }
    }

    property IpcHandler ipcHandler: IpcHandler {
        target: "nothingless"

        function run(command: string) {
            root.run(command);
        }
    }

    function toggleSettings() {
        const willOpen = !GlobalStates.settingsWindowVisible;
        if (willOpen) {
            GlobalStates.settingsTargetWorkspaceId = AxctlService.focusedMonitor?.activeWorkspace?.id || AxctlService.focusedWorkspace?.id || 0;
            GlobalStates.settingsTargetScreenName = AxctlService.focusedMonitor?.name || "";
            Visibilities.setActiveModule("");
        }
        GlobalStates.settingsWindowVisible = willOpen;
    }

    function toggleSimpleModule(moduleName) {
        if (Visibilities.currentActiveModule === moduleName) {
            Visibilities.setActiveModule("");
        } else {
            Visibilities.setActiveModule(moduleName);
        }
    }


    function toggleLauncher() {
        const isActive = Visibilities.currentActiveModule === "launcher";
        if (isActive && GlobalStates.widgetsTabCurrentIndex === 0 && GlobalStates.launcherSearchText === "") {
            Visibilities.setActiveModule("");
        } else {
            GlobalStates.widgetsTabCurrentIndex = 0;
            GlobalStates.launcherSearchText = "";
            GlobalStates.launcherSelectedIndex = -1;
            if (!isActive) {
                Visibilities.setActiveModule("launcher");
            }
        }
    }


    function toggleLauncherWithPrefix(tabIndex, prefix) {
        const isActive = Visibilities.currentActiveModule === "launcher";
        const currentTab = GlobalStates.widgetsTabCurrentIndex;
        const currentText = GlobalStates.launcherSearchText;

        if (isActive && currentTab === tabIndex && (currentText === prefix || currentText === "")) {
            Visibilities.setActiveModule("");
            GlobalStates.clearLauncherState();
            return;
        }

        GlobalStates.widgetsTabCurrentIndex = tabIndex;
        GlobalStates.launcherSearchText = prefix;
        
        if (!isActive) {
            Visibilities.setActiveModule("launcher");
        }
    }

    function toggleDashboardTab(tabIndex) {
        const isActive = Visibilities.currentActiveModule === "dashboard";
        
        // Special handling for widgets tab (launcher)
        if (tabIndex === 0) {
            if (isActive && GlobalStates.dashboardCurrentTab === 0 && GlobalStates.launcherSearchText === "") {
                // Only toggle off if we're already in launcher without prefix
                Visibilities.setActiveModule("");
                return;
            }
            
            // Otherwise, always go to launcher (clear any prefix and ensure tab 0)
            GlobalStates.dashboardCurrentTab = 0;
            GlobalStates.launcherSearchText = "";
            GlobalStates.launcherSelectedIndex = -1;
            if (!isActive) {
                Visibilities.setActiveModule("dashboard");
            }
            return;
        }
        
        // For other tabs, normal toggle behavior
        if (isActive && GlobalStates.dashboardCurrentTab === tabIndex) {
            Visibilities.setActiveModule("");
            return;
        }

        GlobalStates.dashboardCurrentTab = tabIndex;
        if (!isActive) {
            Visibilities.setActiveModule("dashboard");
        }
    }

    function toggleDashboardWithPrefix(prefix) {
        const isActive = Visibilities.currentActiveModule === "dashboard";
        
        if (isActive && GlobalStates.dashboardCurrentTab === 0 && GlobalStates.launcherSearchText === prefix) {
            Visibilities.setActiveModule("");
            GlobalStates.clearLauncherState();
            return;
        }

        GlobalStates.dashboardCurrentTab = 0;
        
        if (!isActive) {
            Visibilities.setActiveModule("dashboard");
            Qt.callLater(() => {
                GlobalStates.launcherSearchText = prefix;
            });
        } else {
            GlobalStates.launcherSearchText = prefix;
        }
    }

    function toggleAssistant() {
        GlobalStates.toggleAssistant();
    }
    function seekActivePlayer(offset) {
        const player = MprisController.activePlayer;
        if (!player || !player.canSeek) {
            return;
        }

        const maxLength = typeof player.length === "number" && !isNaN(player.length)
                ? player.length
                : Number.MAX_SAFE_INTEGER;
        const clamped = Math.max(0, Math.min(maxLength, player.position + offset));
        player.position = clamped;
    }
}
