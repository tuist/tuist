#!/bin/bash
# Launchd-managed supervisor for the trusted interactive shell bridge.
# It waits for inject-env.sh to materialize the Pod env/token files,
# resolves python3 from the runner login environment, and restarts the
# bridge if it exits while the VM is still alive.

set -uo pipefail

LOG=/var/log/tuist-runner/shell-agent.log
exec >>"${LOG}" 2>&1

echo "$(date -u +%FT%TZ) runner-shell-agent-supervisor: starting"

LOCK_DIR=/tmp/tuist-runner-shell-agent.lock
LOCK_PID_FILE="${LOCK_DIR}/pid"
while ! mkdir "${LOCK_DIR}" 2>/dev/null; do
  lock_pid=""
  if [ -f "${LOCK_PID_FILE}" ]; then
    read -r lock_pid <"${LOCK_PID_FILE}" || lock_pid=""
  else
    sleep 1
    if [ -f "${LOCK_PID_FILE}" ]; then
      read -r lock_pid <"${LOCK_PID_FILE}" || lock_pid=""
    fi
  fi

  if [ -z "${lock_pid}" ] || ! kill -0 "${lock_pid}" 2>/dev/null; then
    echo "$(date -u +%FT%TZ) runner-shell-agent-supervisor: removing stale lock at ${LOCK_DIR}"
    rm -rf "${LOCK_DIR}"
    continue
  fi

  echo "$(date -u +%FT%TZ) runner-shell-agent-supervisor: another supervisor is active; waiting"
  sleep 30
done
echo "$$" >"${LOCK_PID_FILE}"
trap 'rm -rf "${LOCK_DIR}" 2>/dev/null || true' EXIT

while true; do
  if [ -f /etc/tuist.env ] && [ -f /etc/tuist-sa-token ]; then
    # shellcheck disable=SC1091
    source /etc/tuist.env

    if [ -n "${TUIST_RUNNER_DISPATCH_URL:-}" ] && [ -s /etc/tuist-sa-token ]; then
      echo "$(date -u +%FT%TZ) runner-shell-agent-supervisor: runner env/token ready (dispatch_url=${TUIST_RUNNER_DISPATCH_URL})"
      break
    fi
  fi

  echo "$(date -u +%FT%TZ) runner-shell-agent-supervisor: waiting for runner env/token"
  sleep 2
done

while true; do
  shell_agent_python=""
  if shell_agent_python="$(command -v python3 2>/dev/null)"; then
    :
  elif [ -x /opt/homebrew/bin/python3 ]; then
    shell_agent_python=/opt/homebrew/bin/python3
  elif [ -x /usr/local/bin/python3 ]; then
    shell_agent_python=/usr/local/bin/python3
  elif [ -x /usr/bin/python3 ]; then
    shell_agent_python=/usr/bin/python3
  elif [ -x /usr/bin/xcrun ] && shell_agent_python="$(/usr/bin/xcrun -f python3 2>/dev/null)"; then
    :
  fi

  if [ -z "${shell_agent_python}" ]; then
    echo "$(date -u +%FT%TZ) runner-shell-agent-supervisor: python3 missing; retrying in 10s"
    sleep 10
    continue
  fi

  if [ ! -x /opt/tuist/runner-shell-agent.py ]; then
    echo "$(date -u +%FT%TZ) runner-shell-agent-supervisor: runner-shell-agent missing or not executable; retrying in 10s"
    sleep 10
    continue
  fi

  if [ -z "${TUIST_RUNNER_SHELL_PATH:-}" ] && [ -x /bin/zsh ]; then
    export TUIST_RUNNER_SHELL_PATH=/bin/zsh
  fi

  echo "$(date -u +%FT%TZ) runner-shell-agent-supervisor: starting runner-shell-agent with ${shell_agent_python}"
  "${shell_agent_python}" /opt/tuist/runner-shell-agent.py
  rc=$?
  echo "$(date -u +%FT%TZ) runner-shell-agent-supervisor: runner-shell-agent exited (rc=${rc}); restarting in 2s"
  sleep 2
done
