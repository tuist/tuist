#!/usr/bin/env bash
# Server lifecycle helpers for e2e tests

E2E_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=style.sh
source "$E2E_LIB_DIR/style.sh"

SERVER_PID_FILE="${TMPDIR:-/tmp}/tuist-e2e-server.pid"
SERVER_URL="${SERVER_URL:-http://localhost:8080}"
SERVER_STARTUP_TIMEOUT="${SERVER_STARTUP_TIMEOUT:-60}"

server_is_running() {
    curl -sf "$SERVER_URL" >/dev/null 2>&1
}

server_start() {
    local server_dir="$1"

    if server_is_running; then
        log "Server already running, stopping first..."
        server_stop
    fi

    log "Starting server..."
    cd "$server_dir" || exit 1
    MIX_ENV=dev mix phx.server &
    echo $! > "$SERVER_PID_FILE"

    server_wait
}

server_stop() {
    if [[ -f "$SERVER_PID_FILE" ]]; then
        local pid
        pid=$(cat "$SERVER_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            debug "Stopping server (PID: $pid)..."
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
        rm -f "$SERVER_PID_FILE"
    fi
}

server_wait() {
    local elapsed=0
    while ! server_is_running; do
        if [[ $elapsed -ge $SERVER_STARTUP_TIMEOUT ]]; then
            err "Server failed to start within ${SERVER_STARTUP_TIMEOUT}s"
            return 1
        fi
        debug "Waiting for server... (${elapsed}s)"
        sleep 2
        elapsed=$((elapsed + 2))
    done
    ok "Server is ready"
}
