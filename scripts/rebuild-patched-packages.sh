#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "$0")" && pwd)/common.sh"

require_cmd docker
require_cmd dpkg-parsechangelog
require_cmd dpkg-scanpackages

if [[ ! -f "${BUILD_DIR}/build.env" ]]; then
    "$(dirname -- "$0")/fetch-metadata.sh"
fi
# shellcheck disable=SC1090
source "${BUILD_DIR}/build.env"

if ! is_dir_nonempty "${PATCHES_DIR}"; then
    log "No source patches present; skipping package rebuild stage"
    exit 0
fi

"$(dirname -- "$0")/unpack-sources.sh"

mkdir -p "${PATCHED_REPO_DIR}/pool/main" "${PATCHED_REPO_DIR}/dists/${SNIPER_APT_DIST}/main/binary-amd64"
work_dir="${BUILD_DIR}/rebuild-work"
rm -rf "$work_dir"
mkdir -p "$work_dir"

for tree in "${SOURCE_TREE_DIR}"/*; do
    [[ -d "$tree" ]] || continue
    srcpkg="$(dpkg-parsechangelog -l"$tree/debian/changelog" -S Source 2>/dev/null || true)"
    [[ -n "$srcpkg" ]] || continue
    [[ -d "${PATCHES_DIR}/${srcpkg}" ]] || continue

    pkg_out="${work_dir}/${srcpkg}"
    rm -rf "$pkg_out"
    mkdir -p "$pkg_out/src" "$pkg_out/out"
    cp -a "$tree/." "$pkg_out/src/"

    log "Rebuilding patched source package ${srcpkg}"
    docker run --rm \
        -v "$pkg_out/src:/src" \
        -v "$pkg_out/out:/out" \
        debian:bullseye \
        bash -lc "set -euo pipefail
            export DEBIAN_FRONTEND=noninteractive
            cat > /etc/apt/sources.list <<SRC
            deb ${DEBIAN_MIRROR} ${DEBIAN_RELEASE} main contrib non-free
            deb-src ${DEBIAN_MIRROR} ${DEBIAN_RELEASE} main contrib non-free
            deb ${DEBIAN_SECURITY_MIRROR} ${DEBIAN_RELEASE}-security main contrib non-free
            deb-src ${DEBIAN_SECURITY_MIRROR} ${DEBIAN_RELEASE}-security main contrib non-free
            deb ${SNIPER_APT_URL} ${SNIPER_APT_DIST} ${SNIPER_APT_COMPONENTS}
            deb-src ${SNIPER_APT_URL} ${SNIPER_APT_DIST} ${SNIPER_APT_COMPONENTS}
SRC
            apt-get update
            apt-get install -y build-essential devscripts dpkg-dev equivs ca-certificates fakeroot
            apt-get build-dep -y /src
            cd /src
            dpkg-buildpackage -us -uc -b
            cp -a /src/../*.deb /out/ 2>/dev/null || true
            cp -a /src/../*.udeb /out/ 2>/dev/null || true"

    find "$pkg_out/out" -maxdepth 1 \( -name '*.deb' -o -name '*.udeb' \) -exec cp -a {} "${PATCHED_REPO_DIR}/pool/main/" \;
done

if compgen -G "${PATCHED_REPO_DIR}/pool/main/*.deb" > /dev/null; then
    pushd "${PATCHED_REPO_DIR}" >/dev/null
    dpkg-scanpackages --multiversion pool/main > "dists/${SNIPER_APT_DIST}/main/binary-amd64/Packages"
    gzip -9c "dists/${SNIPER_APT_DIST}/main/binary-amd64/Packages" > "dists/${SNIPER_APT_DIST}/main/binary-amd64/Packages.gz"
    popd >/dev/null
else
    log "No rebuilt packages were produced"
fi
