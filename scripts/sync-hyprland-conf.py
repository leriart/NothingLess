#!/usr/bin/env python3
"""Sync NothingLess compositor config + keybinds to hyprland.conf and hyprland.lua"""
import json, re, os

BASE = os.path.expanduser('~/.config/nothingless/config')
BINDS_PATH = os.path.expanduser('~/.config/nothingless/binds.json')
CONF_PATH = os.path.expanduser('~/.local/share/nothingless/hyprland.conf')
LUA_PATH = os.path.expanduser('~/.local/share/nothingless/hyprland.lua')
AXCTL_TOML_PATH = os.path.expanduser('~/.local/share/nothingless/axctl.toml')
COMPOSITOR_PATH = os.path.join(BASE, 'compositor.json')

with open(COMPOSITOR_PATH) as f:
    cfg = json.load(f)

# ============================================================================
#  ACTION RESOLVER — mirrors KeybindActions.js
# ============================================================================

def direction_letter(direction):
    d = (direction or "").lower()
    if d in ("up", "u"): return "u"
    if d in ("down", "d"): return "d"
    if d in ("left", "l"): return "l"
    if d in ("right", "r"): return "r"
    return ""

ACTION_MAP = {
    # NothingLess core actions
    "nothingless.launcher":        ("exec", "nothingless run launcher", "r"),
    "nothingless.dashboard":       ("exec", "nothingless run dashboard"),
    "nothingless.assistant":       ("exec", "nothingless run assistant"),
    "nothingless.clipboard":       ("exec", "nothingless run clipboard"),
    "nothingless.emoji":           ("exec", "nothingless run emoji"),
    "nothingless.notes":           ("exec", "nothingless run notes"),
    "nothingless.tmux":            ("exec", "nothingless run tmux"),
    "nothingless.wallpapers":      ("exec", "nothingless run wallpapers"),
    "nothingless.config":          ("exec", "nothingless run config"),
    "nothingless.overview":        ("exec", "nothingless run overview"),
    "nothingless.powermenu":       ("exec", "nothingless run powermenu"),
    "nothingless.tools":           ("exec", "nothingless run tools"),
    "nothingless.screenshot":      ("exec", "nothingless run screenshot"),
    "nothingless.screenrecord":    ("exec", "nothingless run screenrecord"),
    "nothingless.lens":            ("exec", "nothingless run lens"),
    "nothingless.reload":          ("exec", "nothingless reload"),
    "nothingless.quit":            ("exec", "nothingless quit"),
    "nothingless.toggle-metrics":  ("exec", "nothingless run toggle-metrics"),
    "nothingless.lock":            ("exec", "nothingless lock"),

    # Window actions
    # Window movement: SUPER + drag = MOVE (via m flag)
    # Window resize: click border + drag = RESIZE nativo (via resize_on_border)
    # resize-drag no genera bind nativo - lo maneja resize_on_border
    "window.close":                ("killactive", ""),
    "window.focus":                ("movefocus", "direction"),
    "window.move":                 ("movewindow", "direction"),
    "window.drag":                 ("movewindow", "", "m"),
    "window.resize-drag":          ("", ""),  # No bind nativo - lo maneja resize_on_border
    "window.resize":               ("resizeactive", "delta"),
    "window.resize-expand":        ("resizeactive", "50 50"),
    "window.resize-shrink":        ("resizeactive", "-50 -50"),

    # Workspace actions
    "workspace.switch":            ("workspace", "index"),
    "workspace.switch-relative":   ("workspace", "offset"),
    "workspace.switch-occupied":   ("workspace", "offset", "", "e"),
    "workspace.move-window":       ("movetoworkspace", "index"),
    "workspace.move-window-silent":("movetoworkspacesilent", "index"),
    "workspace.toggle-special":    ("togglespecialworkspace", ""),
    "workspace.move-window-special":("movetoworkspace", "special"),
    "workspace.move-window-special-silent":("movetoworkspacesilent", "special"),

    # Scrolling layout actions
    "scrolling.focus":             ("movefocus", "direction"),
    "scrolling.move-window":       ("movewindow", "direction"),
    "scrolling.resize-column":     ("layoutmsg", "delta", "", "colresize "),
    "scrolling.promote":           ("layoutmsg", "promote"),
    "scrolling.toggle-fit":        ("layoutmsg", "togglefit"),
    "scrolling.toggle-full-column":("layoutmsg", "colresize +conf"),
    "scrolling.swap-column":       ("layoutmsg", "direction", "", "swapcol "),
    "scrolling.move-column-workspace":("layoutmsg", "index", "", "movecoltoworkspace "),

    # Free Layout actions (Windows-style hyprctl commands)
    "free.snap-left":              ("exec", "hyprctl dispatch centerwindow && hyprctl dispatch resizeactive -50% 0"),
    "free.snap-right":             ("exec", "hyprctl dispatch centerwindow && hyprctl dispatch resizeactive 50% 0"),
    "free.snap-top":               ("exec", "hyprctl dispatch centerwindow && hyprctl dispatch resizeactive 0 -50%"),
    "free.snap-bottom":            ("exec", "hyprctl dispatch centerwindow && hyprctl dispatch resizeactive 0 50%"),
    "free.snap-center":            ("exec", "hyprctl dispatch centerwindow"),
    "free.snap-maximize":          ("fullscreen", "1"),
    "free.snap-restore":           ("fullscreen", "0"),
    "free.snap-top-left":          ("exec", "hyprctl dispatch movewindow pixel exact 0 0,active && hyprctl dispatch resizeactive 50% 50%"),
    "free.snap-top-right":         ("exec", "hyprctl dispatch movewindow pixel exact 50% 0,active && hyprctl dispatch resizeactive 50% 50%"),
    "free.snap-bottom-left":       ("exec", "hyprctl dispatch movewindow pixel exact 0 50%,active && hyprctl dispatch resizeactive 50% 50%"),
    "free.snap-bottom-right":      ("exec", "hyprctl dispatch movewindow pixel exact 50% 50%,active && hyprctl dispatch resizeactive 50% 50%"),
    "free.toggle-tile":            ("togglefloating", ""),
    "free.show-desktop":           ("exec", "hyprctl dispatch workspaceopt allfloat"),
    "free.workspace-left":         ("exec", "hyprctl dispatch movewindow m:-1"),
    "free.workspace-right":        ("exec", "hyprctl dispatch movewindow m:+1"),

    # Media actions
    "media.play-pause":            ("exec", "playerctl play-pause"),
    "media.play-pause-locked":     ("exec", "playerctl play-pause", "l"),
    "media.prev":                  ("exec", "playerctl previous"),
    "media.next":                  ("exec", "playerctl next"),
    "media.stop-locked":           ("exec", "playerctl stop", "l"),

    # Audio actions
    "audio.volume-up":             ("exec", "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 10%+", "le"),
    "audio.volume-down":           ("exec", "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 10%-", "le"),
    "audio.mute-toggle":           ("exec", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", "le"),

    # Brightness actions
    "brightness.up":               ("exec", "nothingless brightness +5", "le"),
    "brightness.down":             ("exec", "nothingless brightness -5", "le"),

    # System actions
    "system.calculator":           ("exec", "notify-send \"Soon\""),
    "system.lock":                 ("exec", "loginctl lock-session"),
    "system.lock-locked":          ("exec", "loginctl lock-session", "l"),
    "system.dpms-off":             ("exec", "axctl monitor set-dpms 0 0", "l"),
    "system.dpms-on":              ("exec", "axctl monitor set-dpms 0 1", "l"),

    # Custom command
    "command.run":                 ("exec", "command"),
}


def resolve_action(action):
    """Resolve an action dict to (dispatcher, argument, flags)."""
    if not action:
        return None

    # Already resolved form
    if action.get("dispatcher"):
        return (action["dispatcher"], action.get("argument", ""), action.get("flags", ""))

    action_id = action.get("id", "")
    args = action.get("args", {})
    entry = ACTION_MAP.get(action_id)

    if not entry:
        return None

    dispatcher = entry[0]
    arg_spec = entry[1] if len(entry) > 1 else ""
    flags = entry[2] if len(entry) > 2 else ""
    prefix = entry[3] if len(entry) > 3 else ""

    # Resolve argument
    if arg_spec == "direction":
        argument = direction_letter(args.get("direction", ""))
    elif arg_spec == "index":
        argument = str(args.get("index", ""))
    elif arg_spec == "offset":
        raw = str(args.get("offset", ""))
        if raw and (raw.startswith("+") or raw.startswith("-")):
            argument = raw
        else:
            num = int(raw) if raw else 0
            argument = f"+{num}" if num >= 0 else str(num)
    elif arg_spec == "delta":
        argument = str(args.get("delta", ""))
    elif arg_spec == "command":
        argument = str(args.get("command", ""))
    elif arg_spec == "special":
        argument = "special"
    else:
        argument = str(arg_spec) if arg_spec else ""

    # Handle prefix (layoutmsg commands)
    if prefix and argument:
        argument = prefix + argument

    return (dispatcher, argument, flags)


def build_bind_line(modifiers, key, dispatcher, argument, flags):
    """Build a hyprland.conf bind line.

    Hyprland bind syntax:
      bind[flags] = MODS, KEY, DISPATCHER[, ARGS]
    Supported flags: l=locked, r=release, e=repeat, m=mouse
    For mouse binds (m flag): use 'bindm' keyword, no trailing argument.
    Flags can be combined: bindel = locked + repeat (volume/brightness).
    """
    if not key:
        return None

    mods_str = " ".join(modifiers) if modifiers else ""

    if not dispatcher:
        return None

    # Mouse bind with 'm' flag → use 'bindm' keyword (NOT 'bind ... , m')
    if "m" in flags:
        arg_part = f", {argument}" if argument else ""
        if not mods_str:
            return f"bindm = , {key}, {dispatcher}{arg_part}"
        return f"bindm = {mods_str}, {key}, {dispatcher}{arg_part}"

    # Build bind type from flags: e=repeat, l=locked, r=release
    # Hyprland convention: alphabetical order → 'bindel' (not 'bindle')
    bind_type = "bind"
    flag_chars = ""
    if "e" in flags:
        flag_chars += "e"
    if "l" in flags:
        flag_chars += "l"
    if "r" in flags:
        flag_chars += "r"
    if flag_chars:
        bind_type = "bind" + flag_chars

    # Build the argument part (skip if empty to avoid trailing comma)
    arg_part = f", {argument}" if argument else ""

    if not mods_str:
        return f"{bind_type} = , {key}, {dispatcher}{arg_part}"

    return f"{bind_type} = {mods_str}, {key}, {dispatcher}{arg_part}"


def build_lua_bind(modifiers, key, dispatcher, argument, flags):
    """Build a hyprland.lua hl.bind() call."""
    if not key or not dispatcher:
        return None

    mods_lua = "{ " + ", ".join(f'"{m}"' for m in (modifiers or [])) + " }" if modifiers else "{}"

    # Build flags for lua
    lua_flags = []
    if "l" in flags:
        lua_flags.append("locked = true")
    if "r" in flags:
        lua_flags.append("release = true")
    if "m" in flags:
        lua_flags.append("mouse = true")

    flags_str = ", " + ", ".join(lua_flags) if lua_flags else ""

    # Escape double quotes inside argument strings to prevent broken Lua syntax
    # e.g. notify-send "Soon" → notify-send \"Soon\"
    safe_arg = argument.replace('\\', '\\\\').replace('"', '\\"') if argument else ""

    return f'hl.bind({{ mods = {mods_lua}, key = "{key}", dispatcher = "{dispatcher}", arg = "{safe_arg}"{flags_str} }})'


def process_nothingless_binds(binds_data):
    """Process the 'nothingless' section of binds.json."""
    lines = []
    lua_lines = []

    nothingless = binds_data.get("nothingless", {})

    # Process core keys (launcher, dashboard, etc.)
    core_keys = ["launcher", "dashboard", "assistant", "clipboard", "emoji",
                  "notes", "tmux", "wallpapers"]
    for key_name in core_keys:
        bind = nothingless.get(key_name)
        if not bind:
            continue
        resolved = resolve_action(bind.get("action", {}))
        if not resolved:
            continue
        dispatcher, argument, flags = resolved
        line = build_bind_line(bind.get("modifiers", []), bind.get("key", ""), dispatcher, argument, flags)
        lua = build_lua_bind(bind.get("modifiers", []), bind.get("key", ""), dispatcher, argument, flags)
        if line:
            lines.append(line)
        if lua:
            lua_lines.append(lua)

    # Process system keys
    system = nothingless.get("system", {})
    sys_keys = ["overview", "powermenu", "config", "lockscreen", "tools",
                 "screenshot", "screenrecord", "lens", "reload", "quit", "toggle-metrics"]
    for key_name in sys_keys:
        bind = system.get(key_name)
        if not bind:
            continue
        resolved = resolve_action(bind.get("action", {}))
        if not resolved:
            continue
        dispatcher, argument, flags = resolved
        line = build_bind_line(bind.get("modifiers", []), bind.get("key", ""), dispatcher, argument, flags)
        lua = build_lua_bind(bind.get("modifiers", []), bind.get("key", ""), dispatcher, argument, flags)
        if line:
            lines.append(line)
        if lua:
            lua_lines.append(lua)

    return lines, lua_lines


def process_custom_binds(binds_data):
    """Process the 'custom' array of binds.json."""
    lines = []
    lua_lines = []
    custom = binds_data.get("custom", [])

    for bind in custom:
        if bind.get("enabled") is False:
            continue

        keys = bind.get("keys", [])
        actions = bind.get("actions", [])

        if not keys or not actions:
            continue

        for key_obj in keys:
            if not key_obj or not key_obj.get("key"):
                continue

            for action in actions:
                resolved = resolve_action(action)
                if not resolved:
                    continue
                dispatcher, argument, flags = resolved
                line = build_bind_line(key_obj.get("modifiers", []), key_obj.get("key", ""), dispatcher, argument, flags)
                lua = build_lua_bind(key_obj.get("modifiers", []), key_obj.get("key", ""), dispatcher, argument, flags)
                if line:
                    lines.append(line)
                if lua:
                    lua_lines.append(lua)

    return lines, lua_lines


def build_binds_block():
    """Build the keybinds section for hyprland.conf, .lua, and axctl.toml."""
    try:
        with open(BINDS_PATH) as f:
            binds_data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return "", "", ""

    core_lines, core_lua = process_nothingless_binds(binds_data)
    custom_lines, custom_lua = process_custom_binds(binds_data)

    # --- hyprland.conf format ---
    seen = set()
    deduped = []
    for line in core_lines + custom_lines:
        if line not in seen:
            deduped.append(line)
            seen.add(line)

    if not deduped:
        return "", "", ""

    block = "# === NOTHINGLESS KEYBINDS ===\n"
    block += "# Synced from NothingLess binds.json\n"
    for line in deduped:
        block += line + "\n"

    if cfg.get('layout') == 'free':
        block += "\n# Windows-style keybinds (Free layout)\n"
        block += "bind = SUPER, Left, exec, hyprctl dispatch centerwindow && hyprctl dispatch resizeactive -50% 0\n"
        block += "bind = SUPER, Right, exec, hyprctl dispatch centerwindow && hyprctl dispatch resizeactive 50% 0\n"
        block += "bind = SUPER, Up, exec, hyprctl dispatch fullscreen 1\n"
        block += "bind = SUPER, Down, exec, hyprctl dispatch fullscreen 0\n"
        block += "bind = SUPER SHIFT, Left, exec, hyprctl dispatch movewindow m:-1\n"
        block += "bind = SUPER SHIFT, Right, exec, hyprctl dispatch movewindow m:+1\n"
        block += "bind = SUPER, D, exec, hyprctl dispatch workspaceopt allfloat\n"
        block += "\n"

    block += "# === END KEYBINDS ===\n"

    # --- hyprland.lua format ---
    seen_lua = set()
    deduped_lua = []
    for line in core_lua + custom_lua:
        if line not in seen_lua:
            deduped_lua.append(line)
            seen_lua.add(line)

    lua_block = "-- === NOTHINGLESS KEYBINDS ===\n"
    lua_block += "-- Synced from NothingLess binds.json\n"
    for line in deduped_lua:
        lua_block += line + "\n"
    lua_block += "-- === END KEYBINDS ===\n"

    # --- axctl.toml format ---
    # Generate TOML keybinds from scratch using the same bind data
    def build_toml_bind_line(modifiers, key, dispatcher, argument, flags):
        if not key or not dispatcher:
            return None
        mods_json = json.dumps(modifiers or [])
        key_json = json.dumps(key)
        disp_json = json.dumps(dispatcher)
        arg_json = json.dumps(argument or "")
        flags_json = json.dumps(flags or "")
        return (
            "[[keybinds]]\n"
            f"modifiers = {mods_json}\n"
            f"key = {key_json}\n"
            f"dispatcher = {disp_json}\n"
            f"argument = {arg_json}\n"
            f"flags = {flags_json}\n"
            "enabled = true\n"
        )

    toml_binds = []
    seen_toml = set()

    # Process nothingless core + system binds
    nothingless = binds_data.get("nothingless", {})
    if nothingless:
        all_nl_keys = ["launcher", "dashboard", "assistant", "clipboard", "emoji",
                       "notes", "tmux", "wallpapers"]
        system = nothingless.get("system", {})
        all_sys_keys = ["overview", "powermenu", "config", "lockscreen", "tools",
                        "screenshot", "screenrecord", "lens", "reload", "quit", "toggle-metrics"]
        for key_name in all_nl_keys:
            bind = nothingless.get(key_name)
            if not bind:
                continue
            resolved = resolve_action(bind.get("action", {}))
            if not resolved:
                continue
            dispatcher, argument, flags = resolved
            line = build_toml_bind_line(bind.get("modifiers", []), bind.get("key", ""),
                                         dispatcher, argument, flags)
            if line and line not in seen_toml:
                seen_toml.add(line)
                toml_binds.append(line)
        for key_name in all_sys_keys:
            bind = system.get(key_name)
            if not bind:
                continue
            resolved = resolve_action(bind.get("action", {}))
            if not resolved:
                continue
            dispatcher, argument, flags = resolved
            line = build_toml_bind_line(bind.get("modifiers", []), bind.get("key", ""),
                                         dispatcher, argument, flags)
            if line and line not in seen_toml:
                seen_toml.add(line)
                toml_binds.append(line)

    # Process custom binds
    custom = binds_data.get("custom", [])
    if custom:
        for bind in custom:
            if bind.get("enabled") is False:
                continue
            if bind.get("keys") and bind.get("actions"):
                for key_obj in bind["keys"]:
                    if not key_obj or not key_obj.get("key"):
                        continue
                    for action in bind["actions"]:
                        if action.get("layouts") and cfg.get('layout') not in action.get("layouts", []):
                            continue
                        resolved = resolve_action(action)
                        if not resolved:
                            continue
                        dispatcher, argument, flags = resolved
                        line = build_toml_bind_line(key_obj.get("modifiers", []),
                                                     key_obj["key"], dispatcher, argument, flags)
                        if line and line not in seen_toml:
                            seen_toml.add(line)
                            toml_binds.append(line)
            elif bind:
                resolved = resolve_action(bind.get("action", {}))
                if not resolved:
                    continue
                dispatcher, argument, flags = resolved
                line = build_toml_bind_line(bind.get("modifiers", []), bind.get("key", ""),
                                             dispatcher, argument, flags)
                if line and line not in seen_toml:
                    seen_toml.add(line)
                    toml_binds.append(line)

    toml_block = "\n".join(toml_binds)
    if toml_block:
        toml_block = "# === NOTHINGLESS KEYBINDS ===\n" + \
                     "# Synced from NothingLess binds.json\n\n" + \
                     toml_block + "\n# === END KEYBINDS ===\n"

    return block, lua_block, toml_block




# ============================================================================
#  Format helpers
# ============================================================================
def fmt(val):
    if isinstance(val, bool):
        return 'true' if val else 'false'
    if isinstance(val, list):
        return ' '.join(str(v) for v in val)
    if isinstance(val, float):
        s = f'{val:.2f}'.rstrip('0').rstrip('.')
        return s if '.' in s else s + '.0'
    if isinstance(val, str) and val == '':
        return ''
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

    # Determine if Free Layout (floating mode)
    _is_free = cfg.get('layout') == 'free'

    if _is_free:
        # Free Layout: windowrule float ALL windows
        lines.append('windowrule = match:class .*, float on')
        lines.append('')

    # Smart Resize Anchors: override resize_on_border + grab area
    _smart = cfg.get('smartResizeAnchors', True)
    if _smart:
        cfg.update({'resizeOnBorder': True, 'extendBorderGrabArea': 10})
    else:
        cfg.update({'resizeOnBorder': False, 'extendBorderGrabArea': 0})

    sec('general', [
        ('borderSize','border_size'), ('gapsIn','gaps_in'), ('gapsOut','gaps_out'),
        ('allowTearing','allow_tearing'),
        ('hoverIconOnBorder','hover_icon_on_border'),
        ('resizeOnBorder','resize_on_border'),
        ('extendBorderGrabArea','extend_border_grab_area'),
    ] + ([] if _is_free else [('layout','layout')]))

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
                  ]:
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
        ('misc', [('vrr','vrr'), ('mouseMoveEnablesDpms','mouse_move_enables_dpms'),
                  ('keyPressEnablesDpms','key_press_enables_dpms'),
                  ('disableAutoreload','disable_autoreload'),
                  ('focusOnActivate','focus_on_activate'),
                  ('animateManualResizes','animate_manual_resizes'),
                  ('animateMouseWindowdragging','animate_mouse_windowdragging'),
                  ('disableHyprlandLogo','disable_hyprland_logo'),
                  ('disableSplashRendering','disable_splash_rendering'),
                  ('forceDefaultWallpaper','force_default_wallpaper'),
                  ]),
        ('xwayland', [('xwaylandEnabled','enabled'),
                      ('xwaylandForceZeroScaling','force_zero_scaling'),
                      ('xwaylandUseNearestNeighbor','use_nearest_neighbor')]),
    ]:
        lines.append('')
        lines.append(sec_name + ' {')
        for ck, kw in keys:
            if ck in cfg: lines.append('  ' + kw + ' = ' + fmt(cfg[ck]))
        lines.append('}')

    # Workspace rules (hyprlang syntax)
    ws_rules = cfg.get('workspaceRules', [])
    if ws_rules:
        lines.append('')
        lines.append('# Workspace rules')
        for rule in ws_rules:
            ws_sel = rule.get('selector', '')
            if not ws_sel:
                continue
            parts = []
            if 'monitor' in rule and rule['monitor']:
                parts.append(f'monitor:{rule["monitor"]}')
            if 'gapsIn' in rule:
                parts.append(f'gapsin:{rule["gapsIn"]}')
            if 'gapsOut' in rule:
                parts.append(f'gapsout:{rule["gapsOut"]}')
            if 'borderSize' in rule:
                parts.append(f'bordersize:{rule["borderSize"]}')
            if 'rounding' in rule:
                parts.append(f'rounding:{"true" if rule["rounding"] else "false"}')
            if 'layout' in rule and rule['layout']:
                parts.append(f'layoutopt:{rule["layout"]}')
            if 'defaultFloat' in rule and rule['defaultFloat']:
                parts.append('default:float')
            if 'persistent' in rule and rule['persistent']:
                parts.append('persistent:true')
            if parts:
                lines.append(f'workspace = {ws_sel}, {", ".join(parts)}')

    # Smart gaps
    if cfg.get('smartGaps'):
        lines.append('')
        lines.append('# Smart gaps: no gaps with single tiled window')
        lines.append('workspace = w[tv1], gapsin:0, gapsout:0, bordersize:0, rounding:false')

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

    _is_free = cfg.get('layout') == 'free'

    sections = {
        'general': [('borderSize','border_size'), ('gapsIn','gaps_in'), ('gapsOut','gaps_out'),
                    ('allowTearing','allow_tearing'), ('resizeOnBorder','resize_on_border'),
                    ('extendBorderGrabArea','extend_border_grab_area'),
                    ('hoverIconOnBorder','hover_icon_on_border'),
        ] + ([] if _is_free else [('layout','layout')]),
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
        'misc': [('vrr','vrr'),
                 ('mouseMoveEnablesDpms','mouse_move_enables_dpms'),
                 ('keyPressEnablesDpms','key_press_enables_dpms'),
                 ('disableAutoreload','disable_autoreload'),
                 ('focusOnActivate','focus_on_activate'),
                 ('animateManualResizes','animate_manual_resizes'),
                 ('animateMouseWindowdragging','animate_mouse_windowdragging'),
                 ('disableHyprlandLogo','disable_hyprland_logo'),
                 ('disableSplashRendering','disable_splash_rendering'),
                 ('forceDefaultWallpaper','force_default_wallpaper'),
                 ],
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

    # Free Layout: float all windows (Hyprland 0.55+ hl.window_rule API)
    if _is_free:
        lines.insert(2, '-- Free Layout: float all windows')
        lines.insert(3, 'hl.window_rule({ match = { class = ".*" }, float = true })')
        lines.insert(4, '')

    # Workspace rules (Hyprland 0.55+ hl.workspace_rule API)
    ws_rules = cfg.get('workspaceRules', [])
    if ws_rules:
        lines.append('')
        lines.append('-- Workspace rules')
        for rule in ws_rules:
            ws_sel = rule.get('selector', '')
            if not ws_sel:
                continue
            parts = {}
            if 'monitor' in rule and rule['monitor']:
                parts['monitor'] = f'"{rule["monitor"]}"'
            if 'gapsIn' in rule:
                parts['gapsIn'] = rule['gapsIn']
            if 'gapsOut' in rule:
                parts['gapsOut'] = rule['gapsOut']
            if 'borderSize' in rule:
                parts['borderSize'] = rule['borderSize']
            if 'rounding' in rule:
                parts['rounding'] = 'true' if rule['rounding'] else 'false'
            if 'layout' in rule and rule['layout']:
                parts['layout'] = f'"{rule["layout"]}"'
            if 'defaultFloat' in rule:
                parts['default_float'] = 'true' if rule['defaultFloat'] else 'false'
            if 'persistent' in rule:
                parts['persistent'] = 'true' if rule['persistent'] else 'false'
            props = ', '.join(f'{k} = {v}' for k, v in parts.items())
            lines.append(f'hl.workspace_rule({{ selector = "{ws_sel}", {props} }})')

    # Smart gaps: no gaps when only one tiled window visible
    if cfg.get('smartGaps'):
        lines.append('')
        lines.append('-- Smart gaps: no gaps with single tiled window')
        lines.append('hl.workspace_rule({ selector = "w[tv1]", gapsIn = 0, gapsOut = 0, borderSize = 0, rounding = false })')

    lines.append('-- === END COMPOSITOR ===')
    return '\n'.join(lines) + '\n'

# ============================================================================
#  axctl.toml - TOML format (syncs compositor settings to axctl daemon)
# ============================================================================
def build_toml_block():
    """Build the compositor settings section for axctl.toml."""
    lines = ['# === NOTHINGLESS COMPOSITOR ===', '# Synced from compositor.json', '']

    def toml_val(val):
        if isinstance(val, bool):
            return 'true' if val else 'false'
        if isinstance(val, list):
            return '[' + ', '.join(toml_val(v) for v in val) + ']'
        if isinstance(val, float):
            s = f'{val:.2f}'.rstrip('0').rstrip('.')
            return s if '.' in s else s + '.0'
        if isinstance(val, str):
            return '"' + val.replace('\\', '\\\\').replace('"', '\\"') + '"'
        return str(val)

    def fmt_t(val, fixed=None):
        if isinstance(val, bool):
            return 'true' if val else 'false'
        if isinstance(val, float):
            if fixed:
                return f'{val:.{fixed}f}'
            return str(val)
        if isinstance(val, int):
            return str(val)
        return str(val)

    # Gaps
    if 'gapsIn' in cfg or 'gapsOut' in cfg:
        lines.append('[appearance.gaps]')
        if 'gapsIn' in cfg: lines.append(f'inner = {cfg["gapsIn"]}')
        if 'gapsOut' in cfg: lines.append(f'outer = {cfg["gapsOut"]}')
        lines.append('')

    # Border
    lines.append('[appearance.border]')
    if 'borderSize' in cfg: lines.append(f'width = {cfg["borderSize"]}')
    if 'rounding' in cfg: lines.append(f'rounding = {cfg["rounding"]}')
    if 'roundingPower' in cfg: lines.append(f'rounding_power = {fmt_t(cfg["roundingPower"], 1)}')
    lines.append('')

    # Opacity
    lines.append('[appearance.opacity]')
    if 'activeOpacity' in cfg: lines.append(f'active = {fmt_t(cfg["activeOpacity"], 2)}')
    if 'inactiveOpacity' in cfg: lines.append(f'inactive = {fmt_t(cfg["inactiveOpacity"], 2)}')
    if 'fullscreenOpacity' in cfg: lines.append(f'fullscreen = {fmt_t(cfg["fullscreenOpacity"], 2)}')
    lines.append('')

    # Dim
    lines.append('[appearance.dim]')
    if 'dimInactive' in cfg: lines.append(f'enabled = {fmt_t(cfg["dimInactive"])}')
    if 'dimStrength' in cfg: lines.append(f'strength = {fmt_t(cfg["dimStrength"], 2)}')
    if 'dimAround' in cfg: lines.append(f'around = {fmt_t(cfg["dimAround"], 2)}')
    if 'dimSpecial' in cfg: lines.append(f'special = {fmt_t(cfg["dimSpecial"], 2)}')
    lines.append('')

    # Blur
    lines.append('[appearance.blur]')
    if 'blurEnabled' in cfg: lines.append(f'enabled = {fmt_t(cfg["blurEnabled"])}')
    if 'blurSize' in cfg: lines.append(f'size = {cfg["blurSize"]}')
    if 'blurPasses' in cfg: lines.append(f'passes = {cfg["blurPasses"]}')
    if 'blurIgnoreOpacity' in cfg: lines.append(f'ignore_opacity = {fmt_t(cfg["blurIgnoreOpacity"])}')
    if 'blurNewOptimizations' in cfg: lines.append(f'new_optimizations = {fmt_t(cfg["blurNewOptimizations"])}')
    if 'blurXray' in cfg: lines.append(f'xray = {fmt_t(cfg["blurXray"])}')
    if 'blurNoise' in cfg: lines.append(f'noise = {fmt_t(cfg["blurNoise"], 3)}')
    if 'blurContrast' in cfg: lines.append(f'contrast = {fmt_t(cfg["blurContrast"], 2)}')
    if 'blurBrightness' in cfg: lines.append(f'brightness = {fmt_t(cfg["blurBrightness"], 2)}')
    if 'blurVibrancy' in cfg: lines.append(f'vibrancy = {fmt_t(cfg["blurVibrancy"], 2)}')
    if 'blurVibrancyDarkness' in cfg: lines.append(f'vibrancy_darkness = {fmt_t(cfg["blurVibrancyDarkness"], 2)}')
    if 'blurSpecial' in cfg: lines.append(f'special = {fmt_t(cfg["blurSpecial"])}')
    if 'blurPopups' in cfg: lines.append(f'popups = {fmt_t(cfg["blurPopups"])}')
    lines.append('')

    # Shadow
    lines.append('[appearance.shadow]')
    if 'shadowEnabled' in cfg: lines.append(f'enabled = {fmt_t(cfg["shadowEnabled"])}')
    if 'shadowRange' in cfg: lines.append(f'range = {cfg["shadowRange"]}')
    if 'shadowRenderPower' in cfg: lines.append(f'render_power = {cfg["shadowRenderPower"]}')
    if 'shadowOffset' in cfg: lines.append(f'offset = {toml_val(cfg["shadowOffset"])}')
    if 'shadowScale' in cfg: lines.append(f'scale = {fmt_t(cfg["shadowScale"], 2)}')
    lines.append('')

    # Animations
    lines.append('[appearance.animations]')
    if 'animationsEnabled' in cfg: lines.append(f'enabled = {fmt_t(cfg["animationsEnabled"])}')
    lines.append('')

    # General
    _is_free = cfg.get('layout') == 'free'
    lines.append('[general]')
    if 'layout' in cfg and not _is_free: lines.append(f'layout = {toml_val(cfg["layout"])}')
    if 'allowTearing' in cfg: lines.append(f'allow_tearing = {fmt_t(cfg["allowTearing"])}')
    if 'resizeOnBorder' in cfg: lines.append(f'resize_on_border = {fmt_t(cfg["resizeOnBorder"])}')
    if 'extendBorderGrabArea' in cfg: lines.append(f'extend_border_grab_area = {cfg["extendBorderGrabArea"]}')
    if 'hoverIconOnBorder' in cfg: lines.append(f'hover_icon_on_border = {fmt_t(cfg["hoverIconOnBorder"])}')
    lines.append('')

    # Free Layout grid & snap config
    if _is_free:
        lines.append('[general.free]')
        if 'freeGridSize' in cfg: lines.append(f'grid_size = {cfg["freeGridSize"]}')
        if 'freeSnapSensitivity' in cfg: lines.append(f'snap_sensitivity = {cfg["freeSnapSensitivity"]}')
        if 'freeSnapEdges' in cfg: lines.append(f'snap_edges = {fmt_t(cfg["freeSnapEdges"])}')
        if 'freeSnapCenter' in cfg: lines.append(f'snap_center = {fmt_t(cfg["freeSnapCenter"])}')
        if 'freeSnapGaps' in cfg: lines.append(f'snap_gaps = {cfg["freeSnapGaps"]}')
        if 'freeTileByDefault' in cfg: lines.append(f'tile_by_default = {fmt_t(cfg["freeTileByDefault"])}')
        if 'freeMaximizedByDefault' in cfg: lines.append(f'maximized_by_default = {fmt_t(cfg["freeMaximizedByDefault"])}')
        lines.append('')

    # Snap
    lines.append('[general.snap]')
    if 'snapEnabled' in cfg: lines.append(f'enabled = {fmt_t(cfg["snapEnabled"])}')
    if 'snapWindowGap' in cfg: lines.append(f'window_gap = {cfg["snapWindowGap"]}')
    if 'snapMonitorGap' in cfg: lines.append(f'monitor_gap = {cfg["snapMonitorGap"]}')
    if 'snapBorderOverlap' in cfg: lines.append(f'border_overlap = {fmt_t(cfg["snapBorderOverlap"])}')
    if 'snapRespectGaps' in cfg: lines.append(f'respect_gaps = {fmt_t(cfg["snapRespectGaps"])}')
    lines.append('')

    lines.append('# === END COMPOSITOR ===')
    return '\n'.join(lines) + '\n'


# ============================================================================
#  FILE WRITING
# ============================================================================

marker = '# === NOTHINGLESS COMPOSITOR ==='
end_marker = '# === END COMPOSITOR ==='
lua_marker = '-- === NOTHINGLESS COMPOSITOR ==='
lua_end_marker = '-- === END COMPOSITOR ==='

binds_marker = '# === NOTHINGLESS KEYBINDS ==='
binds_end_marker = '# === END KEYBINDS ==='
lua_binds_marker = '-- === NOTHINGLESS KEYBINDS ==='
lua_binds_end_marker = '-- === END KEYBINDS ==='

conf_block = build_conf_block()
lua_block = build_lua_block()
binds_block, lua_binds_block, toml_binds_block = build_binds_block()

# --- hyprland.conf ---
with open(CONF_PATH) as f:
    content = f.read()

# Remove and re-insert compositor block
content = re.sub(re.escape(marker) + '.*?' + re.escape(end_marker), '', content, flags=re.DOTALL).strip()
content += '\n' + conf_block

# Remove and re-insert keybinds block
if binds_block:
    content = re.sub(re.escape(binds_marker) + '.*?' + re.escape(binds_end_marker), '', content, flags=re.DOTALL).strip()
    content += '\n' + binds_block

with open(CONF_PATH, 'w') as f:
    f.write(content)
print(f'hyprland.conf: {len(conf_block)} chars (compositor), {len(binds_block)} chars (keybinds)')

# --- hyprland.lua ---
with open(LUA_PATH) as f:
    content = f.read()

content = re.sub(re.escape(lua_marker) + '.*?' + re.escape(lua_end_marker), '', content, flags=re.DOTALL).strip()

if lua_binds_block:
    content = re.sub(re.escape(lua_binds_marker) + '.*?' + re.escape(lua_binds_end_marker), '', content, flags=re.DOTALL).strip()

# Clean up any stray hyprlang syntax left in the Lua header (outside markers).
# These are lines that are valid in .conf but invalid Lua, e.g.:
#   exec-once = ..., bind = ..., source = ..., env = ...
# They get left behind when the file was originally templated from .conf content.
# NOTE: 'monitor' is NOT cleaned here — monitors_writer.py injects monitor=...
# lines inside NOTHINGLESS MONITORS markers that must be preserved.
_hyprlang_line_re = re.compile(
    r'^(?:exec-once|exec|bind[a-z]*|source|env|windowrule|layerrule)\s*=.*$',
    re.MULTILINE
)
content = _hyprlang_line_re.sub('', content)
# Remove any resulting blank-line runs (more than 2 consecutive newlines)
content = re.sub(r'\n{3,}', '\n\n', content).strip()

content += '\n' + lua_block
if lua_binds_block:
    content += '\n' + lua_binds_block

with open(LUA_PATH, 'w') as f:
    f.write(content)
print(f'hyprland.lua: {len(lua_block)} chars (compositor), {len(lua_binds_block)} chars (keybinds)')

# --- axctl.toml ---
toml_block = build_toml_block()

try:
    with open(AXCTL_TOML_PATH) as f:
        toml_content = f.read()

    # Remove everything from [appearance] through the last section before [[keybinds]]
    # This clears old values from CompositorTomlWriter that may conflict
    # Remove old compositor block and ALL existing [[keybinds]] sections
    old_compositor_pattern = re.compile(
        r'\n?\[appearance\].*?(?=\n?\[\[keybinds\]\]|\n?# === NOTHINGLESS|\Z)',
        re.DOTALL
    )
    toml_content = old_compositor_pattern.sub('', toml_content).strip()

    # Also remove old marker block if present
    toml_content = re.sub(
        re.escape('# === NOTHINGLESS COMPOSITOR ===') + '.*?' + re.escape('# === END COMPOSITOR ==='),
        '', toml_content, flags=re.DOTALL
    ).strip()

    # Remove ALL existing [[keybinds]] sections (they'll be replaced)
    toml_content = re.sub(
        r'\n?(\[\[keybinds\]\].*?)(?=\n\[|\Z)',
        '', toml_content, flags=re.DOTALL
    ).strip()

    # Remove any leftover NOTHINGLESS KEYBINDS markers
    toml_content = re.sub(
        re.escape('# === NOTHINGLESS KEYBINDS ===') + '.*?' + re.escape('# === END KEYBINDS ==='),
        '', toml_content, flags=re.DOTALL
    ).strip()

    # Insert the compositor block after [startup] section
    toml_content = toml_content.rstrip() + '\n\n' + toml_block.strip() + '\n'

    # Append keybinds (if any)
    if toml_binds_block:
        toml_content += '\n' + toml_binds_block.strip() + '\n'

    with open(AXCTL_TOML_PATH, 'w') as f:
        f.write(toml_content)
    print(f'axctl.toml: {len(toml_block)} chars (synced)')
    if toml_binds_block:
        print(f'axctl.toml keybinds: {len(toml_binds_block)} chars')

except FileNotFoundError:
    print(f'axctl.toml: CREATED at {AXCTL_TOML_PATH}')
    with open(AXCTL_TOML_PATH, 'w') as f:
        f.write(toml_block)
        if toml_binds_block:
            f.write('\n\n' + toml_binds_block.strip() + '\n')
    print(f'axctl.toml: {len(toml_block)} chars (compositor) + {len(toml_binds_block) if toml_binds_block else 0} chars (keybinds)')

print('Done - hyprctl reload & axctl config reload recommended')
