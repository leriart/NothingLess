#!/usr/bin/env python3
"""
sync-hyprland.py — NothingLess → Hyprland config translator
===========================================================
Reads:  ~/.config/nothingless/config/compositor.json
        ~/.config/nothingless/binds.json
        scripts/hyprlang-dict.toml  (translation dictionary)

Writes: ~/.local/share/nothingless/hyprland.conf
        ~/.local/share/nothingless/hyprland.lua
        ~/.local/share/nothingless/axctl.toml

All translation logic is driven by hyprlang-dict.toml.
No hardcoded keyword strings or dispatcher mappings remain in this file.
"""

import json
import os
import re
import subprocess
import sys

# ── TOML support: Python 3.11+ has tomllib, fallback to tomli ──────────
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        print("ERROR: tomli/tomllib required. Install: pip install tomli", file=sys.stderr)
        sys.exit(1)

# ═══════════════════════════════════════════════════════════════════════════
#  PATHS
# ═══════════════════════════════════════════════════════════════════════════

CONFIG_DIR = os.path.expanduser("~/.config/nothingless/config")
DATA_DIR   = os.path.expanduser("~/.local/share/nothingless")
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

COMPOSITOR_PATH = os.path.join(CONFIG_DIR, "compositor.json")
BINDS_PATH      = os.path.expanduser("~/.config/nothingless/binds.json")
DICT_PATH       = os.path.join(SCRIPT_DIR, "hyprlang-dict.toml")

CONF_PATH = os.path.join(DATA_DIR, "hyprland.conf")
LUA_PATH  = os.path.join(DATA_DIR, "hyprland.lua")
TOML_PATH = os.path.join(DATA_DIR, "axctl.toml")

NOTHINGLESS_BIN = "/usr/local/bin/nothingless"

# ═══════════════════════════════════════════════════════════════════════════
#  LOAD INPUTS
# ═══════════════════════════════════════════════════════════════════════════

with open(DICT_PATH, "rb") as f:
    DICT = tomllib.load(f)

try:
    with open(COMPOSITOR_PATH) as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    cfg = {}

try:
    with open(BINDS_PATH) as f:
        binds_data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    binds_data = {}


# ═══════════════════════════════════════════════════════════════════════════
#  APPLY THEME SYNC OVERRIDES (mirrors Config.qml computed properties)
# ═══════════════════════════════════════════════════════════════════════════

def _apply_theme_sync(local_cfg):
    """Apply NothingLess theme sync overrides to compositor config.
    When syncRoundness/syncBorderWidth/syncBorderColor/syncShadowOpacity/
    syncShadowColor are true, replace the compositor values with theme-derived
    ones — exactly what Config.qml does at runtime.
    """
    THEME_PATH = os.path.expanduser("~/.config/nothingless/config/theme.json")
    try:
        with open(THEME_PATH) as f:
            theme = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return local_cfg

    # syncRoundness → use theme.roundness for decoration.rounding
    if local_cfg.get("syncRoundness"):
        local_cfg["rounding"] = theme.get("roundness", local_cfg.get("rounding", 16))

    # syncBorderWidth → use theme.srBg.border[1] for general.border_size
    if local_cfg.get("syncBorderWidth"):
        sr_bg = theme.get("srBg", {})
        border_arr = sr_bg.get("border", ["surfaceVariant", 0])
        if isinstance(border_arr, list) and len(border_arr) >= 2:
            try:
                local_cfg["borderSize"] = int(border_arr[1])
            except (ValueError, TypeError):
                pass

    # syncBorderColor → use theme.srBg.border[0] for general.col.active_border
    if local_cfg.get("syncBorderColor"):
        sr_bg = theme.get("srBg", {})
        border_arr = sr_bg.get("border", ["surfaceVariant", 0])
        if isinstance(border_arr, list) and len(border_arr) >= 1:
            local_cfg["activeBorderColor"] = [border_arr[0]]

    # syncShadowOpacity → use theme.shadowOpacity for decoration.shadow.opacity
    if local_cfg.get("syncShadowOpacity"):
        local_cfg["shadowOpacity"] = theme.get("shadowOpacity", local_cfg.get("shadowOpacity", 0.5))

    # syncShadowColor → use theme.shadowColor for decoration.shadow.color
    if local_cfg.get("syncShadowColor"):
        local_cfg["shadowColor"] = theme.get("shadowColor", local_cfg.get("shadowColor", "shadow"))

    return local_cfg


# Apply sync overrides to the global cfg so all builders see them
cfg = _apply_theme_sync(cfg)


# ═══════════════════════════════════════════════════════════════════════════
#  UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

def fmt_conf(val):
    """Format a Python value as a hyprland.conf literal."""
    if isinstance(val, bool):
        return "true" if val else "false"
    if isinstance(val, list):
        if not val:
            return ""
        return " ".join(str(v) for v in val)
    if isinstance(val, float):
        s = f"{val:.2f}".rstrip("0").rstrip(".")
        return s if "." in s else s + ".0"
    s = str(val)
    # Sanitize any control characters / null bytes
    s = s.replace("\x00", "0")
    return s


def fmt_lua(val):
    """Format a Python value as a Lua literal."""
    if isinstance(val, bool):
        return "true" if val else "false"
    if isinstance(val, list):
        return '{ "' + '", "'.join(str(v) for v in val) + '" }'
    if isinstance(val, float):
        s = f"{val:.2f}".rstrip("0").rstrip(".")
        return s if "." in s else s + ".0"
    if isinstance(val, str):
        return '"' + val.replace('\\', '\\\\').replace('"', '\\"') + '"'
    return str(val)


def escape_lua(s):
    """Escape a string for insertion inside a Lua double-quoted string."""
    return s.replace("\\", "\\\\").replace('"', '\\"')


def nothingless_path(cmd):
    """Prefix a nothingless CLI command with its absolute path."""
    if cmd.startswith("nothingless "):
        return NOTHINGLESS_BIN + " " + cmd[len("nothingless "):]
    if cmd == "nothingless":
        return NOTHINGLESS_BIN
    return cmd


# ═══════════════════════════════════════════════════════════════════════════
#  SECTION A — BUILD KEYBINDS  (hyprland.conf + hyprland.lua + axctl.toml)
# ═══════════════════════════════════════════════════════════════════════════

# ── Build action lookup from the TOML dictionary (lazy, cached) ──
_ACTIONS_CACHE = None

def _load_actions():
    """Build {action_id: {dispatcher, argument, flags, arg_type, prefix}} from TOML."""
    global _ACTIONS_CACHE
    if _ACTIONS_CACHE is not None:
        return _ACTIONS_CACHE

    _ACTIONS_CACHE = {}
    actions_section = DICT.get("actions", {})
    for _key, entry in actions_section.items():
        aid = entry.get("id", "")
        if aid:
            _ACTIONS_CACHE[aid] = entry
    return _ACTIONS_CACHE


