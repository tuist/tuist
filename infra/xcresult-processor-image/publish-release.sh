#!/usr/bin/env bash
# Packages a macOS `mix release tuist` directory and pushes it as a
# single-layer OCI artifact, the form fetch-release.sh reads at VM boot.
#
# The tarball is the layer as-is: crane keeps an already-gzipped layer's
# bytes, so the blob digest in the manifest is the sha256 of this file and
# the VM can verify the download against it.
#
# Usage: publish-release.sh <release-dir> <reference>
#   e.g. publish-release.sh _build/prod/rel/tuist ghcr.io/tuist/tuist-xcresult-processor:release-sha-0123456789ab
#
# Requires `crane` logged in to the registry.

set -euo pipefail

release_dir="${1:?usage: publish-release.sh <release-dir> <reference>}"
reference="${2:?usage: publish-release.sh <release-dir> <reference>}"

if [ ! -x "${release_dir}/bin/tuist" ]; then
  echo "publish-release: ${release_dir} does not contain bin/tuist" >&2
  exit 1
fi

tarball="$(mktemp -t tuist-release).tar.gz"
trap 'rm -f "$tarball"' EXIT

tar -czf "$tarball" -C "$release_dir" .
ls -lh "$tarball"

crane append \
  --oci-empty-base \
  --new_layer "$tarball" \
  --new_tag "$reference"

expected="sha256:$(shasum -a 256 "$tarball" | awk '{print $1}')"
published="$(crane manifest "$reference" | /usr/bin/plutil -extract layers.0.digest raw -o - -)"
if [ "$published" != "$expected" ]; then
  echo "publish-release: ${reference} layer is ${published}, expected ${expected}" >&2
  exit 1
fi
echo "publish-release: pushed ${reference} (${published})"
