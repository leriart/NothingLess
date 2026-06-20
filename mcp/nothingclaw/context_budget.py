#!/usr/bin/env python3
"""Context-budget helpers for NothingClaw.

Pure stdlib. Imported by server.py to:

  1. Estimate how many tokens a string will consume when sent back to
     the model. Tokenizer-free approximation: ~4 chars per token for
     English / code, ~1.5 chars per token for CJK. Good enough to
     decide whether a tool result will fit in a small local model's
     4k-8k context window without actually loading a tokenizer.

  2. Resolve the model's effective input budget. Combines the known
     context window for common models (subset of Odysseus's
     KNOWN_CONTEXT_WINDOWS) with a conservative headroom default
     (85%) so we leave room for the model's reply.

  3. Truncate tool result payloads to fit the budget. Slices at the
     nearest paragraph / sentence / line boundary so the truncation
     is invisible when the model sees it.

Adapted from Odysseus's src/context_budget.py and src/model_context.py
(Apache-compatible patterns, stdlib only).
"""

import re


# Approximate chars-per-token by Unicode block. Conservative enough
# that we never overflow the model's window in practice — under-counting
# is fine because the headroom multiplier handles slack.
_CJK_RANGES = (
    (0x4E00, 0x9FFF),     # CJK Unified Ideographs
    (0x3400, 0x4DBF),     # CJK Extension A
    (0x3040, 0x309F),     # Hiragana
    (0x30A0, 0x30FF),     # Katakana
    (0xAC00, 0xD7AF),     # Hangul Syllables
    (0xFF00, 0xFFEF),     # Halfwidth/Fullwidth
)


def _is_cjk(char):
    cp = ord(char)
    for lo, hi in _CJK_RANGES:
        if lo <= cp <= hi:
            return True
    return False


def estimate_tokens(text):
    """Approximate token count for a string.

    English / Latin / code: ~4 chars/token. CJK: ~1.5 chars/token.
    The mixture estimate walks the string once so a half-CJK response
    lands in between. Plus a 4-token per-message overhead so system
    prompt / role markers are accounted for (Odysseus's pattern).
    """
    if not text:
        return 0
    latin = 0
    cjk = 0
    other = 0
    for ch in text:
        if ch.isspace():
            other += 1
        elif _is_cjk(ch):
            cjk += 1
        elif ch.isascii():
            latin += 1
        else:
            other += 1
    # 4 chars/token latin, 1.5 chars/token CJK, 4 chars/token other (whitespace-heavy)
    tokens = (latin / 4.0) + (cjk / 1.5) + (other / 4.0)
    return int(tokens) + 4