def resolve_action(action):
    """Resolve an action dict from binds.json using the TOML dictionary.

    binds.json format: { "id": "window.close", "args": {...} }
    or legacy: { "dispatcher": "killactive", "argument": "", "flags": "" }

    Returns (dispatcher, argument, flags, action_entry) or None.
    action_entry is the TOML action entry dict (for conf-specific overrides).
    """
    if not action:
        return None

    # Already resolved form
    if action.get("dispatcher"):
        return (action["dispatcher"], action.get("argument", ""), action.get("flags", ""), None)

    # Modern form: { "id": "...", "args": {...} }
    action_id = action.get("id", "")
    args = action.get("args", {})

    actions = _load_actions()
    entry = actions.get(action_id)
    if not entry:
        return None

    dispatcher = entry.get("dispatcher", "")
    arg_spec   = entry.get("arg_type", "")
    flags      = entry.get("flags", "")
    prefix     = entry.get("prefix", "")
    argument   = entry.get("argument", "")

    # ── Resolve argument placeholder ──
    def _dir(d):
        d = (d or "").lower()
        if d in ("up", "u"): return "u"
        if d in ("down", "d"): return "d"
        if d in ("left", "l"): return "l"
        if d in ("right", "r"): return "r"
        return ""

    if arg_spec == "direction":
        argument = _dir(args.get("direction", ""))
    elif arg_spec == "index":
        argument = str(args.get("index", ""))
    elif arg_spec == "offset":
        raw = str(args.get("offset", ""))
        if raw.startswith("+") or raw.startswith("-"):
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

    if prefix and argument:
        argument = prefix + argument

    return (dispatcher, argument, flags, entry)


def build_conf_bind(modifiers, key, dispatcher, argument, flags, action_entry=None):
    """Build a hyprland.conf bind line using the dictionary's dispatcher names.

    action_entry is the TOML action entry dict (for conf-specific overrides).
    """
    if not key or not dispatcher:
        return None

    # Resolve full paths for nothingless commands
    if dispatcher == "exec":
        argument = nothingless_path(argument)

    mods_str = " ".join(modifiers) if modifiers else ""

    # Mouse binds with "m" flag
    if "m" in flags:
        # If action has a conf_dispatcher override (e.g. resizeactive), use bind
        conf_disp = ""
        if action_entry:
            conf_disp = action_entry.get("conf_dispatcher", "")
        if conf_disp:
            # Mouse resize: use bind + the conf dispatcher (e.g. resizeactive)
            if not mods_str:
                return f"bind = , {key}, {conf_disp}"
            return f"bind = {mods_str}, {key}, {conf_disp}"
        # Mouse move: use bindm (no dispatcher, it's native hyprland)
        if not mods_str:
            return f"bindm = , {key}"
        return f"bindm = {mods_str}, {key}"

    # Flags → bind type string (alphabetical order: e, l, r)
    bind_type = "bind"
    flag_chars = ""
    for f_char in ("e", "l", "r"):
        if f_char in flags:
            flag_chars += f_char
    if flag_chars:
        bind_type = "bind" + flag_chars

    arg_part = f", {argument}" if argument else ""
    if not mods_str:
        return f"{bind_type} = , {key}, {dispatcher}{arg_part}"
    return f"{bind_type} = {mods_str}, {key}, {dispatcher}{arg_part}"


def build_lua_bind(modifiers, key, dispatcher, argument, flags):
    """Build a hyprland.lua hl.bind() call using the dictionary's dispatcher map."""
    if not key or not dispatcher:
        return None

    # Resolve full paths for nothingless commands
    if dispatcher == "exec":
        argument = nothingless_path(argument)

    # ── Build key string ──
    if modifiers:
        key_str = " + ".join(modifiers) + " + " + key
    else:
        key_str = key

    # ── Build Lua dispatcher expression from dictionary ──
    disp_entry = DICT.get("dispatchers", {}).get(dispatcher)
    if disp_entry:
        lua_template = disp_entry["lua"]
        if disp_entry.get("arg", False):
            lua_expr = lua_template.replace("{arg}", escape_lua(argument) if argument else "")
        else:
            lua_expr = lua_template
    else:
        # Unknown dispatcher — log warning and skip Lua output for this bind
        print(f"WARNING: No Lua mapping for dispatcher '{dispatcher}'. "
              f"Add it to hyprlang-dict.toml [dispatchers] section.", file=sys.stderr)
        return None

    # ── Build flags options from dictionary ──
    flag_dict = DICT.get("binds_flags", {})
    opts = []
    for flag_char, flag_info in flag_dict.items():
        if flag_char in flags:
            opts.append(flag_info["lua_option"])

    if opts:
        return f'hl.bind("{key_str}", {lua_expr}, {{ {", ".join(opts)} }})'
    else:
        return f'hl.bind("{key_str}", {lua_expr})'


def build_toml_bind(modifiers, key, dispatcher, argument, flags):
    """Build a TOML [[keybinds]] block."""
    if not key or not dispatcher:
        return None
    if dispatcher == "exec":
        argument = nothingless_path(argument)

    mods_s = json.dumps(modifiers or [])
    key_s  = json.dumps(key)
    disp_s = json.dumps(dispatcher)
    arg_s  = json.dumps(argument or "")
    flag_s = json.dumps(flags or "")

    return (
        "[[keybinds]]\n"
        f"modifiers = {mods_s}\n"
        f"key = {key_s}\n"
        f"dispatcher = {disp_s}\n"
        f"argument = {arg_s}\n"
        f"flags = {flag_s}\n"
        "enabled = true\n"
    )


def process_binds(bind_section, seen_conf, seen_lua, seen_toml):
    """Process a list of bind definitions → conf lines, lua lines, toml blocks."""
    conf_lines = []
    lua_lines  = []
    toml_blocks = []

    for bind in bind_section:
        if not bind:
            continue

        # Skip disabled custom binds — they must not appear in conf/lua output
        if bind.get("enabled") is False:
            continue

        keys   = bind.get("keys", [bind])  # support both {keys:[...]} and flat
        actions = bind.get("actions", [bind.get("action", {})])

        # If flat bind (core binds), wrap
        if not isinstance(keys, list):
            keys = [keys]
        if not isinstance(actions, list):
            actions = [actions]

        for key_obj in keys:
            if not key_obj or not key_obj.get("key"):
                continue
            for action in actions:
                resolved = resolve_action(action)
                if not resolved:
                    continue
                disp, arg, flg, entry = resolved

                cl = build_conf_bind(key_obj.get("modifiers", []), key_obj["key"], disp, arg, flg, entry)
                ll = build_lua_bind(key_obj.get("modifiers", []), key_obj["key"], disp, arg, flg)
                tl = build_toml_bind(key_obj.get("modifiers", []), key_obj["key"], disp, arg, flg)

                if cl and cl not in seen_conf:
                    seen_conf.add(cl)
                    conf_lines.append(cl)
                if ll and ll not in seen_lua:
                    seen_lua.add(ll)
                    lua_lines.append(ll)
                if tl and tl not in seen_toml:
                    seen_toml.add(tl)
                    toml_blocks.append(tl)

    return conf_lines, lua_lines, toml_blocks


