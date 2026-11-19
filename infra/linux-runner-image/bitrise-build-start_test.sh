#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
hook="$(pwd)/bitrise-hooks/build-start"

cmp "${hook}" ../runner-image/bitrise-hooks/build-start
echo "ok: the macOS and Linux hooks are identical"

fixtures="$(mktemp -d)"
trap 'rm -rf "${fixtures}"' EXIT

# A curl stand-in records each request and answers with $CURL_STATUS.
mkdir -p "${fixtures}/bin"
cat >"${fixtures}/bin/curl" <<'CURL'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${CURL_CALLS}"
printf '%s' "${CURL_STATUS:-204}"
CURL
chmod +x "${fixtures}/bin/curl"
cat >"${fixtures}/bin/sleep" <<'SLEEP'
#!/usr/bin/env bash
exit 0
SLEEP
chmod +x "${fixtures}/bin/sleep"

export PATH="${fixtures}/bin:${PATH}"
export CURL_CALLS="${fixtures}/curl-calls"
export TUIST_RUNNER_JOB_ENV="${fixtures}/job.env"

cat >"${TUIST_RUNNER_JOB_ENV}" <<ENV
TUIST_RUNNER_REPORT_TOKEN=report-token
TUIST_RUNNER_REPORT_URL=https://tuist.example/api/internal/runners
TUIST_RUNNER_JOB_STARTED_MARKER=${fixtures}/job-started
TUIST_RUNNER_WATCHDOG_PID_FILE=${fixtures}/watchdog.pid
ENV

sleep_pid_file="${fixtures}/watchdog.pid"
/bin/sleep 30 &
watchdog=$!
printf '%s' "${watchdog}" >"${sleep_pid_file}"

BITRISE_BUILD_SLUG=b7a1c2 BITRISE_APP_SLUG=a9f3e4 bash "${hook}"
test -f "${fixtures}/job-started"
if kill -0 "${watchdog}" 2>/dev/null; then
  echo "the hook left the watchdog running" >&2
  exit 1
fi
grep -q -- '--header Authorization: Bearer report-token' "${CURL_CALLS}"
grep -q -- '{"build_slug":"b7a1c2","app_slug":"a9f3e4"}' "${CURL_CALLS}"
grep -q -- 'https://tuist.example/api/internal/runners/jobs/bitrise/started' "${CURL_CALLS}"
test "$(wc -l <"${CURL_CALLS}")" -eq 1
echo "ok: reports the build and latches the watchdog"

rm -f "${CURL_CALLS}"
CURL_STATUS=503 BITRISE_BUILD_SLUG=b7a1c2 BITRISE_APP_SLUG=a9f3e4 bash "${hook}"
test "$(wc -l <"${CURL_CALLS}")" -eq 5
echo "ok: retries a server error and still exits 0"

rm -f "${CURL_CALLS}"
CURL_STATUS=422 BITRISE_BUILD_SLUG=b7a1c2 BITRISE_APP_SLUG=a9f3e4 bash "${hook}"
test "$(wc -l <"${CURL_CALLS}")" -eq 1
echo "ok: does not retry a refused report"

rm -f "${CURL_CALLS}"
BITRISE_BUILD_SLUG='b7"a1' BITRISE_APP_SLUG=a9f3e4 bash "${hook}"
test ! -e "${CURL_CALLS}"
env -u BITRISE_BUILD_SLUG BITRISE_APP_SLUG=a9f3e4 bash "${hook}"
test ! -e "${CURL_CALLS}"
TUIST_RUNNER_JOB_ENV="${fixtures}/missing.env" BITRISE_BUILD_SLUG=b7a1c2 BITRISE_APP_SLUG=a9f3e4 bash "${hook}"
test ! -e "${CURL_CALLS}"
echo "ok: sends nothing without a valid build identity and credential, and exits 0"
