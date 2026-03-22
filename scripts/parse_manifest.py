#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path


def parse_manifest(path: Path) -> list[dict[str, str]]:
    text = path.read_text(encoding='utf-8', errors='replace')
    lines = [line.strip() for line in text.splitlines() if line.strip() and not line.startswith('#')]
    entries: list[dict[str, str]] = []
    if lines:
        for line in lines:
            parts = line.split()
            if len(parts) >= 3:
                pkg, ver, arch = parts[0], parts[1], parts[2]
                entries.append({'package': pkg, 'version': ver, 'arch': arch})
        if entries:
            return entries
    tokens = [t for t in text.split() if not t.startswith('#')]
    for i in range(0, len(tokens) - 2, 3):
        pkg, ver, arch = tokens[i : i + 3]
        entries.append({'package': pkg, 'version': ver, 'arch': arch})
    return entries


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('manifest', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    entries = parse_manifest(args.manifest)
    if not entries:
        raise SystemExit('Could not parse manifest.dpkg')
    args.output.write_text(json.dumps(entries, indent=2) + '\n', encoding='utf-8')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
