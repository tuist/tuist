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
# Idle-registration TTL watchdog. A JIT runner that registers with GitHub but
# is never assigned a job sits registered-idle — for hours — freezing whatever
# was staged at claim time (e.g. TUIST_CACHE_ENDPOINT). When
# TUIST_RUNNER_IDLE_TTL_SECONDS > 0, arm a background timer before exec: if no
# job has started within the TTL, SIGTERM the GitHub runner process so the Pod
# completes (exit) and the RunnerPoolReconciler replaces it with a fresh Pod
# that re-claims against the current server. The watchdog is disarmed the
# instant a job starts by ACTIONS_RUNNER_HOOK_JOB_STARTED (job-started-hook.sh),
# which kills it and drops the marker below — so an in-flight job is never
# interrupted. Unset/0/non-numeric leaves the runner behaving exactly as before.
IDLE_TTL=${TUIST_RUNNER_IDLE_TTL_SECONDS:-0}
case "${IDLE_TTL}" in '' | *[!0-9]*) IDLE_TTL=0 ;; esac
if [ "${IDLE_TTL}" -gt 0 ]; then
  export ACTIONS_RUNNER_HOOK_JOB_STARTED=/usr/local/bin/job-started-hook.sh
  idle_marker=/tmp/tuist-job-started
  idle_pidfile=/tmp/tuist-idle-watchdog.pid
  rm -f "${idle_marker}" "${idle_pidfile}"
  (
    sleep "${IDLE_TTL}"
    # A job started meanwhile — the hook created the marker (and killed us,
    # but re-check in case we woke in the same instant): nothing to recycle.
    [ -f "${idle_marker}" ] && exit 0
    echo "$(date -u +%FT%TZ) run-job: idle-registration TTL (${IDLE_TTL}s) exceeded with no job assigned, recycling"
    pkill -TERM -f 'Runner.Listener run' 2>/dev/null || true
  ) &
  echo $! >"${idle_pidfile}"
fi
# Forensic vitals for this job's lifetime. Backgrounded so it
# survives the `exec` below and keeps sampling until the container
# (and microVM) dies; its last line before a mid-job death lands in
# the Pod logs, the only trail left once the VM is reaped. Guarded so
# a missing script (older image) never blocks the runner.
if [ -x /usr/local/bin/vitals.sh ]; then
  /usr/local/bin/vitals.sh &
fi
exec ./run.sh --jitconfig "${jit}" --disableupdate
