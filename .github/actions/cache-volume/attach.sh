#!/usr/bin/env bash
set -euo pipefail

if command -v tuist-cache-volume >/dev/null 2>&1; then
  client=tuist-cache-volume
elif [ -x /__e/tuist-cache-volume ]; then
  client=/__e/tuist-cache-volume
else
  echo '::error::This action requires a Tuist Linux or macOS runner with cache volumes enabled.'
  exit 1
fi

trim() {
  local value=$1
  value=${value#"${value%%[![:space:]]*}"}
  printf '%s' "${value%"${value##*[![:space:]]}"}"
}

key=$(trim "${TUIST_VOLUME_KEY:-}")
if [ -z "$key" ]; then
  key=tuist-default
else
  case "$key" in
    [Tt][Uu][Ii][Ss][Tt]-*)
      echo '::error::Cache volume keys starting with tuist- are reserved for Tuist. Choose another key, or omit key to use the default volume.'
      exit 1
      ;;
  esac
fi

arguments=(--key "$key")
while IFS= read -r line || [ -n "$line" ]; do
  line=$(trim "$line")
  if [ -n "$line" ]; then
    arguments+=(--path "$line")
  fi
done <<< "${TUIST_VOLUME_PATH:-}"
if [ "${#arguments[@]}" -eq 2 ]; then
  echo '::error::The path input must contain at least one path.'
  exit 1
fi

size=$(trim "${TUIST_VOLUME_SIZE:-}")
if [ -n "$size" ]; then
  usage=$("$client" -h 2>&1 || true)
  case "$usage" in
    *-size*) arguments+=(--size "$size") ;;
    *) echo "::warning::This runner image does not support the size input yet; the volume keeps its current size." ;;
  esac
fi
"$client" "${arguments[@]}"
