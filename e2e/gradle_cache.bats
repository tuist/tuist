#!/usr/bin/env bats
# E2E test: Gradle build cache integration through the Tuist plugin
# Tests the full flow: Gradle Plugin -> tuist CLI (cache config) -> Main Server -> Cache Node

setup_file() {
    load 'test_helper'

    # Configuration
    export GRADLE_PROJECT_DIR="${REPO_ROOT}/examples/gradle/simple_android_app"
    export TUIST_URL="${SERVER_URL}"

    # Verify prerequisites
    require_cmd java
    require_cmd curl
    setup_android_sdk

    if [[ ! -d "$GRADLE_PROJECT_DIR" ]]; then
        skip "Gradle project directory not found: $GRADLE_PROJECT_DIR"
    fi

    # Build tuist CLI binary (unless TUIST_EXECUTABLE is already set)
    if [[ -z "${TUIST_EXECUTABLE:-}" ]]; then
        TUIST_EXECUTABLE=$(build_tuist_cli "$REPO_ROOT")
        export TUIST_EXECUTABLE
    fi
    echo "# TUIST_EXECUTABLE is set to: $TUIST_EXECUTABLE" >&3

    # Setup and start the main server if not already running
    if ! server_is_running; then
        setup_main_server "$REPO_ROOT/server"
        server_start "$REPO_ROOT/server"
    fi

    # Setup and start the cache server if not already running
    if ! cache_server_is_running; then
        setup_cache_node "$REPO_ROOT/cache"
        cache_server_start "$REPO_ROOT/cache"
    fi

    # Read account token from file created by seeds, or use environment variable
    if [[ -z "${TUIST_TOKEN:-}" ]]; then
        local token_file="/tmp/gradle-e2e-token.txt"
        if [[ -f "$token_file" ]]; then
            TUIST_TOKEN=$(cat "$token_file")
            echo "# Using token from seed file: ${TUIST_TOKEN:0:25}..." >&3
        else
            echo "# Token file not found at $token_file" >&3
            echo "# Make sure to run 'mix run priv/repo/seeds.exs' first" >&3
        fi
        export TUIST_TOKEN
    fi

    # Debug: test tuist cache config directly
    echo "# Testing tuist cache config..." >&3
    local cache_config_output
    cache_config_output=$("$TUIST_EXECUTABLE" cache config tuist/gradle --json --server-url "$SERVER_URL" 2>&1) || true
    echo "# tuist cache config output: $cache_config_output" >&3
}

teardown_file() {
    load 'test_helper'

    if [[ "${KEEP_SERVER:-}" != "true" ]]; then
        server_stop
        cache_server_stop
    fi
}

@test "first build pushes artifacts to remote cache" {
    cd "$GRADLE_PROJECT_DIR"

    # Clean local Gradle caches to ensure we test remote cache
    rm -rf ~/.gradle/caches/build-cache-1/* 2>/dev/null || true
    rm -rf .gradle/build-cache/* 2>/dev/null || true
    ./gradlew clean --quiet 2>/dev/null || true

    # First build: should push to cache via the Tuist plugin
    run ./gradlew assembleDebug --build-cache --info
    if [ "$status" -ne 0 ]; then
        echo "# Gradle build failed with status $status" >&3
        echo "# Output:" >&3
        echo "$output" >&3
    fi
    [ "$status" -eq 0 ]

    # Verify the plugin configured the remote cache
    [[ "$output" == *"Tuist: Remote build cache configured"* ]]

    # Check if artifacts were stored
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
    if [ "$status" -ne 0 ]; then
        echo "# Gradle build failed with status $status" >&3
        echo "# Output:" >&3
        echo "$output" >&3
    fi
    [ "$status" -eq 0 ]

    # Debug: Show cache-related output
    echo "# Cache-related output from second build:" >&3
    echo "$output" | grep -E "(cache|Cache|FROM-CACHE|Loaded|Stored)" >&3 || echo "# No cache-related lines found" >&3

    # Verify cache was used
    if [[ "$output" != *"Loaded cache entry"* ]]; then
        echo "# FAILED: 'Loaded cache entry' not found in output" >&3
        echo "# Full output:" >&3
        echo "$output" >&3
    fi
    [[ "$output" == *"Loaded cache entry"* ]]

    # Count cache hits
    cache_hits=$(echo "$output" | grep -c "FROM-CACHE" || echo "0")
    [ "$cache_hits" -gt 0 ]

    echo "# Gradle cache integration test passed with $cache_hits cache hits" >&3
}
