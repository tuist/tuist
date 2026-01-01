#!/usr/bin/env bash
# shellcheck disable=SC2155
#MISE description="Run Gradle cache acceptance test"
#USAGE flag "-v --verbose" help="Enable verbose output"
#USAGE flag "-k --keep-server" help="Keep the server running after the test"

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SERVER_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly REPO_ROOT="$(cd "${SERVER_DIR}/.." && pwd)"
readonly GRADLE_PROJECT_DIR="${REPO_ROOT}/examples/gradle/simple_android_app"
readonly TUIST_TOKEN="tuist_01234567-89ab-cdef-0123-456789abcdef_gradlecachedevtoken"
readonly SERVER_URL="http://localhost:8080"
readonly SERVER_PID_FILE="/tmp/tuist-gradle-acceptance-server.pid"
readonly FIRST_BUILD_LOG="/tmp/tuist-gradle-acceptance-first.log"
readonly SECOND_BUILD_LOG="/tmp/tuist-gradle-acceptance-second.log"
readonly MIN_EXPECTED_CACHE_HITS=5
readonly SERVER_STARTUP_TIMEOUT=60

# -----------------------------------------------------------------------------
# Utilities
# -----------------------------------------------------------------------------

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

log_error() {
    echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2
}

log_success() {
    echo "[$(date '+%H:%M:%S')] ✓ $*"
}

verbose() {
    if [[ "${usage_verbose:-}" == "true" ]]; then
        log "$@"
    fi
}

cleanup() {
    local exit_code=$?

    if [[ "${usage_keep_server:-}" != "true" ]]; then
        stop_server
    fi

    rm -f "${FIRST_BUILD_LOG}" "${SECOND_BUILD_LOG}"

    if [[ $exit_code -ne 0 ]]; then
        log_error "Acceptance test failed"
    fi

    exit $exit_code
}

# -----------------------------------------------------------------------------
# Server management
# -----------------------------------------------------------------------------

start_server() {
    log "Starting server..."

    if is_server_running; then
        log "Server already running, stopping first..."
        stop_server
    fi

    cd "${SERVER_DIR}"
    MIX_ENV=dev mix phx.server &
    echo $! > "${SERVER_PID_FILE}"

    wait_for_server
}

stop_server() {
    if [[ -f "${SERVER_PID_FILE}" ]]; then
        local pid
        pid=$(cat "${SERVER_PID_FILE}")

        if kill -0 "$pid" 2>/dev/null; then
            verbose "Stopping server (PID: $pid)..."
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi

        rm -f "${SERVER_PID_FILE}"
    fi
}

is_server_running() {
    curl -sf "${SERVER_URL}" >/dev/null 2>&1
}

wait_for_server() {
    local elapsed=0

    while ! is_server_running; do
        if [[ $elapsed -ge $SERVER_STARTUP_TIMEOUT ]]; then
            log_error "Server failed to start within ${SERVER_STARTUP_TIMEOUT}s"
            return 1
        fi

        verbose "Waiting for server... (${elapsed}s)"
        sleep 2
        elapsed=$((elapsed + 2))
    done

    log_success "Server is ready"
}

# -----------------------------------------------------------------------------
# Gradle build operations
# -----------------------------------------------------------------------------

run_gradle_build() {
    local log_file="$1"
    local description="$2"

    log "Running Gradle build: ${description}"

    cd "${GRADLE_PROJECT_DIR}"

    ./gradlew clean --quiet

    if [[ "${usage_verbose:-}" == "true" ]]; then
        TUIST_TOKEN="${TUIST_TOKEN}" ./gradlew assembleDebug --build-cache --info 2>&1 | tee "${log_file}"
    else
        TUIST_TOKEN="${TUIST_TOKEN}" ./gradlew assembleDebug --build-cache --info > "${log_file}" 2>&1
    fi

    log_success "Build completed: ${description}"
}

clear_local_gradle_cache() {
    log "Clearing local Gradle cache..."
    rm -rf ~/.gradle/caches/build-cache-1/*
    log_success "Local cache cleared"
}

# -----------------------------------------------------------------------------
# Verification
# -----------------------------------------------------------------------------

verify_remote_cache_used() {
    local log_file="$1"

    if ! grep -q "Using remote HTTP build cache" "${log_file}"; then
        log_error "Remote HTTP build cache was not configured"
        return 1
    fi

    log_success "Remote cache configuration verified"
}

count_cache_hits() {
    local log_file="$1"
    grep -c "FROM-CACHE" "${log_file}" 2>/dev/null || echo "0"
}

verify_cache_hits() {
    local log_file="$1"
    local cache_hits

    cache_hits=$(count_cache_hits "${log_file}")

    if [[ $cache_hits -lt $MIN_EXPECTED_CACHE_HITS ]]; then
        log_error "Expected at least ${MIN_EXPECTED_CACHE_HITS} cache hits, got ${cache_hits}"
        log_error "Build log:"
        cat "${log_file}" >&2
        return 1
    fi

    log_success "Cache hits: ${cache_hits} (minimum: ${MIN_EXPECTED_CACHE_HITS})"
}

# -----------------------------------------------------------------------------
# Prerequisites
# -----------------------------------------------------------------------------

check_prerequisites() {
    log "Checking prerequisites..."

    if ! command -v java >/dev/null 2>&1; then
        log_error "Java is required but not installed"
        return 1
    fi

    if [[ -z "${ANDROID_HOME:-}" ]] && [[ ! -d ~/Library/Android/sdk ]]; then
        log_error "Android SDK not found. Set ANDROID_HOME or install Android Studio"
        return 1
    fi

    if [[ -z "${ANDROID_HOME:-}" ]]; then
        export ANDROID_HOME=~/Library/Android/sdk
    fi

    if [[ ! -f "${GRADLE_PROJECT_DIR}/gradlew" ]]; then
        log_error "Gradle wrapper not found at ${GRADLE_PROJECT_DIR}"
        return 1
    fi

    log_success "Prerequisites satisfied"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    trap cleanup EXIT

    log "=== Gradle Cache Acceptance Test ==="

    check_prerequisites
    start_server

    # First build: push artifacts to cache
    run_gradle_build "${FIRST_BUILD_LOG}" "push to cache"
    verify_remote_cache_used "${FIRST_BUILD_LOG}"

    # Clear local cache to force remote fetch
    clear_local_gradle_cache

    # Second build: should pull from remote cache
    run_gradle_build "${SECOND_BUILD_LOG}" "pull from cache"
    verify_remote_cache_used "${SECOND_BUILD_LOG}"
    verify_cache_hits "${SECOND_BUILD_LOG}"

    log "=== Acceptance Test Passed ==="
}

main "$@"
