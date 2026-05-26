#!/usr/bin/env bash
#MISE description "Download an Xcode .xip from Apple via xcodes and push it to ghcr.io/tuist/xcode-xips."
#USAGE arg "<version>" help="Xcode version to publish (e.g. 26.4.1, 26.5)."

# Local maintainer task — populates the in-house Xcode .xip mirror
# at `ghcr.io/tuist/xcode-xips:<version>` that the
# `.github/workflows/macos-xcode-image.yml` workflow pulls from.
#
# Run this when an xcodereleases.com RSS notification lands in
# the infra-ops Slack channel announcing a new Xcode release. See
# `infra/macos-xcode-image/AGENTS.md` for the architecture and the
# RSS subscription command.
#
# Tools come from the repo-root mise.toml (xcodes, oras, jq, gh).
# Beyond that the task self-bootstraps: it uses the operator's
# existing `gh` token to log oras into ghcr.io so they don't have
# to remember the manual login command. xcodes prompts for Apple
# ID password + 2FA the first time per ~30-day window and caches
# the session in the local keychain afterwards.

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

# === Auto-login to GHCR via gh ============================================

# oras has no `whoami` so the cheapest reliable auth check is a
# 404-expected manifest fetch. A 404 means we authenticated and
# the probe tag just doesn't exist (good); anything else means
# we have to log in.
needs_login=true
if oras manifest fetch ghcr.io/tuist/xcode-xips:__probe__ 2>&1 | grep -qiE "not found|404"; then
  needs_login=false
fi

if [ "$needs_login" = "true" ]; then
  if ! command -v gh >/dev/null 2>&1; then
    cat >&2 <<'EOF'
Error: gh CLI not installed, and oras can't authenticate against
ghcr.io/tuist. Install gh (`brew install gh && gh auth login`) or
log oras in manually:

  echo $TOKEN | oras login ghcr.io --username <gh-user> --password-stdin
EOF
    exit 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "Signing in to gh (needed for ghcr.io push)..."
    gh auth login
  fi

  # GHCR distinguishes login (any token does) from push (needs
  # write:packages on the org). `gh auth login` defaults to repo +
  # workflow scopes, so a fresh operator session almost never has
  # write:packages. Probe `gh auth status` for it now and fail
  # fast — better than burning a 2 GB upload before the registry
  # returns "permission_denied: token does not match expected
  # scopes" on the manifest PUT.
  #
  # `gh auth status` quotes each scope (`'write:packages'`),
  # which a bare substring match handles without us having to
  # care about gh's quoting changes between releases.
  if ! gh auth status 2>&1 | grep -q "write:packages"; then
    cat >&2 <<'EOF'
Error: your gh token doesn't include the write:packages scope.

Refresh it (this won't force a full re-login):
  gh auth refresh -s write:packages,read:packages

Then re-run this task.
EOF
    exit 1
  fi

  gh_user=$(gh api user --jq .login 2>/dev/null || echo "tuist-bot")
  echo "Logging oras into ghcr.io as $gh_user..."
  gh auth token | oras login ghcr.io --username "$gh_user" --password-stdin >/dev/null
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

echo "Pushing $(basename "$XIP") → ghcr.io/tuist/xcode-xips:${VERSION}..."
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
    "ghcr.io/tuist/xcode-xips:${VERSION}" \
    "${xip_filename}:application/x-pkcs7-mime"
)

echo
echo "Published ghcr.io/tuist/xcode-xips:${VERSION}"
echo
echo "Next:"
echo "  gh workflow run macos-xcode-image.yml -f xcode_version=${VERSION}"
