#!/usr/bin/env python3
"""
MCP stdio bridge for NothingLess.

Usage:
    python3 mcp_stdio_bridge.py -- <command> [args...]

This bridge spawns an MCP server and forwards JSON-RPC 2.0 messages
between the server's stdin/stdout and our stdout/stdin. Each line of
input/output is a single JSON-RPC message. This lets QML drive MCP
servers without direct stdin access from QML's Process type.
"""
import json
import sys
import subprocess
import threading
import os


def main():
    if "--" not in sys.argv:
        print(json.dumps({"error": "Usage: mcp_stdio_bridge.py -- <command> [args...]"}), flush=True)
        sys.exit(1)

    split = sys.argv.index("--")
    command = sys.argv[split + 1]
    args = sys.argv[split + 2:]

    env = os.environ.copy()
    # Some MCP servers need NODE_NO_WARNINGS etc; keep env clean.

    proc = subprocess.Popen(
        [command] + args,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
        bufsize=1,
    )

    def forward_stdout():
        try:
            for line in proc.stdout:
                sys.stdout.write(line)
                sys.stdout.flush()
        except Exception:
            pass

    def forward_stderr():
        try:
            for line in proc.stderr:
                # Relay stderr as an error notification
                payload = {
                    "jsonrpc": "2.0",
                    "method": "notifications/message",
                    "params": {"level": "error", "data": line.rstrip("\n")},
                }
                sys.stdout.write(json.dumps(payload) + "\n")
                sys.stdout.flush()
        except Exception:
            pass

    t_out = threading.Thread(target=forward_stdout, daemon=True)
    t_err = threading.Thread(target=forward_stderr, daemon=True)
    t_out.start()
    t_err.start()

    try:
        for line in sys.stdin:
            if proc.stdin:
                proc.stdin.write(line)
                proc.stdin.flush()
    except BrokenPipeError:
        pass
    finally:
        try:
            proc.stdin.close()
        except Exception:
            pass
        proc.wait()


if __name__ == "__main__":
    main()
