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
case "${TUIST_VOLUME_COMMIT:-auto}" in
  auto) "$client" --key "$TUIST_VOLUME_KEY" --path "$TUIST_VOLUME_PATH" ;;
  true|false) "$client" --key "$TUIST_VOLUME_KEY" --path "$TUIST_VOLUME_PATH" --commit "$TUIST_VOLUME_COMMIT" ;;
  *) echo '::error::commit must be auto, true, or false.'; exit 2 ;;
esac
