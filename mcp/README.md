# NothingLess MCP Agents

This folder collects **external AI agent bridges** that NothingLess can
load at runtime via the in-shell **Agent Connections** system (see
**Settings → AI → Agent Connections**).

Each subfolder is a self-contained agent:

```
mcp/
├── README.md           ← this file
├── nothingclaw/        ← first agent: HTTP bridge for the NothingClaw assistant
│   ├── README.md
│   ├── requirements.txt
│   └── server.py       ← stdlib-only HTTP bridge (no pip install needed)
└── <your-agent>/       ← drop a new agent here following the same layout
    ├── README.md
    ├── requirements.txt
    └── server.py
```

## Why this layout

NothingLess supports several connection topologies
(`http-bridge`, `mcp-sse`, `command`, `mcp-stdio`). Some agents bundle
their own server script and even their own dependency tree, so they
belong inside their own subdirectory rather than at the repo root.
Keeping each agent isolated also means:

- Per-agent Python dependency trees (no global `pip install` clashes).
- Per-agent start/stop from the shell UI.
- Easier to upstream — each agent can be a standalone repo if desired.

## How lifecycle works

When an agent profile declares an embedded `process` block, the
**NothingLess shell** spawns and tears down the bridge on demand:

- **Connect** → shell spawns `process.command` with `process.args` and
  `process.cwd`, then opens the HTTP / stdio client.
- **Disconnect** → client is closed and the child process is killed.
- **Start** / **Stop** buttons let you run the bridge without keeping
  an active AI session against it.

Agents without a `process` block are treated as plain bridges: the
shell only manages the HTTP client connection, and you are expected to
have the upstream server already running.

## Adding a new agent

1. `mkdir mcp/<your-agent>/`
2. Drop the agent code (`server.py`, requirements, README, etc.).
   Prefer **Python standard library** so nothing has to be installed —
   `http.server.ThreadingHTTPServer` is enough for a JSON-over-HTTP
   bridge.
3. Update `modules/widgets/config/AiPanel.qml` (and optionally
   `modules/sidebar/QuickAddAgentPopup.qml`) with a new preset chip
   that pre-fills the agent's `type` / `endpoint` / `toolsPath` /
   `invokePath` / `process` fields.
4. Document the agent in its own `README.md` and link it from this
   parent file.

The NothingClaw agent below is the reference implementation: a
self-contained stdlib HTTP bridge that the shell spawns and tears down
on demand.