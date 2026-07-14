#!/usr/bin/env bash
#MISE description="Bootstrap this worktree for Claude Code (launch.json + server install)"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_DIR="${MISE_PROJECT_ROOT}/server"

# launch.json regen is cheap and writes outside _build, so always refresh it.
"${SCRIPT_DIR}/regenerate-launch-json.sh"

# `mise run install` runs deps.get + asset installs + ecto migrate/seed, all of
# which recompile the app and touch _build. The SessionStart hook fires this on
# every startup AND resume, so resuming a session that's already set up would
# recompile for nothing and force any running dev server to restart (Phoenix
# reloader: "dependencies changed, you must restart"). Only re-run it when an
# input that actually requires it changed; otherwise leave _build untouched.
fingerprint() {
  {
    cat "${SERVER_DIR}/mix.lock" 2>/dev/null
    ls -1 "${SERVER_DIR}/priv/repo/migrations" "${SERVER_DIR}/priv/ingest_repo/migrations" 2>/dev/null
    cat "${SERVER_DIR}/package.json" "${MISE_PROJECT_ROOT}/noora/package.json" 2>/dev/null
  } | shasum | awk '{ print $1 }'
}

sentinel="${SERVER_DIR}/_build/.claude-bootstrap-fingerprint"
current="$(fingerprint)"

if [ -f "${sentinel}" ] && [ "$(cat "${sentinel}")" = "${current}" ]; then
  echo "claude:bootstrap: deps/migrations unchanged; skipping server install (run 'mise run install' in server/ to force)"
  exit 0
fi

(cd "${SERVER_DIR}" && mise run install)

mkdir -p "$(dirname "${sentinel}")"
printf '%s\n' "${current}" >"${sentinel}"
