#!/usr/bin/env bash
#MISE description="Regenerate .claude/launch.json with this worktree's dev server ports"

set -euo pipefail

WORKTREE_ROOT="$(git rev-parse --show-toplevel)"
LAUNCH_DIR="${WORKTREE_ROOT}/.claude"
LAUNCH_FILE="${LAUNCH_DIR}/launch.json"

# Ports are owned by dev_instance_env.sh, which mise sources for every task via
# mise.toml's [env]._.source. Consume the exported values so launch.json always
# matches what the dev servers actually bind. Fall back to a nested mise exec
# when the task is invoked outside a mise-sourced environment.
server_port="${TUIST_SERVER_PORT:-}"
cache_port="${TUIST_CACHE_PORT:-}"
if [[ -z "${server_port}" || -z "${cache_port}" ]]; then
  read -r server_port cache_port < <(
    cd "${WORKTREE_ROOT}" &&
      mise exec -- bash -c 'printf "%s %s" "${TUIST_SERVER_PORT:-}" "${TUIST_CACHE_PORT:-}"' 2>/dev/null || true
  ) || true
fi

if ! [[ "${server_port}" =~ ^[0-9]+$ && "${cache_port}" =~ ^[0-9]+$ ]]; then
  echo "claude:regenerate-launch-json: could not resolve dev ports; skipping" >&2
  exit 0
fi

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
