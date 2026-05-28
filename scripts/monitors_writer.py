#!/usr/bin/env python3
"""
MonitorsWriter — nwg-displays compatible backend for NothingLess
===============================================================
Reads:  hyprctl monitors -j
Writes: ~/.config/hypr/monitors.conf  (monitor=DP-1,3440x1440@144,0x0,1)
        ~/.config/hypr/monitors.lua   (hl.monitor({...}))
Applies: hyprctl reload

Commands:
  list              Print current monitors as JSON (from hyprctl)
  sync              Write monitors.conf + monitors.lua + reload
  sync --data JSON  Write from explicit data + reload
  sync --no-apply   Write files only, no reload
"""

import json, os, re, shutil, subprocess, sys
from datetime import datetime

CONF = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "hypr", "monitors.conf")
LUA  = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "hypr", "monitors.lua")
NL   = os.path.expanduser("~/.local/share/nothingless")
AXCTL_TOML = os.path.join(NL, "axctl.toml")

# ─── hyprctl ───────────────────────────────────────────────────────────────────

def hyprctl_json(cmd):
    """Run 'hyprctl monitors -j' and return parsed JSON."""
    r = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True, timeout=5)
    if r.returncode == 0 and r.stdout.strip():
        return json.loads(r.stdout)
    # fallback
    r = subprocess.run(["axctl", "monitor", "list"], capture_output=True, text=True, timeout=5)
    if r.returncode == 0 and r.stdout.strip():
        return json.loads(r.stdout)
    return []

def hyprctl_reload():
    try:
        r = subprocess.run(["hyprctl", "reload"], capture_output=True, timeout=10)
        return r.returncode == 0
    except Exception:
        return False

# ─── Normalize / Generate ─────────────────────────────────────────────────────

def normalize(m):
    """Normalize one monitor dict from hyprctl JSON → standard keys."""
    return {
        "name":        str(m.get("name","")),
        "width":       int(m.get("width",0) or 0),
        "height":      int(m.get("height",0) or 0),
        "x":           int(m.get("x",0) or 0),
        "y":           int(m.get("y",0) or 0),
        "scale":       float(m.get("scale",1.0) or 1.0),
        "refreshRate": float(m.get("refreshRate",m.get("refresh_rate",60)) or 60),
        "transform":   int(m.get("transform",0) or 0),
        "vrr":         int(m.get("vrr", m.get("activelyTearing", 0)) or 0),
        "enabled":     True,  # hyprctl only reports active monitors
        "focused":     bool(m.get("focused",False)),
        "make":        str(m.get("make","")),
        "model":       str(m.get("model","")),
        "description": str(m.get("description","")),
        # Available modes
        "modes":       m.get("availableModes", m.get("available_modes", [])),
        # Hyprland 0.55+: HDR support
        "hdrSupported": bool(m.get("hdrSupported", m.get("hdr_supported", False))),
        "hdr":         bool(m.get("hdr", False)),
    }

def normalize_custom(m):
    """Normalize a monitor dict received from QML (--data)."""
    return {
        "name":        str(m.get("name","")),
        "width":       int(m.get("width",0) or 0),
        "height":      int(m.get("height",0) or 0),
        "x":           int(m.get("x",0) or 0),
        "y":           int(m.get("y",0) or 0),
        "scale":       float(m.get("scale",1.0) or 1.0),
        "refreshRate": float(m.get("refreshRate",60) or 60),
        "transform":   int(m.get("transform",0) or 0),
        "vrr":         int(m.get("vrr",0) or 0),
        "enabled":     bool(m.get("enabled",True)),
        "focused":     bool(m.get("focused",False)),
        "make":        str(m.get("make","")),
        "model":       str(m.get("model","")),
        "description": str(m.get("description","")),
        "hdrSupported": bool(m.get("hdrSupported", False)),
        "hdr":         bool(m.get("hdr", False)),
        "modes":       m.get("modes", []),
    }

