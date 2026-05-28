#!/usr/bin/env bash
# NothingLess Monitor — unified loginlock + sleep monitor
# 
# Combines loginlock.sh and sleep_monitor.sh into a single daemon
# with internal job control for reduced process count.
# Outputs SUSPEND/WAKE on stdout for SuspendManager integration.

LOCKFILE="/tmp/nothingless_monitor.lock"
if [ -e "$LOCKFILE" ]; then
	PID=$(cat "$LOCKFILE")
	if kill -0 "$PID" 2>/dev/null; then
		exit 0
	fi
fi
echo $$ >"$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/nothingless/config/system.json"

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
				eval "$(get_before_sleep_cmd)" &
			elif echo "$line" | grep -q "boolean false"; then
				echo "WAKE"
				eval "$(get_after_sleep_cmd)" &
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
				eval "$(get_lock_cmd)" &
			fi
		done
		sleep 1
	done
}

# Start both jobs in background
monitor_sleep &
monitor_lockscreen &

# Wait for both (they run forever, so this never exits)
wait
