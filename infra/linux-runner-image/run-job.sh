#!/usr/bin/env bash
# Entrypoint for the `runner` main container in the token-isolation
# Pod shape. This container holds NO ServiceAccount token: the
# sibling `poller` init container is the one that claims a job and
# mints the JIT, then stages it on a shared emptyDir. kubelet only
# starts this container after the poller init container has exited,
# so by the time we run here the JIT (if any) is already fully
# written — there is nothing to poll or wait for.
#
# This is the half of dispatch-poll.sh that runs the actual job,
# split into its own credential-free container so untrusted workflow
# code never shares a process namespace with the dispatch token.
#
#   JIT present → exec ./run.sh --jitconfig <jit> --disableupdate
#                 (single job, ephemeral, no auto-upgrade).
#   JIT absent  → the poller exited without a claim (HTTP 410 stale
#                 image, or an auth/transport abort). Nothing to run;
#                 exit 0 so the Pod completes and the RunnerPool
#                 reconciler replaces it.

set -uo pipefail

JIT_PATH=${TUIST_RUNNER_JIT_PATH:-/var/lib/tuist-runner/jit}

if [ ! -s "${JIT_PATH}" ]; then
  echo "$(date -u +%FT%TZ) run-job: no JIT staged at ${JIT_PATH}; nothing to run"
  exit 0
fi

jit="$(cat "${JIT_PATH}")"
# Fail closed: -s above proved the file is non-empty, but a failed
# read (I/O error, racing truncation) must not feed an empty
# --jitconfig into the runner, which would fail to register and
# silently burn the already-claimed job. Abort visibly instead.
if [ -z "${jit}" ]; then
  echo "$(date -u +%FT%TZ) run-job: JIT at ${JIT_PATH} unreadable/empty; aborting"
  exit 1
fi
# Optional: route the job's Tuist cache at the account's per-job
# endpoint when dispatch-poll.sh staged one. The CLI honors
# TUIST_CACHE_ENDPOINT as a cache-endpoint override; exporting before
# exec propagates it to the runner process and every job step. Falls
# back to the CLI's default cache resolution when the file is absent.
CACHE_ENDPOINT_PATH="${JIT_PATH}.cache-endpoint"
if [ -s "${CACHE_ENDPOINT_PATH}" ]; then
  cache_endpoint="$(cat "${CACHE_ENDPOINT_PATH}")"
  if [ -n "${cache_endpoint}" ]; then
    echo "$(date -u +%FT%TZ) run-job: routing cache to runner-local endpoint ${cache_endpoint}"
    export TUIST_CACHE_ENDPOINT="${cache_endpoint}"
  fi
fi
echo "$(date -u +%FT%TZ) run-job: JIT staged, starting runner"
# Forensic vitals for this job's lifetime. Backgrounded so it keeps
# sampling until the container (and microVM) dies; its last line
# before a mid-job death lands in the Pod logs, the only trail left
# once the VM is reaped. Guarded so a missing script (older image)
# never blocks the runner.
if [ -x /usr/local/bin/vitals.sh ]; then
  /usr/local/bin/vitals.sh &
fi

