#!/usr/bin/env python3
"""Sync NothingLess compositor config to hyprland.conf"""
import json, re, os, sys

config_dir = os.path.expanduser('~/.config/nothingless/config')
conf_path = os.path.expanduser('~/.local/share/nothingless/hyprland.conf')
config_path = os.path.join(config_dir, 'compositor.json')

with open(config_path) as f:
    config = json.load(f)

# Keyword map
kw_map = {
    'borderSize': 'general:border_size', 'gapsIn': 'general:gaps_in',
    'gapsOut': 'general:gaps_out', 'rounding': 'decoration:rounding',
    'shadowEnabled': 'decoration:shadow:enabled', 'shadowRange': 'decoration:shadow:range',
    'shadowRenderPower': 'decoration:shadow:render_power',
    'shadowSharp': 'decoration:shadow:sharp',
    'shadowIgnoreWindow': 'decoration:shadow:ignore_window',
    'shadowColor': 'decoration:shadow:color',
    'shadowColorInactive': 'decoration:shadow:color_inactive',
    'shadowOpacity': 'decoration:shadow:opacity',
    'shadowOffset': 'decoration:shadow:offset', 'shadowScale': 'decoration:shadow:scale',
    'blurEnabled': 'decoration:blur:enabled', 'blurSize': 'decoration:blur:size',
    'blurPasses': 'decoration:blur:passes',
    'blurIgnoreOpacity': 'decoration:blur:ignore_opacity',
    'blurNewOptimizations': 'decoration:blur:new_optimizations',
    'blurXray': 'decoration:blur:xray', 'blurNoise': 'decoration:blur:noise',
    'blurContrast': 'decoration:blur:contrast',
    'blurBrightness': 'decoration:blur:brightness',
    'blurVibrancy': 'decoration:blur:vibrancy',
    'blurVibrancyDarkness': 'decoration:blur:vibrancy_darkness',
    'blurSpecial': 'decoration:blur:special',
    'blurPopups': 'decoration:blur:popups',
    'blurInputMethods': 'decoration:blur:input_methods',
    'activeOpacity': 'decoration:active_opacity',
    'inactiveOpacity': 'decoration:inactive_opacity',
    'fullscreenOpacity': 'decoration:fullscreen_opacity',
    'dimInactive': 'decoration:dim_inactive',
    'dimStrength': 'decoration:dim_strength', 'dimAround': 'decoration:dim_around',
    'dimSpecial': 'decoration:dim_special',
    'roundingPower': 'decoration:rounding_power',
    'allowTearing': 'general:allow_tearing',
    'resizeOnBorder': 'general:resize_on_border',
    'extendBorderGrabArea': 'general:extend_border_grab_area',
    'hoverIconOnBorder': 'general:hover_icon_on_border',
    'snapEnabled': 'general:snap:enabled',
    'snapWindowGap': 'general:snap:window_gap',
    'snapMonitorGap': 'general:snap:monitor_gap',
    'snapBorderOverlap': 'general:snap:border_overlap',
    'snapRespectGaps': 'general:snap:respect_gaps',
    'animationsEnabled': 'animations:enabled',
    'kbLayout': 'input:kb_layout', 'kbVariant': 'input:kb_variant',
    'kbOptions': 'input:kb_options', 'numlockByDefault': 'input:numlock_by_default',
    'repeatRate': 'input:repeat_rate', 'repeatDelay': 'input:repeat_delay',
    'mouseSensitivity': 'input:sensitivity',
    'mouseAccelProfile': 'input:accel_profile',
    'followMouse': 'input:follow_mouse',
    'mouseNaturalScroll': 'input:natural_scroll',
    'mouseScrollFactor': 'input:scroll_factor',
    'mouseLeftHanded': 'input:left_handed',
    'mouseRefocus': 'input:mouse_refocus',
    'floatSwitchOverrideFocus': 'input:float_switch_override_focus',
    'touchpadDisableWhileTyping': 'input:touchpad:disable_while_typing',
    'touchpadNaturalScroll': 'input:touchpad:natural_scroll',
    'touchpadTapToClick': 'input:touchpad:tap_to_click',
    'touchpadClickfingerBehavior': 'input:touchpad:clickfinger_behavior',
    'touchpadTapButtonMap': 'input:touchpad:tap_button_map',
    'touchpadMiddleButtonEmulation': 'input:touchpad:middle_button_emulation',
    'touchpadDragLock': 'input:touchpad:drag_lock',
    'touchpadScrollFactor': 'input:touchpad:scroll_factor',
    'noHardwareCursors': 'cursor:no_hardware_cursors',
    'enableHyprcursor': 'cursor:enable_hyprcursor',
    'noWarps': 'cursor:no_warps', 'persistentWarps': 'cursor:persistent_warps',
    'warpOnChangeWorkspace': 'cursor:warp_on_change_workspace',
    'cursorZoomFactor': 'cursor:zoom_factor',
    'cursorInactiveTimeout': 'cursor:inactive_timeout',
    'cursorHideOnKeyPress': 'cursor:hide_on_key_press',
    'cursorHideOnTouch': 'cursor:hide_on_touch',
    'cursorHideOnTablet': 'cursor:hide_on_tablet',
    'workspaceSwipeCreateNew': 'gestures:workspace_swipe_create_new',
    'workspaceSwipeForever': 'gestures:workspace_swipe_forever',
    'workspaceSwipeCancelRatio': 'gestures:workspace_swipe_cancel_ratio',
    'workspaceSwipeMinSpeedToForce': 'gestures:workspace_swipe_min_speed_to_force',
    'workspaceSwipeDirectionLock': 'gestures:workspace_swipe_direction_lock',
    'workspaceSwipeUseR': 'gestures:workspace_swipe_use_r',
    'workspaceSwipeDistance': 'gestures:workspace_swipe_distance',
    'workspaceSwipeInvert': 'gestures:workspace_swipe_invert',
    'workspaceSwipeTouch': 'gestures:workspace_swipe_touch',
    'workspaceSwipeTouchInvert': 'gestures:workspace_swipe_touch_invert',
    'dwindlePreserveSplit': 'dwindle:preserve_split',
    'dwindlePseudotile': 'dwindle:pseudotile',
    'dwindleForceSplit': 'dwindle:force_split',
    'dwindleSmartSplit': 'dwindle:smart_split',
    'dwindleDefaultSplitRatio': 'dwindle:default_split_ratio',
    'dwindleSplitWidthMultiplier': 'dwindle:split_width_multiplier',
    'dwindlePermanentDirectionOverride': 'dwindle:permanent_direction_override',
    'dwindleUseActiveForSplits': 'dwindle:use_active_for_splits',
    'dwindleSmartResizing': 'dwindle:smart_resizing',
    'dwindleSpecialScaleFactor': 'dwindle:special_scale_factor',
    'masterOrientation': 'master:orientation', 'masterMfact': 'master:mfact',
    'masterNewStatus': 'master:new_status', 'masterNewOnTop': 'master:new_on_top',
    'masterNewOnActive': 'master:new_on_active',
    'masterSmartResizing': 'master:smart_resizing',
    'masterSpecialScaleFactor': 'master:special_scale_factor',
    'masterAllowSmallSplit': 'master:allow_small_split',
    'scrollingColumnWidth': 'scrolling:column_width',
    'scrollingExplicitColumnWidths': 'scrolling:explicit_column_widths',
    'scrollingDirection': 'scrolling:direction',
    'scrollingFullscreenOnOneColumn': 'scrolling:fullscreen_on_one_column',
    'scrollingFocusFitMethod': 'scrolling:focus_fit_method',
    'scrollingFollowFocus': 'scrolling:follow_focus',
    'scrollingFollowMinVisible': 'scrolling:follow_min_visible',
    'xwaylandEnabled': 'xwayland:enabled',
    'xwaylandForceZeroScaling': 'xwayland:force_zero_scaling',
    'xwaylandUseNearestNeighbor': 'xwayland:use_nearest_neighbor',
    'vrr': 'misc:vrr', 'vfr': 'misc:vfr',
    'mouseMoveEnablesDpms': 'misc:mouse_move_enables_dpms',
    'keyPressEnablesDpms': 'misc:key_press_enables_dpms',
    'disableAutoreload': 'misc:disable_autoreload',
    'focusOnActivate': 'misc:focus_on_activate',
    'animateManualResizes': 'misc:animate_manual_resizes',
    'animateMouseWindowdragging': 'misc:animate_mouse_windowdragging',
    'disableHyprlandLogo': 'misc:disable_hyprland_logo',
    'disableSplashRendering': 'misc:disable_splash_rendering',
    'forceDefaultWallpaper': 'misc:force_default_wallpaper',
    'noUpdateNews': 'misc:no_update_news',
}

def fmt(val):
    if isinstance(val, bool):
        return 'true' if val else 'false'
    if isinstance(val, list):
        return ' '.join(str(v) for v in val)
    return str(val)

lines = []
for key, keyword in kw_map.items():
    if key in config:
        lines.append(f'{keyword} = {fmt(config[key])}')

marker = '# === NOTHINGLESS COMPOSITOR ==='
end_marker = '# === END COMPOSITOR ==='
block = marker + '\n# Applied by NothingLess\n'
block += '\n'.join(lines) + '\n' + end_marker + '\n'

try:
    with open(conf_path) as f:
        content = f.read()
except:
    content = ''

content = re.sub(re.escape(marker) + '.*?' + re.escape(end_marker), '', content, flags=re.DOTALL).strip()
content += '\n' + block

with open(conf_path, 'w') as f:
    f.write(content)

print(f'Synced {len(lines)} settings to {conf_path}')