def build_all_binds():
    """Build keybind blocks for all 3 output formats."""
    seen_conf = set()
    seen_lua  = set()
    seen_toml = set()

    all_conf = []
    all_lua  = []
    all_toml = []

    nl = binds_data.get("nothingless", {})

    # ── Core binds ──
    for key_name in ["launcher", "spotlight", "dashboard", "assistant", "clipboard", "emoji",
                      "notes", "tmux", "wallpapers"]:
        b = nl.get(key_name)
        if not b:
            continue
        cl, ll, tl = process_binds([b], seen_conf, seen_lua, seen_toml)
        all_conf += cl; all_lua += ll; all_toml += tl

    # ── System binds ──
    sys = nl.get("system", {})
    for key_name in ["overview", "powermenu", "config", "lockscreen", "tools",
                      "screenshot", "screenrecord", "lens", "reload", "quit", "toggle-metrics"]:
        b = sys.get(key_name)
        if not b:
            continue
        action = b.get("action", {})
        if key_name == "lockscreen" and action.get("id") == "system.lock":
            action = {"id": "nothingless.lock", "args": {}}
            b["action"] = action
            # Update the in-memory data (don't mutate the file — too fragile)
            print(f"Warning: lockscreen bind references 'system.lock' instead of 'nothingless.lock'")
            print(f"  → Please update binds.json manually or add [actions.system_lock] to the dictionary")
        cl, ll, tl = process_binds([b], seen_conf, seen_lua, seen_toml)
        all_conf += cl; all_lua += ll; all_toml += tl

    # ── Custom binds ──
    custom = binds_data.get("custom", [])
    if custom:
        cl, ll, tl = process_binds(custom, seen_conf, seen_lua, seen_toml)
        all_conf += cl; all_lua += ll; all_toml += tl

    # ── Free Layout extra binds ──
    if cfg.get("layout") == "free":
        free = DICT.get("binds_free_layout", {})
        for k, v in free.items():
            if v["conf"] not in seen_conf:
                seen_conf.add(v["conf"])
                all_conf.append(v["conf"])
            if v["lua"] not in seen_lua:
                seen_lua.add(v["lua"])
                all_lua.append(v["lua"])

    # ── Wrap in marker blocks ──
    conf_block = ""
    lua_block  = ""
    toml_block = ""

    if all_conf:
        conf_block = "# === NOTHINGLESS KEYBINDS ===\n# Synced from NothingLess binds.json\n"
        conf_block += "\n".join(all_conf) + "\n# === END KEYBINDS ===\n"

    if all_lua:
        lua_block = "-- === NOTHINGLESS KEYBINDS ===\n-- Synced from NothingLess binds.json\n"
        lua_block += "\n".join(all_lua) + "\n-- === END KEYBINDS ===\n"

    if all_toml:
        toml_block = "# === NOTHINGLESS KEYBINDS ===\n# Synced from NothingLess binds.json\n\n"
        toml_block += "\n".join(all_toml) + "\n# === END KEYBINDS ===\n"

    return conf_block, lua_block, toml_block



# ═══════════════════════════════════════════════════════════════════════════
#  SECTION B — BUILD COMPOSITOR CONFIG  (hyprland.conf + hyprland.lua)
#  ═══════════════════════════════════════════════════════════════════════════
#
#  All mapping is driven by hyprlang-dict.toml.  Nothing is hardcoded here.
#  Each TOML entry carries:
#    nothingless_key — key in compositor.json (auto-derived or explicit)
#    conf            — full hyprland.conf path  (e.g. "decoration:shadow:enabled")
#    lua             — full hyprland.lua path   (e.g. "decoration.shadow.enabled")
#    type            — value type for formatting
#  The script simply walks every TOML section, matches against compositor.json,
#  builds nested dicts from the paths, and renders them.
# ═══════════════════════════════════════════════════════════════════════════


def _derive_nothingless_key(lua_path):
    """Derive compositor.json camelCase key from a TOML lua path."""
    if not lua_path:
        return ""
    parts = lua_path.split(".")
    if len(parts) >= 3:
        key_parts = parts[-2:]
    else:
        key_parts = [parts[-1]]
    result = ""
    for i, segment in enumerate(key_parts):
        words = segment.split("_")
        for j, word in enumerate(words):
            if not word:
                continue
            if i == 0 and j == 0:
                result += word
            else:
                result += word[0].upper() + word[1:]
    return result


def _walk_dict_sections():
    """Walk ALL TOML sections and return augmented entries.

    Returns: {section_name: [(dict_key, augmented_entry_dict), ...]}
    Each entry is augmented with nothingless_key, conf_keyword, lua_path.
    Skips non-dict sections (dispatchers, binds_flags, actions).
    """
    SKIP_SECTIONS = {"dispatchers", "binds_flags", "actions", "global_rules",
                     "layer_rules", "binds_free_layout", "config_order", "config_derived",
                     "gesture_bindings", "free_layout_rules"}
    tree = {}
    for section_name, section_data in DICT.items():
        if section_name in SKIP_SECTIONS or not isinstance(section_data, dict):
            continue
        entries = []
        for dict_key, entry in section_data.items():
            if not isinstance(entry, dict):
                continue
            aug = dict(entry)
            if "nothingless_key" not in aug:
                aug["nothingless_key"] = _derive_nothingless_key(entry.get("lua", ""))
            if "conf_keyword" not in aug:
                aug["conf_keyword"] = entry.get("conf", "")
            if "lua_path" not in aug:
                aug["lua_path"] = entry.get("lua", "")
            entries.append((dict_key, aug))
        if entries:
            tree[section_name] = entries
    return tree


def _build_color_map():
    """Build a comprehensive color map from TOML color_defaults + all theme files.
    
    Merges TOML color_defaults with ALL theme JSON color definitions (Material 3 tokens).
    Theme tokens take priority for hyprland border colors (primary, surfaceContainer, etc.).
    """
    color_map = {}
    # 1. TOML color_defaults (highest priority for explicitly defined colors)
    toml_defaults = DICT.get("color_defaults", {})
    for name, entry in toml_defaults.items():
        if isinstance(entry, dict) and "hex" in entry:
            color_map[name] = entry["hex"]
    # 2. Generated colors cache (active theme — highest priority after TOML defaults)
    cache_colors_path = os.path.expanduser("~/.cache/nothingless/colors.json")
    if os.path.isfile(cache_colors_path):
        try:
            with open(cache_colors_path) as f:
                cache_colors = json.load(f)
            for token, hex_val in cache_colors.items():
                if isinstance(hex_val, str) and (hex_val.startswith("#") or hex_val.startswith("0x")):
                    if token not in color_map:
                        color_map[token] = hex_val
        except (json.JSONDecodeError, OSError):
            pass
    # 3. Theme JSON files — walk all theme directories (fallback for missing tokens)
    colors_dir = os.path.expanduser("~/.config/nothingless/colors")
    if os.path.isdir(colors_dir):
        for theme_name in os.listdir(colors_dir):
            theme_dir = os.path.join(colors_dir, theme_name)
            if not os.path.isdir(theme_dir):
                continue
            for mode_file in ["light.json", "dark.json"]:
                path = os.path.join(theme_dir, mode_file)
                if not os.path.isfile(path):
                    continue
                try:
                    with open(path) as f:
                        theme = json.load(f)
                    for token, hex_val in theme.items():
                        if isinstance(hex_val, str) and (hex_val.startswith("#") or hex_val.startswith("0x")):
                            # Don't override TOML defaults or cache with theme values
                            if token not in color_map:
                                color_map[token] = hex_val
                except (json.JSONDecodeError, OSError):
                    continue
    return color_map


_COLOR_MAP_CACHE = None


def _resolve_color(value):
    """Resolve symbolic color names to hex using ALL available color definitions.
    Checks TOML color_defaults first, then theme JSON files.
    Returns the original value if no mapping exists.
    Converts #RRGGBB → 0xffRRGGBB (hyprland expects 0x prefix, not #).
    """
    if not isinstance(value, str):
        return value
    global _COLOR_MAP_CACHE
    if _COLOR_MAP_CACHE is None:
        _COLOR_MAP_CACHE = _build_color_map()
    resolved = _COLOR_MAP_CACHE.get(value, value)
    # Convert #RRGGBB to 0xffRRGGBB (hyprland color format with alpha)
    if resolved.startswith("#") and len(resolved) == 7:
        resolved = "0xff" + resolved[1:]
    elif resolved.startswith("#") and len(resolved) == 9:
        # #AARRGGBB → 0xAARRGGBB (just replace prefix)
        resolved = "0x" + resolved[1:]
    return resolved


