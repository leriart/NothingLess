#!/usr/bin/env python3
"""Sync NothingLess compositor config to hyprland.conf and hyprland.lua"""
import json, re, os

BASE = os.path.expanduser('~/.config/nothingless/config')
CONF_PATH = os.path.expanduser('~/.local/share/nothingless/hyprland.conf')
LUA_PATH = os.path.expanduser('~/.local/share/nothingless/hyprland.lua')
COMPOSITOR_PATH = os.path.join(BASE, 'compositor.json')

with open(COMPOSITOR_PATH) as f:
    cfg = json.load(f)

def fmt(val):
    if isinstance(val, bool):
        return 'true' if val else 'false'
    if isinstance(val, list):
        return ' '.join(str(v) for v in val)
    if isinstance(val, float):
        s = f'{val:.2f}'.rstrip('0').rstrip('.')
        return s if '.' in s else s + '.0'
    if isinstance(val, str) and val == '':
        return '""'
    return str(val)

def fmt_lua(val):
    if isinstance(val, bool):
        return 'true' if val else 'false'
    if isinstance(val, list):
        return '{ "' + '", "'.join(str(v) for v in val) + '" }'
    if isinstance(val, float):
        s = f'{val:.2f}'.rstrip('0').rstrip('.')
        return s if '.' in s else s + '.0'
    if isinstance(val, str):
        return '"' + val + '"'
    return str(val)

# Resolve color: the batch command resolves aliases via Config.resolveColor
# Here we use a sensible default since we can't access QML's resolveColor
def resolve_color(name):
    if not name or name == 'shadow':
        return '0xee1a1a1a'
    return name

