# SERVICES KNOWLEDGE BASE

## OVERVIEW
Backend singletons bridging Wayland protocols, CLI tools (nmcli, upower, wpctl, etc.), and AI providers to the QML UI layer. 30+ services following a "Reactive Singleton" pattern — internal state derived from async system calls, exposed as QML properties.

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| **Audio/Volume** | `Audio.qml` | PipeWire/PulseAudio via `wpctl`. Sink/source management |
| **Network/WiFi** | `NetworkService.qml` | `nmcli` wrapper. WiFi scanning, connection, status |
| **Battery/Power** | `Battery.qml` | UPower integration. Percentage, charging state, time remaining. Auto-switches to power-saver when below threshold (configurable). |
| **Bluetooth** | `BluetoothService.qml` | Device listing, connect/disconnect |
| **Brightness** | `Brightness.qml` | Per-monitor brightness via `brightnessctl` |
| **AI Assistant** | `Ai.qml` + `ai/strategies/` | Multi-provider (OpenAI, Gemini, Mistral). Strategy pattern |
| **Clipboard** | `ClipboardService.qml` | Persistent clipboard via `clipboard.db` + helper scripts |
| **Media** | `MprisController.qml` | MPRIS D-Bus player control |
| **Notifications** | `Notifications.qml` | D-Bus notification server with persistence. Suppresses popups when `GlobalStates.notificationsDnd` is true (history still accumulates). |
| **System Monitor** | `SystemResources.qml` | CPU, RAM, GPU, temps via Python script |
| **Compositor** | `AxctlService.qml` | Abstraction layer for compositor IPC (focus, dispatch) |
| **Visibility** | `Visibilities.qml` | Per-screen UI visibility/layering orchestration |
| **State** | `StateService.qml` | JSON persistence for session state (tab positions, etc.) |
| **Focus** | `FocusGrabManager.qml` | Input focus coordination across overlays |
| **Desktop** | `DesktopService.qml` | Desktop icon grid positioning and management |
| **App Search** | `AppSearch.qml` | Application indexing for launcher |
| **Weather** | `WeatherService.qml` | Forecast, sunrise/sunset, day/night detection |
| **Keybinds** | `GlobalShortcuts.qml` | Compositor-level keybind management + IPC dispatcher (volume, caffeine, gamemode, focusmode, dnd, power profile, charge limit) |
| **Caffeine** | `CaffeineService.qml` | Wraps `IdleInhibitor`. State persisted via `StateService` |
| **Game Mode** | `GameModeService.qml` | Snapshot/restore `Config.compositor.*` and live-apply via `CompositorConfig.applyCompositorConfig()`. Triggers Anim.instantMode, pauses VideoWallpaperService, suppresses notifications. State persisted. |
| **Focus Mode** | `FocusModeService.qml` | Zero gaps + DND + caffeine. Snapshot/restore of `gapsIn/gapsOut` and pre-existing DND/caffeine states. State persisted. |
| **Power Profile** | `PowerProfile.qml` | `power-profiles-daemon` only (TLP dropped). Available profiles always `["power-saver", "balanced", "performance"]` in that order. Exposes `setProfile(name)`, `cycle()`. UI binds to `availableProfiles`/`currentProfile` |
| **Charge Limit** | `ChargeLimitService.qml` + `scripts/set-charge-limit.sh` | Battery charge limit via TLP (sudo) or direct sysfs write. Auto-detects backend. State persisted. |

## CONVENTIONS
- **Singleton pattern**: `pragma Singleton` + `Singleton { id: root }` root component.
- **System access**: Prefer `Quickshell.Io.Process` with `SplitParser` for line-by-line stdout handling.
- **Naming**: Properties in camelCase (`wifiEnabled`, `isCharging`). Methods: `update()` for polling, `toggleX()` for booleans. Signals: past-tense or action-based (`initDone`, `discard`).
- **Persistence**: `FileView` for direct JSON manipulation. Reference `Config` for global settings; keep service-specific state local.
- **Async safety**: `Qt.callLater()` when modifying lists/models inside process handlers.
- **Self-init**: Services handle own lifecycle via `Component.onCompleted: update()`.
- **Error handling**: Always provide safe fallback values (`available: device !== null`).

## ANTI-PATTERNS
- Polling without a timer guard (use `Timer` with configurable intervals).
- Modifying list models synchronously inside `Process.onStdout` handlers.
- Creating new services without registering them in `shell.qml` init sequence.
