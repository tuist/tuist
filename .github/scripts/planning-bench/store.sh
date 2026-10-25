#!/usr/bin/env bash
# Builds the generated fixture with the fixed CAS plugin from an empty local
# store and from a store an earlier build of the same commit left behind, and
# with compilation caching off, interleaved, each into a fresh DerivedData.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
work="${RUNNER_TEMP:-/tmp}/planning-store"
out="${work}/out"
project="${work}/project"
dylib="${DYLIBS:?directory with fix/}/fix/libtuist_cas_plugin.dylib"
rounds="${ROUNDS:-3}"
store_root="${STORE_ROOT:-${HOME}/planning-store-cas}"
results="${out}/results.tsv"
mkdir -p "${out}" "${store_root}"
tuist="$(mise which tuist 2>/dev/null || command -v tuist)"

FLAT="${FLAT:-1}" SALT="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}" bash "${here}/generate.sh" "${project}"
cd "${project}"
"${tuist}" setup cache > "${out}/setup.log" 2>&1 || { cat "${out}/setup.log"; exit 1; }
"${tuist}" generate --no-open > "${out}/generate.log" 2>&1 || { cat "${out}/generate.log"; exit 1; }

build() {
  local tag="$1" variant="$2" dd="${work}/dd" cas settings=()
  case "${variant}" in
    off) cas="${store_root}/off"; settings=(COMPILATION_CACHE_ENABLE_CACHING=NO) ;;
    cold) cas="${store_root}/cold-${tag}"; rm -rf "${cas}" ;;
    warm) cas="${store_root}/warm" ;;
  esac
  rm -rf "${dd}"
  local started status sampler=""
  if [ "${tag}" = "cold-2" ] || [ "${tag}" = "warm-2" ]; then
    (
      sleep 12
      pid=$(pgrep -n SWBBuildService) && sample "${pid}" 8 -mayDie -file "${out}/sample-${tag}.txt" >/dev/null 2>&1
    ) &
    sampler=$!
  fi
  started=$(date +%s)
  TUIST_CAS_LOG="${out}/plugin-${tag}.log" TUIST_CAS_DRAINED_STORE="${store_root}" xcodebuild build \
    -workspace Bench.xcworkspace -scheme App \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "${dd}" -showBuildTimingSummary \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
    COMPILATION_CACHE_CAS_PATH="${cas}" COMPILATION_CACHE_PLUGIN_PATH="${dylib}" \
    ${settings[@]+"${settings[@]}"} > "${out}/build-${tag}.log" 2>&1
  status=$?
  [ -z "${sampler}" ] || wait "${sampler}" 2>/dev/null
  local wall=$(($(date +%s) - started)) driver count seconds hits
  driver=$(grep -E '^SwiftDriver \([0-9]+ tasks?\) \|' "${out}/build-${tag}.log" | tail -n 1)
  count=$(sed -nE 's/^SwiftDriver \(([0-9]+) tasks?\).*/\1/p' <<< "${driver}")
  seconds=$(sed -nE 's/.*\| *([0-9.]+) seconds.*/\1/p' <<< "${driver}")
  hits=$(grep -oE '[0-9]+ hits / [0-9]+ cacheable tasks' "${out}/build-${tag}.log" | tail -n 1)
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${tag}" "${variant}" "${status}" "${wall}" \
    "${count:-?}" "${seconds:-?}" "${hits:-none}" | tee -a "${results}"
  [ "${status}" -eq 0 ] || grep -E "error:" "${out}/build-${tag}.log" | head -n 20
}

printf 'build\tstore\texit\twall_s\tplanning_tasks\tplanning_s\thits\n' | tee "${results}"
build seed warm
for _ in $(seq 1 60); do
  [ -z "$(find "${store_root}/warm" -path '*tuist-spool/*' -type f 2>/dev/null | head -n 1)" ] && break
  sleep 2
done
for round in $(seq 1 "${rounds}"); do
  build "off-${round}" off
  build "cold-${round}" cold
  build "warm-${round}" warm
done

{
  echo "### Planning from an empty and a warm local store"
  echo
  echo '| build | store | exit | wall s | planning tasks | planning s (summed) | cache |'
  echo '| --- | --- | --- | --- | --- | --- | --- |'
  tail -n +2 "${results}" | awk -F'\t' '{ printf "| %s | %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6, $7 }'
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
