#!/usr/bin/env bash
# Bats test helper for Tuist e2e tests

# Setup paths
export E2E_DIR="${BATS_TEST_DIRNAME}"
export REPO_ROOT="${E2E_DIR}/.."

# Server configuration
export SERVER_URL="${SERVER_URL:-http://localhost:8080}"

# Require a command to be available
require_cmd() {
    if ! command -v "$1" &>/dev/null; then
        skip "Required command '$1' not found"
    fi
}

# Require an environment variable to be set
require_env() {
    if [[ -z ${!1:-} ]]; then
        skip "Required environment variable '$1' not set"
    fi
}

# Setup Android SDK if not set
setup_android_sdk() {
    if [[ -z "${ANDROID_HOME:-}" ]] && [[ -d ~/Library/Android/sdk ]]; then
        export ANDROID_HOME=~/Library/Android/sdk
    fi

    if [[ -z "${ANDROID_HOME:-}" ]]; then
        skip "Android SDK not found. Set ANDROID_HOME or install Android Studio"
    fi
}
