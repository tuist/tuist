#!/usr/bin/env bash
# Bats test helper for Tuist e2e tests

# Setup paths
export E2E_DIR="${BATS_TEST_DIRNAME}"
export REPO_ROOT="${E2E_DIR}/.."

# Server configuration
export SERVER_PID_FILE="${TMPDIR:-/tmp}/tuist-e2e-server.pid"
export SERVER_URL="${SERVER_URL:-http://localhost:8080}"
export SERVER_STARTUP_TIMEOUT="${SERVER_STARTUP_TIMEOUT:-60}"

# Check if server is running
server_is_running() {
    curl -sf "$SERVER_URL" >/dev/null 2>&1
}

# Start the Phoenix server
server_start() {
    local server_dir="$1"

    if server_is_running; then
        echo "# Server already running, stopping first..." >&3
        server_stop
    fi

    echo "# Starting server..." >&3
    cd "$server_dir" || return 1
    MIX_ENV=dev mix phx.server &
    echo $! > "$SERVER_PID_FILE"

    server_wait
}

# Stop the server
server_stop() {
    if [[ -f "$SERVER_PID_FILE" ]]; then
        local pid
        pid=$(cat "$SERVER_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "# Stopping server (PID: $pid)..." >&3
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
        rm -f "$SERVER_PID_FILE"
    fi
}

# Wait for server to be ready
server_wait() {
    local elapsed=0
    while ! server_is_running; do
        if [[ $elapsed -ge $SERVER_STARTUP_TIMEOUT ]]; then
            echo "# Server failed to start within ${SERVER_STARTUP_TIMEOUT}s" >&3
            return 1
        fi
        echo "# Waiting for server... (${elapsed}s)" >&3
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "# Server is ready" >&3
}

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
