#!/usr/bin/env bash
# POSTs to the Tuist server's runner dispatch endpoint with the
# Pod's projected ServiceAccount token as Bearer to claim a job and
# obtain its JIT runner config.
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
# Runs in the `poller` init container — the only container that
# holds the SA token. On a claim it writes the minted JIT to
# TUIST_RUNNER_JIT_OUTPUT_PATH and exits 0; the sibling `runner`
# main container (no token) then reads it via run-job.sh and runs
# the one job, so untrusted workflow code never shares a container
# with the token.
#
# If TUIST_RUNNER_JIT_OUTPUT_PATH is unset, it execs ./run.sh in
# this same container instead. That branch is purely a rollout
# bridge: the runner image and the controller ship as independent
# artifacts, so during the (image-first) cutover a not-yet-upgraded
# controller runs this image as a single container with the env
# unset. Delete it once the split controller is live in every env.
#
# Server contract (matches the macOS image):
#   POST <url>
#     200 with { encoded_jit_config, pool, owner }
#       → stage the JIT for the runner container, exit 0
#       → (env unset) exec ./run.sh --jitconfig <jit> --disableupdate
#         (single job, ephemeral, no auto-upgrade)
#     204 → no work; sleep + retry
#     401/403 → auth failed; abort (the SA is GC'd or invalid)
#     410 → stale image; exit 0 without staging a JIT so the Pod
#           completes and the reconciler replaces it on the current
#           image
#     5xx / transport error → transient; sleep + retry

set -uo pipefail

: "${TUIST_RUNNER_DISPATCH_URL:?TUIST_RUNNER_DISPATCH_URL not set}"

# When set (the split Pod shape), the minted JIT is written here and
# this script never execs the runner — that's the sibling runner
# container's job. Unset falls back to exec'ing the runner in place
# (the rollout bridge described above).
JIT_OUTPUT_PATH=${TUIST_RUNNER_JIT_OUTPUT_PATH:-}

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
      if [ -n "${JIT_OUTPUT_PATH}" ]; then
        # Stage the JIT for the sibling runner container and exit.
        # Write to a temp file + atomic rename so a partial write can
        # never be observed, and chmod 0644 so the non-root runner
        # user can read it regardless of this container's umask (the
        # JIT is the runner's own job credential, so in-Pod
        # readability is intended).
        #
        # Fail closed: the job is already claimed server-side at this
        # point, so a silent staging failure would strand it until
        # orphan recovery (~5 min). This script runs without errexit,
        # so check the write chain explicitly — on any failure, drop
        # the temp file and exit non-zero so the Pod fails visibly
        # instead of starting a runner with no JIT.
        tmp="${JIT_OUTPUT_PATH}.tmp"
        if ! { printf '%s' "${jit}" >"${tmp}" && chmod 0644 "${tmp}" && mv -f "${tmp}" "${JIT_OUTPUT_PATH}"; }; then
          rm -f "${tmp}" 2>/dev/null || true
          echo "$(date -u +%FT%TZ) dispatch-poll: failed to stage JIT to ${JIT_OUTPUT_PATH}; aborting"
          exit 1
        fi
        echo "$(date -u +%FT%TZ) dispatch-poll: claimed, JIT staged for runner container"
        exit 0
      fi
      echo "$(date -u +%FT%TZ) dispatch-poll: dispatched, starting runner"
      # Forensic vitals (rollout-bridge single-container mode only; the
      # split Pod shape runs vitals from run-job.sh). Backgrounded so it
      # survives the exec and its last sample before a mid-job death
      # lands in the Pod logs. Guarded so a missing script never blocks.
      if [ -x /usr/local/bin/vitals.sh ]; then
        /usr/local/bin/vitals.sh &
      fi
      # `--jitconfig` makes the runner ephemeral (one job + exit).
      # `--disableupdate` pins to whatever runner version is baked
      # into the image; Renovate bumps RUNNER_VERSION in the
      # Dockerfile when a new release is out, which the release
      # pipeline turns into a fresh image + digest bump in helm
      # values. Auto-update would silently swap the runner mid-Pod
      # and race with GitHub's deprecation cadence on cold boot.
      exec ./run.sh --jitconfig "${jit}" --disableupdate
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