# Idle watchdog. GitHub assigns a queued job to any label-eligible
# runner, not necessarily the one the server minted for it, so this
# runner can register and then wait indefinitely for a job GitHub ran
# on a sibling. The watchdog terminates it after
# TUIST_RUNNER_IDLE_TIMEOUT_SECONDS so the Pod completes and the
# reconciler recycles it. A runner holding a job has written the
# JOB_STARTED marker (via the runner's own hook) and is never touched.
# 0 / unset disables the watchdog.
# The job-start signal must be irreversible: everything under /tmp is
# writable by the workflow, so a job that removes the marker (a broad
# `rm -rf /tmp/*` cleanup step is enough) must not be able to make
# itself look idle and get killed mid-run. Two independent latches:
#
#   1. The hook kills the watchdog outright. It runs before any workflow
#      step, so by the time job code executes there is no watchdog left
#      to mislead — deleting anything afterwards is inert.
#   2. The watchdog polls for the marker and exits the moment it sees
#      it, rather than reading it once at the deadline. This covers the
#      hook failing to resolve the pid, and once it has exited a later
#      deletion cannot bring it back.
#
# Neither latch can be undone from inside the job, which is the property
# that matters: the workflow can only ever make the watchdog give up
# earlier, never make it fire on a live job.
JOB_STARTED_MARKER=/tmp/tuist-runner-job-started
JOB_STARTED_HOOK=/tmp/tuist-runner-job-started-hook.sh
WATCHDOG_PID_FILE=/tmp/tuist-runner-watchdog.pid
rm -f "${JOB_STARTED_MARKER}" "${WATCHDOG_PID_FILE}"
cat >"${JOB_STARTED_HOOK}" <<HOOK
#!/usr/bin/env bash
# ACTIONS_RUNNER_HOOK_JOB_STARTED: the ephemeral runner runs this the
# instant GitHub hands it a job, before any workflow step. Cancel the
# idle watchdog permanently, then drop the marker as a backstop.
touch "${JOB_STARTED_MARKER}" 2>/dev/null || true
_wpid="\$(cat "${WATCHDOG_PID_FILE}" 2>/dev/null || true)"
[ -n "\${_wpid}" ] && kill "\${_wpid}" 2>/dev/null || true
exit 0
HOOK
chmod +x "${JOB_STARTED_HOOK}"
export ACTIONS_RUNNER_HOOK_JOB_STARTED="${JOB_STARTED_HOOK}"

idle_timeout="${TUIST_RUNNER_IDLE_TIMEOUT_SECONDS:-0}"

./run.sh --jitconfig "${jit}" --disableupdate &
runner_pid=$!

# Forward pod-deletion SIGTERM to the runner so it deregisters cleanly.
trap 'kill -TERM "${runner_pid}" 2>/dev/null || true' TERM INT

if [ "${idle_timeout}" -gt 0 ] 2>/dev/null; then
  (
    waited=0
    while [ "${waited}" -lt "${idle_timeout}" ]; do
      # Latch and stand down for good the first time work is observed.
      [ -e "${JOB_STARTED_MARKER}" ] && exit 0
      kill -0 "${runner_pid}" 2>/dev/null || exit 0
      sleep 1
      waited=$((waited + 1))
    done
    # The marker alone leaves a narrow race: the hook fires when the
    # Worker STARTS the job, a second or more after the Listener has
    # already acknowledged the assignment — so a job handed over in the
    # last seconds of the budget could still be TERMed as idle after
    # GitHub irrevocably placed it, and an ephemeral runner killed
    # post-acknowledgment marks the job failed rather than re-queuing it.
    # The Runner.Worker process exists from the moment the Listener
    # dispatches, before the hook runs, so it is the authoritative
    # "this runner has work" signal.
    if [ ! -e "${JOB_STARTED_MARKER}" ] && ! pgrep -f "Runner.Worker" >/dev/null 2>&1 &&
      kill -0 "${runner_pid}" 2>/dev/null; then
      echo "$(date -u +%FT%TZ) run-job: no job assigned within ${idle_timeout}s; terminating idle runner"
      kill -TERM "${runner_pid}" 2>/dev/null || true
    fi
  ) &
  watchdog_pid=$!
  printf '%s' "${watchdog_pid}" >"${WATCHDOG_PID_FILE}" 2>/dev/null || true
fi

# Re-wait until the runner is really gone. `wait` returns the moment a
# trapped signal arrives (128+15), so a single wait would let this script —
# the container's main process — exit milliseconds after SIGTERM, and the
# runtime would SIGKILL run.sh mid-cleanup. Under `exec` the runner was the
# main process and got the full terminationGracePeriod to cancel the job,
# report status and deregister; looping restores that window, and leaves rc
# as the runner's real exit code rather than a blanket 143.
wait "${runner_pid}"
rc=$?
while kill -0 "${runner_pid}" 2>/dev/null; do
  wait "${runner_pid}"
  rc=$?
done
[ -n "${watchdog_pid:-}" ] && kill "${watchdog_pid}" 2>/dev/null || true
exit "${rc}"
