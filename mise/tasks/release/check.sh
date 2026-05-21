#!/usr/bin/env bash
#MISE description="Check each Tuist component for releasable changes since its last tag"
#USAGE arg "[component]..." help="Restrict to one or more component names; default is every component in components.json"
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPONENTS_FILE="${SCRIPT_DIR}/components.json"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel)"

# cliff enriches each commit with PR title/username via the GitHub API when a
# token is present; --bumped-version doesn't need that, and the lookups cost
# 60-180s per component. Clear both env vars before invoking cliff.
export GITHUB_TOKEN=""
export GH_TOKEN=""

ANY=false

emit_output() {
  local key=$1 value=$2
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$key" "$value" >> "$GITHUB_OUTPUT"
  fi
}

check_component() {
  local component=$1 tag_prefix=$2 tag_regex=$3 cliff_config=$4 initial=$5
  shift 5
  local include_args=()
  local p
  for p in "$@"; do include_args+=(--include-path "$p"); done

  local latest next_num latest_num
  latest=$(git -C "$REPO_ROOT" tag -l | grep -E "$tag_regex" | sort -V | tail -n1 || true)
  if [[ -n "$latest" ]]; then
    next_num=$(git cliff "${include_args[@]}" --config "$cliff_config" --repository "$REPO_ROOT" --bumped-version 2>/dev/null -- "${latest}..HEAD" || true)
  else
    next_num=$(git cliff "${include_args[@]}" --config "$cliff_config" --repository "$REPO_ROOT" --bumped-version 2>/dev/null || true)
  fi

  if [[ -n "$tag_prefix" ]]; then
    while [[ "$next_num" == "$tag_prefix"* ]]; do
      next_num=${next_num#"$tag_prefix"}
    done
  fi
  [[ -z "$next_num" ]] && next_num=$initial
  latest_num=${latest#"$tag_prefix"}

  local should=false
  if [[ -z "$latest" ]]; then
    should=true
  else
    local greatest
    greatest=$(printf '%s\n%s\n' "$latest_num" "$next_num" | sort -V | tail -n1)
    if [[ "$next_num" != "$latest_num" && "$greatest" == "$next_num" ]]; then
      should=true
    else
      next_num=$latest_num
    fi
  fi

  local full="${tag_prefix}${next_num}"

  [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "::group::Check ${component} (release? ${should})"
  printf 'component:  %s\nlatest tag: %s\nnext:       %s (number: %s)\nrelease?    %s\n' \
    "$component" "${latest:-<none>}" "$full" "$next_num" "$should"
  [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "::endgroup::"

  emit_output "${component}-should-release" "$should"
  emit_output "${component}-next-version" "$full"
  emit_output "${component}-next-version-number" "$next_num"

  [[ "$should" == "true" ]] && ANY=true
  return 0
}

declare -A WANTED=()
for name in "$@"; do WANTED[$name]=1; done

# Iterate the components config. Each iteration receives one component as a JSON
# blob on stdin; per-field jq calls keep the script easy to read and the cost
# (~7 jq invocations × 15 components × <50ms) is negligible next to cliff.
while IFS= read -r component_json; do
  name=$(jq -r '.name' <<< "$component_json")
  if (( ${#WANTED[@]} > 0 )) && [[ -z "${WANTED[$name]:-}" ]]; then
    continue
  fi
  tag_prefix=$(jq -r '.tag_prefix' <<< "$component_json")
  tag_regex=$(jq -r '.tag_regex' <<< "$component_json")
  cliff_config=$(jq -r '.cliff_config' <<< "$component_json")
  initial=$(jq -r '.initial_version' <<< "$component_json")
  mapfile -t include_paths < <(jq -r '.include_paths[]?' <<< "$component_json")

  if (( ${#include_paths[@]} > 0 )); then
    check_component "$name" "$tag_prefix" "$tag_regex" "$cliff_config" "$initial" "${include_paths[@]}"
  else
    check_component "$name" "$tag_prefix" "$tag_regex" "$cliff_config" "$initial"
  fi
done < <(jq -c '.components[]' "$COMPONENTS_FILE")

emit_output "should-release-any" "$ANY"

if [[ -z "${GITHUB_OUTPUT:-}" ]]; then
  printf '\nshould-release-any=%s\n' "$ANY"
fi
