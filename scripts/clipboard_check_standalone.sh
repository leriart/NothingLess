#!/usr/bin/env bash
# Standalone clipboard check — invoked by wl-paste --watch
# Usage: clipboard_check_standalone.sh <check_script> <db_path> <insert_script> <data_dir>

CHECK_SCRIPT="$1"
DB_PATH="$2"
INSERT_SCRIPT="$3"
DATA_DIR="$4"

# Drain stdin (clipboard content from wl-paste) to avoid blocking
cat >/dev/null

if "$CHECK_SCRIPT" "$DB_PATH" "$INSERT_SCRIPT" "$DATA_DIR"; then
    echo "REFRESH_LIST"
else
    echo "Check failed with code $?" >&2
fi
