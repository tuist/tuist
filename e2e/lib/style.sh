#!/usr/bin/env bash
# Styled output helpers for e2e tests
# Adapted from mise's e2e framework

if [[ -n ${GITHUB_ACTIONS:-} ]]; then
    ok() { echo $'\e[92m'"✓ $*"$'\e[0m' >&2; }
    err() { echo "::error::$*" >&2; }
    warn() { echo "::warning::$*" >&2; }
    info() { echo "::notice::$*" >&2; }
    debug() { echo $'\e[90m'"$*"$'\e[0m' >&2; }
    start_group() { echo "::group::$*" >&2; }
    end_group() { echo "::endgroup::" >&2; }
elif [[ -t 2 ]]; then
    ok() { echo $'\e[92m'"✓ $*"$'\e[0m' >&2; }
    err() { echo $'\e[91m'"✗ $*"$'\e[0m' >&2; }
    warn() { echo $'\e[93m'"⚠ $*"$'\e[0m' >&2; }
    info() { echo $'\e[94m'"$*"$'\e[0m' >&2; }
    debug() { echo $'\e[90m'"$*"$'\e[0m' >&2; }
    start_group() { echo $'\e[1m'">>> $*"$'\e[0m' >&2; }
    end_group() { echo >&2; }
else
    ok() { echo "OK: $*" >&2; }
    err() { echo "ERROR: $*" >&2; }
    warn() { echo "WARNING: $*" >&2; }
    info() { echo "INFO: $*" >&2; }
    debug() { echo "DEBUG: $*" >&2; }
    start_group() { echo ">>> $*" >&2; }
    end_group() { echo >&2; }
fi

log() { echo "[$(date '+%H:%M:%S')] $*" >&2; }
