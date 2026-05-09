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

set -uo pipefail

LOG=/var/log/tuist-runner/poll.log
exec >>"${LOG}" 2>&1

# Always halt the VM on script exit. tart-kubelet observes `tart run`
# exiting and transitions the Pod to a terminal phase; without this
# trap a non-zero `./run.sh` (errexit), an early `exit 1` (401 abort,
# missing /etc/tuist.env, etc.), or any other failure path would
# leave macOS up, the Pod stuck Running, and the warm pool never
# refilling. The trap fires once on EXIT so the happy path
# (clean ./run.sh exit) and every error path halt the VM the
# same way.
trap '_rc=$?; echo "$(date -u +%FT%TZ) dispatch-poll: exiting (rc=${_rc}); halting VM"; /sbin/shutdown -h now || true; exit "${_rc}"' EXIT

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
      # `--jitconfig` implies ephemeral: the runner accepts one job
      # and exits. `--disableupdate` pins the runner to whatever
      # version is baked into the image; we bump that via Renovate
      # PRs against `runner_version` in runner.pkr.hcl, which the
      # release-runner-image flow turns into a fresh image + digest
      # bump. Auto-update would self-upgrade the runner mid-VM, which
      # is opaque (the version that ran a job isn't the version we
      # baked in) and can race with GitHub's deprecation message on
      # cold boot. The EXIT trap above halts the VM regardless of
      # rc — the trap is what tart-kubelet ultimately observes, so
      # both clean and crash paths refill the warm pool the same way.
      ./run.sh --jitconfig "${jit}" --disableupdate
      exit $?
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
