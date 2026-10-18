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

# Sets hits and cacheable from xcodebuild's own summary line.
build() {
  local name="$1" started
  started=$(date +%s)
  if ! xcodebuild build \
    -workspace RunnersAcceptance.xcworkspace \
    -scheme Feature \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "${work}/derived-data" \
    COMPILATION_CACHE_CAS_PATH="${work}/cas-${name}" \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
    > "${work}/${name}.log" 2>&1; then
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
    pass "Rebuild from an empty local CAS: ${hits} hits / ${cacheable} cacheable tasks (attempt ${attempt})"
    exit 0
  fi
  if [ "$(date +%s)" -ge "${deadline}" ] || [ "${attempt}" -ge 4 ]; then
    fail "Cache hits" "the rebuild from an empty local CAS got ${hits} hits / ${cacheable} cacheable tasks after ${attempt} attempts; every task should have been served by ${TUIST_CACHE_ENDPOINT:-the server-resolved cache}"
  fi
  sleep 10
done
