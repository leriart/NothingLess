#!/usr/bin/env bash
# NothingLess Monitor — unified loginlock + sleep monitor
# 
# Combines loginlock.sh and sleep_monitor.sh into a single daemon
# with internal job control for reduced process count.
# Outputs SUSPEND/WAKE on stdout for SuspendManager integration.

LOCKFILE="/tmp/nothingless_monitor.lock"
# Atomic lock via mkdir
if ! mkdir "$LOCKFILE" 2>/dev/null; then
	exit 0
fi
trap 'rm -rf "$LOCKFILE"' EXIT

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/nothingless/config/system.json"

# Safely execute a command string by validating the binary exists.
# We do NOT use eval; instead we verify the first token is a real
# command and run it via bash -c.
safe_exec() {
	local cmd="$1"
	if [ -z "$cmd" ]; then
		return 1
	fi
	# Extract first token (the binary)
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

get_before_sleep_cmd() {
	if [ -f "$CONFIG_FILE" ]; then
		jq -r '.idle.general.before_sleep_cmd // "loginctl lock-session"' "$CONFIG_FILE"
	else
		echo "loginctl lock-session"
	fi
}

get_after_sleep_cmd() {
	if [ -f "$CONFIG_FILE" ]; then
		jq -r '.idle.general.after_sleep_cmd // "nothingless screen on"' "$CONFIG_FILE"
	else
		echo "nothingless screen on"
	fi
}

# Job 1: Sleep monitor — trigger on suspend/resume
# Outputs SUSPEND/WAKE for QML SuspendManager integration
monitor_sleep() {
	while true; do
		dbus-monitor --system --profile "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" 2>/dev/null | while read -r line; do
			if echo "$line" | grep -q "boolean true"; then
				echo "SUSPEND"
				safe_exec "$(get_before_sleep_cmd)"
			elif echo "$line" | grep -q "boolean false"; then
				echo "WAKE"
				safe_exec "$(get_after_sleep_cmd)"
			fi
		done
		sleep 1  # Restart dbus-monitor on disconnect
	done
}

# Job 2: Lock screen monitor — trigger on screen lock
monitor_lockscreen() {
	while true; do
		dbus-monitor --session "type='signal',interface='org.freedesktop.ScreenSaver',member='ActiveChanged'" 2>/dev/null | while read -r line; do
			if echo "$line" | grep -q "boolean true"; then
				safe_exec "$(get_lock_cmd)"
			fi
		done
		sleep 1
	done
}

# Job 3: System lock monitor — catch loginctl lock-session (login1.Session.Lock)
monitor_system_lock() {
	while true; do
		dbus-monitor --system "type='signal',interface='org.freedesktop.login1.Session',member='Lock'" 2>/dev/null | while read -r line; do
			if echo "$line" | grep -q "member=Lock"; then
				safe_exec "$(get_lock_cmd)"
			fi
		done
		sleep 1
	done
}

# Start all jobs in background
monitor_sleep &
monitor_lockscreen &
monitor_system_lock &

# Wait for both (they run forever, so this never exits)
wait