# ============================================================================
#  hyprland.conf - BLOCK syntax
# ============================================================================
def build_conf_block():
    lines = ['# === NOTHINGLESS COMPOSITOR ===', '# Applied by NothingLess', '']

    def sec(name, keys, indent=''):
        lines.append(indent + name + ' {')
        for ck, kw in keys:
            if ck in cfg:
                lines.append(indent + '  ' + kw + ' = ' + fmt(cfg[ck]))
        lines.append(indent + '}')

    sec('general', [
        ('borderSize','border_size'), ('gapsIn','gaps_in'), ('gapsOut','gaps_out'),
        ('allowTearing','allow_tearing'), ('resizeOnBorder','resize_on_border'),
        ('extendBorderGrabArea','extend_border_grab_area'),
        ('hoverIconOnBorder','hover_icon_on_border'), ('layout','layout'),
    ])
    lines.append('')

    lines.append('decoration {')
    for k, kw in [('rounding','rounding'), ('roundingPower','rounding_power'),
                  ('activeOpacity','active_opacity'), ('inactiveOpacity','inactive_opacity'),
                  ('fullscreenOpacity','fullscreen_opacity'),
                  ('dimInactive','dim_inactive'), ('dimStrength','dim_strength'),
                  ('dimAround','dim_around'), ('dimSpecial','dim_special')]:
        if k in cfg: lines.append('  ' + kw + ' = ' + fmt(cfg[k]))
    lines.append('')
    lines.append('  shadow {')
    for k, kw in [('shadowRange','range'), ('shadowRenderPower','render_power'),
                  ('shadowSharp','sharp'), ('shadowIgnoreWindow','ignore_window')]:
        if k in cfg: lines.append('    ' + kw + ' = ' + fmt(cfg[k]))
    lines.append('    color = ' + resolve_color(cfg.get('shadowColor', 'shadow')))
    lines.append('    color_inactive = ' + resolve_color(cfg.get('shadowColorInactive', 'shadow')))
    lines.append('  }')
    lines.append('')
    lines.append('  blur {')
    for k, kw in [('blurSize','size'), ('blurPasses','passes'),
                  ('blurIgnoreOpacity','ignore_opacity'),
                  ('blurNewOptimizations','new_optimizations'),
                  ('blurXray','xray'), ('blurNoise','noise'), ('blurContrast','contrast'),
                  ('blurBrightness','brightness'), ('blurVibrancy','vibrancy'),
                  ('blurVibrancyDarkness','vibrancy_darkness')]:
        if k in cfg: lines.append('    ' + kw + ' = ' + fmt(cfg[k]))
    lines.append('  }')
    lines.append('}')

    lines.append('')
    lines.append('input {')
    for k, kw in [('kbLayout','kb_layout'), ('kbVariant','kb_variant'),
                  ('kbOptions','kb_options'),
                  ('numlockByDefault','numlock_by_default'),
                  ('repeatRate','repeat_rate'), ('repeatDelay','repeat_delay'),
                  ('mouseSensitivity','sensitivity'),
                  ('followMouse','follow_mouse'),
                  ('mouseNaturalScroll','natural_scroll'),
                  ('mouseScrollFactor','scroll_factor'),
                  ('mouseLeftHanded','left_handed'),
                  ('mouseRefocus','mouse_refocus'),
                  ('floatSwitchOverrideFocus','float_switch_override_focus')]:
        if k in cfg: lines.append('  ' + kw + ' = ' + fmt(cfg[k]))
    if cfg.get('mouseAccelProfile'): lines.append('  accel_profile = ' + cfg['mouseAccelProfile'])
    lines.append('')
    lines.append('  touchpad {')
    for k, kw in [('touchpadDisableWhileTyping','disable_while_typing'),
                  ('touchpadNaturalScroll','natural_scroll'),
                  ('touchpadTapToClick','tap_to_click'),
                  ('touchpadClickfingerBehavior','clickfinger_behavior'),
                  ('touchpadMiddleButtonEmulation','middle_button_emulation'),
                  ('touchpadDragLock','drag_lock'),
                  ('touchpadScrollFactor','scroll_factor')]:
        if k in cfg: lines.append('    ' + kw + ' = ' + fmt(cfg[k]))
    if cfg.get('touchpadTapButtonMap'): lines.append('    tap_button_map = ' + cfg['touchpadTapButtonMap'])
    lines.append('  }')
    lines.append('}')

    for sec_name, keys in [
        ('cursor', [('noHardwareCursors','no_hardware_cursors'),
                    ('enableHyprcursor','enable_hyprcursor'), ('noWarps','no_warps'),
                    ('persistentWarps','persistent_warps'),
                    ('warpOnChangeWorkspace','warp_on_change_workspace'),
                    ('cursorZoomFactor','zoom_factor'),
                    ('cursorInactiveTimeout','inactive_timeout'),
                    ('cursorHideOnKeyPress','hide_on_key_press'),
                    ('cursorHideOnTouch','hide_on_touch'),
                    ('cursorHideOnTablet','hide_on_tablet')]),
        ('gestures', [('workspaceSwipeCreateNew','workspace_swipe_create_new'),
                      ('workspaceSwipeForever','workspace_swipe_forever'),
                      ('workspaceSwipeCancelRatio','workspace_swipe_cancel_ratio'),
                      ('workspaceSwipeMinSpeedToForce','workspace_swipe_min_speed_to_force'),
                      ('workspaceSwipeDirectionLock','workspace_swipe_direction_lock'),
                      ('workspaceSwipeDistance','workspace_swipe_distance'),
                      ('workspaceSwipeInvert','workspace_swipe_invert'),
                      ('workspaceSwipeTouch','workspace_swipe_touch'),
                      ('workspaceSwipeTouchInvert','workspace_swipe_touch_invert')]),
        ('misc', [('vrr','vrr'), ('vfr','vfr'),
                  ('mouseMoveEnablesDpms','mouse_move_enables_dpms'),
                  ('keyPressEnablesDpms','key_press_enables_dpms'),
                  ('disableAutoreload','disable_autoreload'),
                  ('focusOnActivate','focus_on_activate'),
                  ('animateManualResizes','animate_manual_resizes'),
                  ('animateMouseWindowdragging','animate_mouse_windowdragging'),
                  ('disableHyprlandLogo','disable_hyprland_logo'),
                  ('disableSplashRendering','disable_splash_rendering'),
                  ('forceDefaultWallpaper','force_default_wallpaper'),
                  ('noUpdateNews','no_update_news')]),
        ('xwayland', [('xwaylandEnabled','enabled'),
                      ('xwaylandForceZeroScaling','force_zero_scaling'),
                      ('xwaylandUseNearestNeighbor','use_nearest_neighbor')]),
    ]:
        lines.append('')
        lines.append(sec_name + ' {')
        for ck, kw in keys:
            if ck in cfg: lines.append('  ' + kw + ' = ' + fmt(cfg[ck]))
        lines.append('}')

    lines.append('# === END COMPOSITOR ===')
    return '\n'.join(lines) + '\n'

