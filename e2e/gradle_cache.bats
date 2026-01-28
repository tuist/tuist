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

    # Authenticate with the server and create an account token for the test
    if [[ -z "${TUIST_TOKEN:-}" ]]; then
        echo "# Authenticating with Tuist server..." >&3

        # Run from a temp directory to avoid tuist trying to generate workspace in repo root
        local tmp_dir
        tmp_dir=$(mktemp -d)
        cd "$tmp_dir"

        # Login with fixture credentials
        "$TUIST_EXECUTABLE" auth login --email tuistrocks@tuist.dev --password tuistrocks 2>&1 >&3 || true

        # Create an account token for cache access
        echo "# Creating account token for Gradle cache..." >&3
        local token_output
        token_output=$("$TUIST_EXECUTABLE" account tokens create tuist \
            --scopes project:cache:read --scopes project:cache:write \
            --name "gradle-e2e-test-$(date +%s)" 2>&1) || true
        echo "# Token command output: $token_output" >&3
        TUIST_TOKEN=$(echo "$token_output" | grep -o 'tuist_[a-zA-Z0-9_-]*' || echo "")

        # Clean up temp directory
        cd "$REPO_ROOT"
        rm -rf "$tmp_dir"

        if [[ -z "$TUIST_TOKEN" ]]; then
            echo "# Failed to create account token, test may fail" >&3
        else
            echo "# Account token created successfully: ${TUIST_TOKEN:0:20}..." >&3
        fi
        export TUIST_TOKEN
    fi
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
    [ "$status" -eq 0 ]

    # Verify cache was used
    [[ "$output" == *"Loaded cache entry"* ]]

    # Count cache hits
    cache_hits=$(echo "$output" | grep -c "FROM-CACHE" || echo "0")
    [ "$cache_hits" -gt 0 ]

    echo "# Gradle cache integration test passed with $cache_hits cache hits" >&3
}
