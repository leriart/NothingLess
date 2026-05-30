#!/bin/bash
# Apply NothingLess compositor config to Hyprland
# Called from the shell when user saves compositor settings
#
# Delegates ALL logic to sync-hyprland.py, including live axctl apply.
# Zero duplicate mapping — the Python script handles everything.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Generate config files AND apply live via axctl in one shot
python3 "$SCRIPT_DIR/sync-hyprland.py" --apply
