#!/usr/bin/env bash
#MISE description="Benchmark SwiftPM resolution against swifterpm on real repositories and pinned fixtures"
#USAGE flag "--runs <runs>" help="Number of hyperfine runs per benchmark" default="3"
#USAGE flag "--output-dir <output-dir>" help="Directory where benchmark reports are written" default="benchmark-results"
#USAGE flag "--swifterpm-bin <swifterpm-bin>" help="Path to a swifterpm executable. Defaults to bazel-bin/swifterpm"
#USAGE flag "--tuist-source <tuist-source>" help="Path to a local Tuist checkout to use instead of cloning tuist/tuist"
set -euo pipefail

runs="3"
output_dir="benchmark-results"
swifterpm_bin=""
tuist_source=""

while (($# > 0)); do
  case "$1" in
    --runs)
      runs="$2"
      shift 2
      ;;
    --output-dir)
      output_dir="$2"
      shift 2
      ;;
    --swifterpm-bin)
      swifterpm_bin="$2"
      shift 2
      ;;
    --tuist-source)
      tuist_source="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

for tool in bazel git hyperfine swift; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "${tool} is required" >&2
    exit 1
  fi
done

if [[ -z "${swifterpm_bin}" ]]; then
  bazel build //:swifterpm
  swifterpm_bin="${PWD}/bazel-bin/swifterpm"
fi

if [[ ! -x "${swifterpm_bin}" ]]; then
  echo "swifterpm executable not found or not executable: ${swifterpm_bin}" >&2
  exit 1
fi

quote() {
  printf "%q" "$1"
}

copy_tree() {
  local source="$1"
  local destination="$2"
  rm -rf "${destination}"
  mkdir -p "$(dirname "${destination}")"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude ".git/" \
      --exclude ".build/" \
      --exclude "Derived/" \
      --exclude "node_modules/" \
      "${source}/" "${destination}/"
  else
    cp -R "${source}" "${destination}"
    rm -rf \
      "${destination}/.git" \
      "${destination}/.build" \
      "${destination}/Derived" \
      "${destination}/node_modules"
  fi
}

append_percentage_summary() {
  local json_path="$1"

  swift - "${json_path}" <<'SWIFT'
import Foundation

let jsonPath = CommandLine.arguments[1]
let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
let results = root?["results"] as? [[String: Any]] ?? []

guard results.count >= 2,
      let swiftMean = results[0]["mean"] as? Double,
      let swifterpmMean = results[1]["mean"] as? Double,
      swiftMean > 0,
      swifterpmMean > 0 else {
    exit(0)
}

let reduction = ((swiftMean - swifterpmMean) / swiftMean) * 100
let speedup = swiftMean / swifterpmMean
print(String(format: "swifterpm reduced mean resolution time by %.2f%% (%.2fx speedup).", reduction, speedup))
SWIFT
}

run_hyperfine() {
  local name="$1"
  local mode="$2"
  local prepare="$3"
  local swift_command="$4"
  local swifterpm_command="$5"
  local markdown_path="$6"
  local json_path="$7"

  hyperfine \
    --runs "${runs}" \
    --warmup 0 \
    --style none \
    --export-markdown "${markdown_path}" \
    --export-json "${json_path}" \
    --prepare "${prepare}" \
    --command-name "swift package resolve (${mode})" "${swift_command}" \
    --command-name "swifterpm resolve (${mode})" "${swifterpm_command}"

  {
    echo "## ${name}: ${mode}"
    echo
    cat "${markdown_path}"
    echo
    append_percentage_summary "${json_path}"
    echo
  } >> "${combined_report}"
}

