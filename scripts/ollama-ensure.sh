#!/usr/bin/env bash
# Ollama lifecycle helper for NothingLess.
#
# Checks whether the local Ollama daemon responds to /api/tags. If not,
# tries to start it via systemd (user unit first, system unit second)
# and as a last resort spawns `ollama serve` directly. Polls for up to
# MAX_WAIT seconds after starting.
#
# Exit codes:
#   0 — Ollama responds (was already running, or we started it).
#   1 — Ollama is installed but failed to come up in time.
#   2 — Ollama binary not found AND no systemd unit available.
#
# Logs to stderr with [ollama-ensure] prefix so the Quickshell process
# log surfaces diagnostics when this script is invoked by Ai.qml.
#
# Environment overrides:
#   OLLAMA_URL      — base URL to probe (default http://127.0.0.1:11434).
#   OLLAMA_MAX_WAIT — seconds to wait after starting (default 8).

set -u

OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
MAX_WAIT="${OLLAMA_MAX_WAIT:-8}"

log() { printf '[ollama-ensure] %s\n' "$*" >&2; }

ping() {
    curl -sf --connect-timeout 2 --max-time 3 "$OLLAMA_URL/api/tags" >/dev/null 2>&1
}

if ping; then
    exit 0
fi

log "Ollama not responding at $OLLAMA_URL — attempting to start"

STARTED=0
START_METHOD=""

if command -v systemctl >/dev/null 2>&1; then
    if systemctl --user start ollama 2>/dev/null; then
        STARTED=1
        START_METHOD="systemctl --user"
    elif systemctl start ollama 2>/dev/null; then
        STARTED=1
        START_METHOD="systemctl"
    fi
fi

if [ "$STARTED" -eq 0 ] && command -v ollama >/dev/null 2>&1; then
    log "no systemd unit available, spawning ollama serve directly"
    log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/nothingless"
    mkdir -p "$log_dir"
    nohup ollama serve >>"$log_dir/ollama.log" 2>&1 &
    disown
    STARTED=1
    START_METHOD="nohup ollama serve"
fi

if [ "$STARTED" -eq 0 ]; then
    if ! command -v ollama >/dev/null 2>&1; then
        log "ollama binary not on PATH"
        exit 2
    fi
    log "no working start method found"
    exit 1
fi

log "start method: $START_METHOD — waiting up to ${MAX_WAIT}s"

for i in $(seq 1 "$MAX_WAIT"); do
    sleep 1
    if ping; then
        log "Ollama ready after ${i}s"
        exit 0
    fi
done

log "Ollama failed to respond within ${MAX_WAIT}s"
exit 1