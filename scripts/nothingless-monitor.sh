#!/usr/bin/env bash
# NothingLess Monitor — unified loginlock + sleep monitor
# 
# Combines loginlock.sh and sleep_monitor.sh into a single daemon
# with internal job control for reduced process count.

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

# Job 1: Login lock monitor — lock on suspend/sleep
monitor_loginlock() {
	while true; do
		dbus-monitor --system --profile "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" 2>/dev/null | while read -r line; do
			if echo "$line" | grep -q "boolean true"; then
				# System going to sleep
				eval "$(get_before_sleep_cmd)"
			elif echo "$line" | grep -q "boolean false"; then
				# System woke up
				eval "$(get_after_sleep_cmd)"
			fi
		done
		sleep 1  # Restart dbus-monitor on disconnect
	done
}

# Job 2: Manual lock trigger via logind
monitor_lockscreen() {
	while true; do
		# Monitor for lock/unlock via logind
		dbus-monitor --session "type='signal',interface='org.freedesktop.ScreenSaver',member='ActiveChanged'" 2>/dev/null | while read -r line; do
			if echo "$line" | grep -q "boolean true"; then
				eval "$(get_lock_cmd)"
			fi
		done
		sleep 1
	done
}

# Start both jobs in background
monitor_loginlock &
monitor_lockscreen &

# Wait for both (they run forever, so this never exits)
wait
