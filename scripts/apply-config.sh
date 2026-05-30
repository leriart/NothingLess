#!/bin/bash
# Apply NothingLess compositor config to Hyprland
# Called from the shell when user saves compositor settings

# 1. Sync to hyprland.conf and hyprland.lua
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/sync-hyprland.py"

# 2. Read compositor.json and TOML dictionary to apply via axctl
DICT="$SCRIPT_DIR/hyprlang-dict.toml"
CONFIG="$HOME/.config/nothingless/config/compositor.json"
if [ -f "$CONFIG" ] && [ -f "$DICT" ]; then
    python3 -c "
import json, subprocess, sys
sys.path.insert(0, '$SCRIPT_DIR')

# Import tomllib (Python 3.11+) or tomli
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        print('ERROR: tomllib required', file=sys.stderr)
        sys.exit(1)

with open('$CONFIG') as f:
    cfg = json.load(f)
with open('$DICT', 'rb') as f:
    d = tomllib.load(f)

def derive_key(lua_path):
    if not lua_path: return ''
    parts = lua_path.split('.')
    key_parts = parts[-2:] if len(parts) >= 3 else [parts[-1]]
    result = ''
    for i, segment in enumerate(key_parts):
        words = segment.split('_')
        for j, word in enumerate(words):
            if not word: continue
            if i == 0 and j == 0: result += word
            else: result += word[0].upper() + word[1:]
    return result

# Build kw_map from TOML dictionary (same logic as sync-hyprland.py)
kw_map = {}
SKIP = {'dispatchers','binds_flags','actions','global_rules','layer_rules','binds_free_layout','color_defaults'}
for section, entries in d.items():
    if section in SKIP or not isinstance(entries, dict):
        continue
    for key, entry in entries.items():
        if not isinstance(entry, dict): continue
        nk = entry.get('nothingless_key') or derive_key(entry.get('lua',''))
        conf = entry.get('conf','')
        if not conf:
            # Fallback: use lua path for Lua-only settings
            lua_path = entry.get('lua','')
            if lua_path:
                conf = lua_path.replace('.', ':')
        if nk and conf:
            kw_map[nk] = conf

def fmt(v):
    if isinstance(v, bool): return 'true' if v else 'false'
    if isinstance(v, list): return ' '.join(str(x) for x in v)
    return str(v)

def is_hex_color(v):
    '''Check if a value looks like a valid hex color.'''
    if isinstance(v, str): return v.startswith('0x') or v.startswith('#')
    if isinstance(v, list): return all(is_hex_color(x) for x in v)
    return False

def is_sync_disabled(nk):
    SYNC_FLAGS = {
        'syncBorderWidth': {'borderSize'},
        'syncBorderColor': {'activeBorderColor','inactiveBorderColor'},
        'syncRoundness': {'rounding','roundingPower'},
        'syncShadowColor': {'shadowColor','shadowColorInactive'},
    }
    for flag, blocked in SYNC_FLAGS.items():
        if nk in blocked:
            return not cfg.get(flag, True)
    return False

parts = []
for ck, kw in kw_map.items():
    if ck in cfg:
        val = cfg[ck]
        if is_sync_disabled(ck):
            continue
        # Skip symbolic theme colors
        if (ck.endswith('Color') or 'color' in ck.lower()) and not is_hex_color(val):
            continue
        parts.append(f'keyword {kw} {fmt(val)}')

if parts:
    batch = ' ; '.join(parts)
    r = subprocess.run(['axctl', 'config', 'raw-batch', batch], capture_output=True, text=True)
    print(f'axctl: {len(parts)} settings applied' + (f' — {r.stderr.strip()}' if r.stderr else ''))
"
fi
