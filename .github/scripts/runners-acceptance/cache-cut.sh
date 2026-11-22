#!/usr/bin/env bash
# What a build does when its cache endpoint dies mid-job. A cold build
# publishes the salted fixture through `tuist setup cache` while the endpoint
# works; then a rebuild from an empty DerivedData and local CAS starts, and a
# few seconds in, a pf rule inside this job's own VM drops every packet to the
# endpoint's address, the way a dead inter-rack path looks to the client.
# Nothing outside the VM changes: the rule lives in the guest's pf, which only
# this job's traffic crosses, and the VM is discarded with the job.
#
# The job records how the rebuild ends (completes with local misses, fails, or
# stalls past CUT_BUILD_TIMEOUT_SECONDS), then lifts the rule and rebuilds once
# more to show the cache proxy recovers without restarting.
#
# Env: TUIST_URL, TUIST_CACHE_ENDPOINT, CUT_AFTER_SECONDS (default 1),
# CUT_BUILD_TIMEOUT_SECONDS (default 600).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

endpoint="${TUIST_CACHE_ENDPOINT:-}"
[ -n "${endpoint}" ] || fail "Cache cut" "dispatch handed this job no cache endpoint"
host="$(cache_endpoint_host "${endpoint}")"
address="$(dscacheutil -q host -a name "${host}" | awk '/^ip_address:/{print $2; exit}')"
[ -n "${address}" ] || fail "Cache cut" "${host} does not resolve"
sudo -n true 2>/dev/null || fail "Cache cut" "the guest user has no passwordless sudo, so the job cannot cut its own path; nothing was changed"
echo "endpoint ${endpoint} (${host} -> ${address})"

fixture="$(cd "$(dirname "$0")/project" && pwd)"
tuist="$(mise which tuist 2>/dev/null || command -v tuist)"
work="${RUNNER_TEMP:-$(mktemp -d)}/cache-cut"
rm -rf "${work}"
mkdir -p "${work}"
cp -R "${fixture}" "${work}/project"
cd "${work}/project"
printf 'public let salt = "cut-%s-%s-%s"\n' "${GITHUB_RUN_ID:-local}" "${GITHUB_RUN_ATTEMPT:-0}" "$(date +%s)" > Sources/Core/Salt.swift
"${tuist}" setup cache > "${work}/setup.log" 2>&1 || { cat "${work}/setup.log"; fail "Cache cut" "tuist setup cache failed"; }
"${tuist}" generate --no-open > "${work}/generate.log" 2>&1 || { cat "${work}/generate.log"; fail "Cache cut" "tuist generate failed"; }
state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/tuist"

anchor="com.apple/tuist.cache-cut"
pf_token=""
cut() {
  echo "block drop quick proto tcp from any to ${address} port 443" | sudo -n pfctl -a "${anchor}" -f - 2>/dev/null
  pf_token="$(sudo -n pfctl -E 2>&1 | sed -n 's/^Token : //p')"
  # Connections already open keep passing on their pf state, so drop those too.
  sudo -n pfctl -k 0.0.0.0/0 -k "${address}" >/dev/null 2>&1 || true
  sudo -n pfctl -a "${anchor}" -s rules
  cas_log_mark="$(wc -l < "${state_dir}/cas.log" 2>/dev/null || echo 0)"
  echo "cut: $(date -u +%T) dropping tcp to ${address}:443 inside this VM"
}
restore() {
  sudo -n pfctl -a "${anchor}" -F all >/dev/null 2>&1 || true
  [ -z "${pf_token}" ] || sudo -n pfctl -X "${pf_token}" >/dev/null 2>&1 || true
  pf_token=""
}
trap restore EXIT

# Builds in the background and sets outcome to completed, failed, or stalled.
# cut_after, when set, cuts the path that many seconds into the build.
build() {
  local name="$1" cut_after="${2:-}" limit="${3:-120}" started pid rc=0
  started=$(date +%s)
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
  outcome=""
  while kill -0 "${pid}" 2>/dev/null; do
    elapsed=$(($(date +%s) - started))
    if [ -n "${cut_after}" ] && [ "${elapsed}" -ge "${cut_after}" ]; then
      cut
      cut_after=""
    fi
    if [ "${elapsed}" -ge "${limit}" ]; then
      kill "${pid}" 2>/dev/null || true
      outcome=stalled
      break
    fi
    sleep 1
  done
  wait "${pid}" || rc=$?
  [ -n "${outcome}" ] || { [ "${rc}" -eq 0 ] && outcome=completed || outcome=failed; }
  seconds=$(($(date +%s) - started))
  summary="$(grep -oE '[0-9]+ hits / [0-9]+ cacheable tasks' "${work}/${name}.log" | tail -n 1 || true)"
  pass "${name}: ${outcome} in ${seconds}s, ${summary:-no cache summary} (xcodebuild exit ${rc})"
}

build cold "" 120
[ "${outcome}" = completed ] || { tail -n 40 "${work}/cold.log"; fail "Cache cut" "the cold build ${outcome} before anything was cut"; }

rm -rf "${work}/derived-data"
build cut "${CUT_AFTER_SECONDS:-1}" "${CUT_BUILD_TIMEOUT_SECONDS:-600}"
cut_outcome="${outcome}"
echo "--- rebuild log tail"; tail -n 40 "${work}/cut.log"
sleep 12
echo "--- what the cache proxy logged after the cut"
tail -n +"$((${cas_log_mark:-0} + 1))" "${state_dir}/cas.log" 2>/dev/null | grep -v "^\s*$" | tail -n 40 || true
echo "--- proxy counters per build store (remote_hits went over the network)"
grep -hF "proxy stats: ${work}/cas-" "${state_dir}/cas.log" 2>/dev/null | sed "s|${work}/||" | awk -F"proxy stats: " "{split(\$2,a,\"/\"); last[a[1]]=\$0} END {for (s in last) print last[s]}" || true

restore
rm -rf "${work}/derived-data"
build restored "" 180
restored_outcome="${outcome}"
sleep 12
grep -hF "proxy stats: ${work}/cas-restored/" "${state_dir}/cas.log" 2>/dev/null | tail -n 1 || true

[ "${cut_outcome}" = completed ] || fail "Cache cut" "with its cache endpoint cut mid-build, the rebuild ${cut_outcome} instead of finishing locally"
[ "${restored_outcome}" = completed ] || fail "Cache cut" "after the path came back, the next build ${restored_outcome}"
pass "The build survived its cache endpoint dying mid-job, and the next build ran against the restored endpoint"
