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

arguments=(--key "$TUIST_VOLUME_KEY")
while IFS= read -r line || [ -n "$line" ]; do
  line=${line#"${line%%[![:space:]]*}"}
  line=${line%"${line##*[![:space:]]}"}
  if [ -n "$line" ]; then
    arguments+=(--path "$line")
  fi
done <<< "$TUIST_VOLUME_PATH"
if [ "${#arguments[@]}" -eq 2 ]; then
  echo '::error::The path input must contain at least one path.'
  exit 1
fi
"$client" "${arguments[@]}"
