#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
fixtures="$(mktemp -d)"
trap 'rm -rf "${fixtures}"' EXIT

# Exercise the actual heredoc, including its two expansion phases,
# without starting a runner or touching its shared /tmp watchdog files.
awk '/^cat >"\$\{JOB_STARTED_HOOK\}" <<HOOK$/ { copying = 1 }
     copying { print }
     copying && /^HOOK$/ { exit }' run-job.sh > "${fixtures}/generate-hook.sh"
test -s "${fixtures}/generate-hook.sh"
export JOB_STARTED_HOOK="${fixtures}/job-started.sh"
export JOB_STARTED_MARKER="${fixtures}/job-started"
export WATCHDOG_PID_FILE="${fixtures}/watchdog.pid"
env -u GITHUB_ENV -u TUIST_CACHE_ENDPOINT bash -eu "${fixtures}/generate-hook.sh"
bash -n "${JOB_STARTED_HOOK}"

export GITHUB_ENV="${fixtures}/job env"
printf 'EXISTING_VALUE=preserved\n' > "${GITHUB_ENV}"
cp "${GITHUB_ENV}" "${fixtures}/expected"
env -u TUIST_CACHE_ENDPOINT bash -eu "${JOB_STARTED_HOOK}"
test -f "${JOB_STARTED_MARKER}"
cmp "${fixtures}/expected" "${GITHUB_ENV}"
echo "ok: a job without a cache endpoint preserves the environment"

export TUIST_CACHE_ENDPOINT="http://kura-test-eu.kura.svc.cluster.local:4000"
bash -eu "${JOB_STARTED_HOOK}"
printf 'TUIST_CACHE_ENDPOINT=%s\n' "${TUIST_CACHE_ENDPOINT}" >> "${fixtures}/expected"
cmp "${fixtures}/expected" "${GITHUB_ENV}"
echo "ok: the runtime endpoint is appended to the runtime environment file"

# An environment-file failure must not prevent the watchdog latch or
# turn otherwise successful builds into failures.
rm "${JOB_STARTED_MARKER}"
GITHUB_ENV="${fixtures}/missing/env" bash -eu "${JOB_STARTED_HOOK}" > "${fixtures}/warning" 2>&1
test -f "${JOB_STARTED_MARKER}"
grep -q '::warning::Could not publish' "${fixtures}/warning"
echo "ok: a failed environment write is visible and leaves the job running"

export TUIST_CACHE_VOLUME_URL="http://runner-cache-volumes:8090"
export TUIST_CACHE_VOLUME_POD="pod-test"
export TUIST_CACHE_VOLUME_UID="uid-test"
: > "${GITHUB_ENV}"
bash -eu "${JOB_STARTED_HOOK}"
grep -qx "TUIST_CACHE_VOLUME_URL=${TUIST_CACHE_VOLUME_URL}" "${GITHUB_ENV}"
grep -qx "TUIST_CACHE_VOLUME_POD=${TUIST_CACHE_VOLUME_POD}" "${GITHUB_ENV}"
grep -qx "TUIST_CACHE_VOLUME_UID=${TUIST_CACHE_VOLUME_UID}" "${GITHUB_ENV}"
echo "ok: cache-volume settings reach container job steps"

# Replay the actual Buildkite staging block, then source the global hook with
# a sanitized environment just as buildkite-agent does.
awk '/^  BUILDKITE_JOB_ENV_PATH=\$\(mktemp/ { copying = 1 }
     copying { print }
     copying && /^  done$/ { exit }' run-job.sh > "${fixtures}/stage-volume-env.sh"
export BUILDKITE_ENV_PATH="${fixtures}/buildkite-env"
printf 'export EXISTING_BUILD_SETTING=preserved\n' > "${BUILDKITE_ENV_PATH}"
chmod 0444 "${BUILDKITE_ENV_PATH}"
export TMPDIR="${fixtures}"
source "${fixtures}/stage-volume-env.sh"
test "$(wc -l < "${BUILDKITE_ENV_PATH}" | tr -d ' ')" = 1
env -i PATH="$PATH" TUIST_RUNNER_JOB_ENV="${BUILDKITE_JOB_ENV_PATH}" TUIST_RUNNER_STATE_DIR="${fixtures}/state" \
  bash -ec 'source buildkite-hooks/environment; test "$EXISTING_BUILD_SETTING" = preserved; test "$TUIST_CACHE_VOLUME_URL" = "http://runner-cache-volumes:8090"; test "$TUIST_CACHE_VOLUME_POD" = "pod-test"; test "$TUIST_CACHE_VOLUME_UID" = "uid-test"'
echo "ok: Buildkite restores cache-volume routing after environment sanitization"
