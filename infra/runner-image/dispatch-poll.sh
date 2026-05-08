#!/bin/bash
# Polls the Tuist server's runner dispatch endpoint until it
# returns a JIT config, then execs the GitHub Actions runner.
#
# Env (sourced from /etc/tuist.env, populated by inject-env.sh):
#   TUIST_RUNNER_DISPATCH_URL   — full URL of the dispatch endpoint
#   TUIST_RUNNER_POD_UID        — Pod UID (k8s downward API)
#   TUIST_RUNNER_DISPATCH_TOKEN — per-Pod random token
#
# Server contract:
#   GET <url>?pod_uid=<uid>&token=<tok>
#     204 No Content        -> Pod still idle, sleep + retry
#     200 with body         -> { encoded_jit_config: "...", ... }
#     401                   -> token mismatch / unknown pod, abort
#     5xx                   -> transient; sleep + retry
#
# Once 200 is observed we exec ./run.sh with --jitconfig. JIT
# runners auto-register, run a single job, and exit. Pod
# transitions to Completed and tart-kubelet GCs the VM.

set -euo pipefail

LOG=/var/log/tuist-runner/poll.log
exec >>"${LOG}" 2>&1

if [ ! -f /etc/tuist.env ]; then
  echo "$(date -u +%FT%TZ) dispatch-poll: /etc/tuist.env missing; aborting"
  exit 1
fi
# shellcheck disable=SC1091
source /etc/tuist.env

: "${TUIST_RUNNER_DISPATCH_URL:?TUIST_RUNNER_DISPATCH_URL not set}"
: "${TUIST_RUNNER_POD_UID:?TUIST_RUNNER_POD_UID not set}"
: "${TUIST_RUNNER_DISPATCH_TOKEN:?TUIST_RUNNER_DISPATCH_TOKEN not set}"

interval=5
attempt=0

while true; do
  attempt=$((attempt + 1))
  http=$(curl -fsS -o /tmp/dispatch.json -w '%{http_code}' \
    --max-time 10 \
    --get \
    --data-urlencode "pod_uid=${TUIST_RUNNER_POD_UID}" \
    --data-urlencode "token=${TUIST_RUNNER_DISPATCH_TOKEN}" \
    "${TUIST_RUNNER_DISPATCH_URL}" || echo "000")

  case "${http}" in
    204)
      # Idle. Don't log every tick — the file would balloon.
      [ $((attempt % 12)) -eq 0 ] && echo "$(date -u +%FT%TZ) dispatch-poll: still idle (attempt=${attempt})"
      sleep "${interval}"
      ;;
    200)
      jit=$(/usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["encoded_jit_config"])' < /tmp/dispatch.json)
      if [ -z "${jit}" ]; then
        echo "$(date -u +%FT%TZ) dispatch-poll: 200 but empty encoded_jit_config; retrying"
        sleep "${interval}"
        continue
      fi
      echo "$(date -u +%FT%TZ) dispatch-poll: dispatched, starting runner"
      cd /opt/actions-runner
      # `--jitconfig` implies ephemeral: the runner accepts one
      # job and exits. We then halt the VM so `tart run` returns,
      # tart-kubelet observes the exit, the Pod transitions to
      # Succeeded, and the watcher reconciles a fresh warm Pod
      # into its place. Without the explicit shutdown the VM
      # would idle indefinitely with launchd's wrapper exited but
      # macOS still up — `kubectl get pods` would keep showing
      # Running and the warm pool would never refill.
      ./run.sh --jitconfig "${jit}"
      rc=$?
      echo "$(date -u +%FT%TZ) dispatch-poll: runner exited with code ${rc}; shutting down VM"
      /sbin/shutdown -h now
      exit "${rc}"
      ;;
    401)
      echo "$(date -u +%FT%TZ) dispatch-poll: 401 unauthorized; aborting"
      exit 1
      ;;
    *)
      echo "$(date -u +%FT%TZ) dispatch-poll: HTTP ${http} (attempt=${attempt}); retrying"
      sleep "${interval}"
      ;;
  esac
done
