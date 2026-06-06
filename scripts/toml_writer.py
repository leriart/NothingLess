#!/usr/bin/env python3
"""
toml_writer.py — Merge generated TOML template with [[monitors]] from existing file.

Usage:
    python3 toml_writer.py <base64_template> <output_path>

Reads the existing axctl.toml to preserve [[monitors]] sections (written by
monitors_writer.py), then writes the full output.
"""

import base64, os, re, sys


def extract_monitors(path):
    """Extract [[monitors]] blocks from existing axctl.toml."""
    if not os.path.isfile(path):
        return []
    with open(path) as f:
        content = f.read()
    # Each [[monitors]] block runs until the next top-level [section or EOF
    monitors = re.findall(
        r'(?m)^\[\[monitors\]\].*?(?=^\[|\Z)',
        content,
        re.DOTALL,
    )
    return [m.strip() for m in monitors if m.strip()]


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <base64_template> <output_path>", file=sys.stderr)
        sys.exit(1)

    b64 = sys.argv[1]
    output_path = sys.argv[2]

    # Decode the generated template (safe: base64 has no special chars)
    template = base64.b64decode(b64).decode("utf-8")

    # Preserve monitors from the existing file
    monitors = extract_monitors(output_path)

    if monitors:
        template += "\n" + "\n".join(monitors) + "\n"

    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    with open(output_path, "w") as f:
        f.write(template)

    print(f"Written TOML to {output_path} ({len(template)} bytes)", flush=True)


if __name__ == "__main__":
    main()