# Subset of Odysseus's KNOWN_CONTEXT_WINDOWS, scoped to models a
# NothingLess user is likely to actually invoke. Longest-prefix match
# wins so "gpt-4o-mini" doesn't get shadowed by "gpt-4". Order matters.
KNOWN_CONTEXT_WINDOWS = (
    # OpenAI
    ("gpt-5", 400000),
    ("gpt-4.1", 1000000),
    ("gpt-4o", 128000),
    ("gpt-4-turbo", 128000),
    ("gpt-4", 8192),
    ("o1-preview", 128000),
    ("o1-mini", 128000),
    ("o3-mini", 200000),
    ("gpt-3.5-turbo", 16385),
    # Anthropic
    ("claude-3-opus", 200000),
    ("claude-3.5-sonnet", 200000),
    ("claude-3-sonnet", 200000),
    ("claude-3-haiku", 200000),
    ("claude-4", 200000),
    # Google
    ("gemini-2.5-pro", 1000000),
    ("gemini-2.0-pro", 2000000),
    ("gemini-2.0-flash", 1000000),
    ("gemini-1.5-pro", 2000000),
    ("gemini-1.5-flash", 1000000),
    # DeepSeek
    ("deepseek-chat", 128000),
    ("deepseek-reasoner", 128000),
    # Mistral
    ("mistral-large", 128000),
    ("mistral-medium", 32768),
    ("mistral-small", 32768),
    # xAI
    ("grok-2", 131072),
    # Meta
    ("llama-3.1-405b", 131072),
    ("llama-3.1-70b", 131072),
    ("llama-3.1-8b", 131072),
    # Qwen (both colon Ollama form and hyphen HF form)
    ("qwen2.5-72b", 131072),
    ("qwen2.5-32b", 131072),
    ("qwen2.5-14b", 131072),
    ("qwen2.5-7b", 32768),
    ("qwen2.5-3b", 32768),
    ("qwen2.5-1.5b", 32768),
    ("qwen2.5-0.5b", 32768),
    # Cohere
    ("command-r-plus", 128000),
    # Microsoft Phi
    ("phi-3-medium", 4096),
    ("phi-3-small", 4096),
    ("phi-3-mini", 4096),
    # Generic Ollama defaults by parameter size. The colon form is
    # what Ollama uses (e.g. "qwen2.5:7b"); the bare "B" form
    # matches HF / generic names ("Llama-3-8B").
    (":70b", 32768),
    (":32b", 32768),
    (":14b", 16384),
    (":13b", 8192),
    (":8b", 8192),
    (":7b", 8192),
    (":3b", 4096),
    (":1.5b", 4096),
    (":1b", 4096),
    ("-8b", 8192),
    ("-7b", 8192),
    ("-3b", 4096),
)


def lookup_known_context(model_name):
    """Look up the context window for a known model name. Returns int or
    None when unknown. Strips common provider prefixes/suffixes
    (e.g. "openai/gpt-4o", "qwen2.5:7b-instruct-q4_K_M") before matching.
    Longest-prefix match wins.
    """
    if not model_name:
        return None
    # Normalize: strip path prefix, tag suffix, keep only the basename-ish bit
    cleaned = str(model_name).strip().lower()
    # Strip provider prefix ("openai/", "anthropic/", "groq/")
    if "/" in cleaned:
        cleaned = cleaned.split("/", 1)[1]
    # Strip instruct/quant tags ("-instruct-q4_K_M" → "-instruct")? No — those
    # tags can contain size hints we want to match (":7b" still matches).
    best = None
    for needle, ctx in KNOWN_CONTEXT_WINDOWS:
        if needle in cleaned:
            if best is None or len(needle) > len(best[0]):
                best = (needle, ctx)
    return best[1] if best else None


# Per-tier token budgets for tool *results*. The model receives the
# whole conversation, so tool results that exceed these limits will
# silently get cut off when the provider truncates from the front
# (most providers do). We cut from the right (truncate tail with a
# marker) so the model always sees the first N tokens, which is
# where the structured metadata lives.
#
# Tier mapping (mirrors _TOOL_TIERS in server.py):
#   tiny   ≤3B params     — 4k context, give each tool ~1k tokens of result
#   small  3B-13B         — 8k context, give each tool ~2k tokens
#   medium 13B-30B / API  — 16k context, give each tool ~4k tokens
#   large  30B+           — 32k+ context, give each tool ~8k tokens
DEFAULT_TOOL_RESULT_BUDGET = {
    "tiny": 1000,
    "small": 2000,
    "medium": 4000,
    "large": 8000,
}


def compute_input_token_budget(configured, context_length, explicit=None,
                                default=6000, headroom=0.85, hard_max=200000):
    """Resolve the effective input token budget for the next request.

    Args:
        configured: explicit user-configured budget (or None/0 for auto).
        context_length: known context window in tokens (or 0 if unknown).
        explicit: deprecated alias for `configured` (kept for back-compat).
        default: fallback budget when nothing is known.
        headroom: fraction of context to actually use (0.85 leaves 15% for reply).
        hard_max: safety cap — never return more than this many tokens,
            even if the model claims a 1M-token window. Stops runaway
            prompts from locking up the chat for minutes.

    The "presence of explicit value" semantics (any non-None/non-zero
    int is treated as a cap, even 1) match Odysseus's pattern: a
    default of 6000 means "auto", anything else means "use this".
    """
    if configured is None:
        configured = explicit
    if configured and configured > 0:
        return min(int(configured), hard_max)
    if context_length and context_length > 0:
        return min(int(context_length * headroom), hard_max)
    return min(int(default), hard_max)


