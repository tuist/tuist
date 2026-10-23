#!/usr/bin/env bash
set -euo pipefail

# SWIFTPM_BUILD_DIR takes precedence over --scratch-path in the CLI.
[[ -z "${SWIFTPM_BUILD_DIR:-}" ]] || { echo '::error::Unset SWIFTPM_BUILD_DIR before using this action.' >&2; exit 1; }
project=${TUIST_INSTALL_PROJECT_PATH:?project path required}
scratch=${TUIST_INSTALL_SCRATCH_PATH:?scratch path required}
cache=${TUIST_INSTALL_CACHE_PATH:?cache path required}
materialization=${TUIST_INSTALL_MATERIALIZATION:?materialization required}
[[ "$materialization" == copy || "$materialization" == symlink ]] || { echo '::error::Invalid materialization mode.' >&2; exit 1; }
# Action plumbing must not make manifest fingerprints depend on checkout paths.
unset TUIST_INSTALL_PROJECT_PATH TUIST_INSTALL_SCRATCH_PATH TUIST_INSTALL_CACHE_PATH \
  TUIST_INSTALL_ACTION_PATH TUIST_INSTALL_PATH TUIST_INSTALL_CACHE_KEY TUIST_INSTALL_MATERIALIZATION
cd "$project"
tuist install --path "$project" \
  --force-resolved-versions \
  --scratch-path "$scratch" \
  --cache-path "$cache" \
  --cached-directory-materialization="$materialization"
