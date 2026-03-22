# UMU Sniper Source Builder

This repository builds a UMU-owned Steam Runtime 3 (`sniper`) derivative **without downloading Valve's prebuilt runtime image or runtime tarball**.

Instead, it follows the same broad public pipeline Valve documents for Steam Runtime 3:

1. fetch SteamRT metadata and source package references,
2. optionally fetch and patch source packages,
3. optionally rebuild selected packages,
4. assemble a base runtime from the SteamRT apt repositories plus any locally rebuilt packages,
5. export that filesystem into a `FROM scratch` OCI image,
6. optionally run a second Dockerfile-based overlay stage that matches the old `umu-sdk` customization model,
7. attach artifacts to a tagged GitHub release.

Valve says the official container runtimes and SDKs are built with `flatdeb-steam`, not with the scripts in `steam-runtime`, and that all software making up the Steam Runtime is available in source and binary form in `repo.steampowered.com/steamrt`. The public `sniper` snapshot also publishes `manifest.dpkg`, `source-required.txt`, `Sources.gz`, build IDs, and the sysroot Dockerfile. This project uses those public inputs and never downloads `SteamLinuxRuntime_sniper.tar.xz` or `Platform-...-runtime.tar.gz`.

## What this gives you

- A source-visible pipeline.
- A patch point before package rebuilds.
- A package-assembled base image rather than a downloaded runtime image.
- Your previous `umu-sdk` style of customization preserved as an optional final overlay stage.

## Important scope note

This is the **closest public equivalent** to Valve's pipeline that can be run in GitHub Actions with public artifacts. It is not a byte-for-byte clone of Valve's internal build farm, and it does not call Valve's private or undocumented infrastructure. The assembly step here uses the published SteamRT apt repository and the published package manifest to reconstruct the runtime package set.

## Repository layout

- `config/sniper.env` — snapshot pinning and repo settings.
- `scripts/fetch-metadata.sh` — downloads build metadata, manifests, source lists, and `Sources.gz`.
- `scripts/fetch-sources.sh` — mirrors the source packages listed in `source-required.txt`.
- `scripts/unpack-sources.sh` — expands `.dsc` source packages for inspection and patching.
- `patches/<source-package>/*.patch` — optional patches, applied in lexical order.
- `scripts/rebuild-patched-packages.sh` — rebuilds only the source packages you patched, into a local apt repo.
- `scripts/assemble-base.sh` — assembles the base runtime image from packages, exports it, and emits a `FROM scratch` OCI image.
- `docker/overlay.Dockerfile` — optional old-style “take base image and layer our changes on top” stage.
- `overlays/rootfs/` — optional file overlay copied into the exported rootfs before the final image is built.
- `scripts/hooks/post-extract.sh` — optional shell customization hook after rootfs export.

## How the old `umu-sdk` model fits in

Your old flow was:

1. pull a prebuilt image,
2. apply changes,
3. publish a new image.

This repo keeps the same *shape* for the last step, but changes the upstream stage:

1. build the UMU base image from SteamRT package metadata and sources,
2. tag that as the local base image,
3. run `docker/overlay.Dockerfile` on top of it,
4. export artifacts.

So the “apply changes on top of an image” part survives, but the image you are extending is one you built locally from public SteamRT inputs.

## Releasing

Push a tag such as:

```bash
git tag -a v0.1.0 -m "v0.1.0"
git push origin v0.1.0
```

The workflow will create release artifacts including:

- source metadata bundle,
- mirrored source package bundle,
- assembled base rootfs tarball,
- OCI archive for the base runtime image,
- OCI archive for the final overlaid runtime image,
- `SHA256SUMS`.

## Using patches

Drop patch files in:

```text
patches/bash/*.patch
patches/libdecor-0/*.patch
patches/steam-runtime-tools/*.patch
```

Only patched source packages are rebuilt locally. Everything else is installed from the pinned SteamRT apt repository, which keeps the pipeline practical for CI while still letting you inspect and modify sources where needed.
