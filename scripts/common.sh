#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
DIST_DIR="${ROOT_DIR}/dist"
UPSTREAM_DIR="${BUILD_DIR}/upstream"
SOURCE_CACHE_DIR="${BUILD_DIR}/source-cache"
SOURCE_TREE_DIR="${BUILD_DIR}/source-tree"
PATCHED_REPO_DIR="${BUILD_DIR}/local-repo"
OVERLAY_DIR="${ROOT_DIR}/overlays/rootfs"
PATCHES_DIR="${ROOT_DIR}/patches"
HOOKS_DIR="${ROOT_DIR}/scripts/hooks"
DOCKER_DIR="${ROOT_DIR}/docker"
CONFIG_FILE="${ROOT_DIR}/config/sniper.env"

if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${CONFIG_FILE}"
fi

mkdir -p "${BUILD_DIR}" "${DIST_DIR}" "${UPSTREAM_DIR}" "${SOURCE_CACHE_DIR}" "${SOURCE_TREE_DIR}" "${PATCHED_REPO_DIR}"

log() {
    printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1" >&2
        exit 1
    }
}

sanitize_arch() {
    printf '%s' "$1" | tr ',/' '--'
}

runtime_platform() {
    case "$1" in
        arm64) printf 'linux/arm64' ;;
        amd64,i386|amd64) printf 'linux/amd64' ;;
        *) printf 'linux/amd64' ;;
    esac
}

is_dir_nonempty() {
    local dir="$1"
    [[ -d "$dir" ]] || return 1
    find "$dir" -mindepth 1 -print -quit | grep -q .
}
