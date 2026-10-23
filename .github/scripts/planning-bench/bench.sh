#!/usr/bin/env bash
# Builds the generated fixture under several compilation-cache configurations
# on one VM, interleaved over ROUNDS rounds, and reports the summed and mean
# duration of the SwiftDriver rule ("Planning Swift module") from xcodebuild's
# build timing summary.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
work="${RUNNER_TEMP:-/tmp}/planning-bench"
out="${work}/out"
project="${work}/project"
vol="${TUIST_COMPILATION_CACHE_CAS_PATH:?the xcode-cache volume is not attached}"
local_cas="${HOME}/planning-bench-cas"
variants="${VARIANTS:-off vol_plugin local_plugin vol_builtin local_builtin vol_noproxy vol_plugin_sync}"
rounds="${ROUNDS:-2}"
results="${out}/results.tsv"

mkdir -p "${out}" "${local_cas}"
tuist="$(mise which tuist 2>/dev/null || command -v tuist)"

{
  echo "## Machine"
  sysctl -n machdep.cpu.brand_string hw.ncpu hw.memsize
  sw_vers
  xcodebuild -version
  echo "## Volume"
  df -h "${vol}" "${local_cas}"
  mount | grep -E "tuist|disk" || true
  diskutil info "$(df "${vol}" | awk 'NR == 2 { print $1 }')" 2>/dev/null | grep -E "Protocol|Device Location|File System|Solid|Virtual|Media Name" || true
  echo "## Env"
  env | grep -E '^(TUIST_|XCODE_XCCONFIG_FILE|GITHUB_RUN_ID)' | sed 's/TOKEN=.*/TOKEN=<redacted>/' | sort
  cat "${XCODE_XCCONFIG_FILE:-/dev/null}" 2>/dev/null
} > "${out}/machine.txt" 2>&1
cat "${out}/machine.txt"

SALT="${GITHUB_RUN_ID:-local}" bash "${here}/generate.sh" "${project}"
cd "${project}"
"${tuist}" setup cache > "${out}/setup.log" 2>&1 || { cat "${out}/setup.log"; exit 1; }
"${tuist}" generate --no-open > "${out}/generate.log" 2>&1 || { cat "${out}/generate.log"; exit 1; }

sampler() {
  local tag="$1"
  sleep 20
  for n in 1 2 3; do
    pid=$(pgrep -n SWBBuildService || true)
    [ -n "${pid}" ] && sample "${pid}" 5 -mayDie -file "${out}/sample-${tag}-${n}.txt" >/dev/null 2>&1
    sleep 10
  done
}

build() {
  local variant="$1" round="$2" tag="${1}-r${2}" dd="${work}/dd" cas settings=() envs=()
  case "${variant}" in
    off) cas="${vol}"; settings=(COMPILATION_CACHE_ENABLE_CACHING=NO) ;;
    vol_plugin) cas="${vol}" ;;
    local_plugin) cas="${local_cas}"; envs=(TUIST_CAS_DRAINED_STORE="${local_cas}") ;;
    vol_builtin) cas="${vol}"; settings=(COMPILATION_CACHE_ENABLE_PLUGIN=NO COMPILATION_CACHE_REMOTE_SERVICE_PATH=) ;;
    local_builtin) cas="${local_cas}"; settings=(COMPILATION_CACHE_ENABLE_PLUGIN=NO COMPILATION_CACHE_REMOTE_SERVICE_PATH=) ;;
    vol_noproxy) cas="${vol}"; envs=(TUIST_CAS_PROXY_SOCKET=/tmp/planning-bench-no-proxy.sock) ;;
    vol_plugin_sync) cas="${vol}"; envs=(TUIST_CAS_DRAINED_STORE=) ;;
    *) echo "unknown variant ${variant}"; return 1 ;;
  esac
  rm -rf "${dd}"
  local started ended status sampler_pid=""
  if [ "${round}" = "${rounds}" ]; then
    sampler "${tag}" &
    sampler_pid=$!
  fi
  started=$(date +%s)
  env ${envs[@]+"${envs[@]}"} xcodebuild build \
    -workspace Bench.xcworkspace -scheme App \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "${dd}" -showBuildTimingSummary \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
    COMPILATION_CACHE_CAS_PATH="${cas}" ${settings[@]+"${settings[@]}"} \
    > "${out}/build-${tag}.log" 2>&1
  status=$?
  ended=$(date +%s)
  [ -n "${sampler_pid}" ] && { kill "${sampler_pid}" 2>/dev/null; wait "${sampler_pid}" 2>/dev/null; }
  local driver count seconds hits
  driver=$(grep -E '^SwiftDriver \([0-9]+ tasks?\) \|' "${out}/build-${tag}.log" | tail -n 1)
  count=$(sed -nE 's/^SwiftDriver \(([0-9]+) tasks?\).*/\1/p' <<< "${driver}")
  seconds=$(sed -nE 's/.*\| *([0-9.]+) seconds.*/\1/p' <<< "${driver}")
  hits=$(grep -oE '[0-9]+ hits / [0-9]+ cacheable tasks' "${out}/build-${tag}.log" | tail -n 1)
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${variant}" "${round}" "${status}" "$((ended - started))" \
    "${count:-?}" "${seconds:-?}" \
    "$(awk -v s="${seconds:-0}" -v c="${count:-0}" 'BEGIN { if (c > 0) printf "%.3f", s / c; else print "?" }')" \
    "${hits:-none}" | tee -a "${results}"
  if [ "${status}" -ne 0 ]; then
    grep -E "error:" "${out}/build-${tag}.log" | head -n 20
  fi
}

printf 'variant\tround\texit\twall_s\tdriver_tasks\tdriver_s\tdriver_mean_s\thits\n' | tee "${results}"
for round in $(seq 1 "${rounds}"); do
  for variant in ${variants}; do
    build "${variant}" "${round}"
  done
done

state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/tuist"
cp "${state_dir}/cas.log" "${out}/cas.log" 2>/dev/null || true
du -sh "${vol}"/* "${local_cas}"/* > "${out}/stores.txt" 2>&1 || true

{
  echo "### Planning (SwiftDriver) per configuration"
  echo
  echo '| variant | round | exit | wall s | planning tasks | planning s (summed) | s / task | cache |'
  echo '| --- | --- | --- | --- | --- | --- | --- | --- |'
  tail -n +2 "${results}" | awk -F'\t' '{ printf "| %s | %s | %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6, $7, $8 }'
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
