#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

require_cmd dpkg-source
require_cmd dpkg-parsechangelog
require_cmd patch

if [[ ! -f "${BUILD_DIR}/build.env" ]]; then
    "$(dirname -- "$0")/fetch-metadata.sh"
fi
# shellcheck disable=SC1090
source "${BUILD_DIR}/build.env"

if [[ ! -f "${BUILD_DIR}/source-files.list" ]]; then
    "$(dirname -- "$0")/fetch-sources.sh"
fi

rm -rf "${SOURCE_TREE_DIR}"
mkdir -p "${SOURCE_TREE_DIR}"

find "${SOURCE_CACHE_DIR}" -maxdepth 1 -name '*.dsc' -print | while IFS= read -r dsc; do
    name="$(basename "$dsc" .dsc)"
    out="${SOURCE_TREE_DIR}/${name}"
    log "Unpacking ${name}"
    dpkg-source -x "$dsc" "$out" >/dev/null
    srcpkg="$(dpkg-parsechangelog -l"$out/debian/changelog" -S Source 2>/dev/null || true)"
    if [[ -n "$srcpkg" && -d "${PATCHES_DIR}/${srcpkg}" ]]; then
        log "Applying patches for ${srcpkg}"
        find "${PATCHES_DIR}/${srcpkg}" -maxdepth 1 -type f -name '*.patch' | sort | while IFS= read -r patch_file; do
            patch -d "$out" -p1 < "$patch_file"
        done
    fi
done
