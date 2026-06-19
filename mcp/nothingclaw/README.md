# NothingClaw MCP Bridge

A lightweight, dependency-free HTTP bridge that connects the
**NothingClaw** AI assistant to NothingLess.

The bridge is fully managed by the NothingLess shell — there is **no
manual install step**. Open **Settings → AI → Agent Connections**,
click **`+ NothingClaw`**, then hit **Connect**. The shell spawns the
bridge on demand, exposes its tools to the AI, and tears the process
down on disconnect.

## What it does

The bridge runs an HTTP server on `http://127.0.0.1:8000` (default;
override with `NOTHINGCLAW_HOST` / `NOTHINGCLAW_PORT`) that exposes
the tools below. Most of them are 1:1 wrappers around the
[axctl.c](https://github.com/leriart/axctl.c) CLI — every category and
action pair maps directly to a documented axctl method.

### App catalog (native, flatpak, snap, AppImage)

| Tool | Purpose |
|------|---------|
| `list_installed_apps` | Aggregates every GUI app installed on the system: `.desktop` files in `$HOME/.local/share/applications`, `/usr/share/applications`, `/usr/local/share/applications`, `/var/lib/flatpak/exports/share/applications`, `~/.local/share/flatpak/exports/share/applications`; `flatpak list --app`; `snap list`; and `*.AppImage` files in `~/Applications`, `~/AppImages`, `~/.local/bin`, `~/.local/share/applications`, `/opt`. Returns JSON with `id`, `name`, `generic_name`, `comment`, `source` (native/flatpak/snap/appimage), `command`, `icon`, `categories`, `wmclass`. **Call this before `open_app` to discover display names.** Catalog is cached in-memory for 60 s and auto-rebuilds on the next call after that. |
| `open_app` | Launches a GUI app by display name. Searches the catalog with a multi-stage match (exact → substring on name → substring on `generic_name` → substring on id), strips `%u`/`%f`/`%F`/`%U` placeholders from the desktop `Exec=` line, and `nohup`s the result in the background. If no match is found the error surfaces a "Did you mean: …" hint from the catalog. **Prefer this over `launch_program` for GUI apps** — it resolves the right `Exec=` line and reaches flatpak/snap packages that `command -v` would never find. |
| `close_app` | Closes every window belonging to an app by name. Calls `axctl window list`, filters windows by `app_id` / `wm_class` / `title` substring match, then closes each one via `axctl window close <id>`. Returns JSON with the list of closed window ids and any per-window failures. |

### Window operations

| Tool | Maps to | Purpose |
|------|---------|---------|
| `list_windows` | `axctl window list` | JSON list of every window with id, title, app_id, workspace, geometry, floating / fullscreen / pinned state |
| `focus_window` | `axctl window focus <id>` / `focus-dir <l\|r\|u\|d>` | Bring a window to focus by id, or focus the neighbour in a direction |
| `close_window` | `axctl window close [id]` | Close active or specific window |
| `toggle_window_floating` | `axctl window toggle-floating [id]` | Toggle tiled ↔ floating |
| `set_window_fullscreen` | `axctl window fullscreen <0\|1> [id]` | Enter / leave fullscreen |
| `resize_window` | `axctl window resize <w> <h> [id]` | Resize in pixels |
| `move_window_direction` | `axctl window move <l\|r\|u\|d> [id]` | Swap position in the tiling layout |

### Workspace operations

| Tool | Maps to | Purpose |
|------|---------|---------|
| `list_workspaces` | `axctl workspace list` | JSON list of every workspace |
| `switch_workspace` | `axctl workspace switch <id>` | Focus a different workspace |
| `move_window_to_workspace` | `axctl workspace move-to <ws_id> [win_id]` | Move window to a workspace |
| `move_windows` | `axctl workspace move-to` (one call per window) | Batch-move windows to workspaces. Two modes: many-to-one (`window_ids` or `app_names` + a single `workspace_id`, every match lands on the same target) or many-to-many (`assignments` list of `{window_id, workspace_id}` pairs). Returns per-window success/failure JSON so one bad window does not abort the batch. |
| `toggle_special_workspace` | `axctl workspace toggle-special <name>` | Toggle a Hyprland special workspace (e.g. `scratchpad`) |

### Monitor operations

| Tool | Maps to | Purpose |
|------|---------|---------|
| `list_monitors` | `axctl monitor list` | JSON list of every monitor |
| `focus_monitor` | `axctl monitor focus <id>` | Focus a monitor |
| `move_window_to_monitor` | `axctl monitor move-to <mon_id> [win_id]` | Move window to a different monitor |

### Layout & system

| Tool | Maps to | Purpose |
|------|---------|---------|
| `set_layout` | `axctl layout set <name>` | Set tiling layout (`dwindle`, `master`, etc.) |
| `execute_command` | `axctl system execute <cmd>` | Run an arbitrary shell command via the compositor IPC layer |

### Program helpers

| Tool | Purpose |
|------|---------|
| `check_program_installed` | Returns the absolute path of a program on `$PATH`, or "not installed". Fast and non-blocking — useful before launching a program the user might not have installed. |
| `launch_program` | `nohup <program> &` — opens a binary that lives on `$PATH` in the background. Use for plain CLIs / system binaries; **use `open_app` for GUI apps** that ship as `.desktop` entries (it understands flatpak / snap). |
| `install_package` | Runs the distro package manager (`pacman` / `dnf` / `apt`) with sudo. If sudo prompts for a password the tool returns the exact command so the user can run it themselves. |

## How it runs

`server.py` uses **only the Python standard library** — no `pip install`,
no virtualenv, no systemd unit. When you click **Connect** on the
NothingClaw profile:

1. `AgentManager` spawns `python3 server.py` as a child process with
   `cwd` set to this directory.
2. The HTTP client polls `GET /tools` until the bridge responds.
3. Tool calls go through `POST /tools` with
   `{ "name": "...", "arguments": {...} }`.
4. On disconnect, the child process is terminated and the endpoint
   is released.

You can also start/stop the bridge manually from **Settings → AI →
Agent Connections** via the **Start** / **Stop** buttons without
opening an AI session.

## Discovery vs invocation pattern

The HTTP contract matches the standard NothingLess **http-bridge**
protocol:

```
GET  /tools   → JSON list of tool definitions
POST /tools   → { "name": "<tool>", "arguments": { ... } }
                Response: { "content": "...", "error": null }
```

Read tools (`list_windows`, `list_workspaces`, `list_monitors`,
`list_installed_apps`) return JSON strings. Write tools return
`Success` on stdout (or the axctl JSON output when relevant) and
surface stderr as `error` when axctl returns non-zero.

## Configuration overrides

Three environment variables are honored by `server.py`:

| Variable | Default | Effect |
|----------|---------|--------|
| `NOTHINGCLAW_HOST` | `127.0.0.1` | Bind address |
| `NOTHINGCLAW_PORT` | `8000` | Bind port |
| `NOTHINGCLAW_AXCTL` | `/usr/local/bin/axctl` | Path to the axctl binary |

The `.desktop` parser uses `LANG` (or `LC_ALL`) to pick the locale
variant of `Name[xx]=`; if no locale match is found it falls back to
the bare `Name=` line.

## Files

```
nothingclaw/
├── README.md        ← this file
├── requirements.txt ← stub, kept for tooling compatibility
└── server.py        ← stdlib HTTP bridge + axctl + app catalog
```

For the overall agent layout and how to ship additional agents next to
this one, see [`../README.md`](../README.md).