#!/usr/bin/env python3
from __future__ import annotations

import argparse
import gzip
from pathlib import Path


def parse_packages(path: Path) -> dict[tuple[str, str], list[str]]:
    entries: dict[tuple[str, str], list[str]] = {}
    with gzip.open(path, 'rt', encoding='utf-8', errors='replace') as fh:
        blocks = fh.read().split('\n\n')
    for block in blocks:
        fields: dict[str, str] = {}
        current_key: str | None = None
        for raw in block.splitlines():
            if not raw.strip():
                continue
            if raw[0].isspace() and current_key is not None:
                prev = fields.get(current_key, '')
                fields[current_key] = f"{prev}\n{raw.strip()}" if prev else raw.strip()
                continue
            if ':' not in raw:
                continue
            key, value = raw.split(':', 1)
            fields[key.strip()] = value.strip()
            current_key = key.strip()
        pkg = fields.get('Package', '')
        ver = fields.get('Version', '')
        files_field = fields.get('Files', '')
        if not pkg or not ver or not files_field:
            continue
        names: list[str] = []
        for line in files_field.splitlines():
            parts = line.split()
            if len(parts) >= 3:
                names.append(parts[-1])
        entries[(pkg, ver)] = names
    return entries


def parse_required(path: Path) -> list[tuple[str, str]]:
    text = path.read_text(encoding='utf-8', errors='replace')
    tokens = text.split()
    pairs: list[tuple[str, str]] = []
    i = 0
    while i < len(tokens):
        token = tokens[i]
        if token.startswith('#'):
            i += 1
            continue
        if i + 1 >= len(tokens):
            break
        pairs.append((token, tokens[i + 1]))
        i += 2
    return pairs


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('sources_gz', type=Path)
    parser.add_argument('source_required', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()

    src_map = parse_packages(args.sources_gz)
    required = parse_required(args.source_required)

    missing: list[str] = []
    lines: list[str] = []
    for pkg, ver in required:
        names = src_map.get((pkg, ver))
        if not names:
            missing.append(f'{pkg}={ver}')
            continue
        lines.extend(names)

    args.output.write_text('\n'.join(lines) + ('\n' if lines else ''), encoding='utf-8')
    if missing:
        raise SystemExit('Missing source entries: ' + ', '.join(missing[:20]))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
