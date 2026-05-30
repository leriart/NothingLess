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

with open(COMPOSITOR_PATH) as f:
    cfg = json.load(f)

try:
    with open(BINDS_PATH) as f:
        binds_data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    binds_data = {}

# ═══════════════════════════════════════════════════════════════════════════
#  UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

def fmt_conf(val):
    """Format a Python value as a hyprland.conf literal."""
    if isinstance(val, bool):
        return "true" if val else "false"
    if isinstance(val, list):
        return " ".join(str(v) for v in val)
    if isinstance(val, float):
        s = f"{val:.2f}".rstrip("0").rstrip(".")
        return s if "." in s else s + ".0"
    return str(val)


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

    Returns (dispatcher, argument, flags) or None.
    """
    if not action:
        return None

    # Already resolved form
    if action.get("dispatcher"):
        return (action["dispatcher"], action.get("argument", ""), action.get("flags", ""))

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

    return (dispatcher, argument, flags)


def build_conf_bind(modifiers, key, dispatcher, argument, flags):
    """Build a hyprland.conf bind line using the dictionary's dispatcher names."""
    if not key or not dispatcher:
        return None

    # Resolve full paths for nothingless commands
    if dispatcher == "exec":
        argument = nothingless_path(argument)

    mods_str = " ".join(modifiers) if modifiers else ""

    # Mouse binds → bindm keyword
    if "m" in flags:
        arg_part = f", {argument}" if argument else ""
        if not mods_str:
            return f"bindm = , {key}, {dispatcher}{arg_part}"
        return f"bindm = {mods_str}, {key}, {dispatcher}{arg_part}"

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
                disp, arg, flg = resolved

                cl = build_conf_bind(key_obj.get("modifiers", []), key_obj["key"], disp, arg, flg)
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
    for key_name in ["launcher", "dashboard", "assistant", "clipboard", "emoji",
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
            try:
                with open(BINDS_PATH, "w") as f:
                    json.dump(binds_data, f, indent=2)
                print(f"Repaired lockscreen bind in {BINDS_PATH}: system.lock → nothingless.lock")
            except Exception as e:
                print(f"Warning: could not repair binds.json: {e}")
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
                     "layer_rules", "binds_free_layout"}
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


def _resolve_color(value):
    """Resolve symbolic color names to hex using TOML color_defaults.
    Returns the original value if no mapping exists."""
    if not isinstance(value, str):
        return value
    color_map = DICT.get("color_defaults", {})
    if value in color_map:
        return color_map[value].get("hex", value)
    return value


def _is_hex_color(val):
    """Check if a value looks like a valid hex color (starts with 0x or #)."""
    if isinstance(val, str):
        return val.startswith("0x") or val.startswith("#")
    if isinstance(val, list):
        return all(_is_hex_color(v) for v in val)
    return False


def _is_sync_disabled(compositor_json, nothingless_key):
    """Check if a setting should be skipped based on sync flags.
    
    compositor.json has flags like syncBorderWidth, syncRoundness, etc.
    When these are False, the corresponding settings are excluded.
    """
    SYNC_FLAGS = {
        "syncBorderWidth": {"borderSize"},
        "syncBorderColor": {"activeBorderColor", "inactiveBorderColor"},
        "syncRoundness": {"rounding", "roundingPower"},
        "syncShadowColor": {"shadowColor", "shadowColorInactive"},
    }
    for flag, blocked_keys in SYNC_FLAGS.items():
        if nothingless_key in blocked_keys:
            return not compositor_json.get(flag, True)
    return False


def _build_config_tree(compositor_json):
    """Build a nested dict from TOML entries that match compositor.json.

    Uses conf paths (colon-separated) for structure.
    Leaf values are dicts: {"value": actual_value, "type": entry_type}
    to allow type-aware formatting (e.g., gradients).

    Skips color/gradient values that are symbolic theme names
    (e.g. "primary", "surfaceContainer") — those are resolved at
    runtime by the NothingLess shell, not written to config files.
    """
    tree = {}
    for section_name, entries in _walk_dict_sections().items():
        for _dict_key, entry in entries:
            nk = entry.get("nothingless_key")
            if not nk or nk not in compositor_json:
                continue
            val = compositor_json[nk]
            etype = entry.get("type", "")
            # Resolve known symbolic color names (e.g. "shadow" -> "0xee1a1a1a")
            if etype == "color" and isinstance(val, str):
                val = _resolve_color(val)
            # Skip symbolic theme colors: "primary", "surfaceContainer", etc.
            # These are NothingLess theme references resolved at runtime by the shell
            if etype in ("color", "gradient") and not _is_hex_color(val):
                continue
            # Skip empty values (e.g. empty string for optional fields)
            if val == "" or val is None:
                continue
            # Honor sync flags: if syncBorderWidth=false, skip borderSize, etc.
            if _is_sync_disabled(compositor_json, nk):
                continue
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
            node[parts[-1]] = {"value": val, "type": entry.get("type", "")}
    return tree


