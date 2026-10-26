#!/usr/bin/env bash
set -euo pipefail

cache="${HOME:?}/.cache/tuist-server-docker-mix"

case "${1:-}" in
  prepare)
    mkdir -p "$cache/current/_build"
    rm -rf "$cache/next"
    printf 'context=mix-cache=%s/current\n' "$cache" >> "${GITHUB_OUTPUT:?}"
    printf 'export=type=local,dest=%s/next\n' "$cache" >> "$GITHUB_OUTPUT"
    ;;
  commit)
    complete="${TUIST_MIX_CACHE_EXPORTED:?}"
    for project in tuist tuist_common tuist_ex noora; do
      if [[ ! -d "$cache/next/_build/$project" ]]; then
        complete=false
      fi
    done
    if [[ "$complete" == true ]]; then
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
