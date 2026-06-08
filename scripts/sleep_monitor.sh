#!/usr/bin/env bash

LOCKFILE="/tmp/nothingless_sleep_monitor.lock"
# Atomic lock via mkdir
if ! mkdir "$LOCKFILE" 2>/dev/null; then
	exit 0
fi
trap 'rm -rf "$LOCKFILE"' EXIT

# Sleep Monitor - Executes commands before and after sleep
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

get_cmd() {
	local type=$1
	if [ -f "$CONFIG_FILE" ]; then
		if [ "$type" == "before" ]; then
			jq -r '.idle.general.before_sleep_cmd // "loginctl lock-session"' "$CONFIG_FILE"
		else
			jq -r '.idle.general.after_sleep_cmd // "nothingless screen on"' "$CONFIG_FILE"
		fi
	else
		if [ "$type" == "before" ]; then
			echo "loginctl lock-session"
		else
			echo "nothingless screen on"
		fi
	fi
}

# Monitor logind's PrepareForSleep signal
# We use grep --line-buffered to reliably capture the boolean argument
# which indicates start (true) or end (false) of sleep
dbus-monitor --system "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" |
	grep --line-buffered "boolean" |
	while read -r line; do
		if echo "$line" | grep -q "true"; then
			# Going to sleep
			echo "SUSPEND"
			CMD=$(get_cmd "before")
			if [ -n "$CMD" ]; then
				safe_exec "$CMD"
			fi
		elif echo "$line" | grep -q "false"; then
			# Waking up
			echo "WAKE"
			CMD=$(get_cmd "after")
			if [ -n "$CMD" ]; then
				safe_exec "$CMD"
			fi
		fi
	done