def _fmt_conf_val(val, meta=None):
    """Format a Python value as a hyprland.conf literal.
    If meta contains 'type': gradient lists get angle from compositor.json.
    """
    if isinstance(val, bool):
        return "true" if val else "false"
    if isinstance(val, list):
        if len(val) == 1:
            return str(val[0])
        # Gradient: use angle from config
        angle = cfg.get("borderAngle", 45)
        return " ".join(str(x) for x in val) + f" {angle}deg"
    if isinstance(val, float):
        s = f"{val:.2f}".rstrip("0").rstrip(".")
        return s if "." in s else s + ".0"
    return str(val)


def _fmt_lua_val(val, meta=None):
    """Format a Python value as a Lua literal.
    If meta contains 'type': gradient lists produce {colors, angle} table.
    """
    if isinstance(val, bool):
        return "true" if val else "false"
    if isinstance(val, list):
        if len(val) == 1:
            return '"' + str(val[0]).replace("\\", "\\\\").replace('"', '\\"') + '"'
        # Gradient: { colors = {...}, angle = N }
        colors = '{ "' + '", "'.join(str(x) for x in val) + '" }'
        angle = cfg.get("borderAngle", 45)
        return f'{{ colors = {colors}, angle = {angle} }}'
    if isinstance(val, float):
        s = f"{val:.2f}".rstrip("0").rstrip(".")
        return s if "." in s else s + ".0"
    if isinstance(val, str):
        return '"' + val.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return str(val)


def _render_conf_tree(tree):
    """Render a nested config tree as hyprland.conf block syntax."""
    lines = ["# === NOTHINGLESS COMPOSITOR ===", "# Applied by NothingLess", ""]

    SECTION_ORDER = [
        "general", "decoration", "input", "cursor", "gestures",
        "misc", "xwayland", "dwindle", "master", "scrolling", "animations", "group", "binds",
    ]

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

    for section in SECTION_ORDER:
        if section in tree:
            _write_section(section, tree[section])
            lines.append("")

    lines.append("# === END COMPOSITOR ===")
    return "\n".join(lines) + "\n"


def _render_lua_tree(tree):
    """Render a nested config tree as hyprland.lua hl.config() block."""
    lines = [
        "-- === NOTHINGLESS COMPOSITOR ===",
        "-- NothingLess compositor settings",
        "hl.config({",
    ]

    # Layout sections (dwindle, master, scrolling) are conf-only:
    # they are not valid in hl.config() Lua API
    SECTION_ORDER = [
        "general", "decoration", "input", "cursor", "gestures",
        "misc", "xwayland", "animations", "group", "binds",
    ]

    def _write_table(name, data, indent=4):
        prefix = " " * indent
        if not isinstance(data, dict):
            return
        lines.append(f"{prefix}{name} = {{")
        for key, val in data.items():
            if isinstance(val, dict) and "value" in val:
                # Leaf with metadata
                lines.append(f"{prefix}    {key} = {_fmt_lua_val(val['value'], val)},")
            elif isinstance(val, dict):
                _write_table(key, val, indent + 4)
            else:
                lines.append(f"{prefix}    {key} = {_fmt_lua_val(val)},")
        lines.append(f"{prefix}}},")

    for section in SECTION_ORDER:
        if section in tree:
            _write_table(section, tree[section])

    lines.append("})")
    lines.append("-- === END COMPOSITOR ===")
    return "\n".join(lines) + "\n"


def build_conf_compositor():
    """Build hyprland.conf compositor block from TOML dictionary."""
    _is_free = cfg.get("layout") == "free"
    _smart = cfg.get("smartResizeAnchors", True)
    if _smart:
        grab = max(cfg.get("extendBorderGrabArea", 10), 10)
        cfg.update({"resizeOnBorder": True, "extendBorderGrabArea": grab})
    else:
        cfg.update({"resizeOnBorder": False, "extendBorderGrabArea": 0})
    tree = _build_config_tree(cfg)
    return _render_conf_tree(tree)


