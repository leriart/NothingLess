#!/usr/bin/env bash

LOCKFILE="/tmp/nothingless_loginlock.lock"
# Atomic lock via mkdir
if ! mkdir "$LOCKFILE" 2>/dev/null; then
	exit 0
fi
trap 'rm -rf "$LOCKFILE"' EXIT

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/nothingless/config/system.json"

# Safely execute a command string by validating the binary exists.
safe_exec() {
	local cmd="$1"
	if [ -z "$cmd" ]; then
		return 1
	fi
	local binary
	binary=$(printf '%s' "$cmd" | awk '{print $1}')
	if [ -z "$binary" ]; then
		return 1
	fi
	if ! command -v "$binary" >/dev/null 2>&1; then
		echo "Error: command not found: $binary" >&2
		return 1
	fi
	bash -c "$cmd" &
}

get_lock_cmd() {
	if [ -f "$CONFIG_FILE" ]; then
		jq -r '.idle.general.lock_cmd // "nothingless lock"' "$CONFIG_FILE"
	else
		echo "nothingless lock"
	fi
}

dbus-monitor --system "type='signal',interface='org.freedesktop.login1.Session',member='Lock'" |
	while read -r line; do
		if echo "$line" | grep -q "member=Lock"; then
			COMMAND=$(get_lock_cmd)
			if [ -n "$COMMAND" ]; then
				safe_exec "$COMMAND"
			fi
		fi
	done
