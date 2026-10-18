#!/usr/bin/env bash
# Builds the fixture twice through `tuist setup cache` and the Xcode
# compilation cache: once to publish, then again from an empty DerivedData and
# an empty local CAS, so every hit on the rebuild came over the network from
# the cache endpoint. The fixture is salted per run, so the rebuild can only
# hit what this run uploaded. A rebuild that is not fully served from the
# cache fails, as does any cache error the builds or the proxy logged.
#
# Env: TUIST_URL, and TUIST_CACHE_ENDPOINT when dispatch handed one.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

fixture="$(cd "$(dirname "$0")/project" && pwd)"
# Resolved inside the checkout: the project is copied out of it, where mise's
# shim no longer finds the repository's pinned version.
tuist="$(mise which tuist 2>/dev/null || command -v tuist)"
work="${RUNNER_TEMP:-$(mktemp -d)}/runners-acceptance"
rm -rf "${work}"
mkdir -p "${work}"
cp -R "${fixture}" "${work}/project"
cd "${work}/project"
printf 'public let salt = "%s-%s-%s-%s"\n' "${GITHUB_RUN_ID:-local}" "${GITHUB_RUN_ATTEMPT:-0}" \
  "${RUNNER_NAME:-$(hostname)}" "$(date +%s)" > Sources/Core/Salt.swift

"${tuist}" setup cache > "${work}/setup.log" 2>&1 || { cat "${work}/setup.log"; fail "Xcode cache setup" "tuist setup cache failed"; }
"${tuist}" generate --no-open > "${work}/generate.log" 2>&1 || { cat "${work}/generate.log"; fail "Xcode cache setup" "tuist generate failed"; }
pass "tuist setup cache started the cache proxy and tuist generate wired the fixture to it"

state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/tuist"

check_cache_errors() {
  local line
  line="$(cat "${work}"/*.log "${state_dir}/cas.log" 2>/dev/null | grep -m1 -E "${CACHE_ERROR_PATTERN}" || true)"
  [ -z "${line}" ] && return 0
  if echo "${line}" | grep -qE 'Authentication backend unavailable|backend_unavailable'; then
    fail "Kura auth" "the cache could not validate this job's token: ${line}"
  fi
  fail "Kura data path" "the build or the cache proxy logged a cache error: ${line}"
}

# Sets hits and cacheable from xcodebuild's own summary line. A healthy build of
# the project takes seconds, while a cache that answers nothing stalls every
# lookup wave for minutes before missing, so a build past BUILD_TIMEOUT_SECONDS
# is stopped and reported as a stall rather than waited out.
build() {
  local name="$1" started pid status
  started=$(date +%s)
  # The runner image points XCODE_XCCONFIG_FILE at a compilation cache store on
  # the job's cache volume, which outranks the per-build CAS path below and
  # would serve the rebuild locally.
  env -u XCODE_XCCONFIG_FILE xcodebuild build \
    -workspace RunnersAcceptance.xcworkspace \
    -scheme Feature \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "${work}/derived-data" \
    COMPILATION_CACHE_CAS_PATH="${work}/cas-${name}" \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
    > "${work}/${name}.log" 2>&1 &
  pid=$!
  while kill -0 "${pid}" 2>/dev/null; do
    if [ $(($(date +%s) - started)) -ge "${BUILD_TIMEOUT_SECONDS:-120}" ]; then
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
      tail -n 30 "${work}/${name}.log"
      tail -n 30 "${state_dir}/cas.log" 2>/dev/null || true
      check_cache_errors
      fail "Kura data path" "the ${name} build stalled for ${BUILD_TIMEOUT_SECONDS:-120}s, where a healthy one takes seconds; the cache at ${TUIST_CACHE_ENDPOINT:-the server-resolved endpoint} is not answering"
    fi
    sleep 2
  done
  status=0
  wait "${pid}" || status=$?
  if [ "${status}" -ne 0 ]; then
    tail -n 60 "${work}/${name}.log"
    check_cache_errors
    fail "Xcode build" "the ${name} build failed"
  fi
  echo "${name} build took $(($(date +%s) - started))s"
  read -r hits cacheable <<< "$(grep -oE '[0-9]+ hits / [0-9]+ cacheable tasks' "${work}/${name}.log" | tail -n 1 | awk '{print $1, $4}')"
}

build cold
[ -n "${cacheable:-}" ] || fail "Xcode cache setup" "xcodebuild printed no compilation cache summary, so caching is not enabled in the generated project"
[ "${cacheable}" -gt 0 ] || fail "Xcode cache setup" "the cold build had no cacheable tasks"
check_cache_errors
pass "Cold build: ${hits} hits / ${cacheable} cacheable tasks"

# The outputs uploaded last can trail an immediate rebuild by a moment, so a
# rebuild short of 100% is retried within a bound before it counts as a miss.
deadline=$(($(date +%s) + 180))
attempt=0
while :; do
  attempt=$((attempt + 1))
  rm -rf "${work}/derived-data"
  build "warm-${attempt}"
  check_cache_errors
  [ -n "${cacheable:-}" ] || fail "Xcode cache setup" "the rebuild printed no compilation cache summary"
  if [ "${cacheable}" -gt 0 ] && [ "${hits}" = "${cacheable}" ]; then
    # The proxy logs its counters every ten seconds.
    for _ in $(seq 1 15); do
      remote_hits="$(grep -F "proxy stats: ${work}/cas-warm-${attempt}/" "${state_dir}/cas.log" 2>/dev/null | sed -n 's/.* remote_hits=\([0-9]*\).*/\1/p' | sort -n | tail -n 1 || true)"
      [ "${remote_hits:-0}" -gt 0 ] && break
      sleep 2
    done
    [ "${remote_hits:-0}" -gt 0 ] || grep "proxy stats" "${state_dir}/cas.log" 2>/dev/null | tail -n 5 || true
    [ "${remote_hits:-0}" -gt 0 ] || fail "Cache hits" "the rebuild reported ${hits} hits but the cache proxy fetched none of them from ${TUIST_CACHE_ENDPOINT:-the server-resolved cache} (remote_hits=${remote_hits:-unknown}), so they were served locally"
    pass "Rebuild from an empty local CAS: ${hits} hits / ${cacheable} cacheable tasks, ${remote_hits} fetched from the remote cache (attempt ${attempt})"
    exit 0
  fi
  if [ "$(date +%s)" -ge "${deadline}" ] || [ "${attempt}" -ge 4 ]; then
    fail "Cache hits" "the rebuild from an empty local CAS got ${hits} hits / ${cacheable} cacheable tasks after ${attempt} attempts; every task should have been served by ${TUIST_CACHE_ENDPOINT:-the server-resolved cache}"
  fi
  sleep 10
done
