#!/usr/bin/env bash
# POSTs to the Tuist server's runner dispatch endpoint with the
# Pod's projected ServiceAccount token as Bearer, and execs the
# actions/runner binary with the returned JIT config.
#
# This is the Linux analog of `infra/runner-image/dispatch-poll.sh`
# (the macOS Tart VM version). The Linux side is shorter for a few
# reasons:
#
#   * No EXIT trap to halt a VM — the container exits when this
#     script returns, kubelet observes the container exit, the
#     RunnerPool reconciler reaps the Pod + sibling SA, a fresh
#     Pod boots on the next reconcile.
#   * No /etc/tuist.env staging step — kubelet projects env vars
#     from the Pod spec straight into the container, no shared-mount
#     bridge required.
#   * No SA token copy — the projected token lives at the standard
#     in-cluster path the moment the container starts.
#
# Server contract (matches the macOS image):
#   POST <url>
#     200 with { encoded_jit_config, pool, owner }
#       → exec ./run.sh --jitconfig <jit> --disableupdate (single
#         job, ephemeral, no auto-upgrade)
#     204 → no work; sleep + retry
#     401/403 → auth failed; abort (the SA is GC'd or invalid)
#     5xx / transport error → transient; sleep + retry

set -uo pipefail

: "${TUIST_RUNNER_DISPATCH_URL:?TUIST_RUNNER_DISPATCH_URL not set}"

# Audience-scoped projected token (the controller wires this in via
# a projected volume with audience=tuist-runners-dispatch). Default
# automount is off on Linux runner Pods so this is the only token
# in the container. If a customer workflow exfiltrates the token,
# the apiserver accepts it ONLY against the dispatch audience — no
# replay against the Kubernetes API.
SA_TOKEN_PATH=${TUIST_RUNNER_SA_TOKEN_PATH:-/var/run/secrets/tuist-runner/token}
if [ ! -f "${SA_TOKEN_PATH}" ]; then
  echo "$(date -u +%FT%TZ) dispatch-poll: ${SA_TOKEN_PATH} missing; aborting"
  exit 1
fi
SA_TOKEN="$(cat "${SA_TOKEN_PATH}")"
if [ -z "${SA_TOKEN}" ]; then
  echo "$(date -u +%FT%TZ) dispatch-poll: SA token empty; aborting"
  exit 1
fi

# 2s interval matches the macOS image — close enough to "live" for
# customer dashboards without burning the dispatch endpoint. At
# this rate a warm pool of N Pods generates ~N/2 QPS server-side,
# which is negligible.
interval=2
attempt=0

while true; do
  attempt=$((attempt + 1))
  # `-f` intentionally omitted so 4xx/5xx land in $http instead of
  # being swallowed as transport errors. `|| http="000"` then only
  # fires on actual transport failure (DNS, TCP, TLS, timeout).
  http=$(curl -sS -o /tmp/dispatch.json -w '%{http_code}' \
    --max-time 10 \
    --request POST \
    --header "Authorization: Bearer ${SA_TOKEN}" \
    --header "Content-Type: application/json" \
    --data '{}' \
    "${TUIST_RUNNER_DISPATCH_URL}" 2>/dev/null) || http="000"

  case "${http}" in
    200)
      jit=$(jq -r '.encoded_jit_config // empty' /tmp/dispatch.json)
      if [ -z "${jit}" ]; then
        echo "$(date -u +%FT%TZ) dispatch-poll: 200 but empty encoded_jit_config; retrying"
        sleep "${interval}"
        continue
      fi
      # Per-job log token (see the macOS image for the rationale).
      # When present we tail the runner's Worker diag log through
      # tuist-log-tee to the server's log ingest endpoint.
      log_token=$(jq -r '.log_token // empty' /tmp/dispatch.json)
      logs_url="${TUIST_RUNNER_DISPATCH_URL%/dispatch}/logs"
      echo "$(date -u +%FT%TZ) dispatch-poll: dispatched, starting runner"
      # `--jitconfig` makes the runner ephemeral (one job + exit).
      # `--disableupdate` pins to whatever runner version is baked
      # into the image; Renovate bumps RUNNER_VERSION in the
      # Dockerfile when a new release is out, which the release
      # pipeline turns into a fresh image + digest bump in helm
      # values. Auto-update would silently swap the runner mid-Pod
      # and race with GitHub's deprecation cadence on cold boot.
      if [ -n "${log_token}" ] && command -v tuist-log-tee >/dev/null 2>&1; then
        # We tail the Worker diag log instead of piping run.sh's stdout.
        # The Listener (run.sh) only prints lifecycle markers
        # ("Listening for Jobs", "Running job:", "Job X completed"); the
        # Worker child process executes user steps and writes ALL step
        # output to `_diag/Worker_<utc>.log` rather than its own stdout.
        # Tailing the diag file is the only way to capture step content
        # without modifying GitHub's runner binary. The pipeline closes
        # naturally when we kill the tailer at run.sh exit, letting
        # tuist-log-tee flush its closing batch.
        ( for _ in $(seq 1 60); do
            wlog=$(ls -t "$(pwd)/_diag"/Worker_*.log 2>/dev/null | head -1)
            [ -n "${wlog}" ] && break
            sleep 1
          done
          [ -n "${wlog}" ] && exec tail -F -n +1 "${wlog}" 2>/dev/null \
            | tuist-log-tee --url "${logs_url}" --token "${log_token}"
        ) &
        tee_pid=$!
        ./run.sh --jitconfig "${jit}" --disableupdate
        rc=$?
        # Close the pipeline so tuist-log-tee sees EOF and flushes
        # the `done:true` batch before the container exits.
        kill -TERM "${tee_pid}" 2>/dev/null || true
        wait "${tee_pid}" 2>/dev/null || true
        exit "${rc}"
      else
        exec ./run.sh --jitconfig "${jit}" --disableupdate
      fi
      ;;
    204)
      # No work yet. Quiet log every 30th attempt (~once per
      # minute at 2s interval) so the container log doesn't
      # balloon on a warm Pod that's been idle for hours.
      [ $((attempt % 30)) -eq 0 ] && echo "$(date -u +%FT%TZ) dispatch-poll: warm standby (attempt=${attempt})"
      sleep "${interval}"
      ;;
    401|403)
      echo "$(date -u +%FT%TZ) dispatch-poll: ${http} unauthorized; aborting"
      exit 1
      ;;
    410)
      # Server tells us this Pod is on a stale image and should
      # exit so the RunnerPoolReconciler can replace it with one
      # carrying the current `runnerImage` digest. Exit clean (0)
      # so kubelet records Completed, not Failed — the controller
      # treats both as "drained, recreate" but Completed avoids
      # the misleading CrashLoopBackOff backoff window.
      echo "$(date -u +%FT%TZ) dispatch-poll: 410 stale image; exiting for replacement"
      exit 0
      ;;
    *)
      echo "$(date -u +%FT%TZ) dispatch-poll: HTTP ${http} (attempt=${attempt}); retrying"
      sleep "${interval}"
      ;;
  esac
done
