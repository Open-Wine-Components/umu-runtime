#!/bin/bash
mkdir -p keys

export GNUPGHOME="$(mktemp -d)"
chmod 700 "$GNUPGHOME"
: > "$GNUPGHOME/common.conf"

git clone https://gitlab.steamos.cloud/steamrt/flatdeb-steam

gpg --homedir "$GNUPGHOME" --import \
  flatdeb-steam/suites/8abddd96-valve-archive-steamos-release-key.gpg \
  flatdeb-steam/suites/c948c57e-steam-runtime-2025.gpg

gpg --homedir "$GNUPGHOME" \
  --output keys/steamrt-archive-keyring.gpg \
  --export

gpg --show-keys --keyid-format LONG keys/steamrt-archive-keyring.gpg

rm -Rf flatdeb-steam