def tool_result_budget(tier):
    """Return the per-tool-result token budget for a capability tier.
    Used to size web_search / fetch_url / manage_rag results so a tiny
    Ollama model doesn't drown in 10k tokens of HTML.
    """
    if not tier:
        return DEFAULT_TOOL_RESULT_BUDGET["small"]
    return DEFAULT_TOOL_RESULT_BUDGET.get(
        tier.lower(), DEFAULT_TOOL_RESULT_BUDGET["small"])


def truncate_to_budget(text, max_tokens, marker=None):
    """Truncate `text` to ~`max_tokens` tokens, slicing at the nearest
    paragraph / sentence / line boundary so the cut looks natural.

    Returns (truncated_text, was_truncated: bool). When `marker` is
    provided, append it as a trailing notice (default: a short line
    explaining the truncation so the model doesn't think the source
    just ended).
    """
    if not text:
        return text, False
    current = estimate_tokens(text)
    if current <= max_tokens:
        return text, False
    # Approximate char budget — use the latin ratio so we don't
    # over-truncate CJK. Add 10% slack.
    approx_chars = int(max_tokens * 4 * 1.1)
    if approx_chars >= len(text):
        return text, False
    cut = text[:approx_chars]
    # Try to cut at a paragraph boundary, then a sentence boundary,
    # then a line boundary. Each fallback shortens the cut. We pick
    # the LAST occurrence so the truncated chunk stays as long as
    # possible while still landing on a natural break.
    for sep in ("\n\n", ". ", ".\n", "\n"):
        idx = cut.rfind(sep)
        if idx > approx_chars * 0.6:
            cut = cut[:idx + len(sep)].rstrip()
            break
    else:
        # No break found — fall back to word boundary
        idx = cut.rfind(" ")
        if idx > approx_chars * 0.6:
            cut = cut[:idx]
    if marker is None:
        marker = ("\n\n[Result truncated to fit the model's context budget. "
                  "Call again with a more specific query for the rest.]")
    return cut + marker, True


def trim_messages_to_budget(messages, max_tokens):
    """Hermes-style progressive trim of a message list. Drops oldest
    non-system turns first, then truncates the oldest remaining
    user/assistant message in place. Always preserves the last
    message (the user's current request) intact.

    Mirrors Odysseus's trim_for_context — useful for keeping the
    QML side under control when an agent tool returns a huge payload
    that would otherwise push the next chat request past the model's
    window.
    """
    if not messages:
        return messages
    total = sum(estimate_tokens(m.get("content") or "") for m in messages)
    if total <= max_tokens:
        return messages
    # Protect the last message + any system-role messages.
    out = list(messages)
    protected_idx = set()
    for i, m in enumerate(out):
        if (m.get("role") == "system"
                or i == len(out) - 1):
            protected_idx.add(i)
    # Drop oldest non-protected turn until we're under budget.
    while total > max_tokens and len(out) > 1:
        drop_idx = None
        for i, m in enumerate(out):
            if i not in protected_idx:
                drop_idx = i
                break
        if drop_idx is None:
            break
        out.pop(drop_idx)
        # Recompute protected indices after pop
        protected_idx = set()
        for i, m in enumerate(out):
            if m.get("role") == "system" or i == len(out) - 1:
                protected_idx.add(i)
        total = sum(estimate_tokens(m.get("content") or "") for m in out)
    return out
