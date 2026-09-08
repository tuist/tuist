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

BUILDKITE_ENV_PATH="${JIT_PATH}.buildkite-env"

# Buildkite branch. The poller stages a credential file instead of a JIT
# when the claimed job came from a customer's Buildkite cluster.
#
# None of the GitHub idle-watchdog machinery below applies here. An
# acquisition token names one job UUID, so the assignment already
# happened server-side before this container started: the agent either
# takes that job or exits. There is no window in which a registered agent
# waits to be given work, which is the whole hazard that watchdog bounds.
if [ -s "${BUILDKITE_ENV_PATH}" ]; then
  set -a
  # shellcheck disable=SC1090
  source "${BUILDKITE_ENV_PATH}"
  set +a

  if [ -z "${BUILDKITE_AGENT_TOKEN:-}" ] || [ -z "${BUILDKITE_AGENT_ACQUIRE_JOB:-}" ]; then
    echo "$(date -u +%FT%TZ) run-job: buildkite env staged but incomplete; aborting"
    exit 1
  fi

  # The hooks read their settings from here rather than from the
  # environment: the agent sanitizes the job environment, so what this
  # process exports does not necessarily reach a hook.
  export TUIST_RUNNER_JOB_ENV="${BUILDKITE_ENV_PATH}"
  export TUIST_RUNNER_STATE_DIR="${TUIST_RUNNER_STATE_DIR:-/tmp/tuist-runner}"
  mkdir -p "${TUIST_RUNNER_STATE_DIR}" 2>/dev/null || true

  if [ -x /usr/local/bin/vitals.sh ]; then
    /usr/local/bin/vitals.sh &
  fi

  echo "$(date -u +%FT%TZ) run-job: acquiring buildkite job ${BUILDKITE_AGENT_ACQUIRE_JOB}"
  exec /usr/local/bin/buildkite-agent start \
    --name "$(hostname)" \
    --hooks-path /usr/local/share/tuist/buildkite-hooks \
    --build-path "${TUIST_RUNNER_SHELL_WORKDIR:-/home/runner/work}" \
    --enable-job-log-tmpfile \
    --job-log-path "${TUIST_RUNNER_STATE_DIR}" \
    --disconnect-after-job
fi

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

# RUNNER_PERFLOG makes the Listener append a `MessageReceived_<type>` line to
# `<dir>/Runner.perf` the instant a message arrives from GitHub, before it
# acknowledges the assignment and before it fetches the job body. That is
# seconds ahead of Runner.Worker, and it is the earliest local evidence that
# this runner has been given work.
#
# The Listener's poll loop returns nothing on an idle timeout, so the file
# stays empty until GitHub actually routes something here. Only the two
# job-request message types count; a refresh or cancel message is not an
# assignment.
RUNNER_PERF_DIR=/home/runner/actions-runner/_perf
RUNNER_PERF_FILE="${RUNNER_PERF_DIR}/Runner.perf"
rm -rf "${RUNNER_PERF_DIR}"
export RUNNER_PERFLOG="${RUNNER_PERF_DIR}"
# 404/409/422 on the job fetch make the Listener skip the message and go back
# to waiting, so a received message does not always become a Worker. Bound how
# long the watchdog defers on one.
WORKER_GRACE_SECONDS=60
job_message_received() {
  grep -q 'MessageReceived_PipelineAgentJobRequest\|MessageReceived_RunnerJobRequest' \
    "${RUNNER_PERF_FILE}" 2>/dev/null
}

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
    # Both process-level latches trail the assignment. The Listener
    # acknowledges the job, fetches its body over HTTP and only then forks
    # Runner.Worker, with the job-started hook later still, so a check at the
    # deadline reads "idle" for a runner GitHub has already, irrevocably,
    # given work to. Killing it there marks that job failed rather than
    # re-queuing it, and GitHub then spends ten minutes waiting out the job's
    # lock before anyone learns it died.
    #
    # Deferring on the Listener's own record of the inbound message covers
    # that gap, because that record predates the acknowledgment rather than
    # trailing it. What stays exposed is the interval between the last read
    # and the signal below, not the fetch.
    worker_wait=0
    while :; do
      [ -e "${JOB_STARTED_MARKER}" ] && exit 0
      pgrep -f "Runner.Worker" >/dev/null 2>&1 && exit 0
      kill -0 "${runner_pid}" 2>/dev/null || exit 0
      job_message_received || break
      [ "${worker_wait}" -ge "${WORKER_GRACE_SECONDS}" ] && break
      sleep 1
      worker_wait=$((worker_wait + 1))
    done
    echo "$(date -u +%FT%TZ) run-job: no job assigned within ${idle_timeout}s; terminating idle runner"
    kill -TERM "${runner_pid}" 2>/dev/null || true
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