# ============================================================================
#  hyprland.lua - hl.config() syntax  
# ============================================================================
def build_lua_block():
    lines = [
        '-- === NOTHINGLESS COMPOSITOR ===',
        '-- NothingLess compositor settings',
        'hl.config({',
    ]

    sections = {
        'general': [('borderSize','border_size'), ('gapsIn','gaps_in'), ('gapsOut','gaps_out'),
                    ('allowTearing','allow_tearing'), ('resizeOnBorder','resize_on_border'),
                    ('extendBorderGrabArea','extend_border_grab_area'),
                    ('hoverIconOnBorder','hover_icon_on_border'), ('layout','layout')],
        'decoration': [('rounding','rounding'), ('roundingPower','rounding_power'),
                       ('activeOpacity','active_opacity'), ('inactiveOpacity','inactive_opacity'),
                       ('fullscreenOpacity','fullscreen_opacity'),
                       ('dimInactive','dim_inactive'), ('dimStrength','dim_strength'),
                       ('dimAround','dim_around'), ('dimSpecial','dim_special')],
        'input': [('kbLayout','kb_layout'), ('kbVariant','kb_variant'),
                  ('kbOptions','kb_options'),
                  ('numlockByDefault','numlock_by_default'),
                  ('repeatRate','repeat_rate'), ('repeatDelay','repeat_delay'),
                  ('mouseSensitivity','sensitivity'),
                  ('followMouse','follow_mouse'),
                  ('mouseNaturalScroll','natural_scroll'),
                  ('mouseScrollFactor','scroll_factor'),
                  ('mouseLeftHanded','left_handed'),
                  ('mouseRefocus','mouse_refocus'),
                  ('floatSwitchOverrideFocus','float_switch_override_focus')],
        'cursor': [('noHardwareCursors','no_hardware_cursors'),
                   ('enableHyprcursor','enable_hyprcursor'), ('noWarps','no_warps'),
                   ('persistentWarps','persistent_warps'),
                   ('warpOnChangeWorkspace','warp_on_change_workspace'),
                   ('cursorZoomFactor','zoom_factor'),
                   ('cursorInactiveTimeout','inactive_timeout'),
                   ('cursorHideOnKeyPress','hide_on_key_press'),
                   ('cursorHideOnTouch','hide_on_touch'),
                   ('cursorHideOnTablet','hide_on_tablet')],
        'gestures': [('workspaceSwipeCreateNew','workspace_swipe_create_new'),
                     ('workspaceSwipeForever','workspace_swipe_forever'),
                     ('workspaceSwipeCancelRatio','workspace_swipe_cancel_ratio'),
                     ('workspaceSwipeMinSpeedToForce','workspace_swipe_min_speed_to_force'),
                     ('workspaceSwipeDirectionLock','workspace_swipe_direction_lock'),
                     ('workspaceSwipeDistance','workspace_swipe_distance'),
                     ('workspaceSwipeInvert','workspace_swipe_invert'),
                     ('workspaceSwipeTouch','workspace_swipe_touch'),
                     ('workspaceSwipeTouchInvert','workspace_swipe_touch_invert')],
        'misc': [('vrr','vrr'), ('vfr','vfr'),
                 ('mouseMoveEnablesDpms','mouse_move_enables_dpms'),
                 ('keyPressEnablesDpms','key_press_enables_dpms'),
                 ('disableAutoreload','disable_autoreload'),
                 ('focusOnActivate','focus_on_activate'),
                 ('animateManualResizes','animate_manual_resizes'),
                 ('animateMouseWindowdragging','animate_mouse_windowdragging'),
                 ('disableHyprlandLogo','disable_hyprland_logo'),
                 ('disableSplashRendering','disable_splash_rendering'),
                 ('forceDefaultWallpaper','force_default_wallpaper'),
                 ('noUpdateNews','no_update_news')],
        'xwayland': [('xwaylandEnabled','enabled'),
                     ('xwaylandForceZeroScaling','force_zero_scaling'),
                     ('xwaylandUseNearestNeighbor','use_nearest_neighbor')],
        'dwindle': [('dwindlePreserveSplit','preserve_split'),
                    ('dwindlePseudotile','pseudotile'),
                    ('dwindleForceSplit','force_split'),
                    ('dwindleSmartSplit','smart_split'),
                    ('dwindleDefaultSplitRatio','default_split_ratio'),
                    ('dwindleSplitWidthMultiplier','split_width_multiplier'),
                    ('dwindlePermanentDirectionOverride','permanent_direction_override'),
                    ('dwindleUseActiveForSplits','use_active_for_splits'),
                    ('dwindleSmartResizing','smart_resizing')],
        'master': [('masterOrientation','orientation'), ('masterMfact','mfact'),
                   ('masterNewStatus','new_status'), ('masterNewOnTop','new_on_top'),
                   ('masterNewOnActive','new_on_active'),
                   ('masterSmartResizing','smart_resizing'),
                   ('masterAllowSmallSplit','allow_small_split')],
        'scrolling': [('scrollingColumnWidth','column_width'),
                      ('scrollingExplicitColumnWidths','explicit_column_widths'),
                      ('scrollingDirection','direction'),
                      ('scrollingFullscreenOnOneColumn','fullscreen_on_one_column'),
                      ('scrollingFocusFitMethod','focus_fit_method'),
                      ('scrollingFollowFocus','follow_focus'),
                      ('scrollingFollowMinVisible','follow_min_visible')],
    }

    for section, keys in sections.items():
        lines.append(f'    {section} = {{')
        for ck, kw in keys:
            if ck in cfg:
                lines.append(f'        {kw} = {fmt_lua(cfg[ck])},')
        lines.append('    },')

    lines.append('})')
    lines.append('-- === END COMPOSITOR ===')
    return '\n'.join(lines) + '\n'

# ============================================================================
#  WRITE FILES
# ============================================================================
marker = '# === NOTHINGLESS COMPOSITOR ==='
end_marker = '# === END COMPOSITOR ==='
lua_marker = '-- === NOTHINGLESS COMPOSITOR ==='
lua_end_marker = '-- === END COMPOSITOR ==='

conf_block = build_conf_block()
with open(CONF_PATH) as f:
    content = f.read()
content = re.sub(re.escape(marker) + '.*?' + re.escape(end_marker), '', content, flags=re.DOTALL).strip()
content += '\n' + conf_block
with open(CONF_PATH, 'w') as f:
    f.write(content)
print(f'hyprland.conf: {len(conf_block)} chars')

lua_block = build_lua_block()
with open(LUA_PATH) as f:
    content = f.read()
content = re.sub(re.escape(lua_marker) + '.*?' + re.escape(lua_end_marker), '', content, flags=re.DOTALL).strip()
content += '\n' + lua_block
with open(LUA_PATH, 'w') as f:
    f.write(content)
print(f'hyprland.lua: {len(lua_block)} chars')

print('Done - hyprctl reload recommended')
