#!/usr/bin/env bash
# Clipboard watcher that triggers checks on clipboard changes
# Usage: clipboard_watch.sh <check_script> <db_path> <insert_script> <data_dir>
#
# Uses a standalone helper script (clipboard_check_standalone.sh) invoked
# directly by wl-paste --watch, avoiding a bash -c fork on every clipboard
# change. The helper receives the same four arguments.

CHECK_SCRIPT="$1"
DB_PATH="$2"
INSERT_SCRIPT="$3"
DATA_DIR="$4"

STANDALONE="$(dirname "$(realpath "$0")")/clipboard_check_standalone.sh"

exec wl-paste --watch "$STANDALONE" "$CHECK_SCRIPT" "$DB_PATH" "$INSERT_SCRIPT" "$DATA_DIR"
