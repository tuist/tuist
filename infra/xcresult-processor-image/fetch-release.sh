#!/bin/bash
# Downloads the Tuist server release this VM runs and unpacks it into
# /opt/tuist/release. Runs from the xcresult-processor launchd unit after
# /etc/tuist.env has been sourced, before `tuist start`.
#
# The image carries no release. The Pod names one through
# TUIST_XCRESULT_PROCESSOR_RELEASE, an OCI reference such as
# `ghcr.io/tuist/tuist-xcresult-processor:release-sha-0123456789ab` whose
# single layer is the release tarball. The chart derives the tag from the
# server image tag, so the processor runs the same commit as the Linux pods.
#
# The repository is public, so the pull uses an anonymous registry token.
#
# launchd's KeepAlive re-runs the whole boot chain every time the BEAM
# exits. The reference that was unpacked is recorded next to the release,
# and a restart for the same reference skips the download.

set -euo pipefail

RELEASE_DIR="/opt/tuist/release"
MARKER="${RELEASE_DIR}/.tuist-release-ref"

ref="${TUIST_XCRESULT_PROCESSOR_RELEASE:-}"
if [ -z "$ref" ]; then
  echo "fetch-release: TUIST_XCRESULT_PROCESSOR_RELEASE not set; the image carries no release to fall back to" >&2
  exit 1
fi

if [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$ref" ] && [ -x "${RELEASE_DIR}/bin/tuist" ]; then
  echo "fetch-release: ${ref} already unpacked"
  exit 0
fi

registry="${ref%%/*}"
remainder="${ref#*/}"
repository="${remainder%:*}"
tag="${remainder##*:}"
if [ -z "$registry" ] || [ -z "$repository" ] || [ -z "$tag" ] || [ "$repository" = "$remainder" ]; then
  echo "fetch-release: cannot parse ${ref} as <registry>/<repository>:<tag>" >&2
  exit 1
fi

curl_args=(--fail --silent --show-error --location --connect-timeout 20 --retry 5 --retry-all-errors --retry-delay 5)

token="$(
  curl "${curl_args[@]}" --max-time 60 \
    "https://${registry}/token?service=${registry}&scope=repository:${repository}:pull" |
    sed -n 's/.*"token":"\([^"]*\)".*/\1/p'
)"
if [ -z "$token" ]; then
  echo "fetch-release: ${registry} returned no pull token for ${repository}" >&2
  exit 1
fi

manifest="$(
  curl "${curl_args[@]}" --max-time 60 \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json" \
    "https://${registry}/v2/${repository}/manifests/${tag}"
)"
digest="$(printf '%s' "$manifest" | /usr/bin/plutil -extract layers.0.digest raw -o - -)"
if [[ "$digest" != sha256:* ]]; then
  echo "fetch-release: ${ref} has no sha256 layer (got '${digest}')" >&2
  exit 1
fi

tarball="$(mktemp -t tuist-release)"
trap 'rm -f "$tarball"' EXIT

echo "fetch-release: downloading ${ref} (${digest})"
curl "${curl_args[@]}" --max-time 900 \
  -H "Authorization: Bearer ${token}" \
  -o "$tarball" \
  "https://${registry}/v2/${repository}/blobs/${digest}"

actual="sha256:$(/usr/bin/shasum -a 256 "$tarball" | awk '{print $1}')"
if [ "$actual" != "$digest" ]; then
  echo "fetch-release: digest mismatch for ${ref}: expected ${digest}, got ${actual}" >&2
  exit 1
fi

# Unpack in place rather than swapping the directory: it is the launchd
# job's WorkingDirectory. A previous attempt may have died mid-extract, so
# start from an empty directory.
mkdir -p "$RELEASE_DIR"
find "$RELEASE_DIR" -mindepth 1 -delete
tar -xzf "$tarball" -C "$RELEASE_DIR"
if [ ! -x "${RELEASE_DIR}/bin/tuist" ]; then
  echo "fetch-release: ${ref} does not contain bin/tuist" >&2
  exit 1
fi
printf '%s' "$ref" > "$MARKER"
echo "fetch-release: unpacked ${ref} into ${RELEASE_DIR}"