def _is_hex_color(val):
    """Check if a value looks like a valid hex color (starts with 0x or #)."""
    if isinstance(val, str):
        return val.startswith("0x") or val.startswith("#")
    if isinstance(val, list):
        return all(_is_hex_color(v) for v in val)
    return False


def _is_sync_disabled(compositor_json, nothingless_key):
    """Check if a setting should be excluded from config output.
    
    When sync flag is True: composite.json value IS synced → include in output.
    When sync flag is False: composite.json value is NOT synced → exclude.
    """
    SYNC_FLAGS = {
        "syncBorderWidth": {"borderSize"},
        "syncBorderColor": {"activeBorderColor", "inactiveBorderColor"},
        "syncRoundness": {"rounding", "roundingPower"},
        "syncShadowColor": {"shadowColor", "shadowColorInactive"},
    }
    for flag, blocked_keys in SYNC_FLAGS.items():
        if nothingless_key in blocked_keys:
            # False = sync disabled = theme doesn't provide it = exclude from output
            return not compositor_json.get(flag, True)
    return False


def _build_config_tree(compositor_json, output="conf"):
    """Build a nested dict from TOML entries that match compositor.json.

    Uses conf paths (colon-separated) for structure.
    Leaf values are dicts: {"value": actual_value, "type": entry_type}
    to allow type-aware formatting (e.g., gradients).

    Skips color/gradient values that are symbolic theme names
    (e.g. "primary", "surfaceContainer") — those are resolved at
    runtime by the NothingLess shell, not written to config files.

    When output="conf", entries with conf_skip=true are excluded.
    """
    tree = {}
    _is_layout_free = compositor_json.get("layout", "") == "free"
    for section_name, entries in _walk_dict_sections().items():
        # Skip layout-specific sections when that layout is not active
        if section_name == "free" and not _is_layout_free:
            continue
        if section_name in ("dwindle", "master", "scrolling") and _is_layout_free:
            continue
        for _dict_key, entry in entries:
            # Skip entries marked as conf-only incompatible
            if output == "conf" and entry.get("conf_skip", False):
                continue
            nk = entry.get("nothingless_key")
            if not nk or nk not in compositor_json:
                continue
            # Skip layout directive when it's "free" (not a real Hyprland layout)
            if nk == "layout" and compositor_json[nk] == "free":
                continue
            val = compositor_json[nk]
            etype = entry.get("type", "")
            # Resolve known symbolic color names (e.g. "shadow" -> "0xee1a1a1a")
            if etype == "color":
                if isinstance(val, str):
                    val = _resolve_color(val)
                elif isinstance(val, list):
                    val = [_resolve_color(v) for v in val]
            # Resolve symbolic names inside gradient lists
            if etype == "gradient" and isinstance(val, list):
                val = [_resolve_color(v) if isinstance(v, str) else v for v in val]
            # Skip symbolic theme colors that COULDN'T be resolved to hex
            if etype in ("color", "gradient") and not _is_hex_color(val):
                continue
            # Apply conf value maps (e.g. string → int for .conf-specific types)
            # Only for .conf output; Lua keeps the original string values
            conf_map = entry.get("conf_map", {})
            if output == "conf" and conf_map and val in conf_map:
                val = conf_map[val]
                # Update etype to match the mapped value type (int→int, etc.)
                if isinstance(val, bool):
                    etype = "bool"
                elif isinstance(val, int):
                    etype = "int"
                elif isinstance(val, float):
                    etype = "float"
            # Skip empty values (e.g. empty string for optional fields)
            # Fix vec2 values stored as corrupt strings (e.g. "\x00\x04" → [0, 4])
            if etype == "vec2" and isinstance(val, str):
                # Try to parse the string as space-separated numbers
                cleaned = val.replace("\x00", " ").replace("\x04", " ")
                cleaned = " ".join(cleaned.split())  # normalize whitespace
                if cleaned:
                    try:
                        nums = [int(x) for x in cleaned.split()]
                        val = nums if nums else [0, 0]
                    except ValueError:
                        val = [0, 0]
                else:
                    # Interpret control byte values directly (e.g. \x00=0, \x04=4)
                    nums = [ord(c) for c in val if ord(c) < 0x20]
                    val = nums if nums else [0, 0]
            if val == "" or val is None:
                continue
            # Sync flags control NothingLess runtime behavior, NOT config output.
            # All compositor.json values are always written to generated files.
            # (Sync flags removed from filtering — they're for the NothingLess shell)
            conf_path = entry.get("conf", "")
            if not conf_path:
                # Fallback: use lua path for Lua-only settings
                lua_path = entry.get("lua", "")
                if lua_path:
                    conf_path = lua_path.replace(".", ":")
                else:
                    continue
            parts = conf_path.split(":")
            if len(parts) < 2:
                continue
            # Navigate to the parent, then set the leaf value
            node = tree.setdefault(parts[0], {})
            for p in parts[1:-1]:
                node = node.setdefault(p, {})
            meta = {"type": entry.get("type", "")}
            # Pass angle key so gradient formatters can use active/inactive angles
            if nk == "activeBorderColor":
                meta["angle_key"] = "borderAngle"
            elif nk == "inactiveBorderColor":
                meta["angle_key"] = "inactiveBorderAngle"
            node[parts[-1]] = {"value": val, **meta}
    return tree


def _fmt_conf_val(val, meta=None):
    """Format a Python value as a hyprland.conf literal.
    If meta contains 'type': gradient lists get angle from compositor.json.
    vec2 lists are formatted as space-separated values (no angle).
    """
    if isinstance(val, bool):
        return "true" if val else "false"
    if isinstance(val, list):
        if len(val) == 1:
            return str(val[0])
        # Check type from meta (leaf dict carried from _build_config_tree)
        etype = (meta or {}).get("type", "") if isinstance(meta, dict) else ""
        if etype in ("vec2", "int", "float"):
            # vec2/coordinates: space-separated values, NO angle
            return " ".join(str(x) for x in val)
        # Gradient: use angle from config (respect active vs inactive)
        angle_key = (meta or {}).get("angle_key") if isinstance(meta, dict) else None
        angle = cfg.get(angle_key, 45) if angle_key else cfg.get("borderAngle", 45)
        return " ".join(str(x) for x in val) + f" {angle}deg"
    if isinstance(val, float):
        s = f"{val:.2f}".rstrip("0").rstrip(".")
        return s if "." in s else s + ".0"
    s = str(val)
    # Sanitize control characters (null → 0, others → space)
    sanitized = []
    for ch in s:
        if ch == "\x00":
            sanitized.append("0")
        elif ord(ch) < 0x20 and ch not in ("\t", "\n", "\r"):
            sanitized.append(" ")
        else:
            sanitized.append(ch)
    return "".join(sanitized).strip()


