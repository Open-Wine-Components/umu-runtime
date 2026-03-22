#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print('usage: render-assemble-dockerfile.py <manifest.json> <output>', file=sys.stderr)
        return 2

    manifest = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    output = Path(sys.argv[2])

    install_specs: list[str] = []
    seen: set[str] = set()
    for row in manifest:
        pkg = row['package']
        ver = row['version']
        arch = row['arch']
        spec = f"{pkg}:{arch}={ver}" if arch not in {'all'} else f"{pkg}={ver}"
        if spec not in seen:
            install_specs.append(spec)
            seen.add(spec)

    steamrt_keyring_dest = '/usr/share/keyrings/steamrt-archive-keyring.gpg'
    steamrt_keyring_src = os.environ.get('STEAMRT_KEYRING_SRC', 'keys/steamrt-archive-keyring.gpg')

    lines = [
        'FROM debian:bullseye-slim',
        'ENV DEBIAN_FRONTEND=noninteractive',
        'RUN dpkg --add-architecture i386 || true',
        f'COPY {steamrt_keyring_src} {steamrt_keyring_dest}',
        'RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*',
    ]

    sources_lines = [
        f'deb {os.environ["DEBIAN_MIRROR"]} {os.environ["DEBIAN_RELEASE"]} main contrib non-free',
        f'deb {os.environ["DEBIAN_SECURITY_MIRROR"]} {os.environ["DEBIAN_RELEASE"]}-security main contrib non-free',
        f'deb [signed-by={steamrt_keyring_dest}] {os.environ["SNIPER_APT_URL"]} {os.environ["SNIPER_APT_DIST"]} {os.environ["SNIPER_APT_COMPONENTS"]}',
    ]
    printf_args = ' '.join(f'"{line}"' for line in sources_lines)
    lines.append(f'RUN printf "%s\\n" {printf_args} > /etc/apt/sources.list')

    local_repo = os.environ.get('LOCAL_REPO_URL', '')
    if local_repo:
        lines.append(
            f'RUN printf "%s\\n" "deb [trusted=yes] {local_repo} {os.environ["SNIPER_APT_DIST"]} main" > /etc/apt/sources.list.d/umu-local.list'
        )

    lines.append('RUN apt-get update')
    if install_specs:
        joined = ' \\\n    '.join(install_specs)
        install_cmd = (
            'RUN apt-get install -y --no-install-recommends \\\n    '
            + joined
            + ' \\\n && apt-get clean && rm -rf /var/lib/apt/lists/*'
        )
        lines.append(install_cmd)

    output.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
