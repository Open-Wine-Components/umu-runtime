#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

require_cmd curl
require_cmd sha256sum

snapshot_override="${1:-}"
snapshot="${snapshot_override:-${SNIPER_SNAPSHOT}}"
variant="${SNIPER_VARIANT}"
arch="${SNIPER_ARCH}"
suite="${SNIPER_SUITE}"
base_url="${SNIPER_BASE_URL}/${snapshot}"
artifact_prefix="com.valvesoftware.SteamRuntime.${variant}-${arch}-${suite}"

buildid_file="${artifact_prefix}-buildid.txt"
os_release_file="${artifact_prefix}.os-release.txt"
manifest_file="${artifact_prefix}.manifest.dpkg"
built_using_file="${artifact_prefix}.manifest.dpkg.built-using"
source_required_file="${artifact_prefix}.source-required.txt"
sysroot_dockerfile="${artifact_prefix}-sysroot.Dockerfile"
sources_index="sources/Sources.gz"

files=(
    "${buildid_file}"
    "${os_release_file}"
    "${manifest_file}"
    "${built_using_file}"
    "${source_required_file}"
    "${sysroot_dockerfile}"
    "${sources_index}"
    "VERSION.txt"
    "UUID.txt"
    "SHA256SUMS"
)

log "Fetching metadata for ${variant} ${suite} (${arch}) from ${base_url}"
mkdir -p "${UPSTREAM_DIR}/sources"

for file in "${files[@]}"; do
    url="${base_url}/${file}"
    dest="${UPSTREAM_DIR}/${file}"
    mkdir -p "$(dirname -- "$dest")"
    log "Downloading ${file}"
    curl --fail --location --retry 5 --retry-delay 2 --output "$dest" "$url"
done

log "Verifying downloaded files against upstream SHA256SUMS where possible"
pushd "${UPSTREAM_DIR}" >/dev/null
: > verify.list
for file in "${files[@]}"; do
    grep -F "  ${file}" SHA256SUMS >> verify.list || true
    grep -F " *${file}" SHA256SUMS >> verify.list || true
done
awk '!seen[$0]++' verify.list > verify.list.tmp
mv verify.list.tmp verify.list
if [[ -s verify.list ]]; then
    sha256sum -c verify.list
fi
popd >/dev/null

upstream_build_id="$(tr -d '\n' < "${UPSTREAM_DIR}/${buildid_file}")"
resolved_version="$(tr -d '\n' < "${UPSTREAM_DIR}/VERSION.txt")"
resolved_uuid="$(tr -d '\n' < "${UPSTREAM_DIR}/UUID.txt")"

cat > "${BUILD_DIR}/build.env" <<ENV
ROOT_DIR=${ROOT_DIR}
BUILD_DIR=${BUILD_DIR}
DIST_DIR=${DIST_DIR}
UPSTREAM_DIR=${UPSTREAM_DIR}
SOURCE_CACHE_DIR=${SOURCE_CACHE_DIR}
SOURCE_TREE_DIR=${SOURCE_TREE_DIR}
PATCHED_REPO_DIR=${PATCHED_REPO_DIR}
OVERLAY_DIR=${OVERLAY_DIR}
PATCHES_DIR=${PATCHES_DIR}
HOOKS_DIR=${HOOKS_DIR}
DOCKER_DIR=${DOCKER_DIR}
SNIPER_SNAPSHOT=${snapshot}
SNIPER_SUITE=${suite}
SNIPER_VARIANT=${variant}
SNIPER_ARCH=${arch}
SNIPER_BASE_URL=${SNIPER_BASE_URL}
SNIPER_APT_URL=${SNIPER_APT_URL}
SNIPER_APT_DIST=${SNIPER_APT_DIST}
SNIPER_APT_COMPONENTS=${SNIPER_APT_COMPONENTS}
DEBIAN_MIRROR=${DEBIAN_MIRROR}
DEBIAN_SECURITY_MIRROR=${DEBIAN_SECURITY_MIRROR}
DEBIAN_RELEASE=${DEBIAN_RELEASE}
SNIPER_ARTIFACT_PREFIX=${artifact_prefix}
UPSTREAM_BASE_URL=${base_url}
UPSTREAM_BUILDID_FILE=${buildid_file}
UPSTREAM_OS_RELEASE_FILE=${os_release_file}
UPSTREAM_MANIFEST_FILE=${manifest_file}
UPSTREAM_BUILT_USING_FILE=${built_using_file}
UPSTREAM_SOURCE_REQUIRED_FILE=${source_required_file}
UPSTREAM_SYSROOT_DOCKERFILE=${sysroot_dockerfile}
UPSTREAM_SOURCES_INDEX=${sources_index}
UPSTREAM_BUILD_ID=${upstream_build_id}
UPSTREAM_VERSION=${resolved_version}
UPSTREAM_UUID=${resolved_uuid}
UMU_RUNTIME_PREFIX=${UMU_RUNTIME_PREFIX}
UMU_IMAGE_NAME=${UMU_IMAGE_NAME}
DEFAULT_CMD=${DEFAULT_CMD}
ENABLE_LEGACY_OVERLAY=${ENABLE_LEGACY_OVERLAY}
CONTAINER_PLATFORM=$(runtime_platform "${arch}")
ARCH_TAG=$(sanitize_arch "${arch}")
ENV

log "Resolved upstream build ID: ${upstream_build_id}"
