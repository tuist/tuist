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
echo "$(date -u +%FT%TZ) run-job: JIT staged, starting runner"
exec ./run.sh --jitconfig "${jit}" --disableupdate
