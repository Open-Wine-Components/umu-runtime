#!/usr/bin/env bash
set -euo pipefail

rootfs="${1:?missing rootfs path}"
: "$rootfs"

# Optional customization hook after the package-assembled rootfs is exported
# and after overlays/rootfs has been copied in.
