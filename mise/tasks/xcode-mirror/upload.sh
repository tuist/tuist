#!/usr/bin/env bash
#MISE description "Download an Xcode .xip from Apple via xcodes and push it to the Tuist OCI registry."
#USAGE arg "<version>" help="Xcode version to publish (e.g. 26.4.1, 26.5)."

# Local maintainer task — populates the in-house Xcode .xip mirror
# at `<registry>/xcode-xips:<version>` that the
# `.github/workflows/macos-xcode-image.yml` workflow pulls from.
#
# Run this when an xcodereleases.com RSS notification lands in
# the infra-ops Slack channel announcing a new Xcode release. See
# `infra/macos-xcode-image/AGENTS.md` for the architecture and the
# RSS subscription command.
#
# Tools come from the repo-root mise.toml (xcodes, oras, jq).
# Registry credentials come from the environment (see below).
# xcodes prompts for Apple ID password + 2FA the first time per
# ~30-day window and caches the session in the local keychain
# afterwards.

set -euo pipefail

VERSION="${usage_version:-${1:-}}"
if [ -z "$VERSION" ]; then
  echo "usage: mise run xcode-mirror:upload <version>" >&2
  echo "  e.g. mise run xcode-mirror:upload 26.4.1" >&2
  exit 1
fi

# Tools (`xcodes`, `oras`, `jq`) come from the repo-root mise.toml.
# Running this task via `mise run xcode-mirror:upload` auto-installs
# anything missing.

# === Registry credentials ==================================================

# The mirror now lives on the Tuist OCI registry rather than GHCR, so the
# `gh`-token bootstrap this task used to do no longer applies: the
# registry has its own credentials and does not know about GitHub.
#
# It is also reachable on the tailnet only, so this task needs the
# operator connected. That is the usual state on a maintainer Mac, and
# the failure is legible if not.
: "${TUIST_OCI_REGISTRY_HOST:?set TUIST_OCI_REGISTRY_HOST (e.g. oci.tuist.dev)}"
: "${TUIST_OCI_REGISTRY_USERNAME:?set TUIST_OCI_REGISTRY_USERNAME (OCI_REGISTRY_CREDENTIALS in the env vault)}"
: "${TUIST_OCI_REGISTRY_PASSWORD:?set TUIST_OCI_REGISTRY_PASSWORD (OCI_REGISTRY_CREDENTIALS in the env vault)}"

echo "Logging oras into ${TUIST_OCI_REGISTRY_HOST}..."
if ! printf '%s' "$TUIST_OCI_REGISTRY_PASSWORD" | oras login "$TUIST_OCI_REGISTRY_HOST" \
    --username "$TUIST_OCI_REGISTRY_USERNAME" --password-stdin >/dev/null; then
  cat >&2 <<EOF
Error: could not log in to ${TUIST_OCI_REGISTRY_HOST}.

The registry is reachable on the tailnet only. Check that Tailscale is
up on this machine, then retry.
EOF
  exit 1
fi

# === Cache & download ======================================================

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/tuist-xcode-mirror"
mkdir -p "$CACHE_DIR"

# Reuse a previously-downloaded .xip if it's still on disk. Apple
# rate-limits Xcode downloads (a few per Apple ID per hour); the
# debug loop shouldn't burn that budget on every run.
EXISTING_XIP="$(ls "$CACHE_DIR"/Xcode-"${VERSION}"*.xip 2>/dev/null | head -n1 || true)"
if [ -n "$EXISTING_XIP" ] && [ -f "$EXISTING_XIP" ]; then
  echo "Reusing cached .xip: ${EXISTING_XIP} ($(du -h "$EXISTING_XIP" | awk '{print $1}'))"
  XIP="$EXISTING_XIP"
else
  echo "Downloading Xcode ${VERSION} from Apple..."
  echo "(xcodes prompts for Apple ID + 2FA the first time per ~30-day window;"
  echo " subsequent runs reuse the keychain-cached session silently.)"
  xcodes download "${VERSION}" --directory "${CACHE_DIR}"
  XIP="$(ls "${CACHE_DIR}"/Xcode-"${VERSION}"*.xip | head -n1)"
  if [ ! -f "$XIP" ]; then
    echo "Error: xcodes claimed success but no Xcode-${VERSION}*.xip in ${CACHE_DIR}" >&2
    exit 1
  fi
fi

# === Push ================================================================

echo "Pushing $(basename "$XIP") → ${TUIST_OCI_REGISTRY_HOST}/xcode-xips:${VERSION}..."
# `--artifact-type` advertises the media type for the manifest so
# the build workflow (and future tooling) can verify the tag
# points at a real .xip. The blob's own media type is
# `application/x-pkcs7-mime`, which Apple's signed .xips actually
# are.
#
# Cd into the cache dir + push by basename instead of absolute
# path — `oras push` rejects absolute paths by default
# ("absolute file path detected"). The annotation puts the
# original filename back in the manifest so consumers see the
# real name when they pull.
xip_filename="$(basename "$XIP")"
(
  cd "$(dirname "$XIP")"
  oras push \
    --artifact-type "application/vnd.tuist.xcode-xip" \
    --annotation "org.opencontainers.image.title=${xip_filename}" \
    "${TUIST_OCI_REGISTRY_HOST}/xcode-xips:${VERSION}" \
    "${xip_filename}:application/x-pkcs7-mime"
)

echo
echo "Published ${TUIST_OCI_REGISTRY_HOST}/xcode-xips:${VERSION}"
echo
echo "Next:"
echo "  gh workflow run macos-xcode-image.yml -f xcode_version=${VERSION}"
