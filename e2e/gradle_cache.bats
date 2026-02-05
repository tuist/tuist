#!/usr/bin/env bats
# E2E test: Gradle build cache integration through the Tuist plugin
# Tests the full flow: Gradle Plugin -> tuist CLI (cache config) -> Main Server -> Cache Node
#
# Prerequisites (provided by CI):
#   - TUIST_EXECUTABLE: path to the built tuist CLI binary
#   - SERVER_URL: URL of the running main server (default: http://localhost:8080)
#   - Java and Android SDK installed
#   - Main server and cache node already running

setup_file() {
    load 'test_helper'

    # Configuration
    export GRADLE_PROJECT_DIR="${REPO_ROOT}/examples/gradle/simple_android_app"
    export TUIST_URL="${SERVER_URL}"

    # Use an isolated Gradle home to avoid touching the global cache
    export GRADLE_USER_HOME="${BATS_FILE_TMPDIR}/gradle-home"
    mkdir -p "$GRADLE_USER_HOME"

    # Verify prerequisites
    require_cmd java
    require_cmd curl
    require_env TUIST_EXECUTABLE
    setup_android_sdk

    if [[ ! -d "$GRADLE_PROJECT_DIR" ]]; then
        skip "Gradle project directory not found: $GRADLE_PROJECT_DIR"
    fi

    echo "# TUIST_EXECUTABLE is set to: $TUIST_EXECUTABLE" >&3

    # Authenticate against the local server (stores credentials for tuist cache config)
    echo "# Logging in to server at $TUIST_URL..." >&3
    "$TUIST_EXECUTABLE" auth login --email tuistrocks@tuist.dev --password tuistrocks
}

teardown_file() {
    rm -rf "${BATS_FILE_TMPDIR}/gradle-home" 2>/dev/null || true
}

@test "first build pushes artifacts to remote cache" {
    cd "$GRADLE_PROJECT_DIR"

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

    # Clean build outputs and local cache to force remote cache pull
    ./gradlew clean --quiet
    rm -rf "${GRADLE_USER_HOME}/caches/build-cache-1"/* 2>/dev/null || true
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
