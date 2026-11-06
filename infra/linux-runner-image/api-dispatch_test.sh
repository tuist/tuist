#!/usr/bin/env bash
# Exercises the API job staging branches of both images' poll scripts and the
# Linux run-job.sh branch, with a synthetic job and a fake executor.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
fixtures="$(mktemp -d)"
trap 'rm -rf "${fixtures}"' EXIT
export TUIST_RUNNER_DISPATCH_URL=https://tuist.example/api/internal/runners/dispatch
export JIT_OUTPUT_PATH="${fixtures}/jit"
cat >"${fixtures}/dispatch.json" <<'JSON'
{"api_job":{"workflow_job_id":4000000000000001,"script":"echo hi","report_token":"synthetic-report-token","clone_token":"synthetic-clone-token"},"cache_endpoint_url":"http://kura-local:4000"}
JSON

{
  awk '/^stage_cache_endpoint\(\)/ {copying=1} copying && /^while true/ {exit} copying {print}' dispatch-poll.sh
  awk '/      if jq -e .*api_job/ {copying=1} copying && /      if jq -e .*gitlab_job/ {exit} copying {print}' dispatch-poll.sh
} | sed "s|/tmp/dispatch.json|${fixtures}/dispatch.json|g" >"${fixtures}/linux-stage.sh"
bash -eu "${fixtures}/linux-stage.sh"
test "$(cat "${JIT_OUTPUT_PATH}")" = api
test "$(cat "${JIT_OUTPUT_PATH}.cache-endpoint")" = "http://kura-local:4000"
jq -e '.report_url == "https://tuist.example/api/internal/runners/jobs" and .clone_token == "synthetic-clone-token"' \
  "${JIT_OUTPUT_PATH}.api-job.json" >/dev/null
echo "ok: Linux stages the API job with its report URL and the start marker"

cat >"${fixtures}/executor" <<'SH'
#!/usr/bin/env bash
printf '%s %s' "$*" "${TUIST_CACHE_ENDPOINT-unset}" >"${TUIST_RUNNER_JIT_PATH}.observed"
SH
chmod +x "${fixtures}/executor"
awk '/^if \[ -s "\$\{JIT_PATH\}.gitlab.json" \]/ {exit} {print}' run-job.sh |
  sed -e "s|/usr/local/bin/tuist-job-runner|${fixtures}/executor|g" \
      -e "s|/usr/local/bin/vitals.sh|${fixtures}/no-vitals|g" >"${fixtures}/run.sh"
TUIST_RUNNER_JIT_PATH="${JIT_OUTPUT_PATH}" bash "${fixtures}/run.sh"
grep -q -- "--job-file ${JIT_OUTPUT_PATH}.api-job.json" "${JIT_OUTPUT_PATH}.observed"
grep -q "http://kura-local:4000" "${JIT_OUTPUT_PATH}.observed"
echo "ok: run-job.sh hands the staged job to the executor with the cache endpoint"

awk '/      if ! api_job=/ {copying=1} copying && /      jit=/ {exit} copying {print}' ../runner-image/dispatch-poll.sh |
  sed -e "s|/tmp/dispatch.json|${fixtures}/dispatch.json|g" \
      -e "s|/tmp/tuist-api-job|${fixtures}/mac-job|g" >"${fixtures}/mac-stage.sh"
JQ="$(command -v jq)" bash -eu "${fixtures}/mac-stage.sh"
test "$(find "${fixtures}" -name 'mac-job.json' -perm 0600 | wc -l | tr -d ' ')" = 1
jq -e '.report_url == "https://tuist.example/api/internal/runners/jobs"' "${fixtures}/mac-job.json" >/dev/null
rm "${fixtures}/mac-job.json"
if JQ="${fixtures}/missing-jq" bash -eu "${fixtures}/mac-stage.sh"; then
  echo "failed: macOS ignored its missing JSON parser" >&2
  exit 1
fi
test -z "$(find "${fixtures}" -name 'mac-job*')"
echo "ok: macOS stages the API job as private JSON and fails closed"
