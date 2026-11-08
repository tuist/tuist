#!/usr/bin/env bash
# Package the operator chart with the exact image produced by this release.
set -euo pipefail

version=${1:?chart version required}
tag=${2:?image tag required}
digest=${3:?image digest required}
destination=${4:?destination directory required}

if [[ ! "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "An immutable sha256 image digest is required" >&2
  exit 1
fi

root=$(git rev-parse --show-toplevel)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -R "$root/infra/helm/cloudflare-operator" "$work/cloudflare-operator"
export IMAGE_TAG="$tag" IMAGE_DIGEST="$digest"
yq -i '.image.tag = strenv(IMAGE_TAG) | .image.digest = strenv(IMAGE_DIGEST)' \
  "$work/cloudflare-operator/values.yaml"
helm lint "$work/cloudflare-operator"
helm package "$work/cloudflare-operator" --version "$version" \
  --app-version "$tag" --destination "$destination"
