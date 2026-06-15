#!/usr/bin/env bash
# set-charge-limit.sh — Apply battery charge limit using the best available backend.
#
# Tries in order:
#   1. tlp       (sudo -n tlp setcharge <start> <end>)  — ThinkPads, etc.
#   2. sysfs     (direct write to /sys/class/power_supply/BAT*/charge_control_end_threshold)
#
# Usage:  set-charge-limit.sh <percent>
# Exit 0  = applied
# Exit 1  = invalid argument
# Exit 2  = no backend available or permission denied
# Exit 3  = backend failed

set -euo pipefail

LIMIT="${1:-}"
if [ -z "$LIMIT" ]; then
    echo "Usage: $0 <percent>" >&2
    exit 1
fi

# Validate range
if ! [[ "$LIMIT" =~ ^[0-9]+$ ]] || [ "$LIMIT" -lt 50 ] || [ "$LIMIT" -gt 100 ]; then
    echo "Error: limit must be an integer in [50,100]" >&2
    exit 1
fi

# ── 1. TLP ───────────────────────────────────────────────────────────────
if command -v tlp >/dev/null 2>&1; then
    # START_CHARGE_THRESH_BAT0 = LIMIT - 5 (TLP needs both start and end)
    START=$((LIMIT > 60 ? LIMIT - 5 : 60))
    if sudo -n tlp setcharge "$START" "$LIMIT" BAT0 >/dev/null 2>&1 \
       || sudo -n tlp setcharge "$START" "$LIMIT" >/dev/null 2>&1; then
        echo "tlp: set charge threshold to ${START}-${LIMIT}%"
        exit 0
    else
        echo "Warning: tlp setcharge failed (sudo required or BAT not found)" >&2
    fi
fi

# ── 2. sysfs ─────────────────────────────────────────────────────────────
# Find the first battery with a writable charge_control_end_threshold
for bat in /sys/class/power_supply/BAT*; do
    [ -d "$bat" ] || continue
    target="$bat/charge_control_end_threshold"
    if [ -f "$target" ] && [ -w "$target" ]; then
        # Read current to compare
        current=$(cat "$target" 2>/dev/null || echo "")
        if [ "$current" = "$LIMIT" ]; then
            echo "sysfs: $target already at ${LIMIT}%"
            exit 0
        fi
        if echo "$LIMIT" > "$target" 2>/dev/null; then
            echo "sysfs: set $target to ${LIMIT}%"
            exit 0
        else
            echo "Warning: failed to write $target (permission denied?)" >&2
        fi
    fi
done

echo "Error: no charge-limit backend succeeded (need tlp+sudo or sysfs-writable)" >&2
exit 2
