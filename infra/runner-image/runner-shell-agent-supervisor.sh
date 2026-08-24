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

# The lock is deliberately shared across uids: this script runs as root from
# /Library/LaunchDaemons, while dispatch-poll.sh starts its fallback copy as
# `runner`. Both must see the same lock, so the path stays in /tmp.
#
# kill -0 cannot arbitrate that. From `runner` it fails with EPERM against a
# live root-owned holder exactly as it fails with ESRCH against a dead pid, so
# a healthy daemon reads as stale. ps reports every uid, so it can tell the
# two apart.
lock_holder_alive() {
  case "${1}" in
    '' | *[!0-9]*) return 1 ;;
  esac
  ps -p "${1}" -o pid= >/dev/null 2>&1
}

# Sets lock_pid. Returns 1 only when the pid file is a regular file that cannot
# be read, which is not evidence that the holder died.
#
# The -f test carries weight beyond -r: -r is an access(2) permission check and
# passes on a FIFO or a blocking device node, and the redirect below would then
# hang in open(2), before any of the bounded handling downstream gets to run.
# A non-regular path is never a live holder's doing either, since the holder
# publishes its pid with a plain `echo >` that would block on the same FIFO, so
# anything that is not a regular file falls through to the stale path where
# removal is bounded and refusal exits.
lock_pid=""
read_lock_pid() {
  lock_pid=""
  [ -f "${LOCK_PID_FILE}" ] || return 0
  [ -r "${LOCK_PID_FILE}" ] || return 1
  read -r lock_pid <"${LOCK_PID_FILE}" || lock_pid=""
  return 0
}

LOCK_REMOVAL_ATTEMPT_LIMIT=5
lock_removal_failures=0

while ! mkdir "${LOCK_DIR}" 2>/dev/null; do
  lock_pid=""
  # The holder writes its pid just after mkdir; give it a beat to appear.
  if [ ! -e "${LOCK_PID_FILE}" ]; then
    sleep 1
  fi

  if [ -e "${LOCK_PID_FILE}" ] && ! read_lock_pid; then
    echo "$(date -u +%FT%TZ) runner-shell-agent-supervisor: cannot read ${LOCK_PID_FILE}; assuming the lock is held"
    sleep 30
    continue
  fi

  if lock_holder_alive "${lock_pid}"; then
    echo "$(date -u +%FT%TZ) runner-shell-agent-supervisor: another supervisor is active (pid=${lock_pid}); waiting"
    sleep 30
    continue
  fi

  echo "$(date -u +%FT%TZ) runner-shell-agent-supervisor: removing stale lock at ${LOCK_DIR}"
  if rm -rf "${LOCK_DIR}"; then
    lock_removal_failures=0
    continue
  fi

  # Refused removal means the lock belongs to another uid, and the only other
  # uid reaching this path is the one running the other supervisor copy. Retry
  # bounded and backed off, then exit rather than run unlocked: starting a
  # second runner-shell-agent against the same dispatch URL and claim marker is
  # what the lock exists to prevent. Exiting is safe for both callers. The
  # LaunchDaemon copy is KeepAlive=true, so launchd respawns it under its own
  # 10s throttle and reclaims the lock once the holder is gone; the
  # dispatch-poll.sh fallback copy is redundant while the daemon holds it.
  lock_removal_failures=$((lock_removal_failures + 1))
  if [ "${lock_removal_failures}" -ge "${LOCK_REMOVAL_ATTEMPT_LIMIT}" ]; then
    echo "$(date -u +%FT%TZ) runner-shell-agent-supervisor: cannot remove ${LOCK_DIR} after ${LOCK_REMOVAL_ATTEMPT_LIMIT} attempts; another uid owns it, giving up"
    exit 1
  fi
  echo "$(date -u +%FT%TZ) runner-shell-agent-supervisor: lock removal refused (attempt ${lock_removal_failures}/${LOCK_REMOVAL_ATTEMPT_LIMIT}); retrying"
  sleep $((lock_removal_failures * 5))
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
