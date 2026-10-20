#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
fixtures="$(mktemp -d)"
trap 'rm -rf "${fixtures}"' EXIT
export TUIST_RUNNER_DISPATCH_URL=https://tuist.example/api/internal/runners/dispatch
export JIT_OUTPUT_PATH="${fixtures}/jit"
export REAL_JQ="$(command -v jq)"
cat >"${fixtures}/dispatch.json" <<'JSON'
{"gitlab_job":{"url":"https://gitlab.example","payload":{"id":123,"token":"synthetic-job-token"},"report_token":"synthetic-report-token"},"cache_endpoint_url":"http://kura-local:4000"}
JSON

# Run the actual staging branches in an isolated filesystem with fake credentials.
{
  awk '/^stage_cache_endpoint\(\)/ {copying=1} copying && /^while true/ {exit} copying {print}' dispatch-poll.sh
  awk '/      if jq -e .*gitlab_job/ {copying=1} copying && /      jit=/ {exit} copying {print}' dispatch-poll.sh
} | sed "s|/tmp/dispatch.json|${fixtures}/dispatch.json|g" >"${fixtures}/linux-stage.sh"
bash -eu "${fixtures}/linux-stage.sh"
test "$(cat "${JIT_OUTPUT_PATH}.cache-endpoint")" = "http://kura-local:4000"
test "$(cat "${JIT_OUTPUT_PATH}")" = gitlab
jq -e '.report_url == "https://tuist.example/api/internal/runners/jobs" and .payload.token == "synthetic-job-token"' "${JIT_OUTPUT_PATH}.gitlab.json" >/dev/null

cat >"${fixtures}/executor" <<'SH'
#!/usr/bin/env bash
printf '%s' "${TUIST_CACHE_ENDPOINT-unset}" >"${TUIST_RUNNER_JIT_PATH}.observed-endpoint"
SH
chmod +x "${fixtures}/executor"
awk '/^BUILDKITE_ENV_PATH=/ {exit} {print}' run-job.sh |
  sed -e "s|/usr/local/bin/tuist-gitlab-runner|${fixtures}/executor|g" \
      -e "s|/usr/local/bin/vitals.sh|${fixtures}/no-vitals|g" >"${fixtures}/run.sh"
TUIST_RUNNER_JIT_PATH="${JIT_OUTPUT_PATH}" bash "${fixtures}/run.sh"
test "$(cat "${JIT_OUTPUT_PATH}.observed-endpoint")" = "http://kura-local:4000"
echo "ok: Linux stages the endpoint and the GitLab executor inherits it"

mkdir "${fixtures}/bin"
cat >"${fixtures}/bin/jq" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *--arg* ]]; then
  printf 'partial-synthetic-credential'
  exit 1
fi
exec "${REAL_JQ}" "$@"
SH
chmod +x "${fixtures}/bin/jq"
rm "${JIT_OUTPUT_PATH}" "${JIT_OUTPUT_PATH}.gitlab.json"
if PATH="${fixtures}/bin:${PATH}" bash -eu "${fixtures}/linux-stage.sh"; then
  echo "failed: Linux accepted a partial assignment" >&2
  exit 1
fi
test ! -e "${JIT_OUTPUT_PATH}.gitlab.json.tmp"
test ! -e "${JIT_OUTPUT_PATH}.gitlab.json"
test ! -e "${JIT_OUTPUT_PATH}"
echo "ok: Linux staging failure cleans credentials and never publishes the start marker"

awk '/      if ! gitlab_job=/ {copying=1} copying && /      jit=/ {exit} copying {print}' ../runner-image/dispatch-poll.sh |
  sed -e "s|/tmp/dispatch.json|${fixtures}/dispatch.json|g" \
      -e "s|/tmp/tuist-gitlab-job|${fixtures}/mac-job|g" >"${fixtures}/mac-stage.sh"
JQ="${REAL_JQ}" bash -eu "${fixtures}/mac-stage.sh"
test "$(find "${fixtures}" -name 'mac-job.json' -perm 0600 | wc -l | tr -d ' ')" = 1
jq -e '.payload.token == "synthetic-job-token"' "${fixtures}/mac-job.json" >/dev/null
rm "${fixtures}/mac-job.json"
if JQ="${fixtures}/bin/jq" bash -eu "${fixtures}/mac-stage.sh"; then
  echo "failed: macOS accepted a partial assignment" >&2
  exit 1
fi
test -z "$(find "${fixtures}" -name 'mac-job*')"
if JQ="${fixtures}/missing-jq" bash -eu "${fixtures}/mac-stage.sh"; then
  echo "failed: macOS ignored its missing JSON parser" >&2
  exit 1
fi
echo "ok: macOS publishes private JSON atomically and fails closed without leftover credentials"
