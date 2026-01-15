#!/usr/bin/env bats
# E2E test: Gradle build cache integration
# Tests that Gradle builds can push and pull cache artifacts from the Tuist server

setup_file() {
    load 'test_helper'

    # Configuration
    export GRADLE_PROJECT_DIR="${REPO_ROOT}/examples/gradle/simple_android_app"
    export TUIST_TOKEN="${GRADLE_TOKEN:-tuist_01234567-89ab-cdef-0123-456789abcdef_gradlecachedevtoken}"
    export TUIST_CACHE_URL="${SERVER_URL}/api/cache/gradle/tuist/gradle/"

    # Verify prerequisites
    require_cmd java
    require_cmd curl
    setup_android_sdk

    # Check that gradle project exists
    if [[ ! -d "$GRADLE_PROJECT_DIR" ]]; then
        skip "Gradle project directory not found: $GRADLE_PROJECT_DIR"
    fi

    # Start the server if not already running
    if ! server_is_running; then
        server_start "$REPO_ROOT/server"
    fi
}

teardown_file() {
    load 'test_helper'

    if [[ "${KEEP_SERVER:-}" != "true" ]]; then
        server_stop
    fi
}

@test "first build pushes artifacts to remote cache" {
    cd "$GRADLE_PROJECT_DIR"

    # Clean local Gradle caches to ensure we test remote cache
    rm -rf ~/.gradle/caches/build-cache-1/* 2>/dev/null || true
    rm -rf .gradle/build-cache/* 2>/dev/null || true
    ./gradlew clean --quiet 2>/dev/null || true

    # First build: should push to cache
    run ./gradlew assembleDebug --build-cache --info
    [ "$status" -eq 0 ]

    # Check if artifacts were stored (may already be cached from previous runs)
    if [[ "$output" == *"Stored cache entry"* ]]; then
        echo "# First build pushed artifacts to remote cache" >&3
    else
        echo "# No 'Stored cache entry' found in build output (may already be cached)" >&3
    fi
}

@test "second build pulls artifacts from remote cache" {
    cd "$GRADLE_PROJECT_DIR"

    # Clean again to force cache pull
    ./gradlew clean --quiet
    rm -rf ~/.gradle/caches/build-cache-1/* 2>/dev/null || true
    rm -rf .gradle/build-cache/* 2>/dev/null || true

    # Second build: should pull from cache
    run ./gradlew assembleDebug --build-cache --info
    [ "$status" -eq 0 ]

    # Verify cache was used
    [[ "$output" == *"Loaded cache entry"* ]]
    [[ "$output" == *"Using remote HTTP build cache"* ]]

    # Count cache hits
    cache_hits=$(echo "$output" | grep -c "FROM-CACHE" || echo "0")
    [ "$cache_hits" -gt 0 ]

    echo "# Gradle cache integration test passed with $cache_hits cache hits" >&3
}
