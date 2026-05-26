import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.globals
import qs.modules.theme
import qs.modules.widgets.defaultview
import qs.modules.widgets.dashboard
import qs.modules.widgets.powermenu
import qs.modules.widgets.tools
import qs.modules.services
import qs.modules.components
import qs.modules.widgets.launcher
import qs.modules.bar.workspaces
import qs.modules.bar.clock
import qs.modules.bar.systray
import qs.modules.bar.tasktray
import qs.modules.bar
import qs.modules.widgets.presets
import qs.config
import "./NotchNotificationView.qml"

Item {
    id: root

    required property ShellScreen screen
    property bool unifiedEffectActive: false

    // Get this screen's visibility state
    readonly property var screenVisibilities: Visibilities.getForScreen(screen.name)
    readonly property bool isScreenFocused: AxctlService.focusedMonitor && AxctlService.focusedMonitor.name === screen.name

    // Monitor reference and refrence to toplevels on monitor
    readonly property var compositorMonitor: AxctlService.monitorFor(screen)
    readonly property var toplevels: (!compositorMonitor || !compositorMonitor.activeWorkspace || !AxctlService.clients.values) ? [] : AxctlService.clients.values.filter(c => c.workspace.id === compositorMonitor.activeWorkspace.id)

    // Check if there are any windows on the current monitor and workspace
    readonly property bool hasWindows: toplevels.length > 0

    // Check if notch island is merged with bar (same position + island theme)
    readonly property bool islandMergedWithBar: {
        const theme = Config.notchTheme || "default";
        const bp = root.barPosition;
        const barMode = (Config.bar && Config.bar.barMode) || "extended";
        return theme === "island" && root.notchPosition === bp && barMode === "dynamic";
    }
    
    // Frame offset for positioning
    readonly property int frameOffset: (Config.bar && Config.bar.frameEnabled && !root.activeWindowFullscreen) ? ((Config.bar.frameThickness !== undefined) ? Config.bar.frameThickness : 6) : 0

    // In island mode: always enabled (buttons need to work)
    enabled: root.islandMergedWithBar ? true : !root._mergedHidden

    // Dock joins island bar if same position
    readonly property bool dockSamePosition: {
        if (!Config.dock || !Config.dock.enabled) return false;
        var dp = Config.dock.position || "center";
        if (dp === "center") return root.barPosition === "top" || root.barPosition === "bottom";
        return dp === root.barPosition;
    }

    // In island mode: root always visible, children animate their own hide.
    // In normal mode: hide when merged+idle.
    readonly property bool _mergedHidden: !root.reveal
    opacity: root.islandMergedWithBar ? 1.0 : (root._mergedHidden ? 0.0 : 1.0)
    Behavior on opacity {
        enabled: Anim.animationsEnabled
        NumberAnimation { duration: Anim.emphasizedNormal; easing.type: Anim.easing("decelerate").type; easing.bezierCurve: Anim.easing("decelerate").bezierCurve }
    }
    
    // Get the bar position for this screen
    readonly property string barPosition: PerMonitorConfig.resolve(screen.name, "bar", "position",
        (Config.bar && Config.bar.position !== undefined) ? Config.bar.position : "top")
    readonly property string notchPosition: PerMonitorConfig.resolve(screen.name, "notch", "position",
        Config.notchPosition !== undefined ? Config.notchPosition : "top")

    // Get the bar panel for this screen to check its state
    readonly property var barPanelRef: Visibilities.barPanels[screen.name]

    // Check if bar is pinned (use bar state directly)
    readonly property bool barPinned: {
        // If barPanelRef exists, trust its pinned state explicitly
        if (barPanelRef && typeof barPanelRef.pinned !== 'undefined') {
            return barPanelRef.pinned;
        }
        // Fallback to config only if panel ref is missing
        return (Config.bar && Config.bar.pinnedOnStartup !== undefined) ? Config.bar.pinnedOnStartup : true;
    }
    
    // Check if bar is hovering (for synchronized reveal when bar is at same side)
    readonly property bool barHoverActive: {
        if (barPosition !== notchPosition)
            return false;
        if (barPanelRef && typeof barPanelRef.hoverActive !== 'undefined') {
            return barPanelRef.hoverActive;
        }
        return false;
    }

    // Fullscreen detection - use parent panel's robust detection, fallback to ToplevelManager
    readonly property bool activeWindowFullscreen: {
        // Prefer the parent UnifiedShellPanel's hasFullscreenWindow (checks both ToplevelManager + CompositorData)
        if (barPanelRef && typeof barPanelRef.hasFullscreenWindow !== 'undefined') {
            return barPanelRef.hasFullscreenWindow;
        }
        // Fallback: use ToplevelManager (native Wayland) like the bar does
        const toplevel = ToplevelManager.activeToplevel;
        if (!toplevel || !toplevel.activated)
            return false;
        return toplevel.fullscreen === true;
    }

    // Should auto-hide logic:
    // 1. If notch and bar are on different sides: hide if keepHidden is ON, OR if windows/fullscreen are present
    // 2. If notch and bar are on same side: hide only if bar is unpinned OR if fullscreen is present
    readonly property bool shouldAutoHide: {
        if (barPosition !== notchPosition) {
            if ((Config.notch && Config.notch.keepHidden !== undefined) ? Config.notch.keepHidden : false) return true;
            return hasWindows || activeWindowFullscreen;
        }
        return !barPinned || activeWindowFullscreen;
    }

    // Check if the bar for this screen is vertical
    readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"

    // Island button sizing: square buttons matching notch compact height
    readonly property int islandButtonSize: {
        const baseSize = Config.showBackground ? (Config.notchTheme === "island" ? 36 : 44)
                                               : (Config.notchTheme === "island" ? 36 : 40);
        return Math.max(32, Math.min(48, baseSize));
    }

    // Comprehensive bar proxy for island-mode buttons (mirrors BarContent root)
    readonly property var islandBarProxy: QtObject {
        property var screen: root.screen
        property string orientation: "horizontal"
        property string barPosition: root.barPosition
        property string barMode: "dynamic"
        property bool shadowsEnabled: false
    }

    // Dock apps visible in island mode — only if dock shares position with bar/notch
    readonly property bool islandDockEnabled: Config.dock && Config.dock.enabled && Config.dock.theme !== "integrated" && root.dockSamePosition

    // Notch state properties
    readonly property bool screenNotchOpen: screenVisibilities ? (screenVisibilities.launcher || screenVisibilities.dashboard || screenVisibilities.powermenu || screenVisibilities.tools) : false
    readonly property bool hasActiveNotifications: Notifications.popupList.length > 0

    // Hover state with delay to prevent flickering
    property bool hoverActive: false

    // Hover tracking for buttons — keeps island visible in auto-hide
    property bool islandButtonsHovered: false
    onIslandButtonsHoveredChanged: {
        if (islandButtonsHovered) { hideDelayTimer.stop(); hoverActive = true; }
        else if (!isMouseOverNotch) { hideDelayTimer.restart(); }
    }

    // Track if mouse is over any notch-related area
    readonly property bool isMouseOverNotch: notchMouseAreaHover.hovered || notchRegionHover.hovered

    // Includes button hover so island stays visible when interacting with buttons
    readonly property bool isMouseOverIsland: isMouseOverNotch || islandButtonsHovered

    // Reveal logic:
    readonly property bool reveal: {
        // If fullscreen and bar is NOT available on fullscreen, hard-hide
        if (activeWindowFullscreen && !(Config.bar && Config.bar.availableOnFullscreen !== undefined ? Config.bar.availableOnFullscreen : false)) {
            return false;
        }

        // If metrics overlay is active, always show the notch
        if (Config.notch && Config.notch.showMetrics === true) {
            return true;
        }

        // If keepHidden is true and NOT merged with bar, ONLY show on interaction
        if (((Config.notch && Config.notch.keepHidden !== undefined) ? Config.notch.keepHidden : false) && barPosition !== notchPosition && !root.islandMergedWithBar) {
            return (screenNotchOpen || hasActiveNotifications || hoverActive || barHoverActive);
        }

        // If not auto-hiding (pinned and not fullscreen), always show
        if (!shouldAutoHide) return true;

        // Show on interaction (hover, open, notifications)
        if (screenNotchOpen || hasActiveNotifications || hoverActive || barHoverActive) {
            return true;
        }

        return false;
    }

    // Timer to delay hiding the notch after mouse leaves
    Timer {
        id: hideDelayTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (!root.isMouseOverIsland) {
                root.hoverActive = false;
            }
        }
    }

    // Watch for mouse state changes — island mode includes button hover
    onIsMouseOverIslandChanged: {
        if (isMouseOverIsland) {
            hideDelayTimer.stop();
            hoverActive = true;
        } else {
            hideDelayTimer.restart();
        }
    }

    // The hitbox for the mask
    readonly property Item notchHitbox: root.reveal ? notchRegionContainer : notchHoverRegion

    // Default view component - user@host text
    Component {
        id: defaultViewComponent
        DefaultView {}
    }

    // Persistent views to avoid creation lag when opening the notch
    Loader {
        id: persistentLauncherViewLoader
        active: false
        sourceComponent: Component { LauncherView { visible: false } }
    }

    Loader {
        id: persistentDashboardViewLoader
        active: false
        sourceComponent: Component { DashboardView { visible: false } }
    }

    // Persistent power menu view
    Loader {
        id: persistentPowerMenuViewLoader
        active: false
        sourceComponent: Component { PowerMenuView { visible: false } }
    }

    // Persistent tools menu view
    Loader {
        id: persistentToolsMenuViewLoader
        active: false
        sourceComponent: Component { ToolsMenuView { visible: false } }
    }

    // Notification view component
    Component {
        id: notificationViewComponent
        NotchNotificationView {}
    }

    // Hover region for detecting mouse when notch is hidden (doesn't block clicks)
    Item {
        id: notchHoverRegion

        // Width follows the notch, height is small hover region when hidden
        width: notchRegionContainer.width + 20
        height: root.reveal ? notchRegionContainer.height : Math.max((Config.notch && Config.notch.hoverRegionHeight !== undefined) ? Config.notch.hoverRegionHeight : 8, 8)

        x: (parent.width - width) / 2
        y: root.notchPosition === "top" ? 0 : parent.height - height

        Behavior on height {
            enabled: Anim.animationsEnabled
            NumberAnimation {
                duration: Anim.standardSmall
                easing.type: Anim.easing("standard").type
                easing.bezierCurve: Anim.easing("standard").bezierCurve
            }
        }

        // HoverHandler doesn't block mouse events
        HoverHandler {
            id: notchMouseAreaHover
            enabled: true
        }
    }

    // ── Island-mode buttons ──
    // Fixed to screen top edge, flanking the centered notch.
    // Both sides have equal total width for visual balance.
    // Hover on buttons keeps the island revealed.

    // Left group — compact, balanced with right
    Row {
        id: islandLeftButtons
        z: 5001
        height: root.islandButtonSize
        anchors.top: root.top
        anchors.topMargin: root.frameOffset + 4
        anchors.right: root.horizontalCenter
        anchors.rightMargin: notchContainer.width / 2 + 12
        spacing: 0
        visible: root.islandMergedWithBar

        // Smooth show/hide — uses opacity+scale, NOT visible, so hide animates
        opacity: root.reveal ? 1 : 0
        scale: root.reveal ? 1 : 0.9
        transformOrigin: Item.Right
        Behavior on opacity {
            enabled: Anim.animationsEnabled
            NumberAnimation { duration: Anim.emphasizedNormal; easing.type: Anim.easing("decelerate").type; easing.bezierCurve: Anim.easing("decelerate").bezierCurve }
        }
        Behavior on scale {
            enabled: Anim.animationsEnabled
            NumberAnimation { duration: Anim.emphasizedNormal; easing.type: Anim.easing("emphasized").type; easing.bezierCurve: Anim.easing("emphasized").bezierCurve }
        }

        HoverHandler { onHoveredChanged: root.islandButtonsHovered = hovered }

        LauncherButton {
            visible: !Config.bar.hiddenIcons.includes("launcher")
            startRadius: Styling.radius(3); endRadius: Styling.radius(3); enableShadow: false
            implicitWidth: root.islandButtonSize; implicitHeight: root.islandButtonSize
        }
        // Separator
        Rectangle { width: 1; height: root.islandButtonSize * 0.5; anchors.verticalCenter: parent.verticalCenter; color: Colors.outline; opacity: 0.3 }
        Workspaces {
            visible: !Config.bar.hiddenIcons.includes("workspaces")
            orientation: "horizontal"; bar: root.islandBarProxy
            startRadius: Styling.radius(3); endRadius: Styling.radius(3)
            implicitHeight: root.islandButtonSize
        }
        Rectangle { width: 1; height: root.islandButtonSize * 0.5; anchors.verticalCenter: parent.verticalCenter; color: Colors.outline; opacity: 0.3 }
        LayoutSelectorButton {
            visible: !Config.bar.hiddenIcons.includes("layout")
            bar: root.islandBarProxy; layerEnabled: false
            startRadius: Styling.radius(3); endRadius: Styling.radius(3)
            implicitWidth: root.islandButtonSize; implicitHeight: root.islandButtonSize
        }
        Rectangle { width: 1; height: root.islandButtonSize * 0.5; anchors.verticalCenter: parent.verticalCenter; color: Colors.outline; opacity: 0.3 }
        Button {
            implicitWidth: root.islandButtonSize; implicitHeight: root.islandButtonSize
            visible: Config.bar && Config.bar.showPinButton !== false && !Config.bar.hiddenIcons.includes("pin")
            background: StyledRect {
                variant: "bg"; enableShadow: false
                radius: Styling.radius(3)
            }
            contentItem: Text {
                text: Icons.pin; font.family: Icons.font
                font.pixelSize: Math.round(root.islandButtonSize * 0.5)
                color: Styling.srItem("overprimary") || Colors.foreground
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
            onClicked: { if (Config.bar) Config.bar.pinnedOnStartup = !(Config.bar.pinnedOnStartup !== false); }
        }
    }

    // Right group — dock, tools, system, clock, power
    Row {
        id: islandRightButtons
        z: 5001
        height: root.islandButtonSize
        anchors.top: root.top
        anchors.topMargin: root.frameOffset + 4
        anchors.left: root.horizontalCenter
        anchors.leftMargin: notchContainer.width / 2 + 12
        spacing: 0
        visible: root.islandMergedWithBar

        // Smooth show/hide — uses opacity+scale, NOT visible, so hide animates
        opacity: root.reveal ? 1 : 0
        scale: root.reveal ? 1 : 0.9
        transformOrigin: Item.Left
        Behavior on opacity {
            enabled: Anim.animationsEnabled
            NumberAnimation { duration: Anim.emphasizedNormal; easing.type: Anim.easing("decelerate").type; easing.bezierCurve: Anim.easing("decelerate").bezierCurve }
        }
        Behavior on scale {
            enabled: Anim.animationsEnabled
            NumberAnimation { duration: Anim.emphasizedNormal; easing.type: Anim.easing("emphasized").type; easing.bezierCurve: Anim.easing("emphasized").bezierCurve }
        }

        HoverHandler { onHoveredChanged: root.islandButtonsHovered = hovered }

        // Dock apps with unified background — same size as other buttons
        Repeater {
            model: root.islandDockEnabled && !Config.bar.hiddenIcons.includes("dock") && TaskbarApps.apps.length > 0 ? TaskbarApps.apps : []
            Rectangle {
                width: root.islandButtonSize; height: root.islandButtonSize
                radius: Styling.radius(3); color: Colors.surfaceContainer
                IntegratedDockAppButton {
                    anchors.centerIn: parent
                    appToplevel: modelData; orientation: "horizontal"
                    iconSize: root.islandButtonSize - 10
                }
            }
        }
        // Separator after dock
        Rectangle {
            visible: root.islandDockEnabled && !Config.bar.hiddenIcons.includes("dock") && TaskbarApps.apps.length > 0
            width: 1; height: root.islandButtonSize * 0.5; anchors.verticalCenter: parent.verticalCenter
            color: Colors.outline; opacity: 0.3
        }
        PresetsButton {
            visible: !Config.bar.hiddenIcons.includes("presets")
            startRadius: Styling.radius(3); endRadius: Styling.radius(3); enableShadow: false
            implicitWidth: root.islandButtonSize; implicitHeight: root.islandButtonSize
        }
        Rectangle { width: 1; height: root.islandButtonSize * 0.5; anchors.verticalCenter: parent.verticalCenter; color: Colors.outline; opacity: 0.3 }
        ToolsButton {
            visible: !Config.bar.hiddenIcons.includes("tools")
            startRadius: Styling.radius(3); endRadius: Styling.radius(3); enableShadow: false
            implicitWidth: root.islandButtonSize; implicitHeight: root.islandButtonSize
        }
        Rectangle { width: 1; height: root.islandButtonSize * 0.5; anchors.verticalCenter: parent.verticalCenter; color: Colors.outline; opacity: 0.3 }
        SysTray {
            visible: !Config.bar.hiddenIcons.includes("systray")
            bar: root.islandBarProxy; enableShadow: false
            startRadius: Styling.radius(3); endRadius: Styling.radius(3)
            implicitHeight: root.islandButtonSize
        }
        Rectangle { width: 1; height: root.islandButtonSize * 0.5; anchors.verticalCenter: parent.verticalCenter; color: Colors.outline; opacity: 0.3 }
        TaskTray {
            visible: !Config.bar.hiddenIcons.includes("tasktray")
            bar: root.islandBarProxy
            startRadius: Styling.radius(3); endRadius: Styling.radius(3)
            implicitHeight: root.islandButtonSize
        }
        Rectangle { width: 1; height: root.islandButtonSize * 0.5; anchors.verticalCenter: parent.verticalCenter; color: Colors.outline; opacity: 0.3 }
        ControlsButton {
            visible: !Config.bar.hiddenIcons.includes("controls")
            bar: root.islandBarProxy; layerEnabled: false
            startRadius: Styling.radius(3); endRadius: Styling.radius(3)
            implicitWidth: root.islandButtonSize; implicitHeight: root.islandButtonSize
        }
        BatteryIndicator {
            visible: !Config.bar.hiddenIcons.includes("battery")
            bar: root.islandBarProxy; layerEnabled: false
            startRadius: Styling.radius(3); endRadius: Styling.radius(3)
            implicitWidth: root.islandButtonSize; implicitHeight: root.islandButtonSize
        }
        Rectangle { width: 1; height: root.islandButtonSize * 0.5; anchors.verticalCenter: parent.verticalCenter; color: Colors.outline; opacity: 0.3 }
        Clock {
            visible: !Config.bar.hiddenIcons.includes("clock")
            bar: root.islandBarProxy; layerEnabled: false
            startRadius: Styling.radius(3); endRadius: Styling.radius(3)
            implicitHeight: root.islandButtonSize
        }
        Rectangle { width: 1; height: root.islandButtonSize * 0.5; anchors.verticalCenter: parent.verticalCenter; color: Colors.outline; opacity: 0.3 }
        PowerButton {
            visible: !Config.bar.hiddenIcons.includes("power")
            startRadius: Styling.radius(3); endRadius: Styling.radius(3); enableShadow: false
            implicitWidth: root.islandButtonSize; implicitHeight: root.islandButtonSize
        }
    }

    Item {
        id: notchRegionContainer
        
        width: Math.max(notchAnimationContainer.width, notificationPopupContainer.visible ? notificationPopupContainer.width : 0)
        height: notchAnimationContainer.height + (notificationPopupContainer.visible ? notificationPopupContainer.height + notificationPopupContainer.anchors.topMargin : 0)

        x: (parent.width - width) / 2
        y: root.notchPosition === "top" ? 0 : parent.height - height

        // HoverHandler to detect when mouse is over the revealed notch
        HoverHandler {
            id: notchRegionHover
            enabled: true
        }

        // Animation container for reveal/hide
        Item {
            id: notchAnimationContainer
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: root.notchPosition === "top" ? parent.top : undefined
            anchors.bottom: root.notchPosition === "bottom" ? parent.bottom : undefined

            width: notchContainer.width
            height: notchContainer.height + (root.notchPosition === "top" ? notchContainer.anchors.topMargin : notchContainer.anchors.bottomMargin)

            // ── Island mode: bloom from center ──
            // Normal mode: slide from off-screen
            // All island elements share same duration for synchronized show/hide.
            opacity: root.reveal ? 1 : 0
            scale: root.islandMergedWithBar ? (root.reveal ? 1 : 0.7) : 1
            transformOrigin: root.islandMergedWithBar
                ? (root.notchPosition === "top" ? Item.Top : Item.Bottom)
                : Item.Center

            Behavior on opacity {
                enabled: Anim.animationsEnabled
                NumberAnimation {
                    duration: Anim.emphasizedNormal
                    easing.type: Anim.easing("decelerate").type
                    easing.bezierCurve: Anim.easing("decelerate").bezierCurve
                }
            }
            Behavior on scale {
                enabled: Anim.animationsEnabled && root.islandMergedWithBar
                NumberAnimation {
                    duration: Anim.emphasizedNormal
                    easing.type: Anim.easing("emphasized").type
                    easing.bezierCurve: Anim.easing("emphasized").bezierCurve
                }
            }

            // Slide (only for non-island mode)
            transform: Translate {
                y: {
                    if (root.islandMergedWithBar) return 0;
                    if (root.reveal) return 0;
                    if (root.notchPosition === "top")
                        return -(Math.max(notchContainer.height, 50) + 16);
                    else
                        return (Math.max(notchContainer.height, 50) + 16);
                }
                Behavior on y {
                    enabled: Anim.animationsEnabled && !root.islandMergedWithBar
                    NumberAnimation {
                        duration: Anim.spatialFast
                        easing.type: Anim.easing("spatial").type
                        easing.bezierCurve: Anim.easing("spatial").bezierCurve
                    }
                }
            }

            // Center notch
            Notch {
                id: notchContainer
                unifiedEffectActive: root.unifiedEffectActive
                parentHovered: root.isMouseOverNotch
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: root.notchPosition === "top" ? parent.top : undefined
                anchors.bottom: root.notchPosition === "bottom" ? parent.bottom : undefined

                compactHeight: root.islandButtonSize

                readonly property int frameOffset: (Config.bar && Config.bar.frameEnabled && !root.activeWindowFullscreen) ? ((Config.bar.frameThickness !== undefined) ? Config.bar.frameThickness : 6) : 0

                anchors.topMargin: (root.notchPosition === "top" ? (Config.notchTheme === "default" ? 0 : (Config.notchTheme === "island" ? 4 : 0)) : 0) + (root.notchPosition === "top" ? frameOffset : 0)
                anchors.bottomMargin: (root.notchPosition === "bottom" ? (Config.notchTheme === "default" ? 0 : (Config.notchTheme === "island" ? 4 : 0)) : 0) + (root.notchPosition === "bottom" ? frameOffset : 0)

                // layer.enabled: true
                // layer.effect: Shadow {}

                defaultViewComponent: defaultViewComponent
                launcherViewComponent: null
                dashboardViewComponent: null
                powermenuViewComponent: null
                toolsMenuViewComponent: null
                notificationViewComponent: notificationViewComponent
                visibilities: root.screenVisibilities

                // Handle global keyboard events
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape && root.screenNotchOpen) {
                        Visibilities.setActiveModule("");
                        event.accepted = true;
                    }
                }
            }
        }

        // Popup de notificaciones debajo del notch
        StyledRect {
            id: notificationPopupContainer
            variant: "bg"
            anchors.top: root.notchPosition === "top" ? notchAnimationContainer.bottom : undefined
            anchors.bottom: root.notchPosition === "bottom" ? notchAnimationContainer.top : undefined
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: root.notchPosition === "top" ? 4 : 0
            anchors.bottomMargin: root.notchPosition === "bottom" ? 4 : 0
            
            width: Math.round(popupHovered ? 420 + 48 : 320 + 48)
            height: shouldShowNotificationPopup ? (popupHovered ? notificationPopup.implicitHeight + 32 : notificationPopup.implicitHeight + 32) : 0
            clip: false
            visible: height > 0
            z: 999
            radius: Styling.radius(20)

            // ── Island mode: scale+fade from island ──
            // Normal mode: slide from off-screen
            // All elements share same duration for sync.
            opacity: root.reveal ? 1 : 0
            scale: root.islandMergedWithBar ? (root.reveal ? 1 : 0.85) : 1
            transformOrigin: root.islandMergedWithBar
                ? (root.notchPosition === "top" ? Item.Top : Item.Bottom)
                : Item.Center

            Behavior on opacity {
                enabled: Anim.animationsEnabled
                NumberAnimation {
                    duration: Anim.emphasizedNormal
                    easing.type: Anim.easing("decelerate").type
                    easing.bezierCurve: Anim.easing("decelerate").bezierCurve
                }
            }
            Behavior on scale {
                enabled: Anim.animationsEnabled && root.islandMergedWithBar
                NumberAnimation {
                    duration: Anim.emphasizedNormal
                    easing.type: Anim.easing("emphasized").type
                    easing.bezierCurve: Anim.easing("emphasized").bezierCurve
                }
            }

            transform: Translate {
                y: {
                    if (root.islandMergedWithBar) return 0;
                    if (root.reveal) return 0;
                    if (root.notchPosition === "top")
                        return -(notchContainer.height + 16);
                    else
                        return (notchContainer.height + 16);
                }
                Behavior on y {
                    enabled: Anim.animationsEnabled && !root.islandMergedWithBar
                    NumberAnimation {
                        duration: Anim.spatialFast
                        easing.type: Anim.easing("spatial").type
                        easing.bezierCurve: Anim.easing("spatial").bezierCurve
                    }
                }
            }

            layer.enabled: true
            layer.effect: Shadow {}

            property bool popupHovered: false

            readonly property bool shouldShowNotificationPopup: {
                // Mostrar solo si hay notificaciones y el notch esta expandido
                if (!root.hasActiveNotifications || !root.screenNotchOpen)
                    return false;

                // NO mostrar si estamos en el launcher (widgets tab con currentTab === 0)
                if (screenVisibilities.dashboard) {
                    // Solo ocultar si estamos en el widgets tab (dashboard tab 0) Y mostrando el launcher (widgetsTab index 0)
                    return !(GlobalStates.dashboardCurrentTab === 0 && GlobalStates.widgetsTabCurrentIndex === 0);
                }

                return true;
            }

            Behavior on width {
                enabled: Anim.animationsEnabled
                NumberAnimation {
                    duration: Anim.emphasizedNormal
                    easing.type: Anim.easing("emphasized").type
                    easing.bezierCurve: Anim.easing("emphasized").bezierCurve
                }
            }

            Behavior on height {
                enabled: Anim.animationsEnabled
                NumberAnimation {
                    duration: Anim.standardNormal
                    easing.type: Anim.easing("standard").type
                    easing.bezierCurve: Anim.easing("standard").bezierCurve
                }
            }

            HoverHandler {
                id: popupHoverHandler
                enabled: notificationPopupContainer.shouldShowNotificationPopup

                onHoveredChanged: {
                    notificationPopupContainer.popupHovered = hovered;
                }
            }

            NotchNotificationView {
                id: notificationPopup
                anchors.fill: parent
                anchors.margins: 16
                visible: notificationPopupContainer.shouldShowNotificationPopup
                opacity: visible ? 1 : 0
                notchHovered: notificationPopupContainer.popupHovered

                Behavior on opacity {
                    enabled: Anim.animationsEnabled
                    NumberAnimation {
                        duration: Anim.standardNormal
                        easing.type: Anim.easing("standard").type
                        easing.bezierCurve: Anim.easing("standard").bezierCurve
                    }
                }
            }
        }
    }

    // Listen for dashboard and powermenu state changes
    Connections {
        target: screenVisibilities

        function onLauncherChanged() {
            if (screenVisibilities.launcher) {
                persistentLauncherViewLoader.active = true;
                Qt.callLater(() => {
                    if (persistentLauncherViewLoader.item) {
                        notchContainer.stackView.push(persistentLauncherViewLoader.item);
                        Qt.callLater(() => {
                            if (notchContainer.stackView.currentItem) {
                                notchContainer.stackView.currentItem.forceActiveFocus();
                            }
                        });
                    }
                });
            } else {
                if (notchContainer.stackView.depth > 1) {
                    notchContainer.stackView.pop();
                    notchContainer.isShowingDefault = true;
                    notchContainer.isShowingNotifications = false;
                }
            }
        }

        function onDashboardChanged() {
            if (screenVisibilities.dashboard) {
                persistentDashboardViewLoader.active = true;
                Qt.callLater(() => {
                    if (persistentDashboardViewLoader.item) {
                        notchContainer.stackView.push(persistentDashboardViewLoader.item);
                        Qt.callLater(() => {
                            if (notchContainer.stackView.currentItem) {
                                notchContainer.stackView.currentItem.forceActiveFocus();
                            }
                        });
                    }
                });
            } else {
                if (notchContainer.stackView.depth > 1) {
                    notchContainer.stackView.pop();
                    notchContainer.isShowingDefault = true;
                    notchContainer.isShowingNotifications = false;
                }
            }
        }

        function onPowermenuChanged() {
            if (screenVisibilities.powermenu) {
                persistentPowerMenuViewLoader.active = true;
                Qt.callLater(() => {
                    if (persistentPowerMenuViewLoader.item) {
                        notchContainer.stackView.push(persistentPowerMenuViewLoader.item);
                        Qt.callLater(() => {
                            if (notchContainer.stackView.currentItem) {
                                notchContainer.stackView.currentItem.forceActiveFocus();
                            }
                        });
                    }
                });
            } else {
                if (notchContainer.stackView.depth > 1) {
                    notchContainer.stackView.pop();
                    notchContainer.isShowingDefault = true;
                    notchContainer.isShowingNotifications = false;
                }
            }
        }

        function onToolsChanged() {
            if (screenVisibilities.tools) {
                persistentToolsMenuViewLoader.active = true;
                Qt.callLater(() => {
                    if (persistentToolsMenuViewLoader.item) {
                        notchContainer.stackView.push(persistentToolsMenuViewLoader.item);
                        Qt.callLater(() => {
                            if (notchContainer.stackView.currentItem) {
                                notchContainer.stackView.currentItem.forceActiveFocus();
                            }
                        });
                    }
                });
            } else {
                if (notchContainer.stackView.depth > 1) {
                    notchContainer.stackView.pop();
                    notchContainer.isShowingDefault = true;
                    notchContainer.isShowingNotifications = false;
                }
            }
        }
    }

    // Export some internal items for Visibilities
    property alias notchContainerRef: notchContainer
}
