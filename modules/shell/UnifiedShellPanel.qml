import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.bar
import qs.modules.bar.workspaces
import qs.modules.notch
import qs.modules.dock
import qs.modules.frame
import qs.modules.services
import qs.modules.globals
import qs.modules.components
import qs.config
import qs.modules.sidebar

PanelWindow {
    id: unifiedPanel

    required property ShellScreen targetScreen
    screen: targetScreen

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"

    // Dynamic keyboard focus: Exclusive when a notch module is open (so text fields work),
    // None otherwise (so compositor receives normal input).
    WlrLayershell.keyboardFocus: {
        if (notchContent.screenNotchOpen) {
            return WlrKeyboardFocus.Exclusive;
        }
        if (assistantSidebar.active && assistantSidebar.wantsFocus) {
            return WlrKeyboardFocus.Exclusive;
        }
        return WlrKeyboardFocus.None;
    }
    WlrLayershell.namespace: "nothingless"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    // Full-screen input mask: only active for FocusGrab-managed popups
    // (BarPopup dropdowns, context menus, screenshot/recording overlays)
    // and the AI sidebar.
    //
    // NOT triggered by notch menus (launcher/dashboard/powermenu/tools)
    // because those are contained within the notch area — they should not
    // block clicks on real windows behind the shell.
    readonly property bool needsFullScreenInput: FocusGrabManager.hasActiveGrab || (assistantSidebar.active && assistantSidebar.wantsFocus)

    readonly property bool barEnabled: {
        if (!Config.barReady) return false;
        const list = Config.bar.screenList;
        return (!list || list.length === 0 || list.indexOf(targetScreen.name) !== -1);
    }

    readonly property bool dockEnabled: {
        if (!Config.dockReady) return false;
        if (!(Config.dock.enabled ?? false) || (Config.dock.theme ?? "default") === "integrated")
            return false;
        const list = Config.dock.screenList;
        return (!list || list.length === 0 || list.indexOf(targetScreen.name) !== -1);
    }

    readonly property alias barPosition: barContent.barPosition
    readonly property alias barPinned: barContent.pinned
    readonly property alias barHoverActive: barContent.hoverActive
    readonly property alias barFullscreen: barContent.activeWindowFullscreen
    readonly property bool barReveal: barEnabled && barContent.reveal
    readonly property alias barTargetWidth: barContent.barTargetWidth
    readonly property alias barTargetHeight: barContent.barTargetHeight
    readonly property alias barOuterMargin: barContent.baseOuterMargin

    readonly property alias dockPosition: dockContent.position
    readonly property alias dockPinned: dockContent.pinned
    readonly property bool dockReveal: dockEnabled && dockContent.reveal
    readonly property alias dockFullscreen: dockContent.activeWindowFullscreen
    readonly property int dockHeight: dockContent.dockSize + dockContent.totalMargin

    // Hide dock when island mode is active and dock shares the same position
    readonly property bool _islandActive: (Config.bar && Config.bar.barMode === "dynamic") && (Config.notchTheme || "default") === "island" && barContent.barPosition === (Config.notchPosition || "top")
    readonly property bool _dockHiddenByIsland: _islandActive && (dockContent.position === barContent.barPosition || (dockContent.position === "center" && (barContent.barPosition === "top" || barContent.barPosition === "bottom")))
    // Dock standalone is always hidden in island mode (apps shown in island buttons)
    readonly property bool dockActuallyVisible: dockEnabled && !root._dockHiddenByIsland

    readonly property alias notchHoverActive: notchContent.hoverActive
    readonly property alias notchOpen: notchContent.screenNotchOpen
    readonly property alias notchReveal: notchContent.reveal
    readonly property alias notchPinned: notchContent.notchPinned

    // Generic names for external compatibility (Visibilities expects these on the panel object)
    readonly property alias pinned: barContent.pinned
    readonly property bool reveal: barEnabled ? barContent.reveal : false
    readonly property alias hoverActive: barContent.hoverActive // Default hoverActive points to bar
    readonly property alias notch_hoverActive: notchContent.hoverActive // Used by bar to check notch

    readonly property bool unifiedEffectActive: false // Flag to notify children to disable internal borders

    readonly property var compositorMonitor: AxctlService.monitorFor(targetScreen)
    readonly property bool hasFullscreenWindow: {
        if (!compositorMonitor)
            return false;

        const activeWorkspaceId = compositorMonitor.activeWorkspace.id;
        const monId = compositorMonitor.id;

        // Check active toplevel first (fast path)
        const toplevel = ToplevelManager.activeToplevel;
        if (toplevel && toplevel.fullscreen && AxctlService.focusedMonitor.id === monId) {
            return true;
        }

        // Check all windows on this monitor (robust path)
        const wins = CompositorData && CompositorData.windowList ? CompositorData.windowList : [];
        for (let i = 0; i < wins.length; i++) {
            if (wins[i].monitor === monId && wins[i].fullscreen && wins[i].workspace.id === activeWorkspaceId) {
                return true;
            }
        }
        return false;
    }

    // Proxy properties for Bar/Notch synchronization
    // Note: BarContent and NotchContent already handle their internal sync using Visibilities.

    // Helper properties for shadow logic
    readonly property bool keepBarShadow: Config.bar.keepBarShadow ?? false
    readonly property bool keepBarBorder: Config.bar.keepBarBorder ?? false
    readonly property bool containBar: Config.bar.containBar && (Config.bar.frameEnabled ?? false)

    Component.onCompleted: {
        Visibilities.registerBarPanel(screen.name, unifiedPanel);
        Visibilities.registerNotchPanel(screen.name, unifiedPanel);
        Visibilities.registerDockPanel(screen.name, dockContent);
        Visibilities.registerBar(screen.name, barContent);
        Visibilities.registerNotch(screen.name, notchContent.notchContainerRef);
        Visibilities.registerDock(screen.name, dockContent);
    }

    Component.onDestruction: {
        Visibilities.unregisterBarPanel(screen.name);
        Visibilities.unregisterNotchPanel(screen.name);
        Visibilities.unregisterDockPanel(screen.name);
        Visibilities.unregisterBar(screen.name);
        Visibilities.unregisterNotch(screen.name);
        Visibilities.unregisterDock(screen.name);
    }

    // Full-screen mask item (used when modules/popups are open)
    Item {
        id: fullScreenMask
        anchors.fill: parent
    }

    // Zero-size mask item — used when no full-screen input is needed.
    // Explicitly setting a 0×0 item prevents the compositor from
    // defaulting to the entire surface as an input region.
    Item {
        id: emptyMask
        width: 0
        height: 0
    }

    // Mask Region Logic
    // When a popup/dropdown is open (FocusGrab active): full-screen mask.
    // Otherwise: only Bar, Notch hover edge, Notch content, Dock, and
    // Sidebar hitboxes receive input — clicks everywhere else pass
    // through to real windows behind the shell.
    mask: Region {
        item: unifiedPanel.needsFullScreenInput ? fullScreenMask : emptyMask
        regions: [
            Region {
                // In island mode, exclude bar hitbox so clicks reach the notch
                item: !unifiedPanel._islandActive && barContent.visible ? barContent.barHitbox : null
            },
            Region {
                // Always include hover region for edge detection
                item: notchContent.notchHoverRegionRef
            },
            Region {
                // Full notch area only when active (module open or revealed)
                item: (unifiedPanel.needsFullScreenInput || unifiedPanel.notchReveal || unifiedPanel.notchOpen) ? notchContent.notchActiveRegion : null
            },
            Region {
                // Only include the dock hitbox if the dock is actually enabled and visible on this screen.
                item: unifiedPanel.dockActuallyVisible ? dockContent.dockHitbox : null
            },
            Region {
                item: (assistantSidebar.active || assistantSidebar.hitbox.visible) ? assistantSidebar.hitbox : null
            }
        ]
    }

    // Track which window was focused before the notch opened, so we can detect
    // when the user clicks a real window and dismiss the notch accordingly.
    property string _focusedClientAddressBeforeNotch: ""

    onNotchOpenChanged: {
        if (notchOpen) {
            let fc = AxctlService.focusedClient;
            _focusedClientAddressBeforeNotch = (fc && fc.address) ? fc.address : "";
        }
    }

    // Dismiss the notch when the user clicks a real window.
    //
    // Uses TWO mechanisms because WlrKeyboardFocus.Exclusive (needed for
    // text input in the launcher) prevents Hyprland from updating
    // focusedClient in the normal way:
    //
    // 1. AxctlService.rawEvent — catches Hyprland IPC events directly
    //    (activewindow, activewindowv2) which fire even with Exclusive keyboard.
    // 2. AxctlService.onFocusedClientChanged — fallback for state-poll updates.
    Connections {
        target: AxctlService

        // Primary: listen for Hyprland window-focus events via IPC socket.
        // These fire when the user clicks ANY window, regardless of which
        // surface has WlrKeyboardFocus.
        function onRawEvent(event) {
            if (!notchContent.screenNotchOpen) return;
            if (!event || !event.name) return;

            var name = event.name;

            // activewindow / activewindowv2: a window was focused.
            // The event data contains the window address string.
            // We only dismiss if there IS window data (not null/empty),
            // which guards against spurious events when layer surfaces
            // change keyboard focus.
            if (name === "activewindow" || name === "activewindowv2") {
                if (event.data && event.data !== "") {
                    Visibilities.setActiveModule("");
                }
            }
        }

        // Fallback: state-based focusedClient change detection.
        // Works when Exclusive keyboard is NOT preventing focus changes.
        function onFocusedClientChanged() {
            if (notchContent.screenNotchOpen && AxctlService.focusedClient) {
                let currentAddr = AxctlService.focusedClient.address || "";
                if (_focusedClientAddressBeforeNotch !== currentAddr) {
                    Visibilities.setActiveModule("");
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // CLICK-OUTSIDE BACKDROP
    // ═══════════════════════════════════════════════════════════════
    //
    // Placed as the LAST child of PanelWindow so it renders on top of
    // all visual content.  Uses propagateComposedEvents so clicks on
    // bar/notch/dock widgets still reach their own MouseAreas.
    // Clicks on empty screen areas trigger a full state cleanup.

    // One-shot Process that focuses the real window under the mouse cursor.
    Process {
        id: focusWindowUnderCursor
        command: ["hyprctl", "dispatch", "focuswindow", "mouse"]
        running: false
    }

    // Track what activated needsFullScreenInput so we can log/debug leaks
    property string _lastNeedsInputReason: ""
    onNeedsFullScreenInputChanged: {
        if (needsFullScreenInput) {
            if (FocusGrabManager.hasActiveGrab && !(assistantSidebar.active && assistantSidebar.wantsFocus)) {
                _lastNeedsInputReason = "focus-grab";
                console.warn("needsFullScreenInput activated by FocusGrabManager. Grab count:", FocusGrabManager._activeCount);
            } else if (assistantSidebar.active && assistantSidebar.wantsFocus) {
                _lastNeedsInputReason = "assistant-sidebar";
                console.warn("needsFullScreenInput activated by AssistantSidebar.");
            } else {
                _lastNeedsInputReason = "unknown";
                console.warn("needsFullScreenInput activated for unknown reason.");
            }
        } else {
            _lastNeedsInputReason = "";
            console.log("needsFullScreenInput deactivated.");
        }
    }

    MouseArea {
        id: backdropArea
        anchors.fill: parent
        visible: unifiedPanel.needsFullScreenInput
        enabled: unifiedPanel.needsFullScreenInput
        propagateComposedEvents: true

        onClicked: {
            // Force-clear everything that could be blocking the screen
            FocusGrabManager.clearTopGrab();
            Visibilities.setActiveModule("");
            if (assistantSidebar.active && assistantSidebar.wantsFocus) {
                assistantSidebar.wantsFocus = false;
            }
            // Focus the real window under cursor
            focusWindowUnderCursor.running = true;
        }
    }

    // Safety net: if needsFullScreenInput stays true for more than 5 seconds
    // without any visible popup/tool, force-clear it. This catches any edge
    // case where a destroyed component failed to release its focus grab.
    Timer {
        id: backdropSafetyTimer
        interval: 5000
        repeat: true
        running: unifiedPanel.needsFullScreenInput
        onTriggered: {
            console.warn("UnifiedShellPanel: backdrop safety net checking — reason:", unifiedPanel._lastNeedsInputReason,
                         "| grabs:", FocusGrabManager._activeCount,
                         "| notchOpen:", unifiedPanel.notchOpen,
                         "| screenshot:", GlobalStates.screenshotToolVisible,
                         "| record:", GlobalStates.screenRecordToolVisible,
                         "| settings:", GlobalStates.settingsWindowVisible,
                         "| mirror:", GlobalStates.mirrorWindowVisible,
                         "| assistant:", GlobalStates.assistantVisible);

            // If the reason was a focus grab and no tool/popup is visibly open,
            // the grab is almost certainly orphaned — wipe it.
            if (FocusGrabManager.hasActiveGrab) {
                if (!unifiedPanel.notchOpen && !GlobalStates.screenshotToolVisible && !GlobalStates.screenRecordToolVisible && !GlobalStates.settingsWindowVisible && !GlobalStates.mirrorWindowVisible && !GlobalStates.assistantVisible) {
                    console.warn("UnifiedShellPanel: safety net triggered — clearing orphaned grabs.");
                    while (FocusGrabManager.hasActiveGrab) {
                        FocusGrabManager.clearTopGrab();
                    }
                }
            }

            // Also clear assistant focus if sidebar is not visible anymore
            if (assistantSidebar.active && assistantSidebar.wantsFocus && !GlobalStates.assistantVisible) {
                console.warn("UnifiedShellPanel: safety net clearing stale assistant wantsFocus.");
                assistantSidebar.wantsFocus = false;
            }

            // If after cleanup needsFullScreenInput is still true, log loudly
            if (unifiedPanel.needsFullScreenInput) {
                console.error("UnifiedShellPanel: CRITICAL — needsFullScreenInput STILL true after safety net! Reason:", unifiedPanel._lastNeedsInputReason);
            }
        }
    }

    // Emergency keyboard shortcut: force-clear all blocking state immediately.
    // Use this when the transparent overlay gets stuck and you cannot click windows.
    Shortcut {
        sequences: ["Meta+Shift+Escape", "Ctrl+Shift+Escape"]
        onActivated: {
            console.warn("EMERGENCY: force-clearing all input-blocking state.");
            while (FocusGrabManager.hasActiveGrab) {
                FocusGrabManager.clearTopGrab();
            }
            Visibilities.setActiveModule("");
            if (assistantSidebar.active && assistantSidebar.wantsFocus) {
                assistantSidebar.wantsFocus = false;
            }
            GlobalStates.screenshotToolVisible = false;
            GlobalStates.screenRecordToolVisible = false;
            GlobalStates.settingsWindowVisible = false;
            GlobalStates.mirrorWindowVisible = false;
            GlobalStates.assistantVisible = false;
            focusWindowUnderCursor.running = true;
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // VISUAL CONTENT
    // ═══════════════════════════════════════════════════════════════

    Item {
        id: visualContent
        anchors.fill: parent

        readonly property bool needLayer: 
            (unifiedPanel.barEnabled && unifiedPanel.barReveal) ||
            (unifiedPanel.dockEnabled && unifiedPanel.dockReveal) ||
            unifiedPanel.notchReveal ||
            assistantSidebar.active ||
            (Config.bar?.frameEnabled ?? false)

        layer.enabled: needLayer
        layer.effect: Shadow {}

        ScreenFrameContent {
            id: frameContent
            anchors.fill: parent
            targetScreen: unifiedPanel.targetScreen
            hasFullscreenWindow: unifiedPanel.hasFullscreenWindow
            z: 1
        }

        BarContent {
            id: barContent
            anchors.fill: parent
            screen: unifiedPanel.targetScreen
            z: 2
            visible: unifiedPanel.barEnabled
        }

        DockContent {
            id: dockContent
            unifiedEffectActive: unifiedPanel.unifiedEffectActive
            anchors.fill: parent
            screen: unifiedPanel.targetScreen
            z: 3
            visible: unifiedPanel.dockActuallyVisible
        }

        NotchContent {
            id: notchContent
            unifiedEffectActive: unifiedPanel.unifiedEffectActive
            anchors.fill: parent
            screen: unifiedPanel.targetScreen
            z: 4
        }

        AssistantSidebar {
            id: assistantSidebar
            targetScreen: unifiedPanel.targetScreen
            z: 1
            
            // Respect top/bottom bar reservations so the sidebar doesn't overlap them
            anchors.topMargin: {
                let frameOn = (Config.bar?.frameEnabled ?? false);
                let frameWrapped = frameOn && GlobalStates.assistantPinned;
                let margin = (frameOn && !frameWrapped) ? (Config.bar?.frameThickness ?? 6) : 0;
                if (unifiedPanel.barEnabled && unifiedPanel.barPosition === "top" && unifiedPanel.barPinned) {
                    margin += unifiedPanel.barTargetHeight + unifiedPanel.barOuterMargin + (unifiedPanel.containBar ? Config.bar.frameThickness : 0);
                }
                return margin;
            }
            
            anchors.bottomMargin: {
                let frameOn = (Config.bar?.frameEnabled ?? false);
                let frameWrapped = frameOn && GlobalStates.assistantPinned;
                let margin = (frameOn && !frameWrapped) ? (Config.bar?.frameThickness ?? 6) : 0;
                if (unifiedPanel.barEnabled && unifiedPanel.barPosition === "bottom" && unifiedPanel.barPinned) {
                    margin += unifiedPanel.barTargetHeight + unifiedPanel.barOuterMargin + (unifiedPanel.containBar ? Config.bar.frameThickness : 0);
                } else if (unifiedPanel.dockEnabled && dockContent.dockPosition === "bottom" && dockContent.pinned) {
                    margin += dockContent.dockHeight;
                }
                return margin;
            }

            anchors.leftMargin: {
                let sidebarPos = GlobalStates.assistantPosition;
                let frameOn = (Config.bar?.frameEnabled ?? false);
                let frameWrapped = frameOn && GlobalStates.assistantPinned;
                let margin = 0;
                if (sidebarPos === "left" && frameOn && !frameWrapped)
                    margin += (Config.bar?.frameThickness ?? 6);
                if (unifiedPanel.barEnabled && unifiedPanel.barPosition === "left" && unifiedPanel.barPinned)
                    margin += unifiedPanel.barTargetWidth + unifiedPanel.barOuterMargin + (unifiedPanel.containBar ? Config.bar.frameThickness : 0);
                return margin;
            }

            anchors.rightMargin: {
                let sidebarPos = GlobalStates.assistantPosition;
                let frameOn = (Config.bar?.frameEnabled ?? false);
                let frameWrapped = frameOn && GlobalStates.assistantPinned;
                let margin = 0;
                if (sidebarPos === "right" && frameOn && !frameWrapped)
                    margin += (Config.bar?.frameThickness ?? 6);
                if (unifiedPanel.barEnabled && unifiedPanel.barPosition === "right" && unifiedPanel.barPinned)
                    margin += unifiedPanel.barTargetWidth + unifiedPanel.barOuterMargin + (unifiedPanel.containBar ? Config.bar.frameThickness : 0);
                return margin;
            }
        }
    }
}
