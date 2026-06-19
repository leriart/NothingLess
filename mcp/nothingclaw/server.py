#!/usr/bin/env python3
"""NothingClaw MCP bridge — stdlib-only HTTP server.

Exposes a JSON-RPC-style HTTP API that NothingLess (or any
http-bridge compatible client) can consume to drive system-level
tools. The protocol mirrors the existing NothingLess HTTP-bridge
contract:

  GET  /tools   → JSON list of tool definitions
  POST /tools   → JSON { "name": "...", "arguments": {...} }

The response from POST /tools is JSON of the form:

  { "content": "string", "error": null }
  { "content": "",       "error": "string" }

Tool surface
------------
The axctl-backed tools are 1:1 wrappers around the axctl.c CLI
(https://github.com/leriart/axctl.c). Every category / action pair
matches a documented axctl method, so the agent's intent maps
directly onto the compositor's RPC layer without ad-hoc translation.

Pure standard library — no `pip install` required. The shell spawns
this file directly when the user clicks Connect on the NothingClaw
agent profile.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


# ---------------------------------------------------------------------------
# Tool registry
# ---------------------------------------------------------------------------
#
# Tool names and parameter schemas follow axctl.c's CLI as closely as
# possible. The schema's "description" fields steer the LLM toward
# the right tool for a given user request.

AXCTL = os.environ.get("NOTHINGCLAW_AXCTL", "/usr/local/bin/axctl")


def _str(description):
    return {"type": "string", "description": description}


def _str_enum(values, description):
    return {"type": "string", "enum": list(values), "description": description}


def _bool(description):
    return {"type": "boolean", "description": description}


def _int(description):
    return {"type": "integer", "description": description}


def _arr(items, description):
    return {"type": "array", "items": items, "description": description}


def _obj(props, required):
    return {
        "type": "object",
        "properties": props,
        "required": list(required),
        "additionalProperties": False
    }


# ---------------------------------------------------------------------------
# Capability tiers
# ---------------------------------------------------------------------------
#
# Different model sizes cope with different tool counts. A 1B param local
# model can't reliably pick between 23 tools; a 70B model can. We serve
# a different subset per tier and let the agent either ask for a specific
# one (?capability=) or let us auto-detect from the model name.
#
# Tiers are additive — each higher tier is a superset of the previous one
# plus a few extras. Names align with the common heuristic ranges:
#   tiny    ≤3B params     (~4 tools)
#   small   3B–13B / Ollama (~8 tools)  ← default for local models
#   medium  13B–30B        (~14 tools)
#   large   30B+ / API     (all 23)
#
# Inspired by Odysseus's intent-based tool selection but kept as a static
# lookup table — no embeddings, no RAG, no async wait. Tradeoff: the agent
# has to live with a hardcoded subset per tier instead of getting exactly
# the 8 most-relevant tools, but it's deterministic, fast, and works on
# any CPU-only local model without extra deps.

_TOOL_TIERS = {
    "tiny": [
        "list_windows",
        "list_installed_apps",
        "move_window_to_workspace",
        "open_url",
        "execute_command",
    ],
    "small": [
        "list_windows",
        "list_installed_apps",
        "list_workspaces",
        "move_window_to_workspace",
        "move_windows",
        "open_url",
        "open_app",
        "close_app",
        "execute_command",
    ],
    "medium": [
        # Everything in small, plus:
        "list_monitors",
        "focus_window",
        "close_window",
        "switch_workspace",
        "move_window_to_monitor",
    ],
    # "large" serves the full set — see TOOLS below.
}


# Pre-computed union of each tier with everything below it. Avoids
# recomputing the additive merge on every GET /tools request.
_TIER_NAMES = {
    "tiny": _TOOL_TIERS["tiny"],
    "small": _TOOL_TIERS["tiny"] + _TOOL_TIERS["small"],
    "medium": (_TOOL_TIERS["tiny"]
               + _TOOL_TIERS["small"]
               + _TOOL_TIERS["medium"]),
}


_CLOUD_MODEL_HINTS = {
    # OpenAI
    "gpt-5": "large",
    "gpt-4o": "large",
    "gpt-4-turbo": "large",
    "gpt-4": "large",
    "o1-preview": "large",
    "o1-mini": "medium",
    "o3-mini": "medium",
    "gpt-3.5-turbo": "medium",
    # Anthropic
    "claude-3-opus": "large",
    "claude-3.5-sonnet": "large",
    "claude-3-sonnet": "medium",
    "claude-3.5-haiku": "medium",
    "claude-3-haiku": "medium",
    # Google
    "gemini-1.5-pro": "large",
    "gemini-1.5-flash": "medium",
    "gemini-2.0-pro": "large",
    "gemini-2.0-flash": "medium",
    # Mistral / Groq
    "mistral-large": "large",
    "mistral-medium": "medium",
    "mistral-small": "medium",
    "mixtral-8x7b": "medium",
    "llama-3.1-70b": "large",
    "llama-3.1-405b": "large",
    # DeepSeek
    "deepseek-chat": "large",
    "deepseek-reasoner": "large",
    "deepseek-coder": "medium",
}


_LOCAL_HOST_HINTS = ("localhost", "127.0.0.1", "host.docker.internal", "::1")


# Cache for Ollama /api/show responses. Model metadata is essentially
# static (parameter size, family, context length don't change at runtime),
# so a short TTL avoids re-querying on every /tools hit when the agent
# reconnects frequently. 5 min is long enough that bursts of model
# lookups are cheap, short enough that a freshly-pulled model with a
# bigger parameter size takes effect quickly.
_OLLAMA_SHOW_CACHE = {}
_OLLAMA_SHOW_TTL = 300


def _ollama_show(model_name, endpoint="http://127.0.0.1:11434"):
    """Query Ollama's /api/show for `model_name`. Returns parsed JSON or None.

    Returns None on any failure (network, timeout, model not found,
    malformed JSON). Callers should fall back to name-based heuristics
    when None is returned — Ollama might be remote, down, or serving
    a non-Ollama backend the agent is talking to.

    The Ollama /api/show payload exposes ground-truth capability info
    that name parsing can't reliably recover from:

      details.parameter_size   "7B" / "13B" / "2.5B"
      details.family           "qwen2" / "llama" / ...
      details.quantization_level
      capabilities             ["completion", "tools", ...]
      model_info.<family>.context_length   32768

    Of these, parameter_size is the one we map to a tool tier.
    """
    if not model_name:
        return None
    cache_key = (str(model_name).strip().lower(), endpoint.strip().lower())
    cached = _OLLAMA_SHOW_CACHE.get(cache_key)
    if cached is not None:
        ts, payload = cached
        if (time.time() - ts) < _OLLAMA_SHOW_TTL:
            return payload
    url = endpoint.rstrip("/") + "/api/show"
    try:
        result = subprocess.run(
            ["curl", "-s", "--max-time", "3", "-X", "POST", url,
             "-H", "Content-Type: application/json",
             "-d", json.dumps({"name": model_name})],
            capture_output=True, text=True, timeout=4
        )
    except (subprocess.TimeoutExpired, OSError, Exception):
        return None
    if result.returncode != 0 or not result.stdout.strip():
        return None
    try:
        data = json.loads(result.stdout)
    except (TypeError, ValueError):
        return None
    if not isinstance(data, dict) or "error" in data:
        return None
    _OLLAMA_SHOW_CACHE[cache_key] = (time.time(), data)
    return data


def _parse_ollama_param_size(size_str):
    """Convert Ollama's parameter_size ('7B', '2.5B', '500M') to float billions.

    Returns None for unparseable input. We accept M (millions) and K
    (thousands) for completeness, though Ollama typically reports in B.
    """
    if not size_str:
        return None
    m = re.match(r"^\s*(\d+(?:\.\d+)?)\s*([BMK]?)\s*$", str(size_str).strip().upper())
    if not m:
        return None
    value = float(m.group(1))
    unit = m.group(2)
    if unit == "M":
        return value / 1000.0
    if unit == "K":
        return value / 1_000_000.0
    return value


def _params_to_tier(params_b):
    """Map a parameter count in billions to one of our tool tiers."""
    if params_b is None:
        return None
    if params_b <= 3:
        return "tiny"
    if params_b <= 13:
        return "small"
    if params_b <= 30:
        return "medium"
    return "large"


def _detect_capability(model_name, host=""):
    """Return a tier name ('tiny'|'small'|'medium'|'large') for the model.

    Resolution order:
      1. Known cloud model name (substring match against _CLOUD_MODEL_HINTS).
      2. Ollama /api/show — if the host looks like an Ollama endpoint
         we ask the daemon directly for `details.parameter_size`.
         This is the ground truth: name parsing fails on fine-tuned
         names ("my-llama-fork-v3") or models without a size suffix.
      3. Parameter-size suffix on the model name (e.g. "7b" → small).
      4. Local-provider keyword in the name.
      5. Fallback: 'small' (safe default for a local bridge).

    The host arg is optional; if empty we assume the standard local
    Ollama endpoint (127.0.0.1:11434). Agents can override via
    X-Model-Host / ?host= so a remote Ollama on a GPU box is also
    detectable.
    """
    if not model_name:
        return "small"
    name_lower = model_name.lower().strip()

    # 1. Known cloud models (substring on the model name).
    for needle, tier in _CLOUD_MODEL_HINTS.items():
        if needle in name_lower:
            return tier

    # 2. Ollama /api/show — the reliable path for local models.
    #    Skip the network call if the name obviously points to a
    #    non-Ollama backend (a 'gpt-' prefix, an anthropic name, etc.)
    #    to avoid hanging on every /tools call when the daemon is down.
    ollama_endpoint = host if (host and "11434" in host) else "http://127.0.0.1:11434"
    skip_ollama = any(p in name_lower
                      for p in ("gpt-", "claude", "gemini", "mistral-",
                                "groq/", "deepseek-chat", "deepseek-reasoner",
                                "minimax", "/v1", "openai.com", "anthropic.com"))
    if not skip_ollama:
        show = _ollama_show(model_name, ollama_endpoint)
        if show:
            details = show.get("details") or {}
            params_b = _parse_ollama_param_size(details.get("parameter_size"))
            tier = _params_to_tier(params_b)
            if tier:
                return tier
            # Ollama responded but no parseable parameter_size — fall
            # through to name heuristics below instead of defaulting.

    # 3. Parameter size suffix on the model name. Common Ollama/HF
    #    naming: ":7b", ":13b", "Llama-3.2-3B-Instruct", "Qwen2.5-7B".
    size_match = re.search(r"(\d+(?:\.\d+)?)\s*([bm])\b", name_lower)
    if size_match:
        size = float(size_match.group(1))
        unit = size_match.group(2)
        params_b = size if unit == "b" else size / 1000.0
        if params_b <= 3:
            return "tiny"
        if params_b <= 13:
            return "small"
        if params_b <= 30:
            return "medium"
        return "large"

    # 4. Provider hints. Local providers default to 'small' unless we
    #    have evidence otherwise.
    local_providers = ("ollama", "llama.cpp", "llamacpp", "lm-studio",
                      "lmstudio", "kobold", "oobabooga", "local")
    if any(p in name_lower for p in local_providers):
        return "small"

    # 5. Fallback: small. The bridge runs locally, so defaulting to the
    #    safer tier means a misconfigured agent gets 8 tools instead of 23.
    return "small"


def _filter_tools_for_capability(tier):
    """Return TOOLS filtered to the given tier.

    Tiers are cumulative: 'medium' = tiny + small + medium extras.
    'large' returns the full TOOLS list.
    """
    if not tier or tier == "large":
        return list(TOOLS)
    if tier not in _TIER_NAMES:
        return list(TOOLS)
    names = set(_TIER_NAMES[tier])
    return [t for t in TOOLS if t["name"] in names]


TOOLS = [
    # ── Read-only introspection ──────────────────────────────────────
    {
        "name": "list_windows",
        "description": "List every window the compositor knows about. "
                       "Returns JSON with id, title, app_id, workspace_id, "
                       "is_focused, is_floating, is_fullscreen, monitor_id, "
                       "pinned and geometry. Call this before focus_window / "
                       "close_window / move_window_to_workspace when you need "
                       "to look up an app's window id by name.",
        "parameters": _obj({}, [])
    },
    {
        "name": "list_workspaces",
        "description": "List every workspace with id, name, monitor_id, "
                       "is_active and is_empty.",
        "parameters": _obj({}, [])
    },
    {
        "name": "list_monitors",
        "description": "List every connected monitor with id, name, "
                       "description, width, height, refresh_rate, "
                       "is_focused and is_active.",
        "parameters": _obj({}, [])
    },

    # ── Window operations ────────────────────────────────────────────
    {
        "name": "focus_window",
        "description": "Bring a window to focus. Pass either `window_id` "
                       "(use list_windows to look it up) OR `direction` "
                       "(one of l/r/u/d) to focus the neighbour in that "
                       "direction.",
        "parameters": _obj({
            "window_id": _str("Window id (e.g. '0x55c18cfa9170'). Omit when using direction."),
            "direction": _str_enum(["l", "r", "u", "d"],
                                    "Direction to focus when window_id is omitted.")
        }, [])
    },
    {
        "name": "close_window",
        "description": "Close a window. Omit window_id to close the currently "
                       "focused window.",
        "parameters": _obj({
            "window_id": _str("Window id. Omit to close the active window.")
        }, [])
    },
    {
        "name": "toggle_window_floating",
        "description": "Toggle a window between tiled and floating. Omit "
                       "window_id to target the active window.",
        "parameters": _obj({
            "window_id": _str("Window id. Omit to target the active window.")
        }, [])
    },
    {
        "name": "set_window_fullscreen",
        "description": "Set fullscreen state on a window (true = fullscreen, "
                       "false = windowed).",
        "parameters": _obj({
            "state": _bool("True to enter fullscreen, false to leave it."),
            "window_id": _str("Window id. Omit to target the active window.")
        }, ["state"])
    },
    {
        "name": "resize_window",
        "description": "Resize a window in pixels. The compositor applies the "
                       "size hint to the active or specified window.",
        "parameters": _obj({
            "width": _int("New width in pixels."),
            "height": _int("New height in pixels."),
            "window_id": _str("Window id. Omit to target the active window.")
        }, ["width", "height"])
    },
    {
        "name": "move_window_direction",
        "description": "Move the active (or specified) window in a cardinal "
                       "direction. Useful for swapping positions in the "
                       "tiling layout.",
        "parameters": _obj({
            "direction": _str_enum(["l", "r", "u", "d"], "Direction to swap with."),
            "window_id": _str("Window id. Omit to target the active window.")
        }, ["direction"])
    },

    # ── Workspace operations ─────────────────────────────────────────
    {
        "name": "switch_workspace",
        "description": "Switch the focused workspace.",
        "parameters": _obj({
            "workspace_id": _str("Target workspace id (e.g. '1', '4', or a name).")
        }, ["workspace_id"])
    },
    {
        "name": "move_window_to_workspace",
        "description": "Move a window to a different workspace. Omit "
                       "window_id to move the currently focused window.",
        "parameters": _obj({
            "workspace_id": _str("Target workspace id."),
            "window_id": _str("Window id. Omit to move the active window.")
        }, ["workspace_id"])
    },
    {
        "name": "move_windows",
        "description": "Move one or more windows to one or more workspaces "
                       "in a single batch operation. Two modes are supported, "
                       "mutually exclusive:\n"
                       "  (1) MANY-TO-ONE — provide `workspace_id` together "
                       "with EITHER `window_ids` (list of explicit window "
                       "ids obtained from list_windows) OR `app_names` (list "
                       "of case-insensitive substrings matched against each "
                       "window's app_id / title / wm_class). Every matching "
                       "window is moved to the same target workspace. Useful "
                       "for tasks like 'move all Firefox and Spotify windows "
                       "to workspace 3'.\n"
                       "  (2) MANY-TO-MANY — provide `assignments`, a list of "
                       "{window_id, workspace_id} pairs. Each window is "
                       "moved to its own target workspace in one call. Useful "
                       "for distributing several windows across several "
                       "workspaces without chaining individual move calls.\n"
                       "Returns JSON with a `moved` list (successful moves), "
                       "a `failed` list (per-window errors), and the total "
                       "number of pairs that were attempted. A failure on one "
                       "window does NOT abort the rest of the batch.",
        "parameters": _obj({
            "window_ids": _arr(
                _str("Window id, e.g. '0x55c18cfa9170'."),
                "List of explicit window ids to move. Use list_windows to "
                "look up ids. Used only in many-to-one mode."
            ),
            "app_names": _arr(
                _str("Substring to match against window.app_id, window.title "
                     "or window.wm_class (case-insensitive). Examples: "
                     "'Firefox', 'Spotify', 'code'."),
                "Alternative to window_ids: every window whose app_id, title "
                "or wm_class contains one of these substrings is moved to "
                "the target workspace. Used only in many-to-one mode."
            ),
            "workspace_id": _str(
                "Single target workspace id (e.g. '1', '4', or a workspace "
                "name). Required when using window_ids or app_names."
            ),
            "assignments": _arr(
                _obj({
                    "window_id": _str("Window id to move."),
                    "workspace_id": _str("Target workspace id for this window.")
                }, ["window_id", "workspace_id"]),
                "Per-window target list for many-to-many mode. Each item "
                "maps one window to one workspace. Example: "
                "[{\"window_id\":\"0x55..\",\"workspace_id\":\"2\"}, "
                "{\"window_id\":\"0x56..\",\"workspace_id\":\"5\"}]."
            )
        }, [])
    },
    {
        "name": "toggle_special_workspace",
        "description": "Toggle a Hyprland 'special' workspace by name "
                       "(typically 'scratchpad' or a custom name).",
        "parameters": _obj({
            "name": _str("Special workspace name, e.g. 'scratchpad'.")
        }, ["name"])
    },

    # ── Monitor operations ───────────────────────────────────────────
    {
        "name": "focus_monitor",
        "description": "Focus a monitor by id. The currently focused window "
                       "follows focus.",
        "parameters": _obj({
            "monitor_id": _str("Monitor id (e.g. 'HDMI-A-1', '0').")
        }, ["monitor_id"])
    },
    {
        "name": "move_window_to_monitor",
        "description": "Move a window to a different monitor.",
        "parameters": _obj({
            "monitor_id": _str("Target monitor id."),
            "window_id": _str("Window id. Omit to target the active window.")
        }, ["monitor_id"])
    },

    # ── Layout ───────────────────────────────────────────────────────
    {
        "name": "set_layout",
        "description": "Set the active tiling layout (e.g. 'dwindle', "
                       "'master', 'spiral' — exact names depend on the "
                       "compositor).",
        "parameters": _obj({
            "name": _str("Layout name.")
        }, ["name"])
    },

    # ── System / general ────────────────────────────────────────────
    {
        "name": "execute_command",
        "description": "Run an arbitrary shell command via the compositor's "
                       "IPC layer (so it is dispatched in the same way as a "
                       "keybind would). Use for arbitrary actions not "
                       "covered by other tools (e.g. opening a URL, running "
                       "a one-shot script).",
        "parameters": _obj({
            "command": _str("Shell command to execute.")
        }, ["command"])
    },
    {
        "name": "check_program_installed",
        "description": "Check whether a program is on PATH and return its "
                       "absolute path. Useful before launching a program "
                       "the user might not have installed.",
        "parameters": _obj({
            "program_name": _str("Program name to look up on $PATH.")
        }, ["program_name"])
    },
    {
        "name": "launch_program",
        "description": "Launch a GUI application in the background "
                       "(`nohup <program> &`). Use for opening apps the user "
                       "already has installed (zen-browser, firefox, code, "
                       "etc.). For 'is this installed?' check "
                       "check_program_installed first.",
        "parameters": _obj({
            "program_name": _str("Executable name on $PATH, optionally with "
                                 "arguments (e.g. 'firefox --new-window').")
        }, ["program_name"])
    },
    {
        "name": "install_package",
        "description": "Install a system package via the distro's package "
                       "manager (pacman / dnf / apt). Requires sudo without "
                       "a password prompt; if sudo fails, the tool returns "
                       "the exact command so the user can run it themselves.",
        "parameters": _obj({
            "package_name": _str("Package name as known by the package manager.")
        }, ["package_name"])
    },

    # ── App catalog (native, flatpak, snap, AppImage) ───────────────
    {
        "name": "list_installed_apps",
        "description": "List every GUI application installed on this system. "
                       "Aggregates .desktop files from the standard dirs "
                       "($HOME/.local/share/applications, /usr/share/applications, "
                       "/usr/local/share/applications), flatpak exports, and any "
                       "*.AppImage files in $HOME/Applications and $HOME/.local/bin. "
                       "Returns JSON with id, name, generic_name, comment, "
                       "source (native/flatpak/snap/appimage), command, icon, "
                       "categories. Use this when the user asks 'what apps do I "
                       "have?' or before open_app to find the exact display name.",
        "parameters": _obj({
            "filter": _str("Optional case-insensitive substring filter against "
                           "name / generic_name / comment.")
        }, [])
    },
    {
        "name": "open_url",
        "description": "Open a URL in the user's default browser via xdg-open. "
                       "USE THIS for any 'open X in browser' / 'go to X' / "
                       "'browse to X' request. Accepts full URLs ('https://youtube.com') "
                       "or short aliases ('youtube', 'github', 'gmail') that this "
                       "bridge auto-expands. Do NOT use open_app for URLs — open_app "
                       "launches NATIVE desktop apps (Firefox, Spotify, etc.) and "
                       "will not interpret a website URL.",
        "parameters": _obj({
            "url": _str("URL or short alias. Examples: 'https://youtube.com', "
                        "'youtube.com', 'youtube', 'github.com/Leriart', 'gmail'.")
        }, ["url"])
    },
    {
        "name": "open_app",
        "description": "Open a NATIVE GUI application by name (Firefox, Zen Browser, "
                       "Spotify, Code, etc.). Searches the installed-apps catalog "
                       "(.desktop files + flatpak + snap + AppImage) and launches "
                       "the matching entry. PREFER THIS OVER launch_program for "
                       "GUI apps — it resolves the right Exec= line, finds apps by "
                       "display name, and supports flatpak/snap packages that "
                       "'command not found' would never reach. "
                       "FOR URLs / WEBSITES use open_url instead — this tool "
                       "does NOT accept URLs and will launch the wrong app if you "
                       "pass one. Use check_program_installed first if you want to "
                       "confirm something exists before opening it.",
        "parameters": _obj({
            "app_name": _str("App display name (e.g. 'Firefox', 'Zen Browser', "
                             "'Code', 'Spotify'). Case-insensitive substring match. "
                             "DO NOT pass URLs here — use open_url for those.")
        }, ["app_name"])
    },
    {
        "name": "close_app",
        "description": "Close every window belonging to an app by name. Lists "
                       "windows via axctl, filters by app_id or title match, then "
                       "closes each match. Returns the list of closed window ids. "
                       "Use this when the user asks to close / quit / kill a "
                       "specific application (e.g. 'close Firefox', 'quit Discord').",
        "parameters": _obj({
            "app_name": _str("App name or window title substring (case-insensitive). "
                             "Matches against window.app_id first, then window.title.")
        }, ["app_name"])
    }
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _detect_package_manager():
    """Return (sudo_prefix, manager_name) for the current distro."""
    try:
        with open("/etc/os-release", "r") as fp:
            contents = fp.read().lower()
    except Exception:
        return ("sudo pacman -S --noconfirm", "pacman")
    if "arch" in contents or "cachyos" in contents or "manjaro" in contents:
        return ("sudo pacman -S --noconfirm", "pacman")
    if "fedora" in contents or "nobara" in contents:
        return ("sudo dnf install -y", "dnf")
    if "debian" in contents or "ubuntu" in contents or "pop" in contents:
        return ("sudo apt-get install -y", "apt")
    return ("sudo pacman -S --noconfirm", "pacman")


def _run_axctl(argv, timeout=15):
    """Run `AXCTL <argv>` and return a (content, error) pair.

    axctl prints Success on stdout for write operations and pretty-
    printed JSON for read operations. Errors are written to stderr
    and (usually) come with a non-zero exit code. We surface both.
    """
    cmd = [AXCTL] + list(argv)
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout, env=os.environ
        )
    except subprocess.TimeoutExpired:
        return {"content": "", "error": "axctl command timed out after " + str(timeout) + "s"}
    except FileNotFoundError:
        return {
            "content": "",
            "error": "axctl binary not found at " + AXCTL +
                     " — install it from https://github.com/leriart/axctl.c"
        }
    except Exception as exc:
        return {"content": "", "error": str(exc)}

    out = result.stdout.strip()
    err = result.stderr.strip()
    if result.returncode == 0:
        # axctl sometimes writes "Error: …" to stderr but still exits 0
        # (a known axctl.c quirk for invalid workspace targets and similar).
        # Treat that as a failure so the caller can surface it instead of
        # reporting "Success" while the move silently didn't happen.
        if err and any(line.startswith("Error:") for line in err.splitlines()):
            return {"content": "", "error": err}
        return {"content": out or "Success", "error": None}
    return {"content": "", "error": err or ("axctl exited with code " + str(result.returncode))}


def _compact_windows(windows):
    """Strip a window entry down to the fields a tool-calling LLM actually
    needs to pick the right window: id, app_id, title, workspace_id.

    Local small models struggle with the full axctl payload (per-window
    metadata: monitor_id, x/y/width/height, is_focused, is_floating,
    is_fullscreen, pinned, is_hidden). Those fields burn ~250 chars
    per window that the model has to keep in context for no benefit.
    Mirrors the 'pre-format results' pattern Odysseus uses for its
    read tools — the caller can still get the full payload by passing
    `verbose=true` to list_windows.
    """
    out = []
    for w in windows:
        if not isinstance(w, dict):
            continue
        entry = {
            "id": w.get("id"),
            "app_id": w.get("app_id"),
            "title": w.get("title"),
            "workspace_id": w.get("workspace_id"),
        }
        out.append({k: v for k, v in entry.items() if v is not None})
    return out


def _compact_apps(apps):
    """Reduce an .desktop catalog entry to fields useful for tool picking.

    The full .desktop export has 12+ fields per app (generic_name,
    comment, icon path, categories, wmclass, desktop_file path). For
    200+ apps that's 28KB+ of JSON — way past what a small local model
    can parse in a single tool result. We keep: id (for matching),
    name (for display), source (so the LLM knows it's a flatpak etc.),
    command (so it can verify what would actually run).
    """
    out = []
    for a in apps:
        if not isinstance(a, dict):
            continue
        entry = {
            "id": a.get("id"),
            "name": a.get("name"),
            "source": a.get("source"),
            "command": a.get("command"),
        }
        out.append({k: v for k, v in entry.items() if v})
    return out


def _str_arg(args, key, default=None):
    """Extract a non-empty string argument. Empty strings fall back to default."""
    val = args.get(key, default)
    if val is None:
        return None
    val = str(val).strip()
    if val == "":
        return default
    return val


def _bool_arg(args, key, default=None):
    val = args.get(key, default)
    if val is None:
        return default
    if isinstance(val, bool):
        return val
    if isinstance(val, str):
        if val.lower() in ("true", "1", "yes", "on"):
            return True
        if val.lower() in ("false", "0", "no", "off"):
            return False
    return default


def _resolve_workspace_id(ws_arg):
    """Resolve a workspace name to its numeric ID via `axctl workspace list`.

    Hyprland workspaces can be named (e.g. "code", "web") but axctl's
    `workspace move-to` only accepts IDs. If the caller passes a name,
    we look it up and return the matching ID. Numeric IDs are returned
    unchanged so we don't add an IPC roundtrip in the common case.

    Returns the original arg unchanged if lookup fails.
    """
    if ws_arg is None:
        return ws_arg
    s = str(ws_arg).strip()
    if not s:
        return ws_arg
    if s.isdigit():
        return s
    list_result = _run_axctl(["workspace", "list"])
    if list_result.get("error"):
        return ws_arg
    try:
        workspaces = json.loads(list_result.get("content", "[]"))
    except (TypeError, ValueError):
        return ws_arg
    for w in workspaces:
        if not isinstance(w, dict):
            continue
        wid = w.get("id")
        wname = w.get("name")
        if wid is not None and str(wid) == s:
            return s
        if wname is not None and str(wname) == s:
            return str(wid) if wid is not None else s
    return ws_arg


# ---------------------------------------------------------------------------
# App catalog (native, flatpak, snap, AppImage)
# ---------------------------------------------------------------------------
#
# The catalog is built lazily on first use and cached in memory for
# APPS_CACHE_TTL seconds. Re-scanning all .desktop files on every
# open_app call would add noticeable latency (200+ files on a typical
# desktop install). The cache is invalidated automatically when
# list_installed_apps is called with `force_refresh=true`, or when
# the caller passes a fresh `filter`.

DESKTOP_DIRS = [
    os.path.expanduser("~/.local/share/applications"),
    "/usr/local/share/applications",
    "/usr/share/applications",
    "/var/lib/flatpak/exports/share/applications",
    os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
    "/var/lib/snapd/desktop/applications",
]

APPIMAGE_DIRS = [
    os.path.expanduser("~/Applications"),
    os.path.expanduser("~/AppImages"),
    os.path.expanduser("~/.local/bin"),
    os.path.expanduser("~/.local/share/applications"),
    "/opt",
]

APPS_CACHE = None              # type: list
APPS_CACHE_TIME = 0            # type: float
APPS_CACHE_TTL = 60            # seconds


def _parse_desktop(path):
    """Parse a .desktop file and return a normalized entry dict.

    Returns None for entries that should be skipped: Type !=
    Application, Hidden=true, NoDisplay=true, terminal apps, or
    missing Name/Exec.
    """
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as fp:
            lines = fp.readlines()
    except OSError:
        return None

    entry = None
    in_section = False
    # Localization: Name[es]=, Name[fr]=, ... We fall back to the
    # bare Name= if no LANG match.
    locale = os.environ.get("LANG", "").split(".")[0].split("_")[0]
    names_by_locale = {}
    name_default = None

    for raw in lines:
        line = raw.strip()
        if line.startswith("#"):
            continue
        # Section headers don't carry a `=`, so they must be matched
        # before the "no `=` → skip" guard below or we'd silently
        # drop `[Desktop Entry]` and never enter the entry body.
        if line.startswith("["):
            if entry is None and line == "[Desktop Entry]":
                entry = {"__path__": path}
                in_section = True
            else:
                # Leaving [Desktop Entry] (e.g. into [Desktop Action])
                in_section = False
            continue
        if "=" not in line:
            continue
        if not in_section or entry is None:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip()

        if key.startswith("Name[") and key.endswith("]"):
            loc = key[5:-1].split("_")[0]
            names_by_locale[loc] = val
            continue
        if key == "Name":
            name_default = val
            continue
        if key in ("Type", "Hidden", "NoDisplay", "Terminal",
                   "Exec", "GenericName", "Comment", "Icon",
                   "Categories", "StartupWMClass"):
            entry[key] = val

    if entry is None:
        return None
    if entry.get("Type") and entry["Type"] != "Application":
        return None
    if entry.get("Hidden", "").lower() == "true":
        return None
    if entry.get("NoDisplay", "").lower() == "true":
        return None
    if entry.get("Terminal", "").lower() == "true":
        return None

    # Pick the best Name: locale match > bare Name.
    name = names_by_locale.get(locale) or name_default
    if not name or "Exec" not in entry:
        return None

    source = "native"
    p = path
    if "/flatpak/" in p:
        source = "flatpak"
    elif "/snapd/" in p:
        source = "snap"

    return {
        "id": os.path.basename(p).replace(".desktop", ""),
        "name": name,
        "generic_name": entry.get("GenericName", ""),
        "comment": entry.get("Comment", ""),
        "command": entry["Exec"],
        "icon": entry.get("Icon", ""),
        "categories": entry.get("Categories", ""),
        "wmclass": entry.get("StartupWMClass", ""),
        "source": source,
        "desktop_file": p
    }


def _scan_desktop_dirs():
    """Walk all known desktop directories and yield parsed entries."""
    seen_ids = set()
    for d in DESKTOP_DIRS:
        if not os.path.isdir(d):
            continue
        try:
            names = os.listdir(d)
        except OSError:
            continue
        for fn in names:
            if not fn.endswith(".desktop"):
                continue
            entry = _parse_desktop(os.path.join(d, fn))
            if entry is None:
                continue
            # Flatpak exports can overlap; first source wins.
            if entry["id"] in seen_ids:
                continue
            seen_ids.add(entry["id"])
            yield entry


def _scan_flatpak_cli():
    """Catch flatpak apps that ship without a .desktop export."""
    flatpak_bin = shutil.which("flatpak")
    if not flatpak_bin:
        return
    try:
        out = subprocess.run(
            [flatpak_bin, "list", "--app", "--columns=name,application"],
            capture_output=True, text=True, timeout=8
        )
    except (subprocess.TimeoutExpired, OSError):
        return
    if out.returncode != 0:
        return
    for line in out.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        name = parts[0].strip()
        app_id = parts[1].strip()
        if not name or not app_id:
            continue
        yield {
            "id": app_id,
            "name": name,
            "generic_name": "",
            "comment": "",
            "command": "flatpak run " + app_id,
            "icon": "",
            "categories": "",
            "wmclass": "",
            "source": "flatpak",
            "desktop_file": ""
        }


def _scan_snap_cli():
    """Catch installed snaps (no .desktop file on most distros)."""
    snap_bin = shutil.which("snap")
    if not snap_bin:
        return
    try:
        out = subprocess.run(
            [snap_bin, "list"], capture_output=True, text=True, timeout=8
        )
    except (subprocess.TimeoutExpired, OSError):
        return
    if out.returncode != 0:
        return
    lines = out.stdout.splitlines()
    if len(lines) < 2:
        return
    # Header is "Name Version Rev Tracking Publisher Notes".
    for line in lines[1:]:
        cols = line.split()
        if len(cols) < 2:
            continue
        name = cols[0]
        yield {
            "id": "snap:" + name,
            "name": name,
            "generic_name": "",
            "comment": "",
            "command": "snap run " + name,
            "icon": "",
            "categories": "",
            "wmclass": "",
            "source": "snap",
            "desktop_file": ""
        }


def _scan_appimages():
    """Walk common AppImage directories and yield executable entries."""
    for d in APPIMAGE_DIRS:
        if not os.path.isdir(d):
            continue
        try:
            names = os.listdir(d)
        except OSError:
            continue
        for fn in names:
            lower = fn.lower()
            if not (lower.endswith(".appimage") or lower.endswith(".app")):
                continue
            full = os.path.join(d, fn)
            if not os.path.isfile(full) or not os.access(full, os.X_OK):
                continue
            # Use the filename (minus extension) as the display name.
            stem = fn
            for ext in (".AppImage", ".appimage", ".app"):
                if stem.endswith(ext):
                    stem = stem[: -len(ext)]
                    break
            nice_name = stem.replace("_", " ").replace("-", " ").strip()
            if not nice_name:
                nice_name = stem
            yield {
                "id": "appimage:" + full,
                "name": nice_name,
                "generic_name": "",
                "comment": "",
                "command": full,
                "icon": "",
                "categories": "",
                "wmclass": "",
                "source": "appimage",
                "desktop_file": ""
            }


def _build_apps_catalog():
    """Aggregate every GUI app on the system. Dedupes by id."""
    catalog = {}
    sources = (
        list(_scan_desktop_dirs())
        + list(_scan_flatpak_cli())
        + list(_scan_snap_cli())
        + list(_scan_appimages())
    )
    for entry in sources:
        if entry["id"] in catalog:
            continue
        catalog[entry["id"]] = entry
    return sorted(catalog.values(), key=lambda a: a["name"].lower())


def _get_apps_catalog(force_refresh=False):
    """Return the cached catalog, rebuilding if stale or forced."""
    global APPS_CACHE, APPS_CACHE_TIME
    now = time.time()
    if (not force_refresh
            and APPS_CACHE is not None
            and (now - APPS_CACHE_TIME) < APPS_CACHE_TTL):
        return APPS_CACHE
    APPS_CACHE = _build_apps_catalog()
    APPS_CACHE_TIME = now
    return APPS_CACHE


def _strip_exec_placeholders(exec_line):
    """Strip %u/%f/%F/%U/%c/%i etc. so the command is shell-safe."""
    import re as _re
    # Common desktop entry placeholders.
    return _re.sub(r"%[a-zA-Z]", "", exec_line).strip()


def _find_app(name, catalog):
    """Return the best catalog entry matching `name`, or None.

    Match strategy (most specific first):
      1. Exact case-insensitive name match.
      2. Case-insensitive substring match on name.
      3. Substring match on generic_name.
      4. Substring match on id (without the desktop/.snap:/appimage: prefix).
    """
    needle = name.strip().lower()
    if not needle:
        return None

    # 1. Exact name.
    for entry in catalog:
        if entry["name"].lower() == needle:
            return entry
    # 2. Substring on name.
    for entry in catalog:
        if needle in entry["name"].lower():
            return entry
    # 3. Generic name.
    for entry in catalog:
        if entry.get("generic_name") and needle in entry["generic_name"].lower():
            return entry
    # 4. ID match (strip the snap:/appimage: prefixes).
    for entry in catalog:
        bare_id = entry["id"]
        for prefix in ("snap:", "appimage:"):
            if bare_id.startswith(prefix):
                bare_id = bare_id[len(prefix):]
                break
        if needle in bare_id.lower():
            return entry
    return None


# ---------------------------------------------------------------------------
# Tool dispatch
# ---------------------------------------------------------------------------

def invoke_tool(name, arguments):
    args = arguments or {}

    # ── Introspection ────────────────────────────────────────────────
    if name == "list_windows":
        result = _run_axctl(["window", "list"])
        if result.get("error"):
            return result
        try:
            windows = json.loads(result.get("content", "[]"))
        except (TypeError, ValueError):
            return result
        verbose = _bool_arg(args, "verbose")
        if not verbose:
            windows = _compact_windows(windows)
        return {
            "content": json.dumps(windows, ensure_ascii=False, indent=2),
            "error": None
        }
    if name == "list_workspaces":
        return _run_axctl(["workspace", "list"])
    if name == "list_monitors":
        return _run_axctl(["monitor", "list"])

    # ── Window ops ──────────────────────────────────────────────────
    if name == "focus_window":
        wid = _str_arg(args, "window_id")
        direction = _str_arg(args, "direction")
        if wid:
            return _run_axctl(["window", "focus", wid])
        if direction:
            return _run_axctl(["window", "focus-dir", direction])
        return {"content": "", "error": "focus_window needs either window_id or direction"}

    if name == "close_window":
        argv = ["window", "close"]
        wid = _str_arg(args, "window_id")
        if wid:
            argv.append(wid)
        return _run_axctl(argv)

    if name == "toggle_window_floating":
        argv = ["window", "toggle-floating"]
        wid = _str_arg(args, "window_id")
        if wid:
            argv.append(wid)
        return _run_axctl(argv)

    if name == "set_window_fullscreen":
        state = _bool_arg(args, "state")
        if state is None:
            return {"content": "", "error": "set_window_fullscreen needs state=true|false"}
        argv = ["window", "fullscreen", "1" if state else "0"]
        wid = _str_arg(args, "window_id")
        if wid:
            argv.append(wid)
        return _run_axctl(argv)

    if name == "resize_window":
        try:
            w = int(args.get("width"))
            h = int(args.get("height"))
        except (TypeError, ValueError):
            return {"content": "", "error": "resize_window needs integer width and height"}
        argv = ["window", "resize", str(w), str(h)]
        wid = _str_arg(args, "window_id")
        if wid:
            argv.append(wid)
        return _run_axctl(argv)

    if name == "move_window_direction":
        direction = _str_arg(args, "direction")
        if not direction:
            return {"content": "", "error": "move_window_direction needs direction=l|r|u|d"}
        argv = ["window", "move", direction]
        wid = _str_arg(args, "window_id")
        if wid:
            argv.append(wid)
        return _run_axctl(argv)

    # ── Workspace ops ───────────────────────────────────────────────
    if name == "switch_workspace":
        ws = _str_arg(args, "workspace_id")
        if not ws:
            return {"content": "", "error": "switch_workspace needs workspace_id"}
        return _run_axctl(["workspace", "switch", ws])

    if name == "move_window_to_workspace":
        ws = _str_arg(args, "workspace_id")
        if not ws:
            return {"content": "", "error": "move_window_to_workspace needs workspace_id"}
        argv = ["workspace", "move-to", ws]
        wid = _str_arg(args, "window_id")
        if wid:
            argv.append(wid)
        return _run_axctl(argv)

    if name == "move_windows":
        pairs = []

        assignments = args.get("assignments")
        if isinstance(assignments, list):
            for item in assignments:
                if not isinstance(item, dict):
                    continue
                wid = _str_arg(item, "window_id")
                ws = _str_arg(item, "workspace_id")
                if wid and ws:
                    pairs.append((wid, _resolve_workspace_id(ws)))

        if not pairs:
            ws = _str_arg(args, "workspace_id")
            if ws:
                ws_resolved = _resolve_workspace_id(ws)
                window_ids = args.get("window_ids")
                if isinstance(window_ids, list):
                    for wid in window_ids:
                        if wid is None:
                            continue
                        wid_s = str(wid).strip()
                        if wid_s:
                            pairs.append((wid_s, ws_resolved))

                if not pairs:
                    app_names = args.get("app_names")
                    if isinstance(app_names, list) and app_names:
                        list_result = _run_axctl(["window", "list"])
                        if list_result.get("error"):
                            return list_result
                        try:
                            windows = json.loads(
                                list_result.get("content", "[]")
                            )
                        except (TypeError, ValueError) as exc:
                            return {
                                "content": "",
                                "error": "Could not parse axctl output: "
                                         + str(exc)
                            }
                        needles = []
                        for n in app_names:
                            if n is None:
                                continue
                            n_s = str(n).strip().lower()
                            if n_s:
                                needles.append(n_s)
                        if needles:
                            for w in windows:
                                if not isinstance(w, dict):
                                    continue
                                app_id = (w.get("app_id") or "").lower()
                                title = (w.get("title") or "").lower()
                                wmclass = (
                                    w.get("wm_class")
                                    or w.get("initial_class")
                                    or ""
                                ).lower()
                                haystacks = [app_id, title, wmclass]
                                hit = False
                                for n in needles:
                                    for h in haystacks:
                                        if h and n in h:
                                            hit = True
                                            break
                                    if hit:
                                        break
                                if hit:
                                    wid = w.get("id")
                                    if wid:
                                        pairs.append((str(wid), ws_resolved))

        if not pairs:
            has_assignments = isinstance(args.get("assignments"), list)
            has_window_ids = isinstance(args.get("window_ids"), list)
            has_app_names = isinstance(args.get("app_names"), list)
            ws = _str_arg(args, "workspace_id")
            valid_input = (
                has_assignments
                or (has_window_ids and bool(ws))
                or (has_app_names and bool(ws))
            )
            if not valid_input:
                return {
                    "content": "",
                    "error": "move_windows needs one of: "
                             "(a) 'assignments' (list of "
                             "{window_id, workspace_id}); "
                             "(b) 'window_ids' (list) + 'workspace_id'; "
                             "(c) 'app_names' (list) + 'workspace_id'."
                }
            return {
                "content": "",
                "error": "move_windows found no windows to move — "
                         "check that the supplied window_ids or app_names "
                         "match open windows (use list_windows to verify)."
            }

        moved = []
        failures = []
        for wid, ws in pairs:
            result = _run_axctl(["workspace", "move-to", ws, wid])
            if result.get("error"):
                failures.append({
                    "window_id": wid,
                    "workspace_id": ws,
                    "error": result["error"]
                })
            else:
                moved.append({
                    "window_id": wid,
                    "workspace_id": ws
                })

        verify_result = _run_axctl(["window", "list"])
        if verify_result.get("error"):
            return {
                "content": "",
                "error": "move_to calls returned but verification failed: "
                         + str(verify_result.get("error"))
            }
        try:
            verify_windows = json.loads(verify_result.get("content", "[]"))
        except (TypeError, ValueError):
            verify_windows = []
        current_ws = {}
        for w in verify_windows:
            if isinstance(w, dict) and w.get("id") is not None:
                current_ws[str(w["id"])] = w.get("workspace_id")
        verified_moved = []
        actually_failed = []
        for entry in moved:
            wid = entry["window_id"]
            target_ws = entry["workspace_id"]
            actual_ws = current_ws.get(wid)
            if actual_ws is not None and str(actual_ws) == str(target_ws):
                verified_moved.append(entry)
            elif actual_ws is None:
                verified_moved.append(entry)
            else:
                actually_failed.append({
                    "window_id": wid,
                    "workspace_id": target_ws,
                    "error": "axctl reported Success but window is still on "
                             "workspace " + str(actual_ws)
                })
        moved = verified_moved
        failures.extend(actually_failed)
        time.sleep(0.2)
        retry_result = _run_axctl(["window", "list"])
        if retry_result.get("error"):
            return {
                "content": "",
                "error": "post-move verification retry failed: "
                         + str(retry_result.get("error"))
            }
        try:
            retry_windows = json.loads(retry_result.get("content", "[]"))
        except (TypeError, ValueError):
            retry_windows = []
        retry_ws = {}
        for w in retry_windows:
            if isinstance(w, dict) and w.get("id") is not None:
                retry_ws[str(w["id"])] = w.get("workspace_id")
        revisited_moved = []
        resurrected = []
        for entry in failures:
            wid = entry["window_id"]
            target_ws = entry["workspace_id"]
            actual_ws = retry_ws.get(wid)
            if actual_ws is not None and str(actual_ws) == str(target_ws):
                resurrected.append(entry)
            else:
                revisited_moved.append(entry)
        moved.extend(resurrected)
        failures = revisited_moved

        summary = {
            "requested": len(pairs),
            "moved": moved,
            "failed": failures
        }
        return {
            "content": json.dumps(summary, ensure_ascii=False, indent=2),
            "error": None
        }

    if name == "toggle_special_workspace":
        name_arg = _str_arg(args, "name")
        if not name_arg:
            return {"content": "", "error": "toggle_special_workspace needs name"}
        return _run_axctl(["workspace", "toggle-special", name_arg])

    # ── Monitor ops ─────────────────────────────────────────────────
    if name == "focus_monitor":
        mid = _str_arg(args, "monitor_id")
        if not mid:
            return {"content": "", "error": "focus_monitor needs monitor_id"}
        return _run_axctl(["monitor", "focus", mid])

    if name == "move_window_to_monitor":
        mid = _str_arg(args, "monitor_id")
        if not mid:
            return {"content": "", "error": "move_window_to_monitor needs monitor_id"}
        argv = ["monitor", "move-to", mid]
        wid = _str_arg(args, "window_id")
        if wid:
            argv.append(wid)
        return _run_axctl(argv)

    # ── Layout ───────────────────────────────────────────────────────
    if name == "set_layout":
        layout = _str_arg(args, "name")
        if not layout:
            return {"content": "", "error": "set_layout needs name"}
        return _run_axctl(["layout", "set", layout])

    # ── System / general ────────────────────────────────────────────
    if name == "execute_command":
        command = _str_arg(args, "command")
        if not command:
            return {"content": "", "error": "execute_command needs command"}
        return _run_axctl(["system", "execute", command])

    # ── Program helpers ─────────────────────────────────────────────
    if name == "check_program_installed":
        program = _str_arg(args, "program_name")
        if not program:
            return {"content": "", "error": "check_program_installed needs program_name"}
        path = shutil.which(program.split()[0])
        if path:
            return {
                "content": "The program '" + program + "' IS installed at: " + path,
                "error": None
            }
        return {
            "content": "The program '" + program + "' is NOT installed on this system.",
            "error": None
        }

    if name == "launch_program":
        program = _str_arg(args, "program_name")
        if not program:
            return {"content": "", "error": "launch_program needs program_name"}
        try:
            subprocess.Popen(
                "nohup " + program + " > /dev/null 2>&1 &",
                shell=True,
                env=os.environ,
                preexec_fn=os.setpgrp
            )
            return {
                "content": "Launched '" + program + "' in the background.",
                "error": None
            }
        except Exception as exc:
            return {"content": "", "error": str(exc)}

    if name == "install_package":
        package = _str_arg(args, "package_name")
        if not package:
            return {"content": "", "error": "install_package needs package_name"}
        # Only attempt sudo if we have a passwordless sudo or a recent
        # auth ticket. Otherwise surface the exact command and let the
        # user run it themselves — that's safer than leaving a hung
        # process waiting on a TTY that doesn't exist.
        sudo_prefix, manager = _detect_package_manager()
        cmd = sudo_prefix + " " + package
        try:
            result = subprocess.run(
                cmd,
                shell=True,
                capture_output=True,
                text=True,
                timeout=180,
                env={**os.environ, "DEBIAN_FRONTEND": "noninteractive"}
            )
            if result.returncode == 0:
                return {
                    "content": "Installed '" + package + "' successfully via " + manager + ".",
                    "error": None
                }
            stderr = (result.stderr or "").strip()
            hint = "Run this manually: " + cmd
            return {
                "content": "",
                "error": manager + " failed (exit " + str(result.returncode) + "): "
                         + (stderr or "no stderr output") + ". " + hint
            }
        except subprocess.TimeoutExpired:
            return {
                "content": "",
                "error": manager + " timed out after 180s — sudo may be waiting for a password. "
                         + "Run this manually: " + cmd
            }
        except Exception as exc:
            return {"content": "", "error": str(exc)}

    # ── App catalog ──────────────────────────────────────────────────
    if name == "list_installed_apps":
        try:
            catalog = _get_apps_catalog(force_refresh=True)
        except Exception as exc:
            return {"content": "", "error": "Failed to scan apps: " + str(exc)}
        fil = _str_arg(args, "filter")
        if fil:
            needle = fil.lower()
            catalog = [a for a in catalog
                       if needle in a["name"].lower()
                       or needle in a.get("generic_name", "").lower()
                       or needle in a.get("comment", "").lower()]
        if not catalog:
            hint = ""
            if fil:
                hint = " No apps match the filter '" + fil + "'."
            return {"content": "[]", "error": None} if not fil else {
                "content": "[]",
                "error": None
            }
        verbose = _bool_arg(args, "verbose")
        if not verbose:
            catalog = _compact_apps(catalog)
        try:
            return {"content": json.dumps(catalog, ensure_ascii=False, indent=2), "error": None}
        except (TypeError, ValueError) as exc:
            return {"content": "", "error": "Failed to encode catalog: " + str(exc)}

    if name == "open_url":
        url = _str_arg(args, "url")
        if not url:
            return {"content": "", "error": "open_url needs a url argument"}
        url_aliases = {
            "youtube": "https://www.youtube.com",
            "yt": "https://www.youtube.com",
            "youtu": "https://www.youtube.com",
            "youtubemusic": "https://music.youtube.com",
            "ytmusic": "https://music.youtube.com",
            "github": "https://github.com",
            "gh": "https://github.com",
            "gmail": "https://mail.google.com",
            "mail": "https://mail.google.com",
            "google": "https://www.google.com",
            "calendar": "https://calendar.google.com",
            "maps": "https://maps.google.com",
            "drive": "https://drive.google.com",
            "docs": "https://docs.google.com",
            "reddit": "https://www.reddit.com",
            "twitter": "https://twitter.com",
            "x": "https://twitter.com",
            "wikipedia": "https://wikipedia.org",
            "wiki": "https://wikipedia.org",
            "stackoverflow": "https://stackoverflow.com",
            "so": "https://stackoverflow.com",
            "chatgpt": "https://chat.openai.com",
            "gemini": "https://gemini.google.com",
            "perplexity": "https://www.perplexity.ai",
            "hackernews": "https://news.ycombinator.com",
            "hn": "https://news.ycombinator.com",
            "archwiki": "https://wiki.archlinux.org",
            "arch": "https://archlinux.org",
            "man": "https://man.archlinux.org",
            "aur": "https://aur.archlinux.org",
            "github.io": "https://github.io",
        }
        raw = url.strip()
        key = raw.lower()
        for prefix in ("https://", "http://", "www."):
            if key.startswith(prefix):
                key = key[len(prefix):]
        key = key.split("/", 1)[0]
        resolved = url_aliases.get(key, None)
        if resolved is None:
            # No alias matched. If it looks like a real host
            # (contains a dot, e.g. 'example.com' or 'reddit.com/r/foo')
            # we trust it and prepend https://. Otherwise refuse —
            # we don't want to open 'https://spotify' just because the
            # user said "spotify" without an alias.
            if "." in key:
                resolved = raw
                if "://" not in resolved:
                    resolved = "https://" + resolved
            else:
                suggestions = ", ".join(sorted(url_aliases.keys())[:8])
                return {
                    "content": "",
                    "error": "Unknown URL or alias '" + raw + "'. Pass a "
                             + "full URL ('https://example.com/path') or a known "
                             + "alias. Common aliases: " + suggestions + ", ..."
                }
        try:
            result = subprocess.run(
                ["xdg-open", resolved],
                capture_output=True, text=True, timeout=8,
                env=os.environ
            )
        except (subprocess.TimeoutExpired, OSError) as exc:
            return {"content": "", "error": "xdg-open failed: " + str(exc)}
        if result.returncode != 0:
            return {
                "content": "",
                "error": "xdg-open exited " + str(result.returncode)
                         + ": " + (result.stderr.strip() or "no stderr")
            }
        return {
            "content": "Opened '" + resolved + "' in the user's default browser.",
            "error": None
        }

    if name == "open_app":
        query = _str_arg(args, "app_name")
        if not query:
            return {"content": "", "error": "open_app needs app_name"}
        try:
            catalog = _get_apps_catalog()
        except Exception as exc:
            return {"content": "", "error": "Failed to scan apps: " + str(exc)}
        match = _find_app(query, catalog)
        if not match:
            # Surface a handful of nearby names so the LLM can self-correct
            # (e.g. "Did you mean ...?").
            suggestions = []
            q = query.lower()
            for entry in catalog:
                if q[:3] in entry["name"].lower():
                    suggestions.append(entry["name"])
                if len(suggestions) >= 5:
                    break
            hint = ""
            if suggestions:
                hint = " Did you mean: " + ", ".join(suggestions) + "?"
            return {
                "content": "",
                "error": "No installed app matches '" + query + "'." + hint
            }

        # Build a shell-safe command. .desktop Exec= lines often have
        # %u/%f/%F placeholders and (for flatpak) quoted args — strip
        # the placeholders but keep the original quoting.
        cmd = _strip_exec_placeholders(match["command"])
        try:
            subprocess.Popen(
                "nohup " + cmd + " > /dev/null 2>&1 &",
                shell=True,
                env=os.environ,
                preexec_fn=os.setpgrp
            )
        except Exception as exc:
            return {"content": "", "error": "Failed to launch: " + str(exc)}
        return {
            "content": "Opened '" + match["name"] + "' (" + match["source"]
                     + "). Use list_windows to see the new window.",
            "error": None
        }

    if name == "close_app":
        query = _str_arg(args, "app_name")
        if not query:
            return {"content": "", "error": "close_app needs app_name"}
        needle = query.strip().lower()
        if not needle:
            return {"content": "", "error": "close_app needs a non-empty app_name"}

        # Discover live windows via axctl.
        list_result = _run_axctl(["window", "list"])
        if list_result.get("error"):
            return list_result
        try:
            windows = json.loads(list_result.get("content", "[]"))
        except (TypeError, ValueError) as exc:
            return {"content": "", "error": "Could not parse axctl output: " + str(exc)}

        # Match by app_id first (most precise), then by title.
        matches = []
        for w in windows:
            if not isinstance(w, dict):
                continue
            app_id = (w.get("app_id") or "").lower()
            title = (w.get("title") or "").lower()
            wmclass = (w.get("wm_class") or w.get("initial_class") or "").lower()
            haystacks = [app_id, title, wmclass]
            if any(needle in h for h in haystacks if h):
                matches.append(w)
        if not matches:
            return {
                "content": "",
                "error": "No open window matches '" + query
                         + "'. Try list_windows to see what's running."
            }

        closed = []
        failures = []
        for w in matches:
            wid = w.get("id")
            if not wid:
                continue
            result = _run_axctl(["window", "close", str(wid)])
            if result.get("error"):
                failures.append({
                    "id": wid,
                    "title": w.get("title", ""),
                    "error": result["error"]
                })
            else:
                closed.append({
                    "id": wid,
                    "title": w.get("title", ""),
                    "app_id": w.get("app_id", "")
                })

        summary = {
            "closed": closed,
            "failed": failures,
            "matched": len(matches)
        }
        return {"content": json.dumps(summary, ensure_ascii=False, indent=2), "error": None}

    return {"content": "", "error": "Tool '" + str(name) + "' not found"}


# ---------------------------------------------------------------------------
# HTTP request handler
# ---------------------------------------------------------------------------

class NothingClawHandler(BaseHTTPRequestHandler):
    server_version = "NothingClaw/1.0"

    # Log every request to stderr so the shell's process supervisor
    # can surface it. Short format keeps the Quickshell log readable.
    def log_message(self, fmt, *args):
        sys.stderr.write("[nothingclaw] " + (fmt % args) + "\n")

    def _send_json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.split("?", 1)[0] != "/tools":
            self._send_json(404, {"error": "Not found", "content": ""})
            return
        query = {}
        try:
            from urllib.parse import urlparse, parse_qs
            query = parse_qs(urlparse(self.path).query)
        except Exception:
            query = {}

        # Capability resolution. Precedence (highest first):
        #   1. ?capability= header X-Capability (manual override).
        #   2. Auto-detect from X-Model-Name + X-Model-Host (or query params).
        #   3. ?lite=true (legacy shortcut → 'small').
        #   4. Default 'small' (safe for a local bridge).
        explicit = (query.get("capability", [None])[0]
                    or self.headers.get("X-Capability", "").strip().lower()
                    or None)
        model_name = (query.get("model", [None])[0]
                      or self.headers.get("X-Model-Name", "").strip()
                      or "")
        model_host = (query.get("host", [None])[0]
                      or self.headers.get("X-Model-Host", "").strip()
                      or "")
        lite = bool(query.get("lite"))

        if explicit in ("tiny", "small", "medium", "large"):
            tier = explicit
        elif model_name:
            tier = _detect_capability(model_name, model_host)
        elif lite:
            tier = "small"
        else:
            tier = "small"

        payload = _filter_tools_for_capability(tier)
        self._send_json(200, payload)

    def do_POST(self):
        if self.path.split("?", 1)[0] != "/tools":
            self._send_json(404, {"error": "Not found", "content": ""})
            return
        length = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(length) if length > 0 else b""
        try:
            body = json.loads(raw.decode("utf-8") or "{}")
        except Exception as exc:
            self._send_json(400, {"content": "", "error": "Invalid JSON: " + str(exc)})
            return
        name = body.get("name", "")
        arguments = body.get("arguments", {}) or {}
        if not name:
            self._send_json(400, {"content": "", "error": "Missing 'name'"})
            return
        result = invoke_tool(name, arguments)
        self._send_json(200, result)


class NothingClawHTTPServer(ThreadingHTTPServer):
    # Setting SO_REUSEADDR lets a freshly-spawned bridge rebind the
    # port quickly after the previous instance was killed (TIME_WAIT
    # sockets). Without this, rapid shell restarts can hit
    # "Address already in use" for ~30 s after each kill.
    allow_reuse_address = True

    # If the port is genuinely busy (another live process holds it),
    # surface a single-line, human-readable error to stderr so the
    # shell's process supervisor can pick it up and show it in the UI.
    def server_bind(self):
        try:
            super().server_bind()
        except OSError as exc:
            sys.stderr.write(
                "NothingClaw bridge: cannot bind "
                + str(self.server_address)
                + " — "
                + str(exc)
                + ". Stop the existing instance or pick a different port.\n"
            )
            sys.stderr.flush()
            raise


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    host = os.environ.get("NOTHINGCLAW_HOST", "127.0.0.1")
    try:
        port = int(os.environ.get("NOTHINGCLAW_PORT", "8000"))
    except ValueError:
        port = 8000

    server = NothingClawHTTPServer((host, port), NothingClawHandler)
    print("NothingClaw bridge listening on http://" + host + ":" + str(port), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()