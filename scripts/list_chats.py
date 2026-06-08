#!/usr/bin/env python3
"""
List chat history for NothingLess AI sidebar.
Reads all JSON chat files from the chat directory and outputs
one line per chat: <id>|<title>

Usage: list_chats.py <chat_dir>
"""

import json
import os
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: list_chats.py <chat_dir>", file=sys.stderr)
        sys.exit(1)

    chat_dir = Path(sys.argv[1])
    chat_dir.mkdir(parents=True, exist_ok=True)

    files = sorted(chat_dir.glob("*.json"), key=lambda f: f.stat().st_mtime, reverse=True)

    for f in files:
        chat_id = f.stem  # filename without .json
        title = "New Chat"
        try:
            with open(f) as fp:
                data = json.load(fp)
                for msg in data:
                    if msg.get("role") == "user":
                        content = msg.get("content", "")
                        title = content[:40].replace("\n", " ").strip()
                        if len(content) > 40:
                            title += "..."
                        break
        except (json.JSONDecodeError, OSError):
            pass

        print(f"{chat_id}|{title}")


if __name__ == "__main__":
    main()
