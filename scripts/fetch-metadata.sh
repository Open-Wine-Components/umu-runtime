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
container_platform="$(runtime_platform "${arch}")"
arch_tag="$(sanitize_arch "${arch}")"

write_env() {
    local key="$1"
    local value="$2"
    printf '%s=%q\n' "$key" "$value"
}

{
    write_env ROOT_DIR "${ROOT_DIR}"
    write_env BUILD_DIR "${BUILD_DIR}"
    write_env DIST_DIR "${DIST_DIR}"
    write_env UPSTREAM_DIR "${UPSTREAM_DIR}"
    write_env SOURCE_CACHE_DIR "${SOURCE_CACHE_DIR}"
    write_env SOURCE_TREE_DIR "${SOURCE_TREE_DIR}"
    write_env PATCHED_REPO_DIR "${PATCHED_REPO_DIR}"
    write_env OVERLAY_DIR "${OVERLAY_DIR}"
    write_env PATCHES_DIR "${PATCHES_DIR}"
    write_env HOOKS_DIR "${HOOKS_DIR}"
    write_env DOCKER_DIR "${DOCKER_DIR}"
    write_env SNIPER_SNAPSHOT "${snapshot}"
    write_env SNIPER_SUITE "${suite}"
    write_env SNIPER_VARIANT "${variant}"
    write_env SNIPER_ARCH "${arch}"
    write_env SNIPER_BASE_URL "${SNIPER_BASE_URL}"
    write_env SNIPER_APT_URL "${SNIPER_APT_URL}"
    write_env SNIPER_APT_DIST "${SNIPER_APT_DIST}"
    write_env SNIPER_APT_COMPONENTS "${SNIPER_APT_COMPONENTS}"
    write_env DEBIAN_MIRROR "${DEBIAN_MIRROR}"
    write_env DEBIAN_SECURITY_MIRROR "${DEBIAN_SECURITY_MIRROR}"
    write_env DEBIAN_RELEASE "${DEBIAN_RELEASE}"
    write_env SNIPER_ARTIFACT_PREFIX "${artifact_prefix}"
    write_env UPSTREAM_BASE_URL "${base_url}"
    write_env UPSTREAM_BUILDID_FILE "${buildid_file}"
    write_env UPSTREAM_OS_RELEASE_FILE "${os_release_file}"
    write_env UPSTREAM_MANIFEST_FILE "${manifest_file}"
    write_env UPSTREAM_BUILT_USING_FILE "${built_using_file}"
    write_env UPSTREAM_SOURCE_REQUIRED_FILE "${source_required_file}"
    write_env UPSTREAM_SYSROOT_DOCKERFILE "${sysroot_dockerfile}"
    write_env UPSTREAM_SOURCES_INDEX "${sources_index}"
    write_env UPSTREAM_BUILD_ID "${upstream_build_id}"
    write_env UPSTREAM_VERSION "${resolved_version}"
    write_env UPSTREAM_UUID "${resolved_uuid}"
    write_env UMU_RUNTIME_PREFIX "${UMU_RUNTIME_PREFIX}"
    write_env UMU_IMAGE_NAME "${UMU_IMAGE_NAME}"
    write_env DEFAULT_CMD "${DEFAULT_CMD}"
    write_env ENABLE_LEGACY_OVERLAY "${ENABLE_LEGACY_OVERLAY}"
    write_env CONTAINER_PLATFORM "${container_platform}"
    write_env ARCH_TAG "${arch_tag}"
} > "${BUILD_DIR}/build.env"

log "Resolved upstream build ID: ${upstream_build_id}"
