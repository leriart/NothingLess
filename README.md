<p align="center">
  <img src="./assets/not.gif" alt="NothingLess" width="400"/>
  <br><br>
  A high-performance, deeply customizable Wayland shell built with Quickshell.
  <br><br>
  <i>Inspired by the Nothing Phone — less is more.</i>
  <br><br>
  <b>Fork of <a href="https://github.com/Axenide/Ambxst">Ambxst</a></b>
</p>

<p align="center">
  <a href="https://github.com/Leriart/NothingLess">
    <img src="https://img.shields.io/badge/NothingLess-0A0A0A?style=for-the-badge&logo=github&logoColor=FFFFFF" alt="repo">
  </a>
  <a href="https://github.com/Axenide/Ambxst">
    <img src="https://img.shields.io/badge/Fork%20of-Ambxst-E80012?style=for-the-badge&logo=github&logoColor=FFFFFF&labelColor=0A0A0A" alt="fork">
  </a>
</p>

---

## Screenshots

<p align="center">
  <img src="./assets/screenshots/settings.png" alt="NothingLess Settings" width="45%"/>
  &nbsp;&nbsp;
  <img src="./assets/screenshots/gaming.png" alt="NothingLess Gaming" width="45%"/>
</p>

---

## Installation

```bash
curl -sL https://github.com/Leriart/NothingLess/raw/main/install.sh | sh
```

Or clone manually:

```bash
git clone https://github.com/Leriart/NothingLess.git ~/.local/src/nothingless
sudo ln -s ~/.local/src/nothingless/cli.sh /usr/local/bin/nothingless
```

Then run:

```bash
nothingless
```

### Compositor integration

```bash
nothingless install hyprland           # Auto-detect (default: conf)
nothingless install hyprland --conf    # Force config file mode (safe default)
nothingless install hyprland --lua     # Force Lua mode (Hyprland >= 0.48)
nothingless remove hyprland            # Remove NothingLess config from Hyprland
```

**Mode selection:**
- `--conf` (default): Creates `~/.local/share/nothingless/hyprland.conf` and adds `source = ~/.local/share/nothingless/hyprland.conf` to your Hyprland config. Works on all Hyprland versions.
- `--lua`: Creates `~/.local/share/nothingless/hyprland.lua` as valid Lua and adds `loadfile(...)()` to your Hyprland config. Requires Hyprland >= 0.48.
- No flag: Auto-detects based on existing config (`hyprland.lua` → lua, `hyprland.conf` → conf). If neither exists, defaults to `--conf`.

On first boot, `exec-once = nothingless` launches the shell, which starts the axctl daemon internally. All compositor settings are managed by axctl (live via `raw-batch`, persisted via `axctl.toml`).

Supported on **Arch**, **Fedora**, and **NixOS** (requires Hyprland).

---

## Commands

### CLI

```bash
nothingless                      # Start NothingLess shell
nothingless update               # Update NothingLess
nothingless reload               # Reload NothingLess
nothingless quit                 # Quit NothingLess
nothingless lock                 # Activate lockscreen
nothingless run <command>        # Run a NothingLess module
nothingless brightness <0-100>   # Set brightness
nothingless brightness +/-<delta> # Adjust brightness
nothingless brightness -s        # Save current brightness
nothingless brightness -r        # Restore saved brightness
nothingless screen on|off        # Control display power
nothingless suspend              # Suspend system
```

### Module Commands

| `nothingless run ...` | Description |
|---|---|
| `launcher` | Open app launcher |
| `dashboard` | Open dashboard |
| `assistant` | Open AI assistant |
| `clipboard` | Open clipboard manager |
| `emoji` | Open emoji picker |
| `notes` | Open notes |
| `tmux` | Open tmux session manager |
| `wallpapers` | Open wallpaper picker |
| `overview` | Open workspace overview |
| `powermenu` | Open power menu |
| `tools` | Open tools menu |
| `config` | Open settings |
| `screenshot` | Take screenshot |
| `screenrecord` | Screen record |
| `lens` | Open OCR capture |
| `toggle-metrics` | Toggle notch metrics display |
| `lockscreen` | Lock session |

### Keybinds

| Key | Action |
|---|---|
| `SUPER` (hold) | Launcher |
| `SUPER + D` | Dashboard |
| `SUPER + A` | Assistant |
| `SUPER + V` | Clipboard |
| `SUPER + PERIOD` | Emoji picker |
| `SUPER + N` | Notes |
| `SUPER + T` | Tmux |
| `SUPER + COMMA` | Wallpapers |
| `SUPER + TAB` | Workspace overview |
| `SUPER + ESC` | Power menu |
| `SUPER + S` | Tools menu |
| `SUPER + SHIFT + C` | Settings |
| `SUPER + SHIFT + S` | Screenshot |
| `SUPER + SHIFT + R` | Screen record |
| `SUPER + SHIFT + A` | Lens |
| `SUPER + L` | Lock session |
| `SUPER + SHIFT + BACKSPACE` | Toggle metrics overlay |

---

## FPS Monitoring (`nothingless-fps`)

NothingLess includes a modified MangoHud that captures FPS data and displays it in the notch metrics overlay.

```bash
# Launch a game with FPS monitoring
nothingless-fps ./my-game

# Steam launch options (right-click game > Properties > Launch Options)
nothingless-fps %command%
```

**How it works:**

1. `nothingless-fps` sets up a modified MangoHud (`libMangoHud_shim.so`) via `LD_PRELOAD`
2. MangoHud hooks Vulkan/OpenGL to capture frame-present events
3. Calculated FPS is written to `/dev/shm/nothingless_fps`
4. NothingLess reads this file in real-time and displays FPS in the notch

**Rebuilding MangoHud from source:**

```bash
./scripts/mangohud-patch/build-mangohud.sh
```

Requires: `meson`, `ninja`, `gcc`, `glslang`, `python-mako`.

---

## Performance

| Area | Improvement |
|------|-------------|
| Video wallpaper | QtMultimedia + FFmpeg (hardware-accelerated, lower overhead vs mpv) |
| Rendering backend | Configurable OpenGL (default) or Vulkan with threaded render loop |
| GPU optimization | NVIDIA env vars, GPU texture caching (`GradientCache`) |
| GLSL shaders | Optimized (reduced draw calls, shared GPU textures) |
| FPS monitoring | Custom MangoHud integration with real-time notch display |

## Features

| Area | Enhancement |
|------|-------------|
| Compositor settings | 130+ options across 11 categories |
| Config reload | `configreloaded` event detection with instant bind/settings recovery |
| Installer | Lua/conf dual mode for Hyprland |
| Tasktray | Dynamic systray with expansion animation |
| Monitors | Per-monitor positioning via `monitors_writer.py` |
| Battery alerts | Low battery notifications |
| Presets | Nothing Phone aesthetic theme |

---

## Credits

- **Leriart** — creator of NothingLess
- **Axenide** — original [Ambxst](https://github.com/Axenide/Ambxst) creator (NothingLess is a fork of Ambxst)
- **Zack** ([@zackytodearena](https://bsky.app/profile/zackytodearena.bsky.social)) — logo & animation design
- **outfoxxed** — creator of [Quickshell](https://git.outfoxxed.me/outfoxxed/quickshell)
- **end-4** — inspiration from [dots-hyprland](https://github.com/end-4/dots-hyprland)

---

## License

- NothingLess is based on Ambxst and is provided under the same license terms.
- See [LICENSE](./LICENSE) for details.