def _fmt_lua_val(val, meta=None):
    """Format a Python value as a Lua literal.
    If meta contains 'type': gradient lists produce {colors, angle} table.
    vec2 lists are formatted as { number, number } without angle.
    """
    if isinstance(val, bool):
        return "true" if val else "false"
    if isinstance(val, list):
        if len(val) == 1:
            return '"' + str(val[0]).replace("\\", "\\\\").replace('"', '\\"') + '"'
        # Check type from meta (leaf dict carried from _build_config_tree)
        etype = (meta or {}).get("type", "") if isinstance(meta, dict) else ""
        if etype in ("vec2", "int", "float"):
            # vec2/coordinates: plain table { x, y }, NO gradient angle
            return '{ ' + ', '.join(str(x) for x in val) + ' }'
        # Gradient: { colors = {...}, angle = N }
        colors = '{ "' + '", "'.join(str(x) for x in val) + '" }'
        angle_key = (meta or {}).get("angle_key") if isinstance(meta, dict) else None
        angle = cfg.get(angle_key, 45) if angle_key else cfg.get("borderAngle", 45)
        return f'{{ colors = {colors}, angle = {angle} }}'
    if isinstance(val, float):
        s = f"{val:.2f}".rstrip("0").rstrip(".")
        return s if "." in s else s + ".0"
    if isinstance(val, str):
        # Sanitize control characters before escaping
        clean = []
        for ch in val:
            if ch == "\x00":
                clean.append("0")
            elif ord(ch) < 0x20 and ch not in ("\t", "\n", "\r"):
                clean.append(" ")
            else:
                clean.append(ch)
        val = "".join(clean)
        return '"' + val.replace("\\", "\\\\").replace('"', '\\"') + '"'
    s = str(val)
    # Sanitize control characters
    sanitized = []
    for ch in s:
        if ch == "\x00":
            sanitized.append("0")
        elif ord(ch) < 0x20 and ch not in ("\t", "\n", "\r"):
            sanitized.append(" ")
        else:
            sanitized.append(ch)
    return "".join(sanitized).strip()


def _get_order(target):
    """Read section order for a given target ('conf' or 'lua') from TOML [config_order]."""
    order_cfg = DICT.get("config_order", {})
    sections = order_cfg.get(target, [])
    if not sections:
        # Fallback: use all tree keys in arbitrary dict order
        return list(tree.keys()) if 'tree' in dir() else []
    # Apply target-specific exclusions (e.g. layout-only keys for lua)
    exclude = order_cfg.get(target + "_exclude", [])
    return [s for s in sections if s not in exclude]


def _apply_derived_config(local_cfg):
    """Apply derived/computed config rules from TOML [config_derived].
    
    Reads the TOML [config_derived] section and applies rules to local_cfg.
    Each rule maps a compositor.json key to derived settings.
    Currently handles: smartResizeAnchors rule.
    """
    derived = DICT.get("config_derived", {})
    for rule_name, rule in derived.items():
        if not isinstance(rule, dict):
            continue
        trigger_key = rule.get("key")
        if not trigger_key or trigger_key not in local_cfg:
            continue
        trigger_val = local_cfg[trigger_key]
        target = rule.get("when_true", {}) if trigger_val else rule.get("when_false", {})
        for derived_key, derived_val in target.items():
            # Handle "max(N, current)" pattern
            if isinstance(derived_val, str) and derived_val.startswith("max("):
                m = re.match(r'max\((\d+),\s*current\)', derived_val)
                if m:
                    min_val = int(m.group(1))
                    current = local_cfg.get(derived_key, 0)
                    if isinstance(current, (int, float)):
                        local_cfg[derived_key] = max(current, min_val)
                    else:
                        local_cfg[derived_key] = min_val
                    continue
            local_cfg[derived_key] = derived_val
    return local_cfg


def _render_conf_tree(tree, target="conf"):
    """Render a nested config tree as hyprland.conf block syntax.
    
    Section order is read from TOML [config_order.conf] — no hardcoded order.
    """
    lines = ["# === NOTHINGLESS COMPOSITOR ===", "# Applied by NothingLess", ""]
    order = _get_order(target)

    def _write_section(name, data, indent=0):
        prefix = "  " * indent
        if not isinstance(data, dict):
            return
        lines.append(f"{prefix}{name} {{")
        for key, val in data.items():
            if isinstance(val, dict) and "value" in val:
                # Leaf with metadata
                lines.append(f"{prefix}  {key} = {_fmt_conf_val(val['value'], val)}")
            elif isinstance(val, dict):
                _write_section(key, val, indent + 1)
            else:
                lines.append(f"{prefix}  {key} = {_fmt_conf_val(val)}")
        lines.append(f"{prefix}}}")

    # Render sections in order, then append any remaining sections not in the list
    rendered = set()
    for section in order:
        if section in tree:
            _write_section(section, tree[section])
            lines.append("")
            rendered.add(section)
    for section in tree:
        if section not in rendered:
            _write_section(section, tree[section])
            lines.append("")

    lines.append("# === END COMPOSITOR ===")
    return "\n".join(lines) + "\n"


def _render_lua_tree(tree, target="lua"):
    """Render a nested config tree as hyprland.lua hl.config() block.
    
    Section order is read from TOML [config_order.lua] — no hardcoded order.
    Layout-only sections (dwindle, master, scrolling) are excluded since
    they are not valid in hl.config() Lua API.
    """
    import re as _re
    _LUA_ID = _re.compile(r'^[a-zA-Z_][a-zA-Z0-9_]*$')

    def _lua_key(k):
        """Quote key with [\"...\"] if not a valid Lua identifier."""
        if _LUA_ID.match(k):
            return k
        return f'["{k}"]'

    lines = [
        "-- === NOTHINGLESS COMPOSITOR ===",
        "-- NothingLess compositor settings",
        "hl.config({",
    ]
    order = _get_order(target)

    def _write_table(name, data, indent=4):
        prefix = " " * indent
        if not isinstance(data, dict):
            return
        lines.append(f"{prefix}{_lua_key(name)} = {{")
        for key, val in data.items():
            lk = _lua_key(key)
            if isinstance(val, dict) and "value" in val:
                # Leaf with metadata
                lines.append(f"{prefix}    {lk} = {_fmt_lua_val(val['value'], val)},")
            elif isinstance(val, dict):
                _write_table(key, val, indent + 4)
            else:
                lines.append(f"{prefix}    {lk} = {_fmt_lua_val(val)},")
        lines.append(f"{prefix}}},")

    # Get exclusion list (layout-only sections not valid in hl.config)
    order_cfg = DICT.get("config_order", {})
    exclude = set(order_cfg.get(target + "_exclude", []))

    rendered = set()
    for section in order:
        if section in tree and section not in exclude:
            _write_table(section, tree[section])
            rendered.add(section)
    for section in tree:
        if section not in rendered and section not in exclude:
            _write_table(section, tree[section])

    lines.append("})")
    lines.append("-- === END COMPOSITOR ===")
    return "\n".join(lines) + "\n"


def build_conf_compositor():
    """Build hyprland.conf compositor block — fully data-driven via TOML."""
    local_cfg = dict(cfg)
    _apply_derived_config(local_cfg)
    tree = _build_config_tree(local_cfg)
    result = _render_conf_tree(tree, target="conf")

    # Free layout: inject window rule from TOML dictionary
    if cfg.get("layout") == "free":
        rules = DICT.get("free_layout_rules", {})
        conf_rule = rules.get("conf", "").strip()
        if conf_rule:
            result = result.replace(
                "# === END COMPOSITOR ===",
                "# Free Layout: float all windows (Windows-style)\n"
                + conf_rule + "\n"
                "# === END COMPOSITOR ==="
            )

    return result


