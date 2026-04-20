#!/usr/bin/env bash
#MISE description="Write .claude/launch.json with this worktree's dev server ports"

set -euo pipefail

WORKTREE_ROOT="$(git rev-parse --show-toplevel)"
INSTANCE_FILE="${WORKTREE_ROOT}/.tuist-dev-instance"
LAUNCH_DIR="${WORKTREE_ROOT}/.claude"
LAUNCH_FILE="${LAUNCH_DIR}/launch.json"

# Force mise to load dev_instance_env.sh, which creates .tuist-dev-instance.
if [[ ! -s "${INSTANCE_FILE}" ]]; then
  (cd "${WORKTREE_ROOT}" && mise exec -- true) >/dev/null 2>&1 || true
fi

if [[ ! -s "${INSTANCE_FILE}" ]]; then
  echo "worktree:launch-json: ${INSTANCE_FILE} missing; skipping" >&2
  exit 0
fi

suffix="$(tr -d '[:space:]' < "${INSTANCE_FILE}")"
if ! [[ "${suffix}" =~ ^[0-9]+$ ]]; then
  echo "worktree:launch-json: invalid suffix '${suffix}'" >&2
  exit 1
fi

server_port=$((8080 + suffix))
cache_port=$((8087 + suffix))

mkdir -p "${LAUNCH_DIR}"
cat > "${LAUNCH_FILE}" <<EOF
{
  "version": "0.0.1",
  "configurations": [
    {
      "name": "Tuist Server",
      "runtimeExecutable": "bash",
      "runtimeArgs": ["-c", "cd server && exec mise run dev"],
      "port": ${server_port}
    },
    {
      "name": "Tuist Cache",
      "runtimeExecutable": "bash",
      "runtimeArgs": ["-c", "cd cache && exec mix phx.server"],
      "port": ${cache_port}
    },
    {
      "name": "Handbook",
      "runtimeExecutable": "bash",
      "runtimeArgs": ["-c", "cd handbook && exec mise run dev"],
      "port": 5173
    }
  ]
}
EOF
