#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

require_cmd curl
require_cmd python3

if [[ ! -f "${BUILD_DIR}/build.env" ]]; then
    "$(dirname -- "$0")/fetch-metadata.sh"
fi
# shellcheck disable=SC1090
source "${BUILD_DIR}/build.env"

python3 "$(dirname -- "$0")/parse_sources.py" \
    "${UPSTREAM_DIR}/${UPSTREAM_SOURCES_INDEX}" \
    "${UPSTREAM_DIR}/${UPSTREAM_SOURCE_REQUIRED_FILE}" \
    "${BUILD_DIR}/source-files.list"

while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    url="${UPSTREAM_BASE_URL}/sources/${file}"
    dest="${SOURCE_CACHE_DIR}/${file}"
    log "Mirroring source file ${file}"
    curl --fail --location --retry 5 --retry-delay 2 --output "$dest" "$url"
done < "${BUILD_DIR}/source-files.list"
