#!/usr/bin/env bash
set -euo pipefail

# SWIFTPM_BUILD_DIR takes precedence over --scratch-path in the CLI.
[[ -z "${SWIFTPM_BUILD_DIR:-}" ]] || { echo '::error::Unset SWIFTPM_BUILD_DIR before using this action.' >&2; exit 1; }
project=${TUIST_INSTALL_PROJECT_PATH:?project path required}
scratch=${TUIST_INSTALL_SCRATCH_PATH:?scratch path required}
cache=${TUIST_INSTALL_CACHE_PATH:?cache path required}
materialization=${TUIST_INSTALL_MATERIALIZATION:?materialization required}
[[ "$materialization" == copy || "$materialization" == symlink ]] || { echo '::error::Invalid materialization mode.' >&2; exit 1; }
# The dependency cache lives on the .build volume. Bound it the way runners bound the module
# cache with TUIST_CACHE_MAX_BYTES: the capacity less max(2 GB, 20%), at most half of it.
# A scratch directory that is not a volume (the attachment fell back) stays bounded by age only.
if [[ -z "${TUIST_DEPENDENCIES_CACHE_MAX_BYTES:-}" && "${TUIST_INSTALL_BACKEND:-}" == volume && -L "$scratch" ]]; then
  capacity=$(df -Pk "$scratch/" 2>/dev/null | awk 'NR == 2 && $2 ~ /^[0-9]+$/ { printf "%.0f", $2 * 1024 }')
  if [[ -n "$capacity" ]]; then
    TUIST_DEPENDENCIES_CACHE_MAX_BYTES=$(awk -v capacity="$capacity" 'BEGIN { room = capacity / 5; if (room < 2e9) room = 2e9; if (room > capacity / 2) room = capacity / 2; printf "%.0f", capacity - room }')
    export TUIST_DEPENDENCIES_CACHE_MAX_BYTES
  fi
fi
# Action plumbing must not make manifest fingerprints depend on checkout paths.
unset TUIST_INSTALL_PROJECT_PATH TUIST_INSTALL_SCRATCH_PATH TUIST_INSTALL_CACHE_PATH \
  TUIST_INSTALL_ACTION_PATH TUIST_INSTALL_PATH TUIST_INSTALL_CACHE TUIST_INSTALL_CACHE_KEY TUIST_INSTALL_MATERIALIZATION TUIST_INSTALL_BACKEND
cd "$project"
tuist install --path "$project" \
  --force-resolved-versions \
  --scratch-path "$scratch" \
  --cache-path "$cache" \
  --cached-directory-materialization="$materialization"