benchmark_prepared_codebase() {
  local name="$1"
  local slug="$2"
  local source_dir="$3"
  local package_relative_path="$4"
  local resolved_mode="${5:-checked-in}"

  local codebase_root="${work_root}/${slug}"
  local swiftpm_dir="${codebase_root}/swiftpm"
  local swifterpm_dir="${codebase_root}/swifterpm"

  local source_package_dir="${source_dir}/${package_relative_path}"
  if [[ ! -f "${source_package_dir}/Package.swift" ]]; then
    echo "${name} does not contain ${package_relative_path}/Package.swift" >&2
    exit 1
  fi

  if [[ "${resolved_mode}" == "refresh" ]]; then
    refresh_resolved_file "${name}" "${slug}" "${source_package_dir}"
  elif [[ "${resolved_mode}" != "checked-in" ]]; then
    echo "unknown Package.resolved mode for ${name}: ${resolved_mode}" >&2
    exit 1
  fi

  if [[ ! -f "${source_package_dir}/Package.resolved" ]]; then
    echo "${name} does not contain ${package_relative_path}/Package.resolved" >&2
    echo "SwiftPM and swifterpm are benchmarked with --force-resolved-versions, so Package.resolved is required." >&2
    exit 1
  fi

  copy_tree "${source_dir}" "${swiftpm_dir}"
  copy_tree "${source_dir}" "${swifterpm_dir}"

  local swiftpm_package_dir="${swiftpm_dir}/${package_relative_path}"
  local swifterpm_package_dir="${swifterpm_dir}/${package_relative_path}"

  local swiftpm_scratch="${swiftpm_package_dir}/.build"
  local swifterpm_scratch="${swifterpm_package_dir}/.build"
  local swiftpm_cold_cache="${codebase_root}/swiftpm-cold-cache"
  local swiftpm_warm_cache="${codebase_root}/swiftpm-warm-cache"
  local swifterpm_cold_cache="${codebase_root}/swifterpm-cold-cache"
  local swifterpm_warm_cache="${codebase_root}/swifterpm-warm-cache"

  local swiftpm_cold_command="swift package --package-path $(quote "${swiftpm_package_dir}") --scratch-path $(quote "${swiftpm_scratch}") --cache-path $(quote "${swiftpm_cold_cache}") --force-resolved-versions resolve"
  local swiftpm_warm_command="swift package --package-path $(quote "${swiftpm_package_dir}") --scratch-path $(quote "${swiftpm_scratch}") --cache-path $(quote "${swiftpm_warm_cache}") --force-resolved-versions resolve"
  local swifterpm_cold_command="$(quote "${swifterpm_bin}") --package-path $(quote "${swifterpm_package_dir}") --scratch-path $(quote "${swifterpm_scratch}") --cache-path $(quote "${swifterpm_cold_cache}") --force-resolved-versions --disable-package-info-cache --quiet resolve"
  local swifterpm_warm_command="$(quote "${swifterpm_bin}") --package-path $(quote "${swifterpm_package_dir}") --scratch-path $(quote "${swifterpm_scratch}") --cache-path $(quote "${swifterpm_warm_cache}") --force-resolved-versions --disable-package-info-cache --quiet resolve"

  echo "Benchmarking ${name}: cold resolution"
  run_hyperfine \
    "${name}" \
    "cold" \
    "rm -rf $(quote "${swiftpm_scratch}") $(quote "${swifterpm_scratch}") $(quote "${swiftpm_cold_cache}") $(quote "${swifterpm_cold_cache}")" \
    "${swiftpm_cold_command}" \
    "${swifterpm_cold_command}" \
    "${output_dir}/${slug}-cold.md" \
    "${output_dir}/${slug}-cold.json"

  echo "Priming warm caches for ${name}"
  rm -rf "${swiftpm_scratch}" "${swifterpm_scratch}" "${swiftpm_warm_cache}" "${swifterpm_warm_cache}"
  swift package \
    --package-path "${swiftpm_package_dir}" \
    --scratch-path "${swiftpm_scratch}" \
    --cache-path "${swiftpm_warm_cache}" \
    --force-resolved-versions \
    resolve >/dev/null 2>&1
  rm -rf "${swiftpm_scratch}"
  "${swifterpm_bin}" \
    --package-path "${swifterpm_package_dir}" \
    --scratch-path "${swifterpm_scratch}" \
    --cache-path "${swifterpm_warm_cache}" \
    --force-resolved-versions \
    --disable-package-info-cache \
    --quiet \
    resolve
  rm -rf "${swifterpm_scratch}"

  echo "Benchmarking ${name}: worktree-warm resolution"
  run_hyperfine \
    "${name}" \
    "worktree-warm" \
    "rm -rf $(quote "${swiftpm_scratch}") $(quote "${swifterpm_scratch}")" \
    "${swiftpm_warm_command}" \
    "${swifterpm_warm_command}" \
    "${output_dir}/${slug}-warm.md" \
    "${output_dir}/${slug}-warm.json"
}

