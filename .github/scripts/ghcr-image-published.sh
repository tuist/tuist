#!/usr/bin/env bash
#
# Answers whether a GHCR manifest exists, for the one question the release
# and deploy paths both have to ask: is the image the Helm chart pulls
# actually there?
#
# Exit 0 - published, or absence could not be proven.
# Exit 1 - GHCR definitively answered 404.
#
# The asymmetry is deliberate and is the whole contract. Only a 404 proves
# absence; auth failures, throttling and transport errors prove nothing.
# Treating those as "missing" would let a blip withhold the tag for a
# release that did publish, or silently downgrade a component mid-deploy,
# and both are worse than the failure this check exists to catch.
#
# Usage: ghcr-image-published.sh <repository> <tag>
#   e.g. ghcr-image-published.sh tuist/tuist-xcresult-processor 0.78.1
#
# GITHUB_TOKEN is used when set and falls back to an anonymous pull token,
# which is what actually authorizes these packages today. A probe that can
# obtain no token at all warns rather than failing: it cannot answer the
# question, and a check that quietly always says "published" is worse than
# one that says so out loud.
set -uo pipefail

repository="${1:?usage: ghcr-image-published.sh <repository> <tag>}"
image_tag="${2:?usage: ghcr-image-published.sh <repository> <tag>}"

token_url="https://ghcr.io/token?service=ghcr.io&scope=repository:${repository}:pull"
extract_token() { sed -n 's/.*"token":"\([^"]*\)".*/\1/p'; }

token=""
if [ -n "${GITHUB_TOKEN:-}" ]; then
  token="$(curl -sSL --max-time 30 -u "x-access-token:${GITHUB_TOKEN}" "$token_url" 2>/dev/null | extract_token)"
fi
if [ -z "$token" ]; then
  token="$(curl -sSL --max-time 30 "$token_url" 2>/dev/null | extract_token)"
fi
if [ -z "$token" ]; then
  echo "::warning::Could not obtain a GHCR pull token for ${repository}; treating ${repository}:${image_tag} as published. This check is not protecting anything until that is fixed."
  exit 0
fi

status="$(
  curl -sS --max-time 30 -o /dev/null -w '%{http_code}' -I \
    -H "Authorization: Bearer ${token}" \
    -H 'Accept: application/vnd.oci.image.index.v1+json' \
    -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
    -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
    -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
    "https://ghcr.io/v2/${repository}/manifests/${image_tag}" 2>/dev/null
)"

[ "$status" != "404" ]
