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
# Tools come from the repo-root mise.toml (xcodes, oras, jq, gh).
# Beyond that the task self-bootstraps: it uses the operator's
# existing `gh` token to log oras into ghcr.io so they don't have
# to remember the manual login command.
#
# The only state outside this task that the operator has to set up
# *before* running it is a signed-in xcodes session, which is
# bootstrapped by `mise run xcode-mirror:mint-session`.

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
  echo "(Requires a signed-in xcodes session — run \`mise run xcode-mirror:mint-session\` if absent.)"
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
# the worker (and future tooling) can verify the tag points at a
# real .xip. The blob's own media type is `application/x-pkcs7-mime`,
# which Apple's signed .xips actually are.
oras push \
  --artifact-type "application/vnd.tuist.xcode-xip" \
  "ghcr.io/tuist/xcode-xips:${VERSION}" \
  "$XIP:application/x-pkcs7-mime"

echo
echo "Published ghcr.io/tuist/xcode-xips:${VERSION}"
echo
echo "Next:"
echo "  gh workflow run macos-xcode-image.yml -f xcode_version=${VERSION}"
