#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

require_cmd docker
require_cmd python3
require_cmd tar
require_cmd gzip

if [[ ! -f "${BUILD_DIR}/build.env" ]]; then
    "$(dirname -- "$0")/fetch-metadata.sh"
fi
# shellcheck disable=SC1090
source "${BUILD_DIR}/build.env"

python3 "$(dirname -- "$0")/parse_manifest.py" \
    "${UPSTREAM_DIR}/${UPSTREAM_MANIFEST_FILE}" \
    "${BUILD_DIR}/manifest.json"

if is_dir_nonempty "${PATCHES_DIR}"; then
    "$(dirname -- "$0")/rebuild-patched-packages.sh"
fi

artifact_prefix="${UMU_RUNTIME_PREFIX}-${UPSTREAM_BUILD_ID}-${ARCH_TAG}"
base_tag="local/umu-sniper-base:${UPSTREAM_BUILD_ID}-${ARCH_TAG}"
rootfs_dir="${BUILD_DIR}/rootfs"
docker_context="${BUILD_DIR}/docker-context"
metadata_dir="${BUILD_DIR}/metadata"
rm -rf "$rootfs_dir" "$docker_context" "$metadata_dir"
mkdir -p "$rootfs_dir" "$docker_context" "$metadata_dir"

local_repo_url=""
if compgen -G "${PATCHED_REPO_DIR}/pool/main/*.deb" > /dev/null; then
    local_repo_url="file:///workspace/local-repo"
fi

DEBIAN_MIRROR="$DEBIAN_MIRROR" \
DEBIAN_SECURITY_MIRROR="$DEBIAN_SECURITY_MIRROR" \
DEBIAN_RELEASE="$DEBIAN_RELEASE" \
SNIPER_APT_URL="$SNIPER_APT_URL" \
SNIPER_APT_DIST="$SNIPER_APT_DIST" \
SNIPER_APT_COMPONENTS="$SNIPER_APT_COMPONENTS" \
LOCAL_REPO_URL="$local_repo_url" \
python3 "$(dirname -- "$0")/render-assemble-dockerfile.py" \
    "${BUILD_DIR}/manifest.json" \
    "${docker_context}/Dockerfile"

cp -a "${PATCHED_REPO_DIR}" "${docker_context}/local-repo" 2>/dev/null || true

log "Building base package-assembled image"
docker buildx create --name umu-source-builder --driver docker-container --use >/dev/null 2>&1 || docker buildx use umu-source-builder >/dev/null 2>&1

docker buildx build \
    --platform "${CONTAINER_PLATFORM}" \
    --load \
    --tag "$base_tag" \
    "$docker_context"

cid="$(docker create "$base_tag")"
docker export "$cid" | tar -xf - -C "$rootfs_dir"
docker rm "$cid" >/dev/null

if is_dir_nonempty "${OVERLAY_DIR}"; then
    log "Applying rootfs overlay"
    cp -a "${OVERLAY_DIR}/." "$rootfs_dir/"
fi

if [[ -x "${HOOKS_DIR}/post-extract.sh" ]]; then
    log "Running post-extract hook"
    "${HOOKS_DIR}/post-extract.sh" "$rootfs_dir"
fi

base_rootfs_tar="${DIST_DIR}/${artifact_prefix}-base-runtime.tar.gz"
base_oci_tar="${DIST_DIR}/${artifact_prefix}-base-image.oci.tar"
final_oci_tar="${DIST_DIR}/${artifact_prefix}-final-image.oci.tar"
metadata_tar="${DIST_DIR}/${artifact_prefix}-metadata.tar.gz"
source_bundle_tar="${DIST_DIR}/${artifact_prefix}-sources.tar.gz"

log "Packing exported base rootfs"
tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner -C "$rootfs_dir" -cf - . | gzip -n > "$base_rootfs_tar"

cp "$base_rootfs_tar" "${docker_context}/rootfs.tar.gz"
DEFAULT_CMD="$DEFAULT_CMD" \
REPOSITORY_URL="${REPOSITORY_URL:-}" \
RELEASE_VERSION="${RELEASE_VERSION:-dev}" \
GIT_SHA="${GIT_SHA:-unknown}" \
SNIPER_SNAPSHOT="$SNIPER_SNAPSHOT" \
UPSTREAM_BUILD_ID="$UPSTREAM_BUILD_ID" \
python3 "$(dirname -- "$0")/render-scratch-dockerfile.py" \
    "${UPSTREAM_DIR}/${UPSTREAM_OS_RELEASE_FILE}" \
    rootfs.tar.gz \
    "${docker_context}/Dockerfile.scratch"

docker buildx build \
    --platform "${CONTAINER_PLATFORM}" \
    --file "${docker_context}/Dockerfile.scratch" \
    --output "type=oci,dest=${base_oci_tar}" \
    "${docker_context}"

if [[ "${ENABLE_LEGACY_OVERLAY}" == "1" && -f "${DOCKER_DIR}/overlay.Dockerfile" ]]; then
    log "Running legacy overlay stage"
    docker buildx build \
        --platform "${CONTAINER_PLATFORM}" \
        --build-arg BASE_IMAGE="$base_tag" \
        --file "${DOCKER_DIR}/overlay.Dockerfile" \
        --output "type=oci,dest=${final_oci_tar}" \
        "$ROOT_DIR"
else
    cp "$base_oci_tar" "$final_oci_tar"
fi

for f in \
    "${UPSTREAM_DIR}/${UPSTREAM_BUILDID_FILE}" \
    "${UPSTREAM_DIR}/${UPSTREAM_OS_RELEASE_FILE}" \
    "${UPSTREAM_DIR}/${UPSTREAM_MANIFEST_FILE}" \
    "${UPSTREAM_DIR}/${UPSTREAM_BUILT_USING_FILE}" \
    "${UPSTREAM_DIR}/${UPSTREAM_SOURCE_REQUIRED_FILE}" \
    "${UPSTREAM_DIR}/${UPSTREAM_SYSROOT_DOCKERFILE}" \
    "${UPSTREAM_DIR}/VERSION.txt" \
    "${UPSTREAM_DIR}/UUID.txt" \
    "${BUILD_DIR}/manifest.json" \
    "${BUILD_DIR}/source-files.list"; do
    cp "$f" "$metadata_dir/"
done

tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner -C "$metadata_dir" -cf - . | gzip -n > "$metadata_tar"
tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner -C "$SOURCE_CACHE_DIR" -cf - . | gzip -n > "$source_bundle_tar"

(
    cd "$DIST_DIR"
    sha256sum ./* > SHA256SUMS
)

docker buildx rm umu-source-builder >/dev/null 2>&1 || true
