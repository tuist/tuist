#!/usr/bin/env bash
# Builds the generated fixture with the baseline and the fixed CAS plugin,
# interleaved, each from an empty local store against a remote cache a seed
# build filled, and reports the summed SwiftDriver ("Planning Swift module")
# time and the remote resolves each build made.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
work="${RUNNER_TEMP:-/tmp}/planning-ab"
out="${work}/out"
project="${work}/project"
dylibs="${DYLIBS:?directory with base/ and fix/ dylibs}"
rounds="${ROUNDS:-3}"
store_root="${STORE_ROOT:-${HOME}/planning-ab-cas}"
results="${out}/results.tsv"
mkdir -p "${out}" "${store_root}"
tuist="$(mise which tuist 2>/dev/null || command -v tuist)"

{
  sysctl -n machdep.cpu.brand_string hw.ncpu hw.memsize
  sw_vers
  xcodebuild -version
  df -h "${store_root}"
} > "${out}/machine.txt" 2>&1
cat "${out}/machine.txt"

FLAT="${FLAT:-1}" SALT="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}" bash "${here}/generate.sh" "${project}"
cd "${project}"
"${tuist}" setup cache > "${out}/setup.log" 2>&1 || { cat "${out}/setup.log"; exit 1; }
"${tuist}" generate --no-open > "${out}/generate.log" 2>&1 || { cat "${out}/generate.log"; exit 1; }

build() {
  local tag="$1" variant="$2" cas="${store_root}/${1}" dd="${work}/dd" log="${out}/plugin-${1}.log"
  rm -rf "${dd}" "${cas}"
  local started status
  started=$(date +%s)
  TUIST_CAS_LOG="${log}" TUIST_CAS_DRAINED_STORE="${store_root}" xcodebuild build \
    -workspace Bench.xcworkspace -scheme App \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "${dd}" -showBuildTimingSummary \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
    COMPILATION_CACHE_CAS_PATH="${cas}" \
    COMPILATION_CACHE_PLUGIN_PATH="${dylibs}/${variant}/libtuist_cas_plugin.dylib" \
    > "${out}/build-${tag}.log" 2>&1
  status=$?
  local wall=$(($(date +%s) - started)) driver count seconds hits
  driver=$(grep -E '^SwiftDriver \([0-9]+ tasks?\) \|' "${out}/build-${tag}.log" | tail -n 1)
  count=$(sed -nE 's/^SwiftDriver \(([0-9]+) tasks?\).*/\1/p' <<< "${driver}")
  seconds=$(sed -nE 's/.*\| *([0-9.]+) seconds.*/\1/p' <<< "${driver}")
  hits=$(grep -oE '[0-9]+ hits / [0-9]+ cacheable tasks' "${out}/build-${tag}.log" | tail -n 1)
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${tag}" "${variant}" "${status}" "${wall}" \
    "${count:-?}" "${seconds:-?}" \
    "$(cat "${log}" 2>/dev/null | grep -c 'DEBUG resolve globally=false')" \
    "$(cat "${log}" 2>/dev/null | grep -c 'DEBUG resolve globally=true')" \
    "${hits:-none}" | tee -a "${results}"
  [ "${status}" -eq 0 ] || grep -E "error:" "${out}/build-${tag}.log" | head -n 20
}

printf 'build\tplugin\texit\twall_s\tplanning_tasks\tplanning_s\tlocal_only_resolves\tglobal_resolves\thits\n' | tee "${results}"
build seed base
for _ in $(seq 1 60); do
  [ -z "$(find "${store_root}/seed" -path '*tuist-spool/*' -type f 2>/dev/null | head -n 1)" ] && break
  sleep 2
done
for round in $(seq 1 "${rounds}"); do
  build "base-${round}" base
  build "fix-${round}" fix
done

state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/tuist"
cp "${state_dir}/cas.log" "${out}/cas.log" 2>/dev/null || true

{
  echo "### Planning with the baseline and the fixed CAS plugin"
  echo
  echo '| build | plugin | exit | wall s | planning tasks | planning s (summed) | local-only remote resolves | global resolves | cache |'
  echo '| --- | --- | --- | --- | --- | --- | --- | --- | --- |'
  tail -n +2 "${results}" | awk -F'\t' '{ printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6, $7, $8, $9 }'
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
