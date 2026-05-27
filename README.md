<p align="center">
  <img src="./assets/not.gif" alt="NothingLess" width="400"/>
  <br><br>
  A high-performance, deeply customizable Wayland shell built with Quickshell.
  <br><br>
  <i>Less is more.</i>
</p>

<p align="center">
  <a href="https://github.com/Leriart/NothingLess">
    <img src="https://img.shields.io/badge/NothingLess-0A0A0A?style=for-the-badge&logo=github&logoColor=FFFFFF" alt="repo">
  </a>
  <a href="https://discord.gg/ehQYYW36Up">
    <img src="https://img.shields.io/badge/Discord-5865F2?style=for-the-badge&logo=discord&logoColor=FFFFFF" alt="discord">
  </a>
  <a href="https://github.com/Axenide/Ambxst">
    <img src="https://img.shields.io/badge/Fork%20of-Ambxst-E80012?style=for-the-badge&logo=github&logoColor=FFFFFF&labelColor=0A0A0A" alt="fork">
  </a>
</p>

---

## Screenshots

<p align="center">
  <img src="./assets/screenshots/settings.png" alt="NothingLess Settings" width="30%"/>
  &nbsp;&nbsp;
  <img src="./assets/screenshots/free-layout.png" alt="Free Layout" width="30%"/>
  &nbsp;&nbsp;
  <img src="./assets/screenshots/nothing.png" alt="Nothing" width="30%"/>
  <br><br>
  <img src="./assets/screenshots/dynamic-bar.png" alt="Dynamic Bar" width="45%"/>
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
nothingless
```

### Compositor integration

```bash
nothingless install hyprland           # Auto-detect
nothingless install hyprland --conf    # Force config file mode (default)
nothingless install hyprland --lua     # Force Lua mode (Hyprland >= 0.48)
nothingless remove hyprland            # Remove config
```

On first boot, `exec-once = nothingless` launches the shell, which starts the axctl daemon internally. All compositor settings are managed live via axctl and persisted to `~/.local/share/nothingless/`.

---

## Features

- **Free Layout** — Windows-like floating desktop with edge snap
- **Dynamic Island** — integrated notifications and metrics in the bar
- **Task tray** — system tray with icon show/hide
- **Overview** — workspace manager with drag & drop and live preview
- **Dashboard** — visual config panel with 200+ options
- **FPS Monitoring** — patched MangoHud with notch overlay
- **Monitor configuration** — GUI panel and CLI backend
- **Snap Assistant** — intelligent window snapping via axctl
- **M3 Animations** — Material You, Windows Classic, and macOS profiles

---

## Commands

```bash
nothingless                          # Start the shell
nothingless reload                   # Reload the shell
nothingless quit                     # Quit the shell
nothingless lock                     # Activate lockscreen
nothingless update                   # Update NothingLess
nothingless run <module>             # Run a module (launcher, dashboard, overview, etc.)
nothingless brightness <0-100>       # Set brightness
nothingless screen on|off            # Display power control
nothingless suspend                  # Suspend system
```

---

## Differences from Ambxst

| Area | Ambxst | NothingLess |
|------|--------|-------------|
| Compositor settings | ~25 options | **~100+ options** (4x more) |
| Layouts | Dwindle, Master, Scrolling | **+ Free Layout** (floating desktop) |
| Services | 30 | **39** (+9 new) |
| Scripts | 22 | **38** (+16 new) |
| Config reload handling | None | `configreloaded` detection with instant recovery |
| Dynamic Island | Not available | Unified notch + bar in island mode |
| Task tray | Not available | System tray with icon show/hide |
| Animations | `animDuration` global | **Anim.qml** — M3, Windows Classic, macOS profiles |
| Video wallpaper | mpv-based | **QtMultimedia + FFmpeg** (hardware-accelerated) |
| Bar mode | Static bar | **Extended/dynamic modes** with per-monitor config |
| Monitor configuration | Manual (hyprctl) | **GUI panel + CLI** in NothingLess |
| FPS overlay | Not available | **Patched MangoHud** with notch display |
| Axctl daemon | Basic | **Health check, auto-reconnect, restart on failure** |
| Config sync with hyprland | None | **hyprland.conf/lua generated** from binds.json |
| CLI commands | 9 | **20+** commands |
| Presets | 8 | **12** (+Dot Matrix, Nothing, Pure Monochrome, Minimal) |
| Typography | Roboto | **Ndot** (dot-matrix), monospace-first |
| Color scheme | Vibrant | **Monochrome** with red accents |

---

## Credits

- **Leriart** — fork maintainer and NothingLess developer
- **Axenide** — original [Ambxst](https://github.com/Axenide/Ambxst) creator
- **Zack** ([@zackytodearena](https://bsky.app/profile/zackytodearena.bsky.social)) — logo & animation design
- **outfoxxed** — creator of [Quickshell](https://git.outfoxxed.me/outfoxxed/quickshell)

---

## License

- NothingLess modifications are provided under the same license as the upstream.
- Ambxst and the Ambxst logo are trademarks of Adriano Tisera (Axenide).
- See [LICENSE](./LICENSE) and [TRADEMARK.md](./assets/nothingless/TRADEMARK.md) for details.
