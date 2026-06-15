//@ pragma UseQApplication
//@ pragma ShellId nothingless
//@ pragma DataDir $BASE/nothingless
//@ pragma StateDir $BASE/nothingless
//@ pragma NativeTextRendering
//@ pragma DropExpensiveFonts

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.bar
import qs.modules.bar.workspaces
import qs.modules.notifications
import qs.modules.widgets.dashboard.wallpapers

import qs.modules.notch
import qs.modules.widgets.overview
import qs.modules.widgets.presets
import qs.modules.services
import qs.modules.corners
import qs.modules.frame
import qs.modules.components
import qs.modules.desktop
import qs.modules.lockscreen
import qs.modules.dock
import qs.modules.globals
import qs.modules.shell
import qs.modules.theme
import qs.config
import qs.modules.shell.osd
import "modules/tools"

ShellRoot {
    id: root

    ContextMenu {
        id: contextMenu
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        Component.onCompleted: Visibilities.setContextMenu(contextMenu)
    }

    Variants {
        model: Quickshell.screens

        Loader {
            id: wallpaperLoader
            active: true
            required property ShellScreen modelData
            sourceComponent: Wallpaper {
                screen: wallpaperLoader.modelData
            }
        }
    }

    Variants {
        model: Quickshell.screens

        Loader {
            id: desktopLoader
            active: Config.desktop.enabled && SuspendManager.wakeReady
            required property ShellScreen modelData
            sourceComponent: Desktop {
                screen: desktopLoader.modelData
            }
        }
    }

    // Visual panel & reservations
    Variants {
        model: Quickshell.screens

        Item {
            id: screenShellContainer
            required property ShellScreen modelData

            // Panel components (Bar, Notch, Dock, Frame, Corners)
            UnifiedShellPanel {
                id: unifiedPanel
                targetScreen: screenShellContainer.modelData
            }

            Loader {
                active: Config.theme.enableCorners && Config.roundness > 0
                sourceComponent: ScreenCorners {
                    screen: screenShellContainer.modelData
                }
            }

            // Exclusive zone reservations
            ReservationWindows {
                screen: screenShellContainer.modelData

                // Island mode detection
                readonly property bool _islandActive: (Config.bar && Config.bar.barMode === "dynamic") && (Config.notchTheme || "default") === "island" && unifiedPanel.barPosition === (Config.notchPosition || "top")

                // Bar status for reservations
                barEnabled: {
                    const list = (Config.bar && Config.bar.screenList !== undefined ? Config.bar.screenList : []);
                    const isOnList = !list || list.length === 0 || list.indexOf(screen.name) !== -1;
                    // In island mode: only reserve if island is pinned
                    if (_islandActive) return isOnList && unifiedPanel.notchPinned;
                    return isOnList;
                }
                barPosition: unifiedPanel.barPosition
                barPinned: _islandActive ? unifiedPanel.notchPinned : unifiedPanel.pinned
                barSize: _islandActive ? 44 : (unifiedPanel.barPosition === "left" || unifiedPanel.barPosition === "right") ? unifiedPanel.barTargetWidth : unifiedPanel.barTargetHeight
                barOuterMargin: _islandActive ? 0 : unifiedPanel.barOuterMargin

                // Dock status for reservations
                dockEnabled: {
                    if (!((Config.dock && Config.dock.enabled !== undefined ? Config.dock.enabled : false)) || (Config.dock && Config.dock.theme !== undefined ? Config.dock.theme : "default") === "integrated")
                        return false;

                    // In island mode: only reserve dock space if island is pinned
                    if (_islandActive) {
                        if (!unifiedPanel.notchPinned) return false;
                        const dp = (Config.dock && Config.dock.position) || "center";
                        if (dp === "center" || dp === unifiedPanel.barPosition) return false;
                    }

                    const list = (Config.dock && Config.dock.screenList !== undefined ? Config.dock.screenList : []);
                    if (!list || list.length === 0)
                        return true;
                    return list.indexOf(screenShellContainer.modelData.name) !== -1;
                }
                dockPosition: unifiedPanel.dockPosition
                dockPinned: unifiedPanel.dockPinned
                dockHeight: unifiedPanel.dockHeight
                containBar: unifiedPanel.containBar

                frameEnabled: (Config.bar && Config.bar.frameEnabled !== undefined ? Config.bar.frameEnabled : false)
                frameThickness: (Config.bar && Config.bar.frameThickness !== undefined ? Config.bar.frameThickness : 6)

                // Sidebar status for reservations
                sidebarEnabled: GlobalStates.assistantVisible && screenShellContainer.modelData.name === GlobalStates.assistantScreenName
                sidebarPinned: GlobalStates.assistantPinned
                sidebarWidth: GlobalStates.assistantWidth
                sidebarPosition: GlobalStates.assistantPosition
            }
        }
    }

    // Overview popup
    Variants {
        model: {
            const screens = Quickshell.screens;
            const list = (Config.bar && Config.bar.screenList !== undefined ? Config.bar.screenList : []);
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.indexOf(screen.name) !== -1);
        }

        Loader {
            id: overviewLoader
            active: ((Config.overview && Config.overview.enabled !== undefined ? Config.overview.enabled : true)) && SuspendManager.wakeReady && (Visibilities.getForScreen(modelData.name) ? Visibilities.getForScreen(modelData.name).overview : false)
            required property ShellScreen modelData
            sourceComponent: OverviewPopup {
                screen: overviewLoader.modelData
            }
        }
    }

    // Presets popup
    Variants {
        model: {
            const screens = Quickshell.screens;
            const list = (Config.bar && Config.bar.screenList !== undefined ? Config.bar.screenList : []);
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.indexOf(screen.name) !== -1);
        }

        Loader {
            id: presetsLoader
            active: SuspendManager.wakeReady && (Visibilities.getForScreen(modelData.name) ? Visibilities.getForScreen(modelData.name).presets : false)
            required property ShellScreen modelData
            sourceComponent: PresetsPopup {
                screen: presetsLoader.modelData
            }
        }
    }

    // Secure WlSessionLock lockscreen
    WlSessionLock {
        id: sessionLock
        locked: GlobalStates.lockscreenVisible

        // Surface auto-created per screen
        LockScreen {}
    }

    CompositorConfig {
        id: compositorConfig
    }

    Connections {
        target: GlobalStates
        function onCompositorConfigChanged() {
            compositorConfig.applyCompositorConfig();
        }
    }

    CompositorKeybinds {
        id: compositorKeybinds
    }

    // Screenshot tool
    Variants {
        model: Quickshell.screens

        Loader {
            id: screenshotLoader
            active: GlobalStates.screenshotToolVisible
            required property ShellScreen modelData
            sourceComponent: ScreenshotTool {
                targetScreen: screenshotLoader.modelData
            }
        }
    }

    // Screenshot preview overlay
    Variants {
        model: Quickshell.screens

        Loader {
            id: screenshotOverlayLoader
            active: SuspendManager.wakeReady
            required property ShellScreen modelData
            sourceComponent: ScreenshotOverlay {
                targetScreen: screenshotOverlayLoader.modelData
            }
        }
    }

    // Screen recording tool
    Loader {
        id: screenRecordLoader
        active: SuspendManager.wakeReady && GlobalStates.screenRecordToolVisible
        source: "modules/tools/ScreenrecordTool.qml"

        onLoaded: {
            if (GlobalStates.screenRecordToolVisible && item) {
                item.open();
            }
        }

        Connections {
            target: GlobalStates
            function onScreenRecordToolVisibleChanged() {
                if (screenRecordLoader.status === Loader.Ready) {
                    if (GlobalStates.screenRecordToolVisible) {
                        screenRecordLoader.item.open();
                    } else {
                        screenRecordLoader.item.close();
                    }
                }
            }
        }

        Connections {
            target: screenRecordLoader.status === Loader.Ready ? screenRecordLoader.item : null
            enabled: screenRecordLoader.status === Loader.Ready
            ignoreUnknownSignals: true
            function onVisibleChanged() {
                if (screenRecordLoader.item && !screenRecordLoader.item.visible && GlobalStates.screenRecordToolVisible) {
                    GlobalStates.screenRecordToolVisible = false;
                }
            }
        }
    }

    // Mirror tool
    Loader {
        id: mirrorLoader
        active: SuspendManager.wakeReady && GlobalStates.mirrorWindowVisible
        source: "modules/tools/MirrorWindow.qml"
    }

    // Settings
    Loader {
        id: settingsWindowLoader
        active: SuspendManager.wakeReady && GlobalStates.settingsWindowVisible
        source: "modules/widgets/config/SettingsWindow.qml"
    }

    // On-screen display
    Variants {
        model: Quickshell.screens

        Loader {
            id: osdLoader
            active: SuspendManager.wakeReady
            required property ShellScreen modelData
            sourceComponent: OSD {
                targetScreen: osdLoader.modelData
            }
        }
    }

    // ClipboardService initializes automatically on import; no explicit init needed.

    // Force service init at startup but defer it slightly so it doesn't block the UI
    QtObject {
        id: serviceInitializer

        Component.onCompleted: {
            // Critical services — init immediately (next tick)
            Qt.callLater(() => {
                let _ = CaffeineService.inhibit;
                _ = IdleService.lockCmd; // Force init
                _ = GlobalShortcuts.appId; // Force init (IPC pipe listener)
                _ = BatteryAlertService.enabled; // Force init (battery notifications)
                _ = TodoBoard.initialized; // Force init (load tasks from disk)
            });
        }
    }

    // Non-critical services — defer 2s after startup
    Timer {
        interval: 2000
        running: true
        onTriggered: {
            let _ = NightLightService.active;
            _ = GameModeService.toggled;
        }
    }

    // --- Boot Splash (NOTHING animation with chroma key) ---
    // Duration and visibility controlled by Config.performance
    Loader {
        id: bootSplash
        active: typeof Config !== "undefined" && Config.performance && Config.performance.showSplash !== false
        sourceComponent: Component {
            Variants {
                model: Quickshell.screens
                PanelWindow {
                    required property var modelData
                    screen: modelData
                    anchors { top: true; left: true; right: true; bottom: true }
                    color: "#000000"
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.namespace: "nothingless:splash-overlay"
                    exclusionMode: ExclusionMode.Ignore

                    StyledRect {
                        id: splashBg
                        variant: "transparent"
                        anchors.fill: parent
                        color: "#000000"

                        AnimatedImage {
                            id: splashAnim
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height) * 0.6
                            height: width
                            source: "assets/nothingless/NOTHING_splash.webp"
                            fillMode: Image.PreserveAspectFit
                            playing: true
                            currentFrame: 0
                        }

                        // Fade out using the active animation profile
                        opacity: splashVisible ? 1.0 : 0.0
                        Behavior on opacity {
                            enabled: Anim.animationsEnabled
                            NumberAnimation {
                                duration: Anim.standardExtraLarge
                                easing.type: Anim.easing("standard").type
                                easing.bezierCurve: Anim.easing("standard").bezierCurve || []
                            }
                        }

                        property bool splashVisible: true

                        readonly property int splashDuration: {
                            if (typeof Config !== "undefined" && Config.performance && Config.performance.splashDuration) {
                                const dur = Config.performance.splashDuration;
                                return dur >= 1000 ? dur : 3000;
                            }
                            return 3000;
                        }

                        Timer {
                            interval: splashBg.splashDuration - 800  // Fade starts before destroy
                            running: true
                            onTriggered: {
                                splashBg.splashVisible = false
                            }
                        }

                        Timer {
                            interval: splashBg.splashDuration
                            running: true
                            onTriggered: {
                                splashAnim.playing = false
                                splashAnim.source = ""
                                bootSplash.active = false
                            }
                        }
                    }
                }
            }
        }
    }

    // toggle-metrics bind is in the sourced config (cli.sh) and managed by the config system
}