def build_lua_compositor():
    """Build hyprland.lua compositor block from TOML dictionary."""
    _is_free = cfg.get("layout") == "free"
    _smart = cfg.get("smartResizeAnchors", True)
    if _smart:
        grab = max(cfg.get("extendBorderGrabArea", 10), 10)
        cfg.update({"resizeOnBorder": True, "extendBorderGrabArea": grab})
    else:
        cfg.update({"resizeOnBorder": False, "extendBorderGrabArea": 0})
    tree = _build_config_tree(cfg)
    return _render_lua_tree(tree)

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

    lines.append("# === END COMPOSITOR ===")
    return "\n".join(lines) + "\n"


# ═══════════════════════════════════════════════════════════════════════════
#  MAIN — BUILD & WRITE
# ═══════════════════════════════════════════════════════════════════════════

def _inject_block(content, marker, end_marker, new_block):
    """Replace or inject a marked block in existing content."""
    content = re.sub(
        re.escape(marker) + ".*?" + re.escape(end_marker),
        "", content, flags=re.DOTALL
    ).strip()
    if new_block:
        content += "\n" + new_block
    return content


def main():
    os.makedirs(DATA_DIR, exist_ok=True)

    # ── Generate all blocks ──
    conf_compositor = build_conf_compositor()
    lua_compositor  = build_lua_compositor()
    toml_compositor = build_toml_compositor()
    binds_conf, binds_lua, binds_toml = build_all_binds()

    # ── hyprland.conf ──
    try:
        with open(CONF_PATH) as f:
            content = f.read()
    except FileNotFoundError:
        content = "# NothingLess Hyprland config\n"

    content = _inject_block(content,
        "# === NOTHINGLESS COMPOSITOR ===", "# === END COMPOSITOR ===",
        conf_compositor)
    content = _inject_block(content,
        "# === NOTHINGLESS KEYBINDS ===", "# === END KEYBINDS ===",
        binds_conf)

    with open(CONF_PATH, "w") as f:
        f.write(content)
    print(f"hyprland.conf: {len(conf_compositor)}c compositor + {len(binds_conf)}c keybinds")

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

    content = _inject_block(content,
        "-- === NOTHINGLESS COMPOSITOR ===", "-- === END COMPOSITOR ===",
        lua_compositor)
    content = _inject_block(content,
        "-- === NOTHINGLESS KEYBINDS ===", "-- === END KEYBINDS ===",
        binds_lua)

    with open(LUA_PATH, "w") as f:
        f.write(content)
    print(f"hyprland.lua: {len(lua_compositor)}c compositor + {len(binds_lua)}c keybinds")

    # ── axctl.toml ──
    try:
        with open(TOML_PATH) as f:
            toml_content = f.read()

        # Remove old appearance blocks + keybinds
        toml_content = re.sub(
            r'\n?\[appearance\].*?(?=\n?\[\[keybinds\]\]|\n?# === NOTHINGLESS|\Z)',
            '', toml_content, flags=re.DOTALL
        ).strip()
        toml_content = re.sub(
            re.escape("# === NOTHINGLESS COMPOSITOR ===") + ".*?" + re.escape("# === END COMPOSITOR ==="),
            '', toml_content, flags=re.DOTALL
        ).strip()
        toml_content = re.sub(
            r'\n?(\[\[keybinds\]\].*?)(?=\n\[|\Z)',
            '', toml_content, flags=re.DOTALL
        ).strip()
        toml_content = re.sub(
            re.escape("# === NOTHINGLESS KEYBINDS ===") + ".*?" + re.escape("# === END KEYBINDS ==="),
            '', toml_content, flags=re.DOTALL
        ).strip()

        toml_content = toml_content.rstrip() + "\n\n" + toml_compositor.strip() + "\n"
        if binds_toml:
            toml_content += "\n" + binds_toml.strip() + "\n"

        with open(TOML_PATH, "w") as f:
            f.write(toml_content)
        print(f"axctl.toml: {len(toml_compositor)}c compositor + {len(binds_toml)}c keybinds")

    except FileNotFoundError:
        with open(TOML_PATH, "w") as f:
            f.write(toml_compositor)
            if binds_toml:
                f.write("\n\n" + binds_toml.strip() + "\n")
        print(f"axctl.toml: CREATED ({len(toml_compositor)}c compositor)")

    print("Done — hyprctl reload & axctl config reload recommended")


if __name__ == "__main__":
    main()