def build_lua_compositor():
    """Build hyprland.lua compositor block — fully data-driven via TOML."""
    local_cfg = dict(cfg)
    _apply_derived_config(local_cfg)
    tree = _build_config_tree(local_cfg, output="lua")
    result = _render_lua_tree(tree, target="lua")

    # Free layout: inject window rule from TOML dictionary
    if cfg.get("layout") == "free":
        rules = DICT.get("free_layout_rules", {})
        lua_rule = rules.get("lua", "").strip()
        if lua_rule:
            result = result.replace(
                "-- === END COMPOSITOR ===",
                "-- Free Layout: float all windows (Windows-style)\n"
                + lua_rule + "\n"
                "-- === END COMPOSITOR ==="
            )

    return result

def build_toml_compositor():
    """Build a minimal axctl.toml compositor block."""
    lines = ["# === NOTHINGLESS COMPOSITOR ===", "# Synced from compositor.json", ""]

    _is_free = cfg.get("layout") == "free"

    def tv(val):
        if isinstance(val, bool):
            return "true" if val else "false"
        if isinstance(val, float):
            s = f"{val:.2f}".rstrip("0").rstrip(".")
            return s if "." in s else s + ".0"
        if isinstance(val, str):
            return '"' + val.replace("\\", "\\\\").replace('"', '\\"') + '"'
        return str(val)

    if "gapsIn" in cfg or "gapsOut" in cfg:
        lines.append("[appearance.gaps]")
        if "gapsIn" in cfg: lines.append(f"inner = {cfg['gapsIn']}")
        if "gapsOut" in cfg: lines.append(f"outer = {cfg['gapsOut']}")
        lines.append("")

    lines.append("[appearance.border]")
    if "borderSize" in cfg: lines.append(f"width = {cfg['borderSize']}")
    if "rounding" in cfg: lines.append(f"rounding = {cfg['rounding']}")
    if "roundingPower" in cfg: lines.append(f"rounding_power = {cfg['roundingPower']:.1f}")
    lines.append("")

    lines.append("[appearance.opacity]")
    if "activeOpacity" in cfg: lines.append(f"active = {cfg['activeOpacity']:.2f}")
    if "inactiveOpacity" in cfg: lines.append(f"inactive = {cfg['inactiveOpacity']:.2f}")
    if "fullscreenOpacity" in cfg: lines.append(f"fullscreen = {cfg['fullscreenOpacity']:.2f}")
    lines.append("")

    lines.append("[appearance.dim]")
    if "dimInactive" in cfg: lines.append(f"enabled = {tv(cfg['dimInactive'])}")
    if "dimStrength" in cfg: lines.append(f"strength = {cfg['dimStrength']:.2f}")
    if "dimAround" in cfg: lines.append(f"around = {cfg['dimAround']:.2f}")
    if "dimSpecial" in cfg: lines.append(f"special = {cfg['dimSpecial']:.2f}")
    lines.append("")

    lines.append("[appearance.blur]")
    if "blurEnabled" in cfg: lines.append(f"enabled = {tv(cfg['blurEnabled'])}")
    if "blurSize" in cfg: lines.append(f"size = {cfg['blurSize']}")
    if "blurPasses" in cfg: lines.append(f"passes = {cfg['blurPasses']}")
    lines.append("")

    lines.append("[appearance.shadow]")
    if "shadowEnabled" in cfg: lines.append(f"enabled = {tv(cfg['shadowEnabled'])}")
    if "shadowRange" in cfg: lines.append(f"range = {cfg['shadowRange']}")
    lines.append("")

    lines.append("[appearance.animations]")
    if "animationsEnabled" in cfg: lines.append(f"enabled = {tv(cfg['animationsEnabled'])}")
    lines.append("")

    lines.append("[general]")
    if "layout" in cfg and not _is_free: lines.append(f"layout = {tv(cfg['layout'])}")
    if "allowTearing" in cfg: lines.append(f"allow_tearing = {tv(cfg['allowTearing'])}")
    if "resizeOnBorder" in cfg: lines.append(f"resize_on_border = {tv(cfg['resizeOnBorder'])}")
    lines.append("")

    lines.append("[general.snap]")
    if "snapEnabled" in cfg: lines.append(f"enabled = {tv(cfg['snapEnabled'])}")
    if "snapWindowGap" in cfg: lines.append(f"window_gap = {cfg['snapWindowGap']}")
    if "snapMonitorGap" in cfg: lines.append(f"monitor_gap = {cfg['snapMonitorGap']}")
    lines.append("")

    # Free Layout (only when active)
    if _is_free:
        lines.append("[general.free]")
        if "freeGridSize" in cfg: lines.append(f"grid_size = {cfg['freeGridSize']}")
        if "freeSnapSensitivity" in cfg: lines.append(f"snap_sensitivity = {cfg['freeSnapSensitivity']}")
        if "freeSnapEdges" in cfg: lines.append(f"snap_edges = {tv(cfg['freeSnapEdges'])}")
        if "freeSnapCenter" in cfg: lines.append(f"snap_center = {tv(cfg['freeSnapCenter'])}")
        if "freeSnapGaps" in cfg: lines.append(f"snap_gaps = {cfg['freeSnapGaps']}")
        if "freeTileByDefault" in cfg: lines.append(f"tile_by_default = {tv(cfg['freeTileByDefault'])}")
        if "freeMaximizedByDefault" in cfg: lines.append(f"maximized_by_default = {tv(cfg['freeMaximizedByDefault'])}")
        lines.append("")

    lines.append("# === END COMPOSITOR ===")
    return "\n".join(lines) + "\n"


# ═══════════════════════════════════════════════════════════════════════════
#  SECTION C — BUILD GESTURE BINDINGS  (hyprland.lua + axctl.toml)
#  ═══════════════════════════════════════════════════════════════════════════
#
#  Reads [gesture_bindings] from hyprlang-dict.toml.
#  Each entry maps a compositor.json boolean toggle to hl.gesture() blocks.
#  Supports conf_action (built-in), conf_dispatcher/conf_argument (custom,
#  keyword "dispatcher" without colon per ConfigManager.cpp),
#  lua_action/lua_dispatcher, and toml_action/toml_dispatcher.
#  Nothing is hardcoded — the dictionary defines fingers, direction, and actions.
# ═══════════════════════════════════════════════════════════════════════════