refresh_resolved_file() {
  local name="$1"
  local slug="$2"
  local package_dir="$3"
  local scratch="${work_root}/${slug}/resolved-refresh-build"
  local cache="${work_root}/${slug}/resolved-refresh-cache"

  echo "Refreshing Package.resolved for ${name}"
  rm -rf "${scratch}" "${cache}"
  swift package \
    --package-path "${package_dir}" \
    --scratch-path "${scratch}" \
    --cache-path "${cache}" \
    resolve >/dev/null
  rm -rf "${scratch}" "${cache}"
}

benchmark_codebase() {
  local name="$1"
  local slug="$2"
  local repo="$3"
  local ref="$4"
  local package_relative_path="$5"
  local resolved_mode="${6:-checked-in}"

  local source_dir="${work_root}/${slug}/source"

  echo "Cloning ${name} (${repo}@${ref})"
  git clone --depth 1 --branch "${ref}" "${repo}" "${source_dir}"

  benchmark_prepared_codebase \
    "${name}" \
    "${slug}" \
    "${source_dir}" \
    "${package_relative_path}" \
    "${resolved_mode}"
}

benchmark_local_codebase() {
  local name="$1"
  local slug="$2"
  local source="$3"
  local package_relative_path="$4"
  local resolved_mode="${5:-checked-in}"

  local absolute_source
  absolute_source="$(cd "${source}" && pwd)"
  local source_dir="${work_root}/${slug}/source"

  echo "Copying ${name} from ${absolute_source}"
  copy_tree "${absolute_source}" "${source_dir}"
  benchmark_prepared_codebase \
    "${name}" \
    "${slug}" \
    "${source_dir}" \
    "${package_relative_path}" \
    "${resolved_mode}"
}

mkdir -p "${output_dir}"
repo_root="${PWD}"
output_dir="$(cd "${output_dir}" && pwd)"
combined_report="${output_dir}/resolution-latest.md"
work_root="$(mktemp -d)"
trap 'rm -rf "${work_root}"' EXIT

{
  echo "# Resolution benchmark"
  echo
  echo "Generated with \`mise run benchmark:resolution -- --runs ${runs}\`."
  echo
  echo "Cold resolution removes package-local scratch directories plus each tool's benchmark-local shared cache before each measured run."
  echo "Worktree-warm resolution removes package-local scratch directories before each measured run, but keeps each tool's already-primed benchmark-local shared cache to model switching to another clean worktree."
  echo "Tuist refreshes Package.resolved in the temporary clone before timing because the current tuist/tuist main branch can lag manifest changes."
  echo "SwiftNIO uses this repository's pinned third_party/nio fixture because upstream SwiftNIO does not commit a root Package.resolved."
  echo
} > "${combined_report}"

benchmark_codebase \
  "Pocket Casts iOS Modules" \
  "pocket-casts-ios" \
  "https://github.com/Automattic/pocket-casts-ios.git" \
  "trunk" \
  "Modules"

benchmark_codebase \
  "Firefox iOS" \
  "firefox-ios" \
  "https://github.com/mozilla-mobile/firefox-ios.git" \
  "main" \
  "."

if [[ -n "${tuist_source}" ]]; then
  benchmark_local_codebase \
    "Tuist" \
    "tuist" \
    "${tuist_source}" \
    "." \
    "refresh"
else
  benchmark_codebase \
    "Tuist" \
    "tuist" \
    "https://github.com/tuist/tuist.git" \
    "main" \
    "." \
    "refresh"
fi

benchmark_local_codebase \
  "SwiftNIO" \
  "swift-nio" \
  "${repo_root}/third_party/nio" \
  "."

echo "Benchmark reports written to ${output_dir}"
echo "Combined report: ${combined_report}"
