#!/usr/bin/env bash
set -euo pipefail

if command -v tuist-cache-volume >/dev/null 2>&1; then
  client=tuist-cache-volume
elif [ -x /__e/tuist-cache-volume ]; then
  client=/__e/tuist-cache-volume
else
  echo '::error::This action requires a Tuist Linux runner with cache volumes enabled.'
  exit 1
fi
"$client" --key "$TUIST_VOLUME_KEY" --path "$TUIST_VOLUME_PATH"
