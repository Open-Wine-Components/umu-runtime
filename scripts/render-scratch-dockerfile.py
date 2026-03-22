#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def parse_os_release(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for raw in path.read_text(encoding='utf-8').splitlines():
        line = raw.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        value = value.strip()
        if value.startswith('"') and value.endswith('"'):
            value = value[1:-1]
        data[key] = value
    return data


def docker_escape(value: str) -> str:
    return value.replace('\\', '\\\\').replace('"', '\\"')


def main() -> int:
    if len(sys.argv) != 4:
        print('usage: render-scratch-dockerfile.py <os-release> <rootfs-tar-name> <output>', file=sys.stderr)
        return 2
    meta = parse_os_release(Path(sys.argv[1]))
    rootfs_tar_name = sys.argv[2]
    output = Path(sys.argv[3])
    cmd_json = json.loads(os.environ.get('DEFAULT_CMD', '["/bin/bash"]'))

    labels = {f'os_release.{k.lower()}': v for k, v in meta.items()}
    labels.update({
        'org.opencontainers.image.title': 'UMU Sniper Runtime',
        'org.opencontainers.image.source': os.environ.get('REPOSITORY_URL', ''),
        'org.opencontainers.image.version': os.environ.get('RELEASE_VERSION', ''),
        'org.opencontainers.image.revision': os.environ.get('GIT_SHA', ''),
        'io.github.open_wine_components.umu.upstream.build_id': os.environ.get('UPSTREAM_BUILD_ID', ''),
        'io.github.open_wine_components.umu.upstream.snapshot': os.environ.get('SNIPER_SNAPSHOT', ''),
    })
    lines = ['FROM scratch', f'ADD {rootfs_tar_name} /']
    for k, v in sorted(labels.items()):
        if v:
            lines.append(f'LABEL {k}="{docker_escape(v)}"')
    lines.append('CMD ' + json.dumps(cmd_json, separators=(',', ':')))
    output.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