def conf_line(m):
    """Generate one monitor= line (nwg-displays format).

    Hyprland 0.55 syntax: monitor=NAME,MODE,POS,SCALE[,transform,T]
    """
    n = m["name"]
    if not m["enabled"]:
        return f"monitor={n},disable"
    mode = f"{m['width']}x{m['height']}@{m['refreshRate']:.2f}".rstrip('0').rstrip('.')
    pos  = f"{m['x']}x{m['y']}"
    line = f"monitor={n},{mode},{pos},{m['scale']}"
    # Append transform if non-zero (0=normal, 1=90°, 2=180°, 3=270°, 4=flipped, etc.)
    transform = int(m.get("transform", 0) or 0)
    if transform:
        line += f",transform,{transform}"
    return line

def lua_block(m):
    """Generate hl.monitor({...}) block (Hyprland 0.55+ Lua API)."""
    n = m["name"]
    if not m["enabled"]:
        return f'hl.monitor({{\n    output = "{n}",\n    disabled = true\n}})\n'
    mode = f"{m['width']}x{m['height']}@{m['refreshRate']:.2f}".rstrip('0').rstrip('.')
    pos  = f"{m['x']}x{m['y']}"
    parts = [
        f'    output = "{n}"',
        f'    mode = "{mode}"',
        f'    position = "{pos}"',
        f'    scale = {m["scale"]}',
    ]
    # Transform (0=normal, 1-7=rotations/flips)
    transform = int(m.get("transform", 0) or 0)
    if transform:
        parts.append(f'    transform = {transform}')
    # VRR (variable refresh rate) — Hyprland 0.50+
    vrr = m.get("vrr")
    if vrr is not None and vrr != 0:
        parts.append(f'    vrr = {vrr}')
    return 'hl.monitor({\n' + ',\n'.join(parts) + '\n})\n'

def generate(monitors):
    ts = datetime.now().strftime("%Y-%m-%d at %H:%M:%S")
    hdr = f"# Generated by NothingLess on {ts}. Do not edit manually."
    conf = [hdr, ""]
    lua  = ["-- " + hdr[2:], ""]
    for m in monitors:
        conf.append(conf_line(m))
        lua.append(lua_block(m))
    return conf, lua

# ─── File I/O ─────────────────────────────────────────────────────────────────

def write(path, lines):
    path = os.path.expanduser(path)
    if os.path.isfile(path):
        shutil.copy2(path, path + ".bak")
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")

def inject_nl(conf_lines, lua_lines):
    for ext, lines, sm, em in [
        ("hyprland.conf", conf_lines, "# === NOTHINGLESS MONITORS ===", "# === END MONITORS ==="),
        ("hyprland.lua",  lua_lines,  "-- === NOTHINGLESS MONITORS ===", "-- === END MONITORS ==="),
    ]:
        path = os.path.join(NL, ext)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if not os.path.isfile(path):
            # Create file with header so markers can be injected
            header = "-- NothingLess Hyprland config\n" if ext.endswith(".lua") \
                else "# NothingLess Hyprland config\n"
            with open(path, "w") as f:
                f.write(header)
        filtered = [l for l in lines if l.startswith("monitor=")] if ext.endswith(".conf") \
              else [l for l in lines if l.startswith("hl.monitor")]
        block = f"{sm}\n" + "\n".join(filtered) + f"\n{em}"
        with open(path) as f:
            content = f.read()
        if sm in content:
            content = content.split(sm)[0] + content.split(em)[1]
        content = content.rstrip() + "\n\n" + block + "\n"
        with open(path, "w") as f:
            f.write(content)

