#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck disable=SC1091
source "${script_dir}/common.sh"

require_cmd docker
require_cmd python3
require_cmd tar
require_cmd gzip

snapshot_override="${1:-}"
rm -rf "${BUILD_DIR}" "${DIST_DIR}"
mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

"${script_dir}/fetch-metadata.sh" "$snapshot_override"
"${script_dir}/fetch-sources.sh"
"${script_dir}/assemble-base.sh"

log "Artifacts written to ${DIST_DIR}"
ls -lh "${DIST_DIR}"
