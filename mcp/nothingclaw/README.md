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
GET  /tools                              → JSON list of tool definitions (auto-detected tier)
GET  /tools?lite=true                    → 8 tools (legacy alias for capability=small)
GET  /tools?capability={tiny|small|medium|large}  → manual tier override
GET  /tools?model=<name>                 → auto-detect from model name
GET  /tools -H "X-Model-Name: <name>"    → same, via header
GET  /tools -H "X-Model-Host: <url>"     → override where Ollama is queried
POST /tools                              → { "name": "<tool>", "arguments": { ... } }
                                            Response: { "content": "...", "error": null }
```

Read tools (`list_windows`, `list_workspaces`, `list_monitors`,
`list_installed_apps`) return JSON strings. Write tools return
`Success` on stdout (or the axctl JSON output when relevant) and
surface stderr as `error` when axctl returns non-zero.

## Tuning for small local models

NothingClaw borrows a few patterns from how [Odysseus](https://github.com/pewdiepie-archdaemon/odysseus)
handles chat with limited local models (llama.cpp, Ollama on CPU,
etc.):

### Capability tiers

Tools are served in tiers that match what each model size can
realistically choose between:

| Tier | Tool count | Models |
|------|-----------|--------|
| `tiny`  | 4  | ≤3B params (e.g. granite3.1-dense:2b, qwen2.5:0.5b) |
| `small` | 8  | 3B–13B / local Ollama (e.g. qwen2.5:3b, llama3.2:3b, mistral:7b) |
| `medium`| 13 | 13B–30B / small cloud (gpt-3.5-turbo, claude-3-haiku, gemini-2.0-flash) |
| `large` | 23 | 30B+ / strong cloud (gpt-4o, claude-3-opus, deepseek-chat) |

The `tiny` set covers just the essentials (`list_windows`,
`list_installed_apps`, `move_window_to_workspace`,
`execute_command`). Each higher tier is a superset of the previous
one plus a few extras.

### How the tier is picked

Resolution order, highest precedence first:

1. `?capability=…` query param or `X-Capability` header — manual
   override.
2. `?model=…` query param or `X-Model-Name` header — the agent
   passes the active model name. The bridge then queries Ollama's
   `/api/show` for the real `details.parameter_size` and maps that
   to a tier. This is the ground truth path — name parsing fails
   on fine-tuned names like `my-llama-fork-v3` or models without
   a size suffix. Cloud models (GPT, Claude, Gemini, DeepSeek,
   Mistral) are matched by name against a known list since those
   endpoints don't expose `/api/show`.
3. `?lite=true` — legacy shortcut, equivalent to `capability=small`.
4. Default — `small`. The bridge runs locally so a misconfigured
   agent gets 8 tools instead of 23.

The Ollama lookup is cached for 5 minutes per `(model, endpoint)`
pair — model metadata doesn't change at runtime, so bursts of
discovery requests stay cheap. The cache key includes the endpoint
so a remote Ollama on a GPU box doesn't poison the local cache.

NothingLess's `HttpAgentClient` automatically passes `X-Model-Name`
when the agent profile has a `model` field set (the AI settings
panel exposes this), so the auto-detection works without any
extra config from the user — set the model name in the agent
profile and the bridge handles the rest.

### Compact tool results

- **`list_windows` and `list_installed_apps` return compact JSON
  by default** — only the fields the LLM needs to chain the next
  call (id, app_id, title, workspace_id for windows; id, name,
  source, command for apps). Full axctl payload (geometry,
  is_floating, is_fullscreen, pinned, icon path, etc.) is dropped
  to keep tool results small. Pass `"verbose": true` in arguments
  to get the raw payload when needed.

### Robustness

- **axctl silent-failure detection** — `_run_axctl` treats stderr
  lines starting with `Error:` as a failure even when exit code is
  0, so a failed `move-to` surfaces as `failed` instead of being
  reported as `moved`.
- **Workspace-name resolution** — non-numeric `workspace_id`
  arguments are resolved to the real ID via `axctl workspace list`
  before dispatch. Hyprland allows `name:code` workspaces but
  axctl's `move-to` only accepts IDs.
- **Post-move verification + 200ms retry** — `move_windows`
  re-lists windows after the move to confirm each one actually
  changed workspace; this catches the EVENT_WINDOW_MOVED
  propagation race in axctl's cache.

For a small Ollama model that previously timed out on
`list_installed_apps` (28 KB JSON output eating the entire context
window), the compact mode drops it to ~10 KB and the lite tool
list shrinks the system prompt by ~7 KB — together enough to fit
multi-turn agent flows on a 4 K-context local model. With the
Ollama-backed tier detection, a 2B param model gets 4 tools
instead of 23 without the user having to know the model's
parameter size in advance.

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