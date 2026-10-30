#!/usr/bin/env bash
#
# Prints the digest of the single layer of the OCI artifact GHCR serves for
# <repository>:<tag> to an anonymous client, which is how the xcresult
# processor's Tart guest downloads it.
#
# Usage: ghcr-artifact-layer-digest.sh <repository> <tag>
#   e.g. ghcr-artifact-layer-digest.sh tuist/tuist-xcresult-processor-release sha-36541cf45c69
set -uo pipefail

repository="${1:?usage: ghcr-artifact-layer-digest.sh <repository> <tag>}"
tag="${2:?usage: ghcr-artifact-layer-digest.sh <repository> <tag>}"

curl_args=(--fail --silent --show-error --location --max-time 30 --retry 3)

token="$(curl "${curl_args[@]}" "https://ghcr.io/token?service=ghcr.io&scope=repository:${repository}:pull" |
  sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"

digest=""
if [ -n "$token" ]; then
  digest="$(curl "${curl_args[@]}" \
    -H "Authorization: Bearer ${token}" \
    -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
    "https://ghcr.io/v2/${repository}/manifests/${tag}" |
    jq -r 'if (.layers | length) == 1 then .layers[0].digest else empty end')"
fi

if [[ ! "$digest" =~ ^sha256:[a-f0-9]{64}$ ]]; then
  echo "::warning::ghcr.io/${repository}:${tag} is not a single-layer artifact readable anonymously: it is missing, or the package is not public." >&2
  exit 1
fi
echo "$digest"
