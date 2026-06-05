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
echo "$(date -u +%FT%TZ) run-job: JIT staged, starting runner"
# Forensic vitals for this job's lifetime. Backgrounded so it
# survives the `exec` below and keeps sampling until the container
# (and microVM) dies; its last line before a mid-job death lands in
# the Pod logs, the only trail left once the VM is reaped. Guarded so
# a missing script (older image) never blocks the runner.
if [ -x /usr/local/bin/vitals.sh ]; then
  /usr/local/bin/vitals.sh &
fi
# Tail the actions/runner _diag/*.log files to stdout so the runner's
# own diagnostic output (Listener handshake, Worker job, retry/HTTP
# errors against the GitHub Actions service) lands in Loki. Without
# this, an exit-0 disconnect — runner agent decides it's done while
# GitHub stops seeing the heartbeat — leaves no record of why it
# stopped responding. See diag-tail.sh for the empirical justification.
if [ -x /usr/local/bin/diag-tail.sh ]; then
  /usr/local/bin/diag-tail.sh &
fi
exec ./run.sh --jitconfig "${jit}" --disableupdate
