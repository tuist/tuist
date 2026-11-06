#!/usr/bin/env bash
set -uo pipefail

cache=${1:?usage: activate.sh CACHE}
if ! command -v tuist-runner-cache >/dev/null 2>&1; then
  echo "This runner does not provide Tuist runner caches; nothing to set up."
  exit 0
fi

arguments=(activate "$cache")
size=${TUIST_RUNNER_CACHE_SIZE:-}
if [ -n "$size" ]; then
  case "$(tuist-runner-cache -h 2>&1 || true)" in
    *--size*) arguments+=(--size "$size") ;;
    *) echo "::warning::This runner image does not support the size input yet; the cache keeps its current size." ;;
  esac
fi

env_file=$(mktemp)
trap 'rm -f "$env_file"' EXIT
status=0
tuist-runner-cache "${arguments[@]}" >"$env_file" || status=$?
case "$status" in
  0) cat "$env_file" >>"$GITHUB_ENV" ;;
  3) echo "::warning::The Tuist runner could not mount this cache; the job runs with an empty one." ;;
  *) echo "::warning::Could not set up the Tuist runner cache (tuist-runner-cache exited $status)." ;;
esac
