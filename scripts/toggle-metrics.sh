#!/usr/bin/env bash
# Toggle notch metrics overlay
# IPC call handled by GlobalShortcuts - this triggers the QML handler

PID=$(pidof nothingless || true)
if [ -z "$PID" ]; then
    echo "Error: NothingLess is not running" >&2
    exit 1
fi

qs ipc --pid "$PID" call nothingless run toggle-metrics 2>/dev/null || true
