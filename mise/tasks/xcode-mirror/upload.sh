#!/usr/bin/env bash
#MISE description "Download an Xcode .xip from Apple via xcodes and push it to ghcr.io/tuist/xcode-xips."
#USAGE arg "<version>" help="Xcode version to publish (e.g. 26.4.1, 26.5)."

# Local maintainer task — the break-glass path for the xcode-mirror
# service. Use when:
#   * a new Xcode is out and the in-cluster Tuist.XcodeMirror worker
#     hasn't picked it up yet (cookies expired, Apple API change, etc.)
#   * you need to seed a brand-new version in CI before the worker's
#     next tick
#
# Steady state: the in-cluster worker handles this. See
# `infra/macos-xcode-image/AGENTS.md` for the architecture.
#
# Pre-reqs (run once on your Mac):
#   * `brew install xcodes oras jq`
#   * `xcodes signin <apple-id>` and approve 2FA. The session lives
#     in your login keychain for ~30 days.
#   * `gh auth token | oras login ghcr.io --username <gh-user> --password-stdin`
#     (the token needs `write:packages` scope on the tuist org)

set -euo pipefail

VERSION="${usage_version:-${1:-}}"
if [ -z "$VERSION" ]; then
  echo "usage: mise run xcode-mirror:upload <version>" >&2
  echo "  e.g. mise run xcode-mirror:upload 26.4.1" >&2
  exit 1
fi

# Pre-flight checks. Fail fast with an actionable message instead of
# halfway through a 10 GB download.
for cmd in xcodes oras jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: ${cmd} not installed. Run \`brew install xcodes oras jq\`." >&2
    exit 1
  fi
done

# Trust-but-verify the GHCR auth. `oras` doesn't expose a `whoami`,
# so we round-trip a manifest fetch against a probe tag we don't
# expect to exist. A 404 means we authenticated and the tag is just
# missing (expected); anything else means oras can't reach the
# registry — surfacing the most likely fix.
if ! oras manifest fetch ghcr.io/tuist/xcode-xips:__probe__ >/dev/null 2>&1; then
  http_err=$(oras manifest fetch ghcr.io/tuist/xcode-xips:__probe__ 2>&1 || true)
  if ! echo "$http_err" | grep -qiE "not found|404"; then
    cat >&2 <<EOF
Error: oras can't authenticate against ghcr.io/tuist/xcode-xips.
Run: gh auth token | oras login ghcr.io --username <gh-user> --password-stdin
(Token needs the write:packages scope on the tuist org.)

oras said:
$http_err
EOF
    exit 1
  fi
fi

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
  echo "Downloading Xcode ${VERSION} from Apple (requires signed-in xcodes session)..."
  xcodes download "${VERSION}" --directory "${CACHE_DIR}"
  XIP="$(ls "${CACHE_DIR}"/Xcode-"${VERSION}"*.xip | head -n1)"
  if [ ! -f "$XIP" ]; then
    echo "Error: xcodes claimed success but no Xcode-${VERSION}*.xip in ${CACHE_DIR}" >&2
    exit 1
  fi
fi

echo "Pushing $(basename "$XIP") → ghcr.io/tuist/xcode-xips:${VERSION}..."
# `--artifact-type` advertises the media type for the manifest so the
# worker (and future tooling) can verify the tag points at a real
# .xip instead of some unrelated artifact that happened to land under
# the same tag. The blob media type below is what Apple's .xips
# actually are — a signed pkcs7-mime envelope.
oras push \
  --artifact-type "application/vnd.tuist.xcode-xip" \
  "ghcr.io/tuist/xcode-xips:${VERSION}" \
  "$XIP:application/x-pkcs7-mime"

echo
echo "Published ghcr.io/tuist/xcode-xips:${VERSION}"
echo
echo "Next:"
echo "  gh workflow run macos-xcode-image.yml -f xcode_version=${VERSION}"
