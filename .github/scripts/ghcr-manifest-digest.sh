#!/usr/bin/env bash
#
# Prints the digest GHCR serves for <repository>:<tag> to an anonymous
# client, which is how macOS runner hosts pull it.
#
# Usage: ghcr-manifest-digest.sh <repository> <tag>
#   e.g. ghcr-manifest-digest.sh tuist/tuist-runner-payload 0.1.0
set -uo pipefail

repository="${1:?usage: ghcr-manifest-digest.sh <repository> <tag>}"
tag="${2:?usage: ghcr-manifest-digest.sh <repository> <tag>}"

curl_args=(--fail --silent --show-error --location --max-time 30 --retry 3)

token="$(curl "${curl_args[@]}" "https://ghcr.io/token?service=ghcr.io&scope=repository:${repository}:pull" |
  sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"

digest=""
if [ -n "$token" ]; then
  digest="$(curl "${curl_args[@]}" --head \
    -H "Authorization: Bearer ${token}" \
    -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
    "https://ghcr.io/v2/${repository}/manifests/${tag}" |
    tr -d '\r' |
    awk -F': ' 'tolower($1) == "docker-content-digest" { print $2 }')"
fi

if [[ ! "$digest" =~ ^sha256:[a-f0-9]{64}$ ]]; then
  echo "::error::ghcr.io/${repository}:${tag} is not readable anonymously: it is missing, or the package is not public. Hosts pull it without credentials." >&2
  exit 1
fi
echo "$digest"
