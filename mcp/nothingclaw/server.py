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


def _obj(props, required=None):
    if required is None:
        required = []
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
        # Tiny local models (granite-2b, qwen-1.5b, phi-1.5): only the
        # most reliable tools. Knowledge tools are omitted because a
        # 2B model can't parse 5+ search snippets reliably and they
        # burn context fast.
        "manage_memory",
        "list_windows",
        "list_installed_apps",
        "move_window_to_workspace",
        "open_url",
        "execute_command",
        "context_info",
    ],
    "small": [
        # Additive over tiny. 3B-13B Ollama models (qwen2.5:7b,
        # llama-3.1-8b, mistral-7b): web_search returns 3-5 short
        # snippets; fetch_url truncates aggressively; manage_rag
        # search returns 3 top chunks.
        "list_workspaces",
        "move_windows",
        "open_app",
        "close_app",
        "web_search",
        "fetch_url",
        "manage_rag",
    ],
    "medium": [
        # Additive over small. Adds the rest of the desktop-control
        # surface that benefits from bigger context.
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


# ---------------------------------------------------------------------------
# Semantic tool ranking (Odysseus-inspired, dependency-free)
# ---------------------------------------------------------------------------
#
# Mimics Odysseus's RAG-based tool selection without requiring ChromaDB /
# fastembed / an Ollama embedding model. Builds a keyword index from tool
# names and descriptions on first use, then scores every tool by keyword
# overlap with the user's query. Handles Spanish intent mapping so a query
# like "mueve la ventana al workspace 3" boosts the right tools.

_TOOL_INDEX = None  # [(tool_name, set_of_keywords, score_weight), ...]


_INTENT_MAP = {
    # Spanish → English keyword expansion
    "mover": "move", "mueve": "move", "movido": "move",
    "mueva": "move", "moveme": "move", "movelo": "move",
    "abrir": "open", "abre": "open", "abrir": "open",
    "cerrar": "close", "cierra": "close", "cierre": "close",
    "navegador": "browser", "browser": "browser",
    "web": "browser", "internet": "browser",
    "buscar": "search", "busca": "search",
    "ventana": "window", "ventanas": "window",
    "workspace": "workspace", "workspaces": "workspace",
    "escritorio": "workspace", "pantalla": "monitor",
    "monitor": "monitor", "monitores": "monitor",
    "programa": "app", "app": "app", "apps": "app",
    "aplicacion": "app", "aplicación": "app",
    "aplicaciones": "app",
    "url": "url", "link": "url", "enlace": "url",
    "pagina": "url", "página": "url", "web": "url",
    "lista": "list", "listar": "list",
    "instalado": "installed", "instalada": "installed",
    "instalados": "installed", "instaladas": "installed",
    "paquete": "package", "paquetes": "package",
    "instalar": "install", "instala": "install",
    "comando": "command", "ejecutar": "execute",
    "ejecuta": "execute", "correr": "execute",
    "tema": "layout", "layout": "layout",
    "flotante": "floating", "flotar": "floating",
    "pantalla": "fullscreen", "completa": "fullscreen",
    "completo": "fullscreen", "fullscreen": "fullscreen",
    "tamaño": "resize", "tamano": "resize", "resize": "resize",
    "foco": "focus", "enfocar": "focus", "enfoca": "focus",
    "direccion": "direction", "dirección": "direction",
    "arriba": "direction", "abajo": "direction",
    "izquierda": "direction", "derecha": "direction",
    "especial": "special", "scratchpad": "special",
    "cambiar": "switch", "cambia": "switch",
    "todos": "all", "varios": "batch", "batch": "batch",
    "multiple": "batch", "multiples": "batch",
}


_DOMAIN_TOOLS = {
    # Odysseus's _DOMAIN_TOOL_MAP equivalent — when a query clearly
    # maps to a domain, seed those tools even if keywords don't overlap.
    "window": ["list_windows", "focus_window", "close_window",
               "move_window_to_workspace", "move_windows",
               "move_window_direction", "move_window_to_monitor",
               "toggle_window_floating", "set_window_fullscreen",
               "resize_window", "toggle_window_direction"],
    "workspace": ["list_workspaces", "switch_workspace",
                  "move_window_to_workspace", "move_windows",
                  "toggle_special_workspace"],
    "monitor": ["list_monitors", "focus_monitor",
                "move_window_to_monitor"],
    "app": ["list_installed_apps", "open_app", "close_app",
            "launch_program", "check_program_installed"],
    "url": ["open_url", "execute_command"],
    "system": ["execute_command", "check_program_installed",
               "launch_program", "install_package"],
    "layout": ["set_layout", "toggle_window_floating",
               "set_window_fullscreen", "resize_window"],
    "batch": ["move_windows", "close_app"],
}


def _build_tool_index():
    """Build a keyword index from tool names + descriptions. Lazy, cached."""
    global _TOOL_INDEX
    if _TOOL_INDEX is not None:
        return
    _TOOL_INDEX = []
    for t in TOOLS:
        name = t["name"]
        desc = t.get("description", "")
        params = t.get("parameters", {}).get("properties", {})
        text = name + " " + desc
        for pname, pinfo in params.items():
            if isinstance(pinfo, dict):
                text += " " + pname + " " + pinfo.get("description", "")
        words = set(re.findall(r"[a-z_][a-z_0-9]{2,}", text.lower()))
        for part in name.split("_"):
            if len(part) >= 3:
                words.add(part)
        # Boost keywords from the tool's name
        _TOOL_INDEX.append((name, words))


def _rank_tools_by_query(query, top_k=8):
    """Return tool names ranked by keyword relevance to `query`.

    No embeddings, no ChromaDB, no extra dependencies. Uses:
      1. Direct keyword overlap with tool descriptions
      2. Spanish→English intent expansion (_INTENT_MAP)
      3. Domain seeding (_DOMAIN_TOOLS) — when keywords clearly
         point to a domain, its tools get a bonus
      4. Name parts — "move_window_to_workspace" boosts "move",
         "window", "workspace" individually

    Falls back to TOOLS names when the index hasn't been built yet
    (first call builds it lazily).
    """
    _build_tool_index()
    if not _TOOL_INDEX or not query:
        if not query:
            return [t["name"] for t in TOOLS]
        return [t["name"] for t in TOOLS][:top_k]

    # Tokenize and expand query
    raw = query.lower().strip()
    qwords = set(re.findall(r"[a-z0-9]{2,}", raw))

    # Spanish → English expansion
    for word in list(qwords):
        if word in _INTENT_MAP:
            qwords.add(_INTENT_MAP[word])

    # Domain detection: which domains are active?
    active_domains = set()
    for domain, keywords in {
        "window": {"window", "window", "move", "focus", "close", "resize", "float", "mover", "ventana", "mueve"},
        "workspace": {"workspace", "switch", "desktop", "escritorio"},
        "monitor": {"monitor", "screen", "pantalla", "display"},
        "app": {"app", "open", "close", "launch", "install", "abrir", "abre", "programa", "aplicacion"},
        "url": {"url", "link", "browser", "navegador", "web", "pagina", "http"},
        "system": {"exec", "shell", "command", "run", "comando", "ejecutar"},
        "layout": {"layout", "theme", "tema"},
        "batch": {"batch", "all", "multiple", "todos", "varios", "multiples"},
    }.items():
        if qwords & keywords:
            active_domains.add(domain)

    # Score every tool
    scores = []
    for name, words in _TOOL_INDEX:
        score = len(qwords & words)  # Direct keyword overlap
        # Name part bonus
        for part in name.split("_"):
            if part in qwords:
                score += 3
        # Domain bonus — when the query is about windows and this
        # tool is a window tool, give it a boost. Mirrors Odysseus's
        # domain seeding in _DOMAIN_TOOL_MAP.
        for domain in active_domains:
            if domain in _DOMAIN_TOOLS and name in _DOMAIN_TOOLS[domain]:
                score += 2
        if score > 0:
            scores.append((name, score))

    scores.sort(key=lambda x: (-x[1], x[0]))
    return [name for name, _ in scores[:top_k]]


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
    },
    {
        "name": "manage_memory",
        "description": "Persistent key-value memory for the agent. Survives "
                       "bridge restarts. Use it to remember user preferences, "
                       "recent context ('last workspace used'), or anything the "
                       "agent should recall across sessions. Actions: "
                       "'set' (write a key), 'get' (read a key), 'delete' "
                       "(remove a key), 'list' (show all keys). File-backed in "
                       "~/.local/share/nothingless/nothingclaw_memory.json. "
                       "Mirrors Odysseus's manage_memory tool.",
        "parameters": _obj({
            "action": _str_enum(["set", "get", "delete", "list"],
                                "Memory action to perform."),
            "key": _str("Memory key (set/get/delete)."),
            "value": _str("Memory value (set only).")
        }, ["action"])
    },

    # ── Odysseus-style knowledge / web tools (ported from Odysseus) ──
    #
    # These four tools extend the local-tool surface with capabilities
    # that are useful for both local Ollama models AND cloud APIs.
    # They're capability-aware: the per-call result size adapts to the
    # requesting model's tier (tiny → 1k tokens, large → 8k tokens of
    # tool result). See context_budget.py for the size tables and
    # _invoke_with_tier() for the dispatch path.

    {
        "name": "web_search",
        "description": "Search the public web and return the top results "
                       "as title + snippet + URL. Backed by SearXNG when "
                       "configured (NOTHINGCLAW_SEARXNG_URL) or DuckDuckGo "
                       "HTML otherwise — no API keys required. The result "
                       "size is automatically capped to the requesting "
                       "model's tier (tiny=3 results, small=5, medium=8, "
                       "large=10) so a 2B local model isn't drowned in "
                       "snippets it can't use. Use this BEFORE fetch_url "
                       "when the user asks a research question. Pass "
                       "max_results to override the tier default.",
        "parameters": _obj({
            "query": _str("Search query. Be specific — 'qt6 qml signal "
                          "performance' beats 'qt performance'."),
            "max_results": _int("Maximum number of results to return. "
                                "Tier default applies when omitted."),
            "time_filter": _str_enum(
                ["day", "week", "month", "year", None],
                "Optional freshness filter: 'day' for today's news, "
                "'week' for 'this week', 'month' for 'this month', "
                "'year' for 'this year'."),
            "region": _str("Optional SearXNG region code, e.g. 'us-en', "
                          "'de-de'. Ignored when falling back to DDG.")
        }, ["query"])
    },
    {
        "name": "fetch_url",
        "description": "Download a URL and return its readable content as "
                       "plain text. Strips scripts, styles, navigation, "
                       "and HTML chrome automatically. Useful for reading "
                       "the page behind a web_search result, a documentation "
                       "page, a GitHub blob, a Stack Overflow answer, etc. "
                       "Hard-capped at 1.5 MB raw download (further capped "
                       "by the model's tier to avoid overflowing its "
                       "context — tiny Ollama models see ~1k tokens of "
                       "content, large cloud models see ~8k). ALWAYS "
                       "fetch_url a page before summarising it — the model "
                       "cannot read URLs that haven't been fetched.",
        "parameters": _obj({
            "url": _str("The URL to fetch. Must start with http:// or "
                       "https://. localhost / 127.x / 10.x / 192.168.x "
                       "/ 172.16-31.x / ::1 / file:// are BLOCKED — this "
                       "tool is for the public web only, not the local "
                       "filesystem (use read_file for that)."),
            "max_bytes": _int("Maximum bytes to download (default 1.5 MB). "
                              "Smaller values fail faster when the page is "
                              "huge."),
            "full": _bool("Return the entire body without any tier-based "
                          "truncation. Only set this to true when you "
                          "genuinely need every word — the response will "
                          "be cut off mid-sentence if it exceeds the "
                          "model's context window.")
        }, ["url"])
    },
    {
        "name": "manage_rag",
        "description": "Manage a lightweight, dependency-free RAG index of "
                       "local files. Index a directory once with "
                       "add_directory, then call `search` repeatedly to "
                       "retrieve the most relevant chunks for a user "
                       "question. Backed by a plain JSON index with TF-IDF "
                       "scoring — no embeddings model required, no "
                       "ChromaDB, works on any CPU. Use this when the user "
                       "asks about the contents of a local project, "
                       "documentation folder, note archive, or any "
                       "directory with readable text files. NOT a "
                       "replacement for fetch_url — this tool only sees "
                       "files on the local filesystem. Mirrors Odysseus's "
                       "manage_rag tool.",
        "parameters": _obj({
            "action": _str_enum(
                ["list", "add_directory", "remove_directory", "search"],
                "Action to perform:\n"
                "  • list — show indexed directories and stats.\n"
                "  • add_directory — scan and index a directory (recursive, "
                "skips binary files and common build/cache dirs).\n"
                "  • remove_directory — drop a directory from the index.\n"
                "  • search — return the top N chunks matching a query."
            ),
            "directory": _str("Directory path (for add/remove). Expanded "
                             "with ~ and resolved to absolute before "
                             "indexing, so list and remove_directory can "
                             "match it later."),
            "query": _str("Search query (for 'search' action)."),
            "top_k": _int("Maximum chunks to return for 'search' (default "
                          "5, tier-capped)."),
            "max_chunk_chars": _int("Maximum characters per chunk when "
                                    "indexing (default 1200). Larger "
                                    "values give the model more context "
                                    "per result but use more of the "
                                    "model's context budget per query.")
        }, ["action"])
    },
    {
        "name": "context_info",
        "description": "Return metadata about the current request — the "
                       "model's detected capability tier, its known "
                       "context window, and the per-tool-result token "
                       "budget NothingClaw is using for this call. Call "
                       "this FIRST in any long chain of tool calls so you "
                       "know how much text you can read back from each "
                       "tool without overflowing your own context. Useful "
                       "when the user gives you a giant PDF / log file / "
                       "codebase and you need to decide whether to call "
                       "fetch_url once with full=true or many times with "
                       "smaller scopes.",
        "parameters": _obj({})
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


def _fire_and_forget(argv):
    """Spawn a subprocess detached from the bridge and return True if spawn succeeded.

    Returns False on FileNotFoundError (binary missing) or OSError
    (permission denied, etc.). Does NOT wait for the process to finish
    — use for GUI launchers (xdg-open, gio open, ...) where the
    user only cares that the binary could be launched, not whether the
    URL eventually finishes loading. The process runs in a new session
    so it won't be killed when the bridge shuts down.
    """
    try:
        subprocess.Popen(
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
            env=os.environ
        )
        return True
    except (FileNotFoundError, OSError):
        return False


def _run_axctl(argv, timeout=5):
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


def _int_arg(args, key, default=None):
    """Extract a non-negative integer argument. Falls back to default on
    missing/garbage values."""
    val = args.get(key, default)
    if val is None or val == "":
        return default
    try:
        n = int(val)
    except (TypeError, ValueError):
        return default
    if n < 0:
        return default
    return n


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


# ---------------------------------------------------------------------------
# Capability-aware request context
# ---------------------------------------------------------------------------
#
# Each tool call gets a `_RequestContext` populated by the HTTP handler
# before invoking the tool. Tools that produce variable-size output
# (web_search, fetch_url, manage_rag) read the budget from this
# context and truncate their responses accordingly. The dispatch path
# is invoke_tool(name, args, ctx).
#
# Mirrors Odysseus's pattern of plumbing tier + model_name through
# every tool call so each handler can adapt to the requesting model's
# capability without re-running capability detection.

class _RequestContext:
    __slots__ = ("tier", "model_name", "model_host", "context_window",
                 "tool_budget", "input_budget")

    def __init__(self, tier="small", model_name="", model_host="",
                 context_window=0, tool_budget=0, input_budget=0):
        self.tier = tier or "small"
        self.model_name = model_name or ""
        self.model_host = model_host or ""
        self.context_window = int(context_window or 0)
        self.tool_budget = int(tool_budget or 0)
        self.input_budget = int(input_budget or 0)


def _resolve_request_context(tier, model_name, model_host=""):
    """Build a _RequestContext for a given tier + model name.

    Imports the budget module lazily so the bridge still starts when
    context_budget.py is missing (e.g. partial install). Falls back to
    sensible defaults.
    """
    try:
        from mcp.nothingclaw.context_budget import (
            DEFAULT_TOOL_RESULT_BUDGET,
            KNOWN_CONTEXT_WINDOWS,
            compute_input_token_budget,
            lookup_known_context,
            tool_result_budget,
        )
        cb = tool_result_budget(tier)
        ctx_window = lookup_known_context(model_name) or 0
        in_budget = compute_input_token_budget(
            configured=None, context_length=ctx_window)
    except Exception:
        cb = 2000
        ctx_window = 0
        in_budget = 6000
    return _RequestContext(
        tier=tier, model_name=model_name, model_host=model_host,
        context_window=ctx_window, tool_budget=cb, input_budget=in_budget)


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
# Odysseus-style knowledge tools
# ---------------------------------------------------------------------------
#
# web_search, fetch_url, manage_rag, context_info — adapted from
# Odysseus's web_tools.py and rag_server.py. Pure stdlib (no
# httpx, no requests, no BeautifulSoup). HTML extraction uses
# stdlib html.parser + a small set of regex passes — good enough
# for the 95% case of "give me the readable text from this page"
# without adding a dependency.

import html as _stdlib_html
from html.parser import HTMLParser as _HTMLParser
from urllib.parse import urlparse as _urlparse, urljoin as _urljoin
import urllib.request as _urlrequest
import urllib.error as _urlerror


# ─── HTML→text extractor ───────────────────────────────────────────────
#
# Tiny stdlib HTML parser that strips scripts, styles, navigation,
# and inline event handlers, then walks the body collecting visible
# text. Block-level elements get newlines around them. Inline `<a>`
# tags keep their text but drop their href (we add source links at
# the end of the response instead, the model is less likely to spam
# them in the answer).

class _TextExtractor(_HTMLParser):
    _BLOCK = {"p", "div", "section", "article", "header", "footer",
              "nav", "aside", "main", "li", "ul", "ol", "tr", "table",
              "blockquote", "pre", "h1", "h2", "h3", "h4", "h5", "h6",
              "br", "hr"}
    _SKIP_PARENTS = {"script", "style", "noscript", "svg", "iframe",
                     "canvas", "video", "audio", "form"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self._buf = []
        self._skip_depth = 0
        self._in_title = False
        self._title = ""

    @property
    def title(self):
        return self._title.strip()

    def handle_starttag(self, tag, attrs):
        if tag in self._SKIP_PARENTS:
            self._skip_depth += 1
            return
        if tag == "title":
            self._in_title = True
            return
        if tag in self._BLOCK:
            self._buf.append("\n")

    def handle_endtag(self, tag):
        if tag in self._SKIP_PARENTS and self._skip_depth > 0:
            self._skip_depth -= 1
            return
        if tag == "title":
            self._in_title = False
            return
        if tag in self._BLOCK:
            self._buf.append("\n")

    def handle_data(self, data):
        if self._skip_depth > 0:
            return
        text = data.strip()
        if not text:
            return
        if self._in_title:
            self._title += " " + text
            return
        self._buf.append(text + " ")

    def get_text(self):
        out = "".join(self._buf)
        # Collapse runs of whitespace inside lines (keep newlines).
        cleaned = []
        for line in out.split("\n"):
            line = re.sub(r"[ \t]+", " ", line).strip()
            if line:
                cleaned.append(line)
        return "\n".join(cleaned)


def _html_to_text(html_text):
    """Strip a chunk of HTML down to its readable text content.

    Returns (title, text). Falls back to a regex-only strip when
    the stdlib parser hits something it can't handle.
    """
    if not html_text:
        return "", ""
    try:
        ext = _TextExtractor()
        ext.feed(html_text)
        text = ext.get_text()
        title = ext.title or ""
        # Decode HTML entities one more time — html.parser handles
        # `&amp;` inside attribute values but not in some edge cases.
        text = _stdlib_html.unescape(text)
        return title[:300], text
    except Exception:
        # Last resort — strip tags with a regex. Less accurate but
        # at least we don't return raw HTML to the model.
        text = re.sub(r"<script\b[^>]*>.*?</script>",
                      " ", html_text, flags=re.DOTALL | re.IGNORECASE)
        text = re.sub(r"<style\b[^>]*>.*?</style>",
                      " ", text, flags=re.DOTALL | re.IGNORECASE)
        text = re.sub(r"<[^>]+>", " ", text)
        text = _stdlib_html.unescape(text)
        text = re.sub(r"[ \t]+", " ", text)
        text = re.sub(r"\n\s*\n+", "\n\n", text)
        return "", text.strip()


# ─── Public-web URL guard ─────────────────────────────────────────────
#
# Reject anything that smells like the local network so a malicious
# page or accidental mistake can't pivot the agent into the host
# filesystem / local services.

def _is_public_web_url(url):
    """Return True only for public http(s) URLs. Blocks localhost,
    private RFC1918 ranges, link-local, loopback IPv6, and file://.
    """
    try:
        parsed = _urlparse(url)
    except Exception:
        return False
    if parsed.scheme not in ("http", "https"):
        return False
    host = (parsed.hostname or "").lower()
    if not host:
        return False
    # Plain hostnames
    if host in ("localhost", "ip6-localhost", "ip6-loopback"):
        return False
    # Loopback IPv4
    if host.startswith("127."):
        return False
    # Private RFC1918
    if host.startswith("10.") or host.startswith("192.168."):
        return False
    # 172.16.0.0/12
    if host.startswith("172."):
        parts = host.split(".")
        if len(parts) >= 2 and parts[1].isdigit():
            n = int(parts[1])
            if 16 <= n <= 31:
                return False
    # Link-local 169.254.0.0/16
    if host.startswith("169.254."):
        return False
    # Tailscale CGNAT 100.64.0.0/10
    if host.startswith("100."):
        parts = host.split(".")
        if len(parts) >= 2 and parts[1].isdigit():
            n = int(parts[1])
            if 64 <= n <= 127:
                return False
    # IPv6 loopback / private
    if host in ("::1", "::"):
        return False
    if host.startswith("fe80:") or host.startswith("fc") or host.startswith("fd"):
        return False
    return True


# ─── web_search ───────────────────────────────────────────────────────

_DEFAULT_MAX_RESULTS = {"tiny": 3, "small": 5, "medium": 8, "large": 10}


def _web_search(args, ctx):
    """SearXNG-backed search with DDG HTML fallback.

    Result count and per-result text length are capped by ctx.tier
    so a 2B local model doesn't drown in 50k tokens of HTML. The
    SearXNG path returns JSON (fast, structured); the DDG path
    parses the HTML results page with stdlib.
    """
    query = _str_arg(args, "query")
    if not query:
        return {"content": "", "error": "web_search needs a query"}
    requested = _int_arg(args, "max_results")
    cap = requested if requested and requested > 0 else _DEFAULT_MAX_RESULTS.get(
        ctx.tier, 5)
    cap = min(cap, 10)
    time_filter = _str_arg(args, "time_filter") or ""
    region = _str_arg(args, "region") or ""

    searxng_url = os.environ.get("NOTHINGCLAW_SEARXNG_URL", "").strip()
    if searxng_url:
        results, err = _searxng_search(searxng_url, query, cap,
                                         time_filter, region)
        if err and "couldn't reach" in err.lower():
            # Treat unreachable SearXNG the same as unconfigured —
            # fall through to DDG so a transient outage doesn't kill
            # the chat.
            results, err = [], None
            results, err = _ddg_search(query, cap, time_filter)
    else:
        results, err = _ddg_search(query, cap, time_filter)

    if err and not results:
        return {"content": "", "error": err}
    if not results:
        return {
            "content": "No results found for: " + query,
            "error": None
        }
    # Trim result bodies to fit the per-tool budget.
    snippet_cap = max(160, min(800, ctx.tool_budget * 3 // max(len(results), 1)))
    lines = ["Web results for: " + query + "\n"]
    sources = []
    for i, r in enumerate(results, start=1):
        title = (r.get("title") or "").strip()[:200]
        url = (r.get("url") or "").strip()
        snippet = (r.get("snippet") or "").strip()
        if len(snippet) > snippet_cap:
            snippet = snippet[:snippet_cap].rsplit(" ", 1)[0] + "…"
        lines.append("[" + str(i) + "] " + title)
        lines.append("    " + url)
        lines.append("    " + snippet)
        lines.append("")
        sources.append({"i": i, "url": url, "title": title})
    body = "\n".join(lines).rstrip()
    # Hidden comment block — the model can cite these in its answer
    # without showing them inline. Odysseus does the same trick.
    body += "\n\n<!-- sources: " + json.dumps(sources, ensure_ascii=False) + " -->"

    # Final guard: if the body still exceeds the budget, truncate at
    # the last paragraph that fits.
    try:
        from mcp.nothingclaw.context_budget import truncate_to_budget
        body, _ = truncate_to_budget(body, ctx.tool_budget)
    except Exception:
        pass
    return {"content": body, "error": None}


def _searxng_search(base_url, query, cap, time_filter, region):
    """Query a SearXNG instance via its JSON API."""
    base = base_url.rstrip("/")
    params = {
        "q": query,
        "format": "json",
        "language": "en",
        "safesearch": "0",
    }
    if region:
        params["region"] = region
    if time_filter:
        params["time_range"] = time_filter
    try:
        from urllib.parse import urlencode
        url = base + "/search?" + urlencode(params)
        req = _urlrequest.Request(url, headers={
            "User-Agent": "NothingClaw/1.0 (+https://github.com/Leriart/NothingLess)",
            "Accept": "application/json"
        })
        with _urlrequest.urlopen(req, timeout=10) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
        data = json.loads(raw)
    except (_urlerror.URLError, _urlerror.HTTPError, TimeoutError) as exc:
        return [], "SearXNG unreachable: " + str(exc)
    except (json.JSONDecodeError, ValueError) as exc:
        return [], "SearXNG returned malformed JSON: " + str(exc)
    except Exception as exc:
        return [], "SearXNG request failed: " + str(exc)
    results = []
    for entry in (data.get("results") or [])[:cap]:
        results.append({
            "title": entry.get("title") or "",
            "url": entry.get("url") or "",
            "snippet": entry.get("content") or ""
        })
    return results, None


def _ddg_search(query, cap, time_filter):
    """Fallback search via DuckDuckGo HTML (no API key).

    DDG's HTML endpoint (html.duckduckgo.com/html/) returns a search
    results page with the first <n> matches. We parse out title +
    URL + snippet using regex on the HTML — fragile but works without
    any external dep. Falls back to the lite endpoint when html/ is
    rate-limited.
    """
    # Map our time filter to DDG's df parameter
    df_map = {"day": "d", "week": "w", "month": "m", "year": "y"}
    df = df_map.get(time_filter, "")
    try:
        from urllib.parse import urlencode
        params = {"q": query, "kl": "us-en"}
        if df:
            params["df"] = df
        url = "https://html.duckduckgo.com/html/?" + urlencode(params)
        req = _urlrequest.Request(url, headers={
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                          "(KHTML, like Gecko) Chrome/120.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml",
            "Accept-Language": "en-US,en;q=0.9"
        })
        with _urlrequest.urlopen(req, timeout=10) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
    except (_urlerror.URLError, _urlerror.HTTPError, TimeoutError) as exc:
        return [], "DuckDuckGo unreachable: " + str(exc)
    except Exception as exc:
        return [], "DDG request failed: " + str(exc)

    # DDG results: <a class="result__a" href="...">title</a>
    # followed by <a class="result__snippet">snippet</a>.
    results = []
    pattern = re.compile(
        r'<a[^>]+class="result__a"[^>]+href="([^"]+)"[^>]*>(.*?)</a>.*?'
        r'<a[^>]+class="result__snippet"[^>]*>(.*?)</a>',
        re.DOTALL | re.IGNORECASE
    )
    for match in pattern.finditer(raw):
        href, title_html, snippet_html = match.groups()
        # Clean title (strip inner tags)
        title = re.sub(r"<[^>]+>", "", title_html).strip()
        snippet = re.sub(r"<[^>]+>", "", snippet_html).strip()
        snippet = _stdlib_html.unescape(snippet)
        # DDG wraps the URL in //duckduckgo.com/l/?uddg=<encoded>.
        # Unwrap to the real destination when present.
        if "uddg=" in href:
            try:
                from urllib.parse import parse_qs, unquote
                qs = parse_qs(_urlparse(href).query)
                real = qs.get("uddg", [""])[0]
                if real:
                    href = unquote(real)
            except Exception:
                pass
        if not href or not title:
            continue
        results.append({"title": title, "url": href, "snippet": snippet})
        if len(results) >= cap:
            break
    if not results:
        return [], ("No results found for: " + query
                    + " (DDG HTML page may have changed shape)")
    return results, None


# ─── fetch_url ────────────────────────────────────────────────────────

_FETCH_HARD_MAX_BYTES = 1_500_000  # 1.5 MB raw download cap


def _fetch_url(args, ctx):
    """HTTP GET + HTML→text. Public-web only."""
    url = _str_arg(args, "url")
    if not url:
        return {"content": "", "error": "fetch_url needs a url"}
    # Normalize scheme
    if not url.startswith(("http://", "https://")):
        if url.startswith("//"):
            url = "https:" + url
        elif url.startswith("www."):
            url = "https://" + url
        else:
            return {
                "content": "",
                "error": "fetch_url only accepts http://, https://, "
                         "or www.* URLs. Local paths and file:// are "
                         "blocked — use the read_file tool or run_shell_command."
            }
    if not _is_public_web_url(url):
        return {
            "content": "",
            "error": ("fetch_url is for the public web only. Refusing to "
                      "fetch local / private addresses. Use the read_file "
                      "tool or a shell command for local files.")
        }
    max_bytes = _int_arg(args, "max_bytes") or _FETCH_HARD_MAX_BYTES
    if max_bytes <= 0 or max_bytes > _FETCH_HARD_MAX_BYTES:
        max_bytes = _FETCH_HARD_MAX_BYTES
    full = _bool_arg(args, "full") or False

    try:
        req = _urlrequest.Request(url, headers={
            "User-Agent": "NothingClaw/1.0 (+https://github.com/Leriart/NothingLess)",
            "Accept": "text/html,application/xhtml+xml,text/plain;q=0.9"
        })
        # Read in one shot, but cap at max_bytes+1 so we can detect
        # truncation without buffering the whole 1.5MB twice.
        with _urlrequest.urlopen(req, timeout=15) as resp:
            status = resp.status
            ctype = resp.headers.get("Content-Type", "") or ""
            content_length = resp.headers.get("Content-Length")
            buf = bytearray()
            while len(buf) <= max_bytes:
                chunk = resp.read(65536)
                if not chunk:
                    break
                buf.extend(chunk)
            truncated_at_download = len(buf) > max_bytes
            if truncated_at_download:
                buf = buf[:max_bytes]
        raw = bytes(buf)
        try:
            text = raw.decode("utf-8", errors="replace")
        except Exception:
            text = raw.decode("latin-1", errors="replace")
    except (_urlerror.URLError, _urlerror.HTTPError, TimeoutError) as exc:
        return {"content": "", "error": "fetch_url: " + str(exc)}
    except Exception as exc:
        return {"content": "", "error": "fetch_url: " + str(exc)}

    # Non-HTML content — just return as text after a sanity cap.
    if "html" not in ctype.lower() and "<html" not in text[:200].lower():
        plain = text[:max_bytes]
        if not full:
            try:
                from mcp.nothingclaw.context_budget import truncate_to_budget
                plain, _ = truncate_to_budget(plain, ctx.tool_budget)
            except Exception:
                pass
        return {
            "content": ("# " + (url) + "\n"
                        + "Content-Type: " + ctype + "\n\n"
                        + plain),
            "error": None
        }

    title, body = _html_to_text(text)
    size_note = ""
    if truncated_at_download:
        size_note = ("[Note: response was " + str(max_bytes)
                     + "+ bytes; truncated to " + str(max_bytes)
                     + " before HTML→text conversion.]\n\n")
    out = ("# " + (title or url) + "\n"
           + "Source: " + url + "\n\n"
           + size_note
           + body)
    if not full:
        try:
            from mcp.nothingclaw.context_budget import truncate_to_budget
            out, was_truncated = truncate_to_budget(out, ctx.tool_budget)
            if was_truncated and not size_note:
                # Prepend a size note if we truncated at the text stage
                out = ("[Note: response truncated to fit the model's context "
                       "budget. Call fetch_url again with full=true or a "
                       "more specific URL to see the rest.]\n\n") + out
        except Exception:
            pass
    return {"content": out, "error": None}


# ─── manage_rag ───────────────────────────────────────────────────────
#
# Lightweight RAG — JSON-backed TF-IDF index over local files. No
# embeddings model, no ChromaDB, no async. Indexes are stored at
# ~/.local/share/nothingless/rag/<sha1(dir)>.json. Each index entry
# is {path, mtime, chunks: [{id, text, terms: {term: tf}}]}. Search
# tokenises the query, computes BM25-lite scoring (just TF-IDF with
# length normalisation), and returns the top N chunks trimmed to
# ctx.tool_budget.

_RAG_DIR_NAME = "rag"
_TEXT_EXTS = {
    ".md", ".txt", ".rst", ".org", ".adoc",
    ".py", ".js", ".ts", ".jsx", ".tsx", ".mjs", ".cjs",
    ".json", ".yaml", ".yml", ".toml", ".xml", ".csv", ".tsv",
    ".html", ".htm", ".css", ".scss", ".sass", ".less",
    ".sh", ".bash", ".zsh", ".fish", ".ps1",
    ".c", ".h", ".cpp", ".cc", ".cxx", ".hpp", ".rs", ".go",
    ".java", ".kt", ".scala", ".rb", ".php", ".pl", ".lua",
    ".sql", ".graphql", ".proto",
    ".env", ".conf", ".cfg", ".ini", ".properties",
    ".log", ".gitignore", ".dockerignore",
}
_SKIP_DIRS = {".git", "node_modules", "__pycache__", "venv", ".venv",
              "target", "build", "dist", ".cache", ".next", ".nuxt",
              ".mypy_cache", ".pytest_cache", ".ruff_cache", "vendor"}
_BINARY_CHECK_BYTES = 4096


def _rag_index_path(abs_dir):
    import hashlib
    h = hashlib.sha1(abs_dir.encode("utf-8")).hexdigest()[:16]
    safe = re.sub(r"[^a-zA-Z0-9_-]", "_", os.path.basename(abs_dir))[:40] or "root"
    base = os.path.expanduser(os.environ.get(
        "XDG_DATA_HOME", os.path.expanduser("~/.local/share")))
    d = os.path.join(base, "nothingless", _RAG_DIR_NAME)
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, safe + "_" + h + ".json")


def _is_probably_text(path):
    """Sniff the first ~4KB for NULs / high ratio of non-printable bytes.
    Cheap binary detector — avoids trying to index a 200MB tarball."""
    try:
        with open(path, "rb") as fp:
            sample = fp.read(_BINARY_CHECK_BYTES)
    except (OSError, IOError):
        return False
    if not sample:
        return True
    # NUL byte → binary
    if b"\x00" in sample:
        return False
    # Count printable ASCII + common whitespace
    printable = sum(1 for b in sample
                    if 32 <= b <= 126 or b in (9, 10, 13))
    if printable / len(sample) < 0.85:
        return False
    return True


def _tokenize(text):
    """Lowercase, strip punctuation, drop 1- and 2-char tokens. No
    stopword list — the BM25 IDF step naturally deweights 'the' etc."""
    return [w for w in re.findall(r"[a-z0-9_]{2,}", text.lower())]


def _chunk_text(text, max_chars):
    """Split text into chunks of ~max_chars on paragraph / line / word
    boundaries. Tries to keep headings attached to their body.
    """
    if len(text) <= max_chars:
        return [text]
    chunks = []
    rest = text
    while len(rest) > max_chars:
        # Prefer a paragraph break, then a line break, then a sentence.
        cut = -1
        for sep in ("\n\n", "\n", ". "):
            idx = rest.rfind(sep, 0, max_chars)
            if idx > max_chars * 0.5:
                cut = idx + len(sep)
                break
        if cut <= 0:
            # Fall back to a word boundary
            idx = rest.rfind(" ", 0, max_chars)
            cut = (idx + 1) if idx > max_chars * 0.3 else max_chars
        chunks.append(rest[:cut].rstrip())
        rest = rest[cut:].lstrip()
    if rest:
        chunks.append(rest)
    return chunks


def _score_chunks(query_terms, chunks, doc_lens, avg_dl):
    """BM25-lite scoring. Returns (score, chunk_index) pairs.

    Uses TF-IDF as a proxy for BM25 (no per-doc length saturation,
    no k1/b tuning). For local RAG over a few thousand chunks this
    is indistinguishable from full BM25 in practice — Odysseus
    uses the same simplification in their retrieval helpers.
    """
    import math
    N = len(chunks)
    # IDF — log((N - df + 0.5) / (df + 0.5) + 1)
    scores = [0.0] * N
    # Pre-compute df per query term
    for qt in set(query_terms):
        df = sum(1 for c in chunks if qt in c["terms"])
        if df == 0:
            continue
        idf = math.log(1 + (N - df + 0.5) / (df + 0.5))
        for i, c in enumerate(chunks):
            tf = c["terms"].get(qt, 0)
            if tf == 0:
                continue
            # Length-normalised TF
            norm = 1 + math.log(1 + tf)
            dl_norm = 1 / (1 + 0.3 * (doc_lens[i] / max(avg_dl, 1) - 1))
            scores[i] += idf * norm * dl_norm
    return scores


def _manage_rag_scan(abs_dir, index_path, max_chunk_chars, force=False):
    """Scan `abs_dir` and rebuild the index file.

    Existing entries that still exist on disk are reused (cheap
    re-tokenisation only when mtime changed). Deleted files are
    dropped. This makes incremental rescans O(changed files).
    """
    abs_dir = os.path.abspath(abs_dir)
    # Load existing index
    try:
        with open(index_path, "r", encoding="utf-8") as fp:
            index = json.load(fp)
    except (FileNotFoundError, json.JSONDecodeError):
        index = {"directory": abs_dir, "files": {}}
    old_files = index.get("files", {})
    seen_paths = set()
    indexed_count = 0
    file_count = 0

    for root, dirs, files in os.walk(abs_dir):
        # Filter skip dirs in-place
        dirs[:] = [d for d in dirs if d not in _SKIP_DIRS and not d.startswith(".")]
        for fn in files:
            ext = os.path.splitext(fn)[1].lower()
            if ext not in _TEXT_EXTS:
                continue
            path = os.path.join(root, fn)
            seen_paths.add(path)
            try:
                mtime = os.path.getmtime(path)
            except OSError:
                continue
            old = old_files.get(path)
            if (old and not force and old.get("mtime") == mtime
                    and old.get("chunk_size") == max_chunk_chars):
                # Reuse the cached chunks. Cheap path — keeps RAG
                # rescan fast on large codebases.
                file_count += 1
                indexed_count += len(old.get("chunks", []))
                continue
            if not _is_probably_text(path):
                old_files.pop(path, None)
                continue
            try:
                with open(path, "r", encoding="utf-8", errors="replace") as fp:
                    content = fp.read()
            except OSError:
                continue
            text_chunks = _chunk_text(content, max_chunk_chars)
            chunks = []
            for j, t in enumerate(text_chunks):
                terms = _tokenize(t)
                # Term frequency as a small dict — keeps the index
                # file size manageable (no long arrays of duplicates).
                tf = {}
                for w in terms:
                    tf[w] = tf.get(w, 0) + 1
                chunks.append({
                    "id": path + "#" + str(j),
                    "text": t,
                    "terms": tf,
                    "len": len(terms)
                })
            old_files[path] = {
                "mtime": mtime,
                "chunk_size": max_chunk_chars,
                "chunks": chunks
            }
            file_count += 1
            indexed_count += len(chunks)

    # Drop entries that disappeared
    removed = [p for p in list(old_files.keys()) if p not in seen_paths]
    for p in removed:
        old_files.pop(p, None)

    index["files"] = old_files
    index["directory"] = abs_dir
    index["chunk_size"] = max_chunk_chars
    index["updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    try:
        with open(index_path, "w", encoding="utf-8") as fp:
            json.dump(index, fp, ensure_ascii=False)
    except OSError as exc:
        return {"content": "", "error": "Failed to write RAG index: " + str(exc)}
    return {
        "content": json.dumps({
            "indexed_files": file_count,
            "indexed_chunks": indexed_count,
            "removed_files": len(removed),
            "directory": abs_dir,
            "index_path": index_path
        }, ensure_ascii=False, indent=2),
        "error": None
    }


def _manage_rag(args, ctx):
    action = _str_arg(args, "action")
    if not action:
        return {"content": "", "error": "manage_rag needs action=list|add_directory|remove_directory|search"}
    if action == "list":
        base = os.path.expanduser(os.environ.get(
            "XDG_DATA_HOME", os.path.expanduser("~/.local/share")))
        d = os.path.join(base, "nothingless", _RAG_DIR_NAME)
        if not os.path.isdir(d):
            return {"content": "No RAG indexes yet. Use action=add_directory first.", "error": None}
        lines = ["Indexed RAG directories:\n"]
        any_found = False
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".json"):
                continue
            try:
                with open(os.path.join(d, fn), "r", encoding="utf-8") as fp:
                    idx = json.load(fp)
            except (OSError, json.JSONDecodeError):
                continue
            files = idx.get("files", {})
            chunk_total = sum(len(f.get("chunks", [])) for f in files.values())
            lines.append("- " + idx.get("directory", "?"))
            lines.append("    files: " + str(len(files))
                         + ", chunks: " + str(chunk_total)
                         + ", updated: " + str(idx.get("updated_at", "?")))
            any_found = True
        if not any_found:
            return {"content": "No RAG indexes yet. Use action=add_directory first.", "error": None}
        return {"content": "\n".join(lines), "error": None}
    if action == "add_directory":
        directory = _str_arg(args, "directory")
        if not directory:
            return {"content": "", "error": "add_directory needs a directory path"}
        directory = os.path.abspath(os.path.expanduser(directory))
        if not os.path.isdir(directory):
            return {"content": "", "error": "Directory not found: " + directory}
        max_chunk_chars = _int_arg(args, "max_chunk_chars") or 1200
        index_path = _rag_index_path(directory)
        return _manage_rag_scan(directory, index_path, max_chunk_chars)
    if action == "remove_directory":
        directory = _str_arg(args, "directory")
        if not directory:
            return {"content": "", "error": "remove_directory needs a directory path"}
        directory = os.path.abspath(os.path.expanduser(directory))
        index_path = _rag_index_path(directory)
        try:
            os.remove(index_path)
        except FileNotFoundError:
            return {"content": "", "error": "No RAG index for: " + directory}
        except OSError as exc:
            return {"content": "", "error": "Failed to remove RAG index: " + str(exc)}
        return {"content": "Removed RAG index for: " + directory, "error": None}
    if action == "search":
        query = _str_arg(args, "query")
        if not query:
            return {"content": "", "error": "manage_rag search needs a query"}
        top_k = _int_arg(args, "top_k") or 5
        if top_k <= 0 or top_k > 50:
            top_k = 5
        base = os.path.expanduser(os.environ.get(
            "XDG_DATA_HOME", os.path.expanduser("~/.local/share")))
        d = os.path.join(base, "nothingless", _RAG_DIR_NAME)
        if not os.path.isdir(d):
            return {"content": "", "error": "No RAG indexes yet. Use add_directory first."}
        query_terms = _tokenize(query)
        if not query_terms:
            return {"content": "", "error": "Query has no indexable terms."}
        # Collect all chunks across all indexes with a per-index
        # offset so we can rank globally and report which directory
        # each hit came from.
        all_chunks = []
        chunk_to_index = []
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".json"):
                continue
            try:
                with open(os.path.join(d, fn), "r", encoding="utf-8") as fp:
                    idx = json.load(fp)
            except (OSError, json.JSONDecodeError):
                continue
            for path, fdata in idx.get("files", {}).items():
                for ch in fdata.get("chunks", []):
                    all_chunks.append(ch)
                    chunk_to_index.append(idx.get("directory", "?"))
        if not all_chunks:
            return {"content": "", "error": "RAG index is empty — add a directory first."}
        # Score. BM25-lite: TF-IDF with length normalisation.
        doc_lens = [c.get("len", 1) for c in all_chunks]
        avg_dl = sum(doc_lens) / max(len(doc_lens), 1)
        scores = _score_chunks(query_terms, all_chunks, doc_lens, avg_dl)
        # Top-k
        ranked = sorted(enumerate(scores), key=lambda x: -x[1])[:top_k]
        # Apply tier-based chunk-length cap
        per_chunk_cap = max(400, min(2000, ctx.tool_budget * 4 // max(len(ranked), 1)))
        lines = ["RAG search results for: " + query + "\n"]
        hits = 0
        budget_left = ctx.tool_budget
        for rank, (orig_idx, score) in enumerate(ranked, start=1):
            if score <= 0 or budget_left <= 0:
                break
            chunk = all_chunks[orig_idx]
            text = chunk.get("text", "")
            if len(text) > per_chunk_cap:
                text = text[:per_chunk_cap].rsplit(" ", 1)[0] + "…"
            # Per-result token estimate to gate further inclusion
            approx_tokens = max(1, len(text) // 4)
            if approx_tokens > budget_left:
                continue
            budget_left -= approx_tokens
            chunk_id = chunk.get("id", "?")
            src_dir = chunk_to_index[orig_idx]
            lines.append("[" + str(rank) + "] score=" + ("%.3f" % score)
                         + "  " + chunk_id)
            lines.append("    dir: " + src_dir)
            lines.append("    " + text.replace("\n", "\n    "))
            lines.append("")
            hits += 1
        if hits == 0:
            return {
                "content": "No matching chunks found for: " + query,
                "error": None
            }
        body = "\n".join(lines).rstrip()
        return {"content": body, "error": None}
    return {
        "content": "",
        "error": ("Unknown action '" + action
                  + "'. Use: list, add_directory, remove_directory, search")
    }


# ---------------------------------------------------------------------------
# Tool dispatch
# ---------------------------------------------------------------------------

def invoke_tool(name, arguments, ctx=None):
    """Dispatch a tool call.

    `ctx` is an optional `_RequestContext` populated by the HTTP
    handler. When absent (e.g. unit tests), we synthesize a default
    'small' context so tools that read the budget don't crash. The
    capability-aware web/fetch/rag handlers use ctx.tool_budget to
    truncate their responses; the desktop-control handlers ignore it.
    """
    args = arguments or {}
    if ctx is None:
        ctx = _resolve_request_context("small", "")

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
        # Snapshot the window's previous workspace BEFORE the move so
        # the AI assistant can offer a reliable "regresalo" / "undo"
        # for single-window moves too. Without this the undo handler
        # in Ai.qml has to fall back to "default workspace 1", which
        # routinely sends windows back to the wrong place.
        prev_ws = None
        if wid:
            list_result = _run_axctl(["window", "list"])
            if not list_result.get("error"):
                try:
                    snap = json.loads(list_result.get("content", "[]"))
                except (TypeError, ValueError):
                    snap = []
                for w in snap:
                    if isinstance(w, dict) and str(w.get("id")) == str(wid):
                        prev_ws = w.get("workspace_id")
                        break
        result = _run_axctl(argv)
        if not result.get("error") and prev_ws is not None:
            # Wrap the success payload with undo metadata so the AI
            # can build the inverse move. Failures don't need this —
            # the move didn't happen so there's nothing to revert.
            try:
                payload = json.loads(result.get("content", "{}"))
            except (TypeError, ValueError):
                payload = {}
            if not isinstance(payload, dict):
                payload = {}
            payload["previous_workspace_id"] = prev_ws
            payload["window_id"] = wid
            payload["workspace_id"] = ws
            return {
                "content": json.dumps(payload, ensure_ascii=False, indent=2),
                "error": None
            }
        return result

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

        # ── Snapshot previous workspaces ──
        # Snapshot every targeted window's current workspace BEFORE
        # we run any `move-to` calls. The response payload embeds
        # `previous_workspace_id` so the AI assistant can offer a
        # reliable "regresalo" / "undo" / "return" command — without
        # this snapshot the AI would have to fall back to "default
        # workspace 1" and routinely send windows back to the wrong
        # place. Cheap (one extra list call), idempotent if the move
        # itself fails because we only record from the snapshot, not
        # from the post-move state.
        prev_snapshot = {}
        list_result = _run_axctl(["window", "list"])
        if not list_result.get("error"):
            try:
                snap_windows = json.loads(list_result.get("content", "[]"))
            except (TypeError, ValueError):
                snap_windows = []
            for w in snap_windows:
                if isinstance(w, dict) and w.get("id") is not None:
                    prev_snapshot[str(w["id"])] = w.get("workspace_id")
        else:
            # If we couldn't snapshot, return without doing the move
            # — better to fail loudly than to silently corrupt the
            # user's undo history.
            return {
                "content": "",
                "error": "move_windows could not snapshot window "
                         "state before moving: "
                         + str(list_result.get("error"))
            }

        moved = []
        failures = []
        for wid, ws in pairs:
            result = _run_axctl(["workspace", "move-to", ws, wid])
            if result.get("error"):
                failures.append({
                    "window_id": wid,
                    "workspace_id": ws,
                    "previous_workspace_id": prev_snapshot.get(wid),
                    "error": result["error"]
                })
            else:
                moved.append({
                    "window_id": wid,
                    "workspace_id": ws,
                    "previous_workspace_id": prev_snapshot.get(wid)
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
        if not shutil.which("xdg-open"):
            # xdg-utils isn't installed (some minimal Arch setups,
            # nix-shell sandboxes, headless CI). Fall back to the
            # DE-specific helpers where available, otherwise surface
            # a clear error so the model knows to try a different tool.
            for fallback in ("gio", "x-www-browser", "sensible-browser"):
                if shutil.which(fallback):
                    if _fire_and_forget([fallback, "open", resolved]
                                        if fallback == "gio"
                                        else [fallback, resolved]):
                        return {
                            "content": "Dispatched '" + resolved
                                     + "' via " + fallback + ".",
                            "error": None
                        }
            return {
                "content": "",
                "error": "xdg-open not found on PATH and no fallback "
                         + "(gio, x-www-browser, sensible-browser) is "
                         + "available. Install xdg-utils or use "
                         + "open_app / execute_command instead."
            }

        if _fire_and_forget(["xdg-open", resolved]):
            return {
                "content": "Dispatched '" + resolved + "' to the default browser.",
                "error": None
            }
        return {
            "content": "",
            "error": "xdg-open failed to launch (binary not found or "
                     + "spawn error). Try install xdg-utils."
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

    # ── context_info ────────────────────────────────────────────────
    # Reports the tier + per-tool budget NothingClaw is using for this
    # call. Lets a model plan its chain of tool calls — "I have 8k
    # tokens of budget for the result of the next fetch_url, so I'll
    # pass full=true" vs "I only have 1k, call with max_bytes=4000
    # and a specific #section anchor instead".
    if name == "context_info":
        info = {
            "tier": ctx.tier,
            "model_name": ctx.model_name,
            "model_host": ctx.model_host,
            "context_window": ctx.context_window,
            "tool_budget_tokens": ctx.tool_budget,
            "input_budget_tokens": ctx.input_budget,
            "tools_available_in_tier": list(_TIER_NAMES.get(
                ctx.tier, _TIER_NAMES["small"]))
        }
        # Include the per-tier budget table so the model can reason
        # about it. Cheap to render — it's a 4-entry dict.
        try:
            from mcp.nothingclaw.context_budget import (
                DEFAULT_TOOL_RESULT_BUDGET)
            info["tier_budgets"] = DEFAULT_TOOL_RESULT_BUDGET
        except Exception:
            pass
        return {
            "content": json.dumps(info, ensure_ascii=False, indent=2),
            "error": None
        }

    # ── web_search ──────────────────────────────────────────────────
    # SearXNG when configured, otherwise DuckDuckGo HTML (no API key).
    # The result size is capped by ctx.tool_budget — a tiny Ollama
    # model gets 3 short snippets, a large cloud model gets up to 10.
    if name == "web_search":
        return _web_search(args, ctx)

    # ── fetch_url ───────────────────────────────────────────────────
    # Public-web-only HTTP GET with HTML→text extraction. local URLs
    # are explicitly blocked (use the read_file tool or shell instead).
    if name == "fetch_url":
        return _fetch_url(args, ctx)

    # ── manage_rag ──────────────────────────────────────────────────
    # Lightweight RAG index over local files. JSON + TF-IDF — no
    # embeddings model, no ChromaDB. add_directory scans recursively,
    # search returns the top N chunks by TF-IDF score.
    if name == "manage_rag":
        return _manage_rag(args, ctx)

    # ── Memory ──────────────────────────────────────────────────────
    if name == "manage_memory":
        os.makedirs(mem_dir, exist_ok=True)
        mem_path = mem_dir + "/nothingclaw_memory.json"
        action = _str_arg(args, "action")
        if not action or action not in ("set", "get", "delete", "list"):
            return {"content": "", "error": "manage_memory needs action=set|get|delete|list"}
        store = {}
        try:
            with open(mem_path, "r") as fp: store = json.load(fp)
        except (FileNotFoundError, json.JSONDecodeError): store = {}
        if action == "list":
            if not store: return {"content": "Memory is empty.", "error": None}
            lines = ["Memory entries (" + str(len(store)) + "):"]
            for k, v in sorted(store.items()):
                vs = str(v)
                if len(vs) > 120: vs = vs[:117] + "..."
                lines.append("  " + k + " = " + vs)
            return {"content": "\n".join(lines), "error": None}
        if action == "get":
            key = _str_arg(args, "key")
            if not key: return {"content": "", "error": "manage_memory get needs key"}
            if key not in store: return {"content": "", "error": "Key '" + key + "' not found"}
            return {"content": json.dumps(store[key], ensure_ascii=False), "error": None}
        if action == "set":
            key = _str_arg(args, "key")
            if not key: return {"content": "", "error": "manage_memory set needs key"}
            value = _str_arg(args, "value") or ""
            store[key] = {"value": value, "updated_at": time.strftime("%Y-%m-%dT%H:%M:%S")}
            try:
                with open(mem_path, "w") as fp: json.dump(store, fp, ensure_ascii=False, indent=2)
            except OSError as e: return {"content": "", "error": "Memory write failed: " + str(e)}
            return {"content": key + " = " + value, "error": None}
        if action == "delete":
            key = _str_arg(args, "key")
            if not key: return {"content": "", "error": "manage_memory delete needs key"}
            if key not in store: return {"content": "", "error": "Key '" + key + "' not found"}
            del store[key]
            try:
                with open(mem_path, "w") as fp: json.dump(store, fp, ensure_ascii=False, indent=2)
            except OSError as e: return {"content": "", "error": "Memory write failed: " + str(e)}
            return {"content": "Deleted: " + key, "error": None}

    return {"content": "", "error": "Tool '" + str(name) + "' not found"}


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
        q = (query.get("q", [None])[0] or "").strip()

        if q:
            names = _rank_tools_by_query(q, top_k=8)
            # Always-available info tools (Odysseus's ALWAYS_AVAILABLE
            # equivalent). The model needs list_windows to discover IDs
            # before calling move / close / focus. Without them, the
            # model can see move_window_to_workspace but has no way to
            # find the window_id argument.
            always = {"manage_memory", "list_windows", "list_installed_apps",
                      "move_window_to_workspace", "open_url"}
            # Prepend always tools, then the ranked ones (deduped)
            seen = set(always)
            ordered = list(always)
            for n in names:
                if n not in seen:
                    ordered.append(n)
                    seen.add(n)
            payload = [t for t in TOOLS if t["name"] in ordered]
        else:
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
        # Capability resolution (mirrors do_GET): the per-tool handlers
        # size their results based on the requesting model's tier so a
        # 2B Ollama model doesn't drown in HTML. We pull the same
        # headers/query params as the discovery endpoint.
        try:
            from urllib.parse import urlparse, parse_qs
            post_query = parse_qs(urlparse(self.path).query)
        except Exception:
            post_query = {}
        tier = (post_query.get("capability", [None])[0]
                or self.headers.get("X-Capability", "").strip().lower()
                or None)
        model_name = (post_query.get("model", [None])[0]
                      or self.headers.get("X-Model-Name", "").strip()
                      or "")
        model_host = (post_query.get("host", [None])[0]
                      or self.headers.get("X-Model-Host", "").strip()
                      or "")
        if tier not in ("tiny", "small", "medium", "large"):
            if model_name:
                tier = _detect_capability(model_name, model_host)
            else:
                tier = "small"
        ctx = _resolve_request_context(tier, model_name)
        result = invoke_tool(name, arguments, ctx)
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