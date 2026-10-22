#!/bin/bash
# Installs the server release this VM runs into /opt/tuist/release. Runs at
# every launch of the dev.tuist.xcresult-processor unit, after /etc/tuist.env
# is sourced.
#
# The release is the single `release.tar.gz` layer of an OCI artifact that
# the deploy pins by that layer's digest:
#
#   TUIST_XCRESULT_PROCESSOR_RELEASE_REPOSITORY  e.g. ghcr.io/tuist/tuist-xcresult-processor-release
#   TUIST_XCRESULT_PROCESSOR_RELEASE_DIGEST      sha256:<64 hex>
#
# The blob is fetched anonymously, verified against the digest and unpacked
# in place. A launch that finds the same digest already installed (launchd
# restarting the chain on this VM) skips the download.

set -euo pipefail

RELEASE_DIR="/opt/tuist/release"
INSTALLED_DIGEST_FILE="${RELEASE_DIR}/.tuist-release-digest"

repository="${TUIST_XCRESULT_PROCESSOR_RELEASE_REPOSITORY:-}"
digest="${TUIST_XCRESULT_PROCESSOR_RELEASE_DIGEST:-}"

if [ -z "$repository" ] || [ -z "$digest" ]; then
  echo "fetch-release: TUIST_XCRESULT_PROCESSOR_RELEASE_REPOSITORY and TUIST_XCRESULT_PROCESSOR_RELEASE_DIGEST must be set" >&2
  exit 1
fi
if [[ ! "$digest" =~ ^sha256:[a-f0-9]{64}$ ]]; then
  echo "fetch-release: ${digest} is not a sha256 digest" >&2
  exit 1
fi

if [ -f "$INSTALLED_DIGEST_FILE" ] && [ "$(cat "$INSTALLED_DIGEST_FILE")" = "$digest" ]; then
  echo "fetch-release: ${repository}@${digest} is already installed"
  exit 0
fi

registry="${repository%%/*}"
name="${repository#*/}"
curl_args=(--fail --silent --show-error --location --retry 5 --retry-all-errors --retry-delay 2)

# Registries hand anonymous pull tokens out through the realm named in the
# `WWW-Authenticate` challenge on /v2/.
auth_args=()
challenge="$(curl --silent --show-error --max-time 30 --output /dev/null --dump-header - "https://${registry}/v2/" |
  tr -d '\r' | awk 'tolower($1) == "www-authenticate:" { sub(/^[^:]*: */, ""); print }')"
if [[ "$challenge" == Bearer* ]]; then
  realm="$(sed -n 's/.*realm="\([^"]*\)".*/\1/p' <<< "$challenge")"
  service="$(sed -n 's/.*service="\([^"]*\)".*/\1/p' <<< "$challenge")"
  token="$(curl "${curl_args[@]}" --max-time 30 --get \
    --data-urlencode "service=${service}" \
    --data-urlencode "scope=repository:${name}:pull" \
    "$realm" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
  if [ -z "$token" ]; then
    echo "fetch-release: ${realm} returned no pull token for ${name}" >&2
    exit 1
  fi
  auth_args=(-H "Authorization: Bearer ${token}")
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "fetch-release: downloading ${repository}@${digest}"
curl "${curl_args[@]}" --max-time 600 ${auth_args[@]+"${auth_args[@]}"} \
  --output "${work}/release.tar.gz" \
  "https://${registry}/v2/${name}/blobs/${digest}"

actual="sha256:$(shasum -a 256 "${work}/release.tar.gz" | awk '{ print $1 }')"
if [ "$actual" != "$digest" ]; then
  echo "fetch-release: downloaded blob is ${actual}, expected ${digest}" >&2
  exit 1
fi

mkdir -p "$RELEASE_DIR"
find "$RELEASE_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
tar -xzf "${work}/release.tar.gz" -C "$RELEASE_DIR"
if [ ! -x "${RELEASE_DIR}/bin/tuist" ]; then
  echo "fetch-release: ${repository}@${digest} has no bin/tuist" >&2
  exit 1
fi
echo "$digest" > "$INSTALLED_DIGEST_FILE"
echo "fetch-release: installed ${repository}@${digest}"