def build_gesture_binds():
    """Build gesture binding blocks for .conf, .lua, and .toml output.
    
    Reads [gesture_bindings] from the TOML dictionary and checks compositor.json
    for the corresponding nothingless_key boolean. If true, generates the gesture
    binding in each output format.
    
    Returns (conf_block, lua_block, toml_block) strings.
    """
    gb_section = DICT.get("gesture_bindings", {})
    if not gb_section:
        return "", "", ""
    
    conf_lines = []
    lua_lines  = []
    toml_blocks = []

    # Hyprland matches gestures first-come-first-served. Generic directions
    # ('swipe', 'pinch') match the same axis as specific ones (up/down/left/right),
    # so a generic gesture declared before a specific one will overshadow it and
    # Hyprland will log "Gesture will be overshadowed by a previous gesture".
    # We therefore emit all specific-direction gestures before generic ones.
    GENERIC_GESTURE_DIRS = {"swipe", "pinch"}

    def _gesture_sort_key(item):
        key, gb = item
        fingers = gb.get("fingers", 0)
        direction = gb.get("direction", "")
        is_generic = 1 if direction in GENERIC_GESTURE_DIRS else 0
        return (is_generic, fingers, direction, key)

    for _key, gb in sorted(gb_section.items(), key=_gesture_sort_key):
        if not isinstance(gb, dict):
            continue
        
        nk = gb.get("nothingless_key", "")
        if not nk or not cfg.get(nk, False):
            continue
        
        fingers   = gb.get("fingers", 0)
        direction = gb.get("direction", "")
        if not fingers or not direction:
            continue
        
        # ── .conf format (hyprlang single-line) ────────────────────
        # Hyprland 0.55+ still supports the legacy 'gesture' keyword.
        # Syntax: gesture = <fingers>, <direction>, <action>[, <opts>]
        # Built-in:  gesture = 3, swipe, move
        # Dispatcher: gesture = 4, up, dispatcher, exec, nothingless run overview
        #             (keyword "dispatcher" — NO colon — per ConfigManager.cpp)
        # Specific directions must be declared before generic 'swipe'/'pinch'
        # to avoid "Gesture will be overshadowed by a previous gesture".
        conf_action     = gb.get("conf_action", "")
        conf_dispatcher = gb.get("conf_dispatcher", "")
        conf_argument   = gb.get("conf_argument", "")

        if conf_dispatcher:
            if conf_argument:
                arg_processed = nothingless_path(conf_argument) if conf_dispatcher == "exec" else conf_argument
                conf_lines.append(
                    f"gesture = {fingers}, {direction}, dispatcher, {conf_dispatcher}, {arg_processed}"
                )
            else:
                conf_lines.append(
                    f"gesture = {fingers}, {direction}, dispatcher, {conf_dispatcher}"
                )
        elif conf_action:
            conf_lines.append(
                f"gesture = {fingers}, {direction}, {conf_action}"
            )
        
        # ── .lua format ──────────────────────────────────────────
        lua_action     = gb.get("lua_action", "")
        lua_dispatcher = gb.get("lua_dispatcher", "")
        lua_argument   = gb.get("lua_argument", "")
        
        if lua_action:
            # Built-in action: hl.gesture({ fingers = 3, direction = "swipe", action = "move" })
            lua_lines.append(
                f'hl.gesture({{ fingers = {fingers}, direction = "{direction}", action = "{lua_action}" }})'
            )
        elif lua_dispatcher:
            # Custom dispatcher: wrap dispatcher call in a function.
            # The dispatcher lua template IS the function call (e.g. "hl.dsp.exec_cmd('...')"
            # or "hl.dsp.focus({ workspace = '...' })") — call it directly, no hl.dispatch wrapper.
            arg_escaped = escape_lua(nothingless_path(lua_argument) if lua_dispatcher == "exec" else lua_argument)
            disp_entry = DICT.get("dispatchers", {}).get(lua_dispatcher)
            if disp_entry:
                lua_template = disp_entry["lua"]
                if disp_entry.get("arg", False):
                    lua_expr = lua_template.replace("{arg}", arg_escaped)
                else:
                    lua_expr = lua_template
            else:
                # Fallback: direct hl.dsp call
                lua_expr = f'hl.dsp.{lua_dispatcher}("{arg_escaped}")'

            lua_lines.append(
                f'hl.gesture({{ fingers = {fingers}, direction = "{direction}", '
                f'action = function()\n'
                f'    {lua_expr}\n'
                f'end }})'
            )
        
        # ── .toml format ──────────────────────────────────────────
        toml_action     = gb.get("toml_action", "")
        toml_dispatcher = gb.get("toml_dispatcher", "")
        toml_argument   = gb.get("toml_argument", "")
        
        block = "[[gestures]]\n"
        block += f"fingers = {fingers}\n"
        block += f'direction = "{direction}"\n'
        
        if toml_action:
            block += f'action = "{toml_action}"\n'
        elif toml_dispatcher:
            if toml_dispatcher == "exec":
                toml_argument = nothingless_path(toml_argument)
            block += f'dispatcher = "{toml_dispatcher}"\n'
            block += f'argument = "{toml_argument}"\n'
        
        toml_blocks.append(block)
    
    # ── Wrap in marker blocks ──
    # Gestures must be emitted in EXACTLY ONE output. They are applied at
    # runtime by axctl via [[gestures]] blocks in axctl.toml, so emitting
    # them in .conf/.lua as well causes Hyprland to register the same
    # gesture twice ("previous UP shadows new UP").
    conf_block = ""
    lua_block  = ""

    toml_block = ""
    if toml_blocks:
        toml_block = "# === NOTHINGLESS GESTURES ===\n# Synced from NothingLess compositor.json\n\n"
        toml_block += "\n".join(toml_blocks) + "\n# === END GESTURES ===\n"

    return conf_block, lua_block, toml_block


# ═══════════════════════════════════════════════════════════════════════════
#  MAIN — BUILD & WRITE
# ═══════════════════════════════════════════════════════════════════════════

def _inject_block(content, marker, end_marker, new_block):
    """Replace or inject a marked block in existing content.

    Uses safe line-by-line scanning instead of regex DOTALL.
    This avoids catastrophic deletion when an END marker is missing
    due to a partial/aborted write — unmatched markers simply stop
    skipping at EOF without consuming other sections.
    """
    marker_stripped = marker.strip()
    end_stripped = end_marker.strip()
    lines = content.split('\n')
    result = []
    skip = False
    for line in lines:
        stripped = line.strip()
        if stripped == marker_stripped:
            skip = True
            continue
        if skip and stripped == end_stripped:
            skip = False
            continue
        if not skip:
            result.append(line)

    content = '\n'.join(result).strip()

    if new_block:
        if content:
            content += '\n' + new_block
        else:
            content = new_block
    return content


def live_apply():
    """Apply compositor settings live via axctl (no file writes).
    
    Uses the same TOML mapping as Sync-hyprland.py — NO duplicated logic.
    """
    kw_map = []
    for section_name, entries in _walk_dict_sections().items():
        for _dict_key, entry in entries:
            nk = entry.get("nothingless_key")
            if not nk or nk not in cfg:
                continue
            val = cfg[nk]
            etype = entry.get("type", "")
            # Resolve known symbolic color names
            if etype == "color":
                if isinstance(val, str):
                    val = _resolve_color(val)
                elif isinstance(val, list):
                    val = [_resolve_color(v) for v in val]
            if etype == "gradient" and isinstance(val, list):
                val = [_resolve_color(v) if isinstance(v, str) else v for v in val]
            # Skip symbolic theme colors (non-hex strings that couldn't be resolved)
            if etype in ("color", "gradient") and not _is_hex_color(val):
                continue
            if val == "" or val is None:
                continue
            conf_path = entry.get("conf", "")
            if not conf_path:
                lua_path = entry.get("lua", "")
                if lua_path:
                    conf_path = lua_path.replace(".", ":")
                else:
                    continue
            kw_map.append((conf_path, val, etype))
    
    if not kw_map:
        print("axctl: no settings to apply")
        return
    
    kv_pairs = {}
    for kw, val, etype in kw_map:
        # Pass etype as meta so _fmt_conf_val can distinguish vec2 from gradient
        val_str = _fmt_conf_val(val, {"type": etype})
        kv_pairs[kw] = val_str
    
    json_input = json.dumps(kv_pairs, indent=2)
    try:
        import subprocess
        r = subprocess.run(["axctl", "config", "batch", "-"],
                          input=json_input,
                          capture_output=True, text=True)
        if r.returncode == 0:
            print(f"axctl: {len(kv_pairs)} settings applied")
        else:
            err_detail = r.stderr.strip() if r.stderr else "no stderr"
            print(f"axctl: batch failed (exit {r.returncode}): {err_detail}", file=sys.stderr)
            first_keys = list(kv_pairs.keys())[:5]
            print(f"  First 5 keys sent: {first_keys}", file=sys.stderr)
            print(f"  Full JSON: {json_input[:500]}...", file=sys.stderr)
    except FileNotFoundError:
        print("axctl: not found — live apply skipped", file=sys.stderr)
    except Exception as e:
        print(f"axctl: error — {e}", file=sys.stderr)


