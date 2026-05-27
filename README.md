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

Supported on **Arch**, **Fedora**, and **NixOS**.

---

## Features

- **Free Layout** — modo escritorio libre tipo Windows (ventanas flotantes, snap a bordes, show desktop)
- **Dynamic Island** — notificaciones y métricas integradas en la barra
- **Task tray** — system tray con show/hide
- **Overview** — gestor de workspaces con drag & drop y live preview
- **Dashboard** — panel de configuración visual con 200+ opciones
- **AI Assistant** — soporte para OpenAI, Anthropic, DeepSeek, Gemini, Ollama y más
- **FPS Monitoring** — MangoHud parcheado con overlay de FPS en el notch
- **Configuración de monitores** — backends gráfico y por línea de comandos
- **Music Recognition** — identificación de canciones vía SongRec/Shazam
- **Screen Translation** — traducción de pantalla vía translate-shell
- **Snap Assistant** — intelligent window snapping via axctl
- **Animaciones M3** — perfiles Material You, Windows Classic y macOS

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
| Git history | 1 commit (snapshot) | **449 commits** — mantenimiento activo |
| Compositor settings | ~25 propiedades | **~100+ propiedades** (4x más) |
| Layouts | Dwindle, Master, Scrolling | **+ Free Layout** (escritorio libre) |
| Services | 30 | **39** (+9 nuevos) |
| Scripts | 22 | **38** (+16 nuevos) |
| Config reload handling | Ninguno | Detección de `configreloaded` con recuperación instantánea |
| Dynamic Island | No disponible | Notch + barra unificados en modo island |
| Task tray | No disponible | System tray con show/hide de iconos |
| Animations | `animDuration` global | **Anim.qml** — perfiles M3, Windows Classic, macOS |
| Video wallpaper | mpv-based | **QtMultimedia + FFmpeg** (hardware-accelerated) |
| Bar mode | Barra estática | **Modos extended/dynamic** con per-monitor config |
| Configuración de monitores | Manual (hyprctl) | **Panel gráfico + CLI** en NothingLess |
| FPS overlay | No disponible | **MangoHud parcheado** con notch display |
| Music recognition | No disponible | **SongRec/Shazam** integrado |
| Screen translation | No disponible | **translate-shell** integrado |
| Axctl daemon | Básico | **Health check, auto-reconnect, restart on failure** |
| Sync con hyprland | No disponible | **hyprland.conf/lua generado** desde binds.json |
| CLI commands | 9 | **20+** comandos |
| Presets | 8 | **12** (+Dot Matrix, Nothing, Pure Monochrome, Minimal) |
| Typography | Roboto | **Ndot** (dot-matrix), monospace-first |
| Color scheme | Vibrante | **Monocromático** con acentos rojos |
| Distros soportadas | Arch, NixOS | **+ Fedora** |

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
