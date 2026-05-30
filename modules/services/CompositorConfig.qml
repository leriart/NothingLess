import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.services
import qs.config
import qs.modules.theme
import qs.modules.bar
import qs.modules.globals

QtObject {
    id: root

    property Process evalProcess: Process {
        id: evalProcess
        running: false
        stdout: SplitParser {}
    }
    property string _lastBatchCmd: ""
    property bool _savingCompositor: false

    property var currentAnimationConfig: null
    property Process readAnimationsProcess: Process {
        command: ["axctl", "config", "get-animations"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (!text || text.trim().length === 0) { return; }
                    const parsed = JSON.parse(text);
                    if (Array.isArray(parsed) && parsed.length > 0) {
                        currentAnimationConfig = parsed;
                    }
                } catch (e) {
                    // Silently ignore - axctl returns non-JSON when no custom animations
                }
            }
        }
    }

    property var barInstances: []

    function registerBar(barInstance) {
        barInstances.push(barInstance);
    }

    function getBarOrientation() {
        if (barInstances.length > 0) {
            return barInstances[0].orientation || "horizontal";
        }
        const position = Config.bar.position || "top";
        return (position === "left" || position === "right") ? "vertical" : "horizontal";
    }

    property Timer applyTimer: Timer {
        interval: 100
        repeat: false
        onTriggered: applyCompositorConfigInternal()
    }

    function getColorValue(colorName) {
        const resolved = Config.resolveColor(colorName);
        // Convert HEX string to color, or return if already a color.
        return (typeof resolved === 'string') ? Qt.color(resolved) : resolved;
    }

    function formatColorForCompositor(color) {
        // AxctlService expects colors in format: rgb(rrggbb) or rgba(rrggbbaa)
        const r = Math.round(color.r * 255).toString(16).padStart(2, '0');
        const g = Math.round(color.g * 255).toString(16).padStart(2, '0');
        const b = Math.round(color.b * 255).toString(16).padStart(2, '0');
        const a = Math.round(color.a * 255).toString(16).padStart(2, '0');

        if (color.a === 1.0) {
            return `rgb(${r}${g}${b})`;
        } else {
            return `rgba(${r}${g}${b}${a})`;
        }
    }

    function applyCompositorConfig() {
        if (_savingCompositor) return;
        readAnimationsProcess.running = true;
        applyTimer.restart();
    }

    function applyCompositorConfigInternal(writeFile = true) {
        if (!Config.loader.loaded) {
            console.log("CompositorConfig: Esperando que se cargue Config...");
            return;
        }
        if (!GlobalStates.compositorLayoutReady) {
            console.log("CompositorConfig: Esperando que se detecte el layout de AxctlService...");
            return;
        }

        // ── Resolve QML-specific theme colors ──
        const borderColors = Config.compositor.syncBorderColor ? null : Config.compositor.activeBorderColor;

        let activeColorHex = "";
        if (borderColors && borderColors.length > 1) {
            // Gradient: multiple colors, handled by sync-hyprland.py via config file
            activeColorHex = "0xff" + formatColorForCompositor(getColorValue(borderColors[0])).replace("rgb(", "").replace(")", "");
        } else {
            const name = (borderColors && borderColors.length === 1) ? borderColors[0] : Config.compositorBorderColor;
            const c = getColorValue(name);
            activeColorHex = "0x" + (Math.round(c.a * 255).toString(16).padStart(2, '0')) +
                Math.round(c.r * 255).toString(16).padStart(2, '0') +
                Math.round(c.g * 255).toString(16).padStart(2, '0') +
                Math.round(c.b * 255).toString(16).padStart(2, '0');
        }

        let inactiveColorHex = "";
        const inactiveBorderColors = Config.compositor.inactiveBorderColor;
        if (inactiveBorderColors && inactiveBorderColors.length > 1) {
            inactiveColorHex = "0xff" + formatColorForCompositor(getColorValue(inactiveBorderColors[0])).replace("rgb(", "").replace(")", "");
        } else {
            const name = (inactiveBorderColors && inactiveBorderColors.length === 1) ? inactiveBorderColors[0] : "surface";
            const c = getColorValue(name);
            inactiveColorHex = "0x" + (Math.round(c.a * 255).toString(16).padStart(2, '0')) +
                Math.round(c.r * 255).toString(16).padStart(2, '0') +
                Math.round(c.g * 255).toString(16).padStart(2, '0') +
                Math.round(c.b * 255).toString(16).padStart(2, '0');
        }

        // Dynamic ignorealpha (calced from bar/bg opacity)
        let ignoreAlphaValue = 0.0;
        if (Config.compositor.blurExplicitIgnoreAlpha) {
            ignoreAlphaValue = Config.compositor.blurIgnoreAlphaValue.toFixed(2);
        } else {
            const barBgOpacity = (Config.theme.srBarBg && Config.theme.srBarBg.opacity !== undefined) ? Config.theme.srBarBg.opacity : 0;
            const bgOpacity = (Config.theme.srBg && Config.theme.srBg.opacity !== undefined) ? Config.theme.srBg.opacity : 1.0;
            ignoreAlphaValue = (barBgOpacity > 0 ? Math.min(barBgOpacity, bgOpacity) : bgOpacity).toFixed(2);
        }

        // Animations
        const barOrientation = getBarOrientation();
        let speed = 2.5, bezier = "default";
        if (currentAnimationConfig && currentAnimationConfig[0]) {
            const wa = currentAnimationConfig[0].find(a => a.name === "workspaces");
            if (wa) { speed = wa.speed || speed; bezier = wa.bezier || bezier; }
        }
        const wsAnim = barOrientation === "vertical" ? "slidefadevert 20%" : "slidefade 20%";

        // ── Build Lua hl.config() call with resolved theme colors ──
        // (Animations are handled by sync-hyprland.py via config file)
        let luaConfig = `hl.config({ general = { col = { active_border = ${activeColorHex}, inactive_border = ${inactiveColorHex} } } })`;

        console.log("CompositorConfig: Lua eval:", luaConfig);

        // ── Apply via hyprctl eval (hyprctl keyword / axctl raw-batch is broken in Hyprland 0.55+) ──
        evalProcess.command = ["hyprctl", "eval", luaConfig];
        evalProcess.running = true;

        // ── Save and apply ALL settings via TOML (only on user-initiated changes) ──
        if (writeFile) {
            _savingCompositor = true;
            Config.saveCompositor();
            Qt.callLater(() => { _savingCompositor = false; });
            applyConfigTimer.restart();
        }

        // ── Handle Free Layout ──
        if (GlobalStates.compositorLayout === "free") {
            floatAllProcess.running = true;
        } else if (GlobalStates.compositorLayout) {
            tileAllProcess.running = true;
        }
    }

    // Apply all non-color settings via TOML dictionary (data-driven)
    // Uses a timer delay to ensure compositor.json is flushed to disk first
    property Timer applyConfigTimer: Timer {
        interval: 200
        repeat: false
        onTriggered: {
            const scriptPath = Qt.resolvedUrl("../../scripts/apply-config.sh").toString().replace("file://", "");
            console.log("CompositorConfig: Running apply-config.sh:", scriptPath);
            applyConfigProcess.command = ["bash", scriptPath];
            applyConfigProcess.running = true;
        }
    }

    property Process applyConfigProcess: Process {
        id: applyConfigProcess
        running: false
        stdout: SplitParser {}
    }

    property Connections configConnections: Connections {
        target: Config.loader
        function onFileChanged() {
            applyCompositorConfig();
        }
        function onLoaded() {
            applyCompositorConfig();
        }
    }

    property Connections compositorConfigConnections: Connections {
        target: Config.compositor

        function onBorderSizeChanged() {
            applyCompositorConfig();
        }
        function onRoundingChanged() {
            applyCompositorConfig();
        }
        function onGapsInChanged() {
            applyCompositorConfig();
        }
        function onGapsOutChanged() {
            applyCompositorConfig();
        }
        function onActiveBorderColorChanged() {
            applyCompositorConfig();
        }
        function onInactiveBorderColorChanged() {
            applyCompositorConfig();
        }
        function onBorderAngleChanged() {
            applyCompositorConfig();
        }
        function onInactiveBorderAngleChanged() {
            applyCompositorConfig();
        }
        function onSyncRoundnessChanged() {
            applyCompositorConfig();
        }
        function onSyncBorderWidthChanged() {
            applyCompositorConfig();
        }
        function onSyncBorderColorChanged() {
            applyCompositorConfig();
        }
        function onSyncShadowOpacityChanged() {
            applyCompositorConfig();
        }
        function onSyncShadowColorChanged() {
            applyCompositorConfig();
        }
        function onShadowEnabledChanged() {
            applyCompositorConfig();
        }
        function onShadowRangeChanged() {
            applyCompositorConfig();
        }
        function onShadowRenderPowerChanged() {
            applyCompositorConfig();
        }
        function onShadowSharpChanged() {
            applyCompositorConfig();
        }
        function onShadowIgnoreWindowChanged() {
            applyCompositorConfig();
        }
        function onShadowColorChanged() {
            applyCompositorConfig();
        }
        function onShadowColorInactiveChanged() {
            applyCompositorConfig();
        }
        function onShadowOpacityChanged() {
            applyCompositorConfig();
        }
        function onShadowOffsetChanged() {
            applyCompositorConfig();
        }
        function onShadowScaleChanged() {
            applyCompositorConfig();
        }
        function onBlurEnabledChanged() {
            applyCompositorConfig();
        }
        function onBlurSizeChanged() {
            applyCompositorConfig();
        }
        function onBlurPassesChanged() {
            applyCompositorConfig();
        }
        function onBlurIgnoreOpacityChanged() {
            applyCompositorConfig();
        }
        function onBlurExplicitIgnoreAlphaChanged() {
            applyCompositorConfig();
        }
        function onBlurIgnoreAlphaValueChanged() {
            applyCompositorConfig();
        }
        function onBlurNewOptimizationsChanged() {
            applyCompositorConfig();
        }
        function onBlurXrayChanged() {
            applyCompositorConfig();
        }
        function onBlurNoiseChanged() {
            applyCompositorConfig();
        }
        function onBlurContrastChanged() {
            applyCompositorConfig();
        }
        function onBlurBrightnessChanged() {
            applyCompositorConfig();
        }
        function onBlurVibrancyChanged() {
            applyCompositorConfig();
        }
        function onBlurVibrancyDarknessChanged() {
            applyCompositorConfig();
        }
        function onBlurSpecialChanged() {
            applyCompositorConfig();
        }
        function onBlurPopupsChanged() {
            applyCompositorConfig();
        }
        function onBlurPopupsIgnorealphaChanged() {
            applyCompositorConfig();
        }
        function onBlurInputMethodsChanged() {
            applyCompositorConfig();
        }
        function onBlurInputMethodsIgnorealphaChanged() {
            applyCompositorConfig();
        }

        // Opacity & Dim
        function onActiveOpacityChanged() { applyCompositorConfig(); }
        function onInactiveOpacityChanged() { applyCompositorConfig(); }
        function onFullscreenOpacityChanged() { applyCompositorConfig(); }
        function onDimInactiveChanged() { applyCompositorConfig(); }
        function onDimStrengthChanged() { applyCompositorConfig(); }
        function onDimAroundChanged() { applyCompositorConfig(); }
        function onDimSpecialChanged() { applyCompositorConfig(); }
        function onRoundingPowerChanged() { applyCompositorConfig(); }

        // General extras
        function onAllowTearingChanged() { applyCompositorConfig(); }
        function onResizeOnBorderChanged() { applyCompositorConfig(); }
        function onExtendBorderGrabAreaChanged() { applyCompositorConfig(); }
        function onHoverIconOnBorderChanged() { applyCompositorConfig(); }

        // Snap
        function onSnapEnabledChanged() { applyCompositorConfig(); }
        function onSnapWindowGapChanged() { applyCompositorConfig(); }
        function onSnapMonitorGapChanged() { applyCompositorConfig(); }
        function onSnapBorderOverlapChanged() { applyCompositorConfig(); }
        function onSnapRespectGapsChanged() { applyCompositorConfig(); }

        // Animations
        function onAnimationsEnabledChanged() { applyCompositorConfig(); }

        // Input: Keyboard
        function onKbLayoutChanged() { applyCompositorConfig(); }
        function onKbVariantChanged() { applyCompositorConfig(); }
        function onKbOptionsChanged() { applyCompositorConfig(); }
        function onNumlockByDefaultChanged() { applyCompositorConfig(); }
        function onRepeatRateChanged() { applyCompositorConfig(); }
        function onRepeatDelayChanged() { applyCompositorConfig(); }

        // Input: Mouse
        function onMouseSensitivityChanged() { applyCompositorConfig(); }
        function onMouseAccelProfileChanged() { applyCompositorConfig(); }
        function onFollowMouseChanged() { applyCompositorConfig(); }
        function onMouseNaturalScrollChanged() { applyCompositorConfig(); }
        function onMouseScrollFactorChanged() { applyCompositorConfig(); }
        function onMouseLeftHandedChanged() { applyCompositorConfig(); }
        function onMouseRefocusChanged() { applyCompositorConfig(); }
        function onFloatSwitchOverrideFocusChanged() { applyCompositorConfig(); }

        // Input: Touchpad
        function onTouchpadDisableWhileTypingChanged() { applyCompositorConfig(); }
        function onTouchpadNaturalScrollChanged() { applyCompositorConfig(); }
        function onTouchpadTapToClickChanged() { applyCompositorConfig(); }
        function onTouchpadClickfingerBehaviorChanged() { applyCompositorConfig(); }
        function onTouchpadTapButtonMapChanged() { applyCompositorConfig(); }
        function onTouchpadMiddleButtonEmulationChanged() { applyCompositorConfig(); }
        function onTouchpadDragLockChanged() { applyCompositorConfig(); }
        function onTouchpadScrollFactorChanged() { applyCompositorConfig(); }

        // Cursor
        function onNoHardwareCursorsChanged() { applyCompositorConfig(); }
        function onEnableHyprcursorChanged() { applyCompositorConfig(); }
        function onNoWarpsChanged() { applyCompositorConfig(); }
        function onPersistentWarpsChanged() { applyCompositorConfig(); }
        function onWarpOnChangeWorkspaceChanged() { applyCompositorConfig(); }
        function onCursorZoomFactorChanged() { applyCompositorConfig(); }
        function onCursorInactiveTimeoutChanged() { applyCompositorConfig(); }
        function onCursorHideOnKeyPressChanged() { applyCompositorConfig(); }
        function onCursorHideOnTouchChanged() { applyCompositorConfig(); }
        function onCursorHideOnTabletChanged() { applyCompositorConfig(); }

        // Gestures
        function onWorkspaceSwipeCreateNewChanged() { applyCompositorConfig(); }
        function onWorkspaceSwipeForeverChanged() { applyCompositorConfig(); }
        function onWorkspaceSwipeCancelRatioChanged() { applyCompositorConfig(); }
        function onWorkspaceSwipeMinSpeedToForceChanged() { applyCompositorConfig(); }
        function onWorkspaceSwipeDirectionLockChanged() { applyCompositorConfig(); }
        function onWorkspaceSwipeUseRChanged() { applyCompositorConfig(); }
        function onWorkspaceSwipeDistanceChanged() { applyCompositorConfig(); }
        function onWorkspaceSwipeInvertChanged() { applyCompositorConfig(); }
        function onWorkspaceSwipeTouchChanged() { applyCompositorConfig(); }
        function onWorkspaceSwipeTouchInvertChanged() { applyCompositorConfig(); }

        // Gesture Bindings
        function onGesture3FingerSwipeChanged() { applyCompositorConfig(); }
        function onGesture3FingerPinchChanged() { applyCompositorConfig(); }
        function onGesture4FingerWorkspaceChanged() { applyCompositorConfig(); }
        function onGesture4FingerOverviewChanged() { applyCompositorConfig(); }
        function onGesture4FingerCloseChanged() { applyCompositorConfig(); }
        function onGesture3FingerScratchpadChanged() { applyCompositorConfig(); }
        function onWorkspaceSwipeDirectionLockThresholdChanged() { applyCompositorConfig(); }
        function onGestureCloseTimeoutChanged() { applyCompositorConfig(); }

        // Dwindle
        function onDwindlePreserveSplitChanged() { applyCompositorConfig(); }
        function onDwindlePseudotileChanged() { applyCompositorConfig(); }
        function onDwindleForceSplitChanged() { applyCompositorConfig(); }
        function onDwindleSmartSplitChanged() { applyCompositorConfig(); }
        function onDwindleDefaultSplitRatioChanged() { applyCompositorConfig(); }
        function onDwindleSplitWidthMultiplierChanged() { applyCompositorConfig(); }
        function onDwindlePermanentDirectionOverrideChanged() { applyCompositorConfig(); }
        function onDwindleUseActiveForSplitsChanged() { applyCompositorConfig(); }
        function onDwindleSmartResizingChanged() { applyCompositorConfig(); }
        function onDwindleSpecialScaleFactorChanged() { applyCompositorConfig(); }

        // Master
        function onMasterOrientationChanged() { applyCompositorConfig(); }
        function onMasterMfactChanged() { applyCompositorConfig(); }
        function onMasterNewStatusChanged() { applyCompositorConfig(); }
        function onMasterNewOnTopChanged() { applyCompositorConfig(); }
        function onMasterNewOnActiveChanged() { applyCompositorConfig(); }
        function onMasterSmartResizingChanged() { applyCompositorConfig(); }
        function onMasterSpecialScaleFactorChanged() { applyCompositorConfig(); }
        function onMasterAllowSmallSplitChanged() { applyCompositorConfig(); }

        // Scrolling
        function onScrollingColumnWidthChanged() { applyCompositorConfig(); }
        function onScrollingExplicitColumnWidthsChanged() { applyCompositorConfig(); }
        function onScrollingDirectionChanged() { applyCompositorConfig(); }
        function onScrollingFullscreenOnOneColumnChanged() { applyCompositorConfig(); }
        function onScrollingFocusFitMethodChanged() { applyCompositorConfig(); }
        function onScrollingFollowFocusChanged() { applyCompositorConfig(); }
        function onScrollingFollowMinVisibleChanged() { applyCompositorConfig(); }

        // XWayland
        function onXwaylandEnabledChanged() { applyCompositorConfig(); }
        function onXwaylandForceZeroScalingChanged() { applyCompositorConfig(); }
        function onXwaylandUseNearestNeighborChanged() { applyCompositorConfig(); }

        // Misc
        function onVrrChanged() { applyCompositorConfig(); }
        function onVfrChanged() { applyCompositorConfig(); }
        function onMouseMoveEnablesDpmsChanged() { applyCompositorConfig(); }
        function onKeyPressEnablesDpmsChanged() { applyCompositorConfig(); }
        function onDisableAutoreloadChanged() { applyCompositorConfig(); }
        function onFocusOnActivateChanged() { applyCompositorConfig(); }
        function onAnimateManualResizesChanged() { applyCompositorConfig(); }
        function onAnimateMouseWindowdraggingChanged() { applyCompositorConfig(); }
        function onDisableHyprlandLogoChanged() { applyCompositorConfig(); }
        function onDisableSplashRenderingChanged() { applyCompositorConfig(); }
        function onForceDefaultWallpaperChanged() { applyCompositorConfig(); }
        function onNoUpdateNewsChanged() { applyCompositorConfig(); }
    }

    property Connections colorsConnections: Connections {
        target: Colors
        function onFileChanged() {
            applyCompositorConfig();
        }
        function onLoaded() {
            applyCompositorConfig();
        }
    }

    property Connections barConnections: Connections {
        target: Config.bar
        function onPositionChanged() {
            applyCompositorConfig();
        }
    }

    property Connections srBgConnections: Connections {
        target: Config.theme.srBg
        function onOpacityChanged() {
            applyCompositorConfig();
        }
    }

    property Connections srBarBgConnections: Connections {
        target: Config.theme.srBarBg
        function onOpacityChanged() {
            applyCompositorConfig();
        }
    }

    property Connections globalStatesConnections: Connections {
        target: GlobalStates
        function onCompositorLayoutChanged() {
            applyCompositorConfig();
        }
        function onCompositorLayoutReadyChanged() {
            if (GlobalStates.compositorLayoutReady) {
                applyCompositorConfig();
            }
        }
    }

    // Write config to hyprland.conf — reads values directly from Config.compositor
    // No dependency on batchCommand, always gets current values
        function writeConfigToFile(batchCmd) {
        // Call the Python sync script which reads compositor.json directly
        // Use Qt.resolvedUrl to find the script relative to this QML file,
        // so it works regardless of where NothingLess is installed.
        const scriptPath = Qt.resolvedUrl("../../scripts/sync-hyprland.py").toString().replace("file://", "");
        syncProcess.command = ["python3", scriptPath];
        syncProcess.running = true;
    }

    property Process syncProcess: Process {
        id: syncProcess
        running: false
        onExited: (code) => {
            if (code === 0) {
                console.log("Config written to hyprland.conf/lua via sync script");
                // Reload axctl daemon so it picks up the new config
                reloadProcess.command = ["axctl", "config", "reload"];
                reloadProcess.running = true;
            } else {
                console.error("sync-hyprland.py failed, code:", code);
            }
        }
    }

    property Process reloadProcess: Process {
        id: reloadProcess
        running: false
    }

    property Process writeConfProcess: Process {
        id: writeConfProcess
        running: false
        onExited: (code) => {
            if (code === 0) {
                console.log("Config written to hyprland.conf (auto-reload handles reload)");
            } else {
                console.error("Failed to write hyprland.conf, code:", code);
            }
        }
    }

    // Float all EXISTING windows + enable catch-all rule for NEW windows
    property Process floatAllProcess: Process {
        command: ["bash", "-c",
            // Create/enable catch-all float rule for new windows
            "hyprctl eval \"nl_free_rule = hl.window_rule({ name = 'nl-free-float', match = { class = '.*' }, float = true })\" 2>/dev/null; " +
            "hyprctl eval 'nl_free_rule:set_enabled(true)' 2>/dev/null; " +
            // Float all existing non-floating windows
            "count=0; " +
            "while IFS= read -r addr; do " +
            "  [ -n \"$addr\" ] && { " +
            "    hyprctl eval \"hl.dispatch(hl.dsp.window.float({ window = 'address:$addr' }))\" 2>/dev/null; " +
            "    count=$((count+1)); " +
            "  }; " +
            "done < <(hyprctl -j clients 2>/dev/null | jq -r '.[] | select(.floating != true) | .address'); " +
            "echo \"NL_FLOAT: $count existing + rule for new windows\""
        ]
        running: false
        stdout: StdioCollector { onStreamFinished: { if (text.length > 0) console.log(String(text.trim())); } }
        stderr: StdioCollector { onStreamFinished: { if (text.length > 0) console.warn(String(text.trim())); } }
    }

    // Tile all windows + disable catch-all rule
    property Process tileAllProcess: Process {
        command: ["bash", "-c",
            // Disable the catch-all float rule
            "hyprctl eval 'nl_free_rule:set_enabled(false)' 2>/dev/null; " +
            // Unfloat all existing floating windows
            "count=0; " +
            "while IFS= read -r addr; do " +
            "  [ -n \"$addr\" ] && { " +
            "    hyprctl eval \"hl.dispatch(hl.dsp.window.float({ window = 'address:$addr' }))\" 2>/dev/null; " +
            "    count=$((count+1)); " +
            "  }; " +
            "done < <(hyprctl -j clients 2>/dev/null | jq -r '.[] | select(.floating == true) | .address'); " +
            "echo \"NL_TILE: $count existing + disabled float rule\""
        ]
        running: false
        stdout: StdioCollector { onStreamFinished: { if (text.length > 0) console.log(String(text.trim())); } }
        stderr: StdioCollector { onStreamFinished: { if (text.length > 0) console.warn(String(text.trim())); } }
    }

    // Force re-apply when Config.compositor adapter becomes available
    // Also reassign the connections target (QML Connections may not rebind target)
    property QtObject compWatch: Config.compositor
    onCompWatchChanged: {
        if (root.compWatch) {
            root.applyCompositorConfig();
        }
        // Re-assign Connections target in case it was null during init
        Qt.callLater(() => {
            if (root.compWatch && !root.compositorConfigConnections.target) {
                root.compositorConfigConnections.target = root.compWatch;
            }
        });
    }

    // Removed globalStateConnections - it was redundant.
    // Every Config.compositor property already has its own handler
    // (above in compositorConfigConnections) that calls applyCompositorConfig().
    // That covers: dispatch + writeConfig + reload.
    // This ADDITIONAL connection caused double dispatch, double file write,
    // and double axctl reload on every property change.

    // Re-apply settings when Hyprland config is reloaded (user edits hyprland.conf)
    property Connections axctlConnections: Connections {
        target: AxctlService
        function onRawEvent(event) {
            if (event && event.name === "configreloaded") {
                console.log("CompositorConfig: Hyprland config reloaded, reapplying settings...");
                applyCompositorConfigInternal(false);  // Don't write file (already correct)
            }
        }

        function onConfigReloaded() {
            console.log("CompositorConfig: Config reloaded signal, reapplying settings...");
            applyCompositorConfigInternal(false);
        }

        function onSubscribeReady() {
            console.log("CompositorConfig: Subscribe reconnected, reapplying settings...");
            applyCompositorConfig();
        }
    }

    Component.onCompleted: {
        // Apply immediately if Config is already loaded.
        if (Config.loader.loaded) {
            applyCompositorConfig();
        }
        // Otherwise, handled by onLoaded.
    }
}
