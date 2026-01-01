#!/usr/bin/env bash
#MISE description="Run an e2e test by name"
#USAGE arg "<test>" help="Name of the test to run (e.g., gradle_cache)"

set -euo pipefail

readonly E2E_DIR="${MISE_PROJECT_ROOT}/e2e"
readonly TEST_NAME="${usage_test:-}"

if [[ -z "$TEST_NAME" ]]; then
    echo "Usage: mise run e2e <test_name>" >&2
    echo "Available tests:" >&2
    ls -1 "${E2E_DIR}/tests/" 2>/dev/null | sed 's/^/  /' >&2
    exit 1
fi

exec "${E2E_DIR}/run_test" "${E2E_DIR}/tests/${TEST_NAME}"
