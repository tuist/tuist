#!/usr/bin/env bash
set -euo pipefail

cache="${RUNNER_TEMP:?}/server-docker-mix-cache"

case "${1:-}" in
  prepare)
    mkdir -p "$cache/current/deps" "$cache/current/_build"
    rm -rf "$cache/next"
    printf 'context=mix-cache=%s/current\n' "$cache" >> "${GITHUB_OUTPUT:?}"
    printf 'export=type=local,dest=%s/next\n' "$cache" >> "$GITHUB_OUTPUT"
    ;;
  commit)
    if [[ "${TUIST_MIX_CACHE_EXPORTED:?}" == true && -d "$cache/next/deps" && -d "$cache/next/_build" ]]; then
      rm -rf "$cache/current"
      mv "$cache/next" "$cache/current"
    else
      echo '::warning::Production Mix cache export unavailable; retaining the previous snapshot.'
      rm -rf "$cache/next"
    fi
    ;;
  *)
    echo 'Usage: server-docker-mix-cache.sh prepare|commit' >&2
    exit 1
    ;;
esac
