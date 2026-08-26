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
# This talks to ghcr.io, which is not the api.github.com bucket that CI
# exhausts; it returns no x-ratelimit accounting at all. GITHUB_TOKEN is
# used when set so the requests bill to the token rather than to a runner
# egress IP shared by the whole fleet, and falls back to an anonymous pull
# token. A probe that can obtain no token warns rather than failing: it
# cannot answer the question, and a check that quietly always says
# "published" is worse than one that says so out loud.
set -uo pipefail

repository="${1:?usage: ghcr-image-published.sh <repository> <tag>}"
image_tag="${2:?usage: ghcr-image-published.sh <repository> <tag>}"

token_cache="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ghcr-pull-token"

fetch_token() {
  local url="https://ghcr.io/token?service=ghcr.io&scope=repository:${repository}:pull"
  local auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-u "x-access-token:${GITHUB_TOKEN}")
  local token
  token="$(curl -sSL --max-time 30 "${auth[@]}" "$url" 2>/dev/null |
    sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
  [ -n "$token" ] || return 1
  (umask 077; printf '%s' "$token" > "$token_cache")
  printf '%s' "$token"
}

manifest_status() {
  curl -sS --max-time 30 -o /dev/null -w '%{http_code}' -I \
    -H "Authorization: Bearer $1" \
    -H 'Accept: application/vnd.oci.image.index.v1+json' \
    -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
    -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
    -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
    "https://ghcr.io/v2/${repository}/manifests/${image_tag}" 2>/dev/null
}

# One pull token covers every repository probed in a job, so it is cached
# and reused across invocations instead of re-minted per image. That is an
# optimization, not an assumption: a cached token rejected for this
# repository is discarded and re-minted against it, so correctness holds
# even if the shared-scope behaviour ever changes.
token=""
if [ -s "$token_cache" ]; then
  token="$(cat "$token_cache")"
fi
[ -n "$token" ] || token="$(fetch_token)" || token=""

if [ -n "$token" ]; then
  status="$(manifest_status "$token")"
  if [ "$status" = "401" ] || [ "$status" = "403" ]; then
    rm -f "$token_cache"
    if token="$(fetch_token)"; then
      status="$(manifest_status "$token")"
    fi
  fi
else
  status=""
fi

if [ -z "$status" ]; then
  echo "::warning::Could not reach GHCR to check ${repository}:${image_tag}; treating it as published. This check is not protecting anything until that is fixed."
  exit 0
fi

[ "$status" != "404" ]
