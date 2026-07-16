#!/bin/bash
# Launchd-managed supervisor for the trusted interactive shell bridge.
# It waits for inject-env.sh to materialize the Pod env/token files,
# and restarts the Go bridge if it exits while the VM is still alive.

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
      export TUIST_RUNNER_SHELL_CLAIM_MARKER="${TUIST_RUNNER_SHELL_CLAIM_MARKER:-/tmp/tuist-runner-shell-claimed}"
      echo "$(date -u +%FT%TZ) runner-shell-agent-supervisor: runner env/token ready (dispatch_url=${TUIST_RUNNER_DISPATCH_URL})"
      break
    fi
  fi

  echo "$(date -u +%FT%TZ) runner-shell-agent-supervisor: waiting for runner env/token"
  sleep 2
done

while true; do
  if [ ! -x /opt/tuist/runner-shell-agent ]; then
    echo "$(date -u +%FT%TZ) runner-shell-agent-supervisor: runner-shell-agent missing or not executable; retrying in 10s"
    sleep 10
    continue
  fi

  if [ -z "${TUIST_RUNNER_SHELL_PATH:-}" ] && [ -x /bin/zsh ]; then
    export TUIST_RUNNER_SHELL_PATH=/bin/zsh
  fi

  echo "$(date -u +%FT%TZ) runner-shell-agent-supervisor: starting runner-shell-agent"
  /opt/tuist/runner-shell-agent
  rc=$?
  echo "$(date -u +%FT%TZ) runner-shell-agent-supervisor: runner-shell-agent exited (rc=${rc}); restarting in 2s"
  sleep 2
done