def toml_entry(m):
    """Generate one [[monitors]] TOML block."""
    n = m["name"]
    if not m.get("enabled", True):
        return (
            f"[[monitors]]\n"
            f'name = "{n}"\n'
            f"enabled = false\n"
        )
    mode = f"{m['width']}x{m['height']}@{m['refreshRate']:.2f}Hz"
    pos = f"{m['x']}x{m['y']}"
    lines = [
        f"[[monitors]]",
        f'name = "{n}"',
        f'mode = "{mode}"',
        f'position = "{pos}"',
        f'scale = {m["scale"]}',
        f"enabled = true",
    ]
    # Transform (rotation)
    transform = int(m.get("transform", 0) or 0)
    if transform:
        lines.append(f"transform = {transform}")
    # VRR
    vrr = int(m.get("vrr", 0) or 0)
    if vrr:
        lines.append(f"vrr = {vrr}")
    return "\n".join(lines) + "\n"

def write_axctl_monitors(monitors):
    """Update [[monitors]] section in axctl.toml with correct data."""
    path = AXCTL_TOML
    if not os.path.isfile(path):
        return

    # Generate the new monitors block
    toml_mons = ""
    for m in monitors:
        toml_mons += toml_entry(m) + "\n"

    with open(path) as f:
        content = f.read()

    # Remove old [[monitors]] sections
    content = re.sub(
        r'\n?\[\[monitors\]\].*?(?=\n?\[|\Z)',
        '', content, flags=re.DOTALL
    ).strip()

    # Insert monitors block after [startup] section
    if toml_mons:
        match = re.search(r'^\[.*?\]', content, re.MULTILINE)
        if match:
            first_section_end = content.find('\n', match.start())
            if first_section_end == -1:
                first_section_end = len(content)
            after_startup = content[:first_section_end + 1]
            rest = content[first_section_end + 1:]
            content = after_startup + '\n' + toml_mons.strip() + '\n\n' + rest
        else:
            content += '\n\n' + toml_mons + '\n'

    with open(path, "w") as f:
        f.write(content + "\n")

# ─── Commands ─────────────────────────────────────────────────────────────────

def cmd_list():
    """Output current monitors as JSON (nwg-displays format)."""
    raw = hyprctl_json("monitors -j")
    monitors = [normalize(m) for m in raw]
    json.dump(monitors, sys.stdout)
    return 0

def cmd_sync(args):
    """Write monitors.conf + monitors.lua + reload."""
    # Get data
    if args.data:
        raw = json.loads(args.data)
        monitors = [normalize_custom(m) for m in raw]
    elif args.json and os.path.isfile(args.json):
        with open(args.json) as f:
            raw = json.load(f)
        monitors = [normalize_custom(m) for m in raw]
    else:
        raw = hyprctl_json("monitors -j")
        monitors = [normalize(m) for m in raw]

    if not monitors:
        print("[WARN] No monitors", file=sys.stderr)
        return 1

    print(f"[sync] {len(monitors)} monitors: " + ", ".join(
        f"{m['name']} {m['width']}x{m['height']}@{m['refreshRate']:.0f}Hz {m['x']},{m['y']}" for m in monitors))

    conf, lua = generate(monitors)
    write(args.conf or CONF, conf)
    write(args.lua or LUA, lua)
    inject_nl(conf, lua)

    # Write monitors section to axctl.toml with the correct data (no stale QML state)
    write_axctl_monitors(monitors)

    if not args.no_apply:
        ok = hyprctl_reload()
        print("[OK] reload" if ok else "[WARN] reload failed")
    print("[OK] Done")
    return 0

def main():
    import argparse
    p = argparse.ArgumentParser()
    sp = p.add_subparsers(dest="cmd")
    sp.add_parser("list", help="Output monitors as JSON")
    s = sp.add_parser("sync", help="Write config + reload")
    s.add_argument("--data")
    s.add_argument("--json")
    s.add_argument("--conf")
    s.add_argument("--lua")
    s.add_argument("--no-apply", action="store_true")
    args = p.parse_args()
    if args.cmd == "list":
        return cmd_list()
    if args.cmd == "sync":
        return cmd_sync(args)
    p.print_help()
    return 0

if __name__ == "__main__":
    sys.exit(main())