def main():
    do_apply = "--apply" in sys.argv
    binds_only = "--binds-only" in sys.argv

    os.makedirs(DATA_DIR, exist_ok=True)

    # ── Generate all blocks ──
    conf_compositor = "" if binds_only else build_conf_compositor()
    lua_compositor  = "" if binds_only else build_lua_compositor()
    toml_compositor = "" if binds_only else build_toml_compositor()
    binds_conf, binds_lua, binds_toml = build_all_binds()
    gestures_conf = gestures_lua = gestures_toml = ""
    if not binds_only:
        gestures_conf, gestures_lua, gestures_toml = build_gesture_binds()

    # ── hyprland.conf ──
    try:
        with open(CONF_PATH) as f:
            content = f.read()
    except FileNotFoundError:
        content = "# NothingLess Hyprland config\n"

    if binds_only:
        # Only touch the keybinds block — preserve compositor and gestures as-is
        content = _inject_block(content,
            "# === NOTHINGLESS KEYBINDS ===", "# === END KEYBINDS ===",
            binds_conf)
    else:
        content = _inject_block(content,
            "# === NOTHINGLESS COMPOSITOR ===", "# === END COMPOSITOR ===",
            conf_compositor)
        content = _inject_block(content,
            "# === NOTHINGLESS KEYBINDS ===", "# === END KEYBINDS ===",
            binds_conf)
        # Gestures intentionally not written to .conf — they live in
        # axctl.toml only, to avoid double-registration (see build_gesture_binds).
        # Strip any stale gesture block left over from earlier versions.
        content = _inject_block(content,
            "# === NOTHINGLESS GESTURES ===", "# === END GESTURES ===",
            "")

    with open(CONF_PATH, "w") as f:
        f.write(content)
    if binds_only:
        print(f"hyprland.conf: keybinds-only sync ({len(binds_conf)}c keybinds)")
    else:
        print(f"hyprland.conf: {len(conf_compositor)}c compositor + {len(binds_conf)}c keybinds + 0c gestures (axctl.toml only)")

    # ── hyprland.lua ──
    try:
        with open(LUA_PATH) as f:
            content = f.read()
    except FileNotFoundError:
        content = "-- NothingLess Hyprland config\n"

    # Clean stray hyprlang syntax from Lua file
    content = re.sub(
        r'^(?:exec-once|exec|bind[a-z]*|source|env|windowrule|layerrule)\s*=.*$',
        '', content, flags=re.MULTILINE
    )
    content = re.sub(r'\n{3,}', '\n\n', content).strip()

    if binds_only:
        content = _inject_block(content,
            "-- === NOTHINGLESS KEYBINDS ===", "-- === END KEYBINDS ===",
            binds_lua)
    else:
        content = _inject_block(content,
            "-- === NOTHINGLESS COMPOSITOR ===", "-- === END COMPOSITOR ===",
            lua_compositor)
        content = _inject_block(content,
            "-- === NOTHINGLESS KEYBINDS ===", "-- === END KEYBINDS ===",
            binds_lua)
        # Gestures intentionally not written to .lua — they live in
        # axctl.toml only, to avoid double-registration (see build_gesture_binds).
        # Strip any stale gesture block left over from earlier versions.
        content = _inject_block(content,
            "-- === NOTHINGLESS GESTURES ===", "-- === END GESTURES ===",
            "")

    with open(LUA_PATH, "w") as f:
        f.write(content)
    if binds_only:
        print(f"hyprland.lua: keybinds-only sync ({len(binds_lua)}c keybinds)")
    else:
        print(f"hyprland.lua: {len(lua_compositor)}c compositor + {len(binds_lua)}c keybinds + 0c gestures (axctl.toml only)")

    # ── axctl.toml ──
    try:
        with open(TOML_PATH) as f:
            toml_content = f.read()

        # Remove ALL old NothingLess section markers and content.
        # Uses safe line-by-line scanning — no DOTALL regex that could
        # consume user content when markers are malformed.
        for section_id in ["KEYBINDS", "COMPOSITOR", "GESTURES"]:
            start_marker = f"# === NOTHINGLESS {section_id} ==="
            end_marker = f"# === END {section_id} ==="
            toml_content = _inject_block(toml_content, start_marker, end_marker, "")

        # Remove legacy [appearance] and [[keybinds]] blocks (pre-NothingLess format).
        # These are one-time migration cleanups; once migrated they won't match.
        # We use line-by-line to avoid crossing TOML section boundaries.
        toml_lines = toml_content.split('\n')
        cleaned = []
        skip_legacy = False
        for line in toml_lines:
            stripped = line.strip()
            # Start skipping on legacy [appearance] or [[keybinds]] sections
            if stripped.startswith('[appearance]') or stripped.startswith('[[keybinds]]'):
                skip_legacy = True
                continue
            # Stop skipping at the next TOML section header or NothingLess marker
            if skip_legacy and (stripped.startswith('[') or stripped.startswith('# === NOTHINGLESS')):
                skip_legacy = False
            if not skip_legacy:
                cleaned.append(line)
        toml_content = '\n'.join(cleaned).strip()

        toml_content = toml_content.rstrip() + "\n\n"
        if toml_compositor:
            toml_content += toml_compositor.strip() + "\n"
        if binds_toml:
            toml_content += "\n" + binds_toml.strip() + "\n"
        if gestures_toml:
            toml_content += "\n" + gestures_toml.strip() + "\n"

        with open(TOML_PATH, "w") as f:
            f.write(toml_content)
        if binds_only:
            print(f"axctl.toml: keybinds-only sync ({len(binds_toml)}c keybinds)")
        else:
            print(f"axctl.toml: {len(toml_compositor)}c compositor + {len(binds_toml)}c keybinds + {len(gestures_toml)}c gestures")

    except FileNotFoundError:
        lines = []
        if toml_compositor:
            lines.append(toml_compositor)
        if binds_toml:
            lines.append(binds_toml.strip())
        if gestures_toml:
            lines.append(gestures_toml.strip())
        with open(TOML_PATH, "w") as f:
            f.write("\n\n".join(lines) + "\n")
        print(f"axctl.toml: CREATED ({len(toml_compositor)}c compositor)")

    # ── Re-inject monitors after compositor sync (skip in binds-only mode) ──
    if not binds_only:
        monitors_writer = os.path.join(SCRIPT_DIR, "monitors_writer.py")
        if os.path.isfile(monitors_writer):
            subprocess.run(["python3", monitors_writer, "sync", "--no-apply"],
                           capture_output=True, timeout=10)

    if do_apply:
        live_apply()
        print("Done — compositor config applied")
    elif binds_only:
        print("Done — keybinds synced to persistent files")
    else:
        print("Done — hyprctl reload & axctl config reload recommended")


if __name__ == "__main__":
    main()
