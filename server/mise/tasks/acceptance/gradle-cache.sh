#!/usr/bin/env bash
#MISE description="Run Gradle cache acceptance test"
#USAGE flag "-v --verbose" help="Enable verbose output"
#USAGE flag "-k --keep-server" help="Keep the server running after the test"

set -euo pipefail

readonly REPO_ROOT="${MISE_PROJECT_ROOT}/.."
readonly E2E_DIR="${REPO_ROOT}/e2e"

# Export environment for the test
export SERVER_URL="http://localhost:8080"
export GRADLE_TOKEN="tuist_01234567-89ab-cdef-0123-456789abcdef_gradlecachedevtoken"

if [[ "${usage_keep_server:-}" == "true" ]]; then
    export KEEP_SERVER="true"
fi

exec "${E2E_DIR}/run_test" "${E2E_DIR}/tests/gradle_cache"
