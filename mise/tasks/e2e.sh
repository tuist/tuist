#!/usr/bin/env bash
#MISE description="Run e2e tests using bats"
#USAGE arg "[test]" help="Name of the test to run (e.g., gradle_cache). If not provided, runs all tests."

set -euo pipefail

readonly E2E_DIR="${MISE_PROJECT_ROOT}/e2e"
readonly TEST_NAME="${usage_test:-}"

if [[ -n "$TEST_NAME" ]]; then
    # Run specific test
    TEST_FILE="${E2E_DIR}/${TEST_NAME}.bats"
    if [[ ! -f "$TEST_FILE" ]]; then
        echo "Test file not found: $TEST_FILE" >&2
        echo "Available tests:" >&2
        ls -1 "${E2E_DIR}"/*.bats 2>/dev/null | xargs -n1 basename | sed 's/\.bats$//' | sed 's/^/  /' >&2
        exit 1
    fi
    exec bats "$TEST_FILE"
else
    # Run all tests
    exec bats "${E2E_DIR}"/*.bats
fi
