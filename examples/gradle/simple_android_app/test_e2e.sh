#!/usr/bin/env bash
set -euo pipefail

TUIST_BIN="/Users/marekfort/.local/share/mise/installs/tuist/4.138.1/tuist"
SERVER_URL="http://localhost:8080"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
FULL_HANDLE="tuist/android-app"

cd "$PROJECT_DIR"
eval "$(mise env)"

clean_caches() {
    rm -rf ~/.gradle/caches/build-cache-*
    rm -rf "$PROJECT_DIR/.gradle" "$PROJECT_DIR/app/build" "$PROJECT_DIR/build"
}

run_build() {
    local label="$1"
    echo ""
    echo "=========================================="
    echo " $label"
    echo "=========================================="
    gradle --stop 2>/dev/null || true
    TUIST_EXECUTABLE="$TUIST_BIN" TUIST_SERVER_URL="$SERVER_URL" gradle build --info 2>&1 \
        | grep -iE "Could not load|Stored cache|remote build cache|Tuist:|FROM-CACHE|status 40" \
        || true
    echo ""
}

check_api() {
    echo "=========================================="
    echo " Build reports from API"
    echo "=========================================="
    local token
    token=$(cd /tmp && "$TUIST_BIN" cache config "$FULL_HANDLE" --json --url "$SERVER_URL" 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
    curl -s "$SERVER_URL/api/projects/$FULL_HANDLE/gradle/builds?limit=3" \
        -H "Authorization: Bearer $token" \
        | python3 -c "
import sys, json
data = json.load(sys.stdin)
for b in data['builds']:
    print(f\"Build {b['id'][:13]}...  local_hit={b['tasks_local_hit_count']}  remote_hit={b['tasks_remote_hit_count']}  executed={b['tasks_executed_count']}  up_to_date={b['tasks_up_to_date_count']}  hit_rate={b['cache_hit_rate']}%\")
"
}

echo "=== E2E Test: local_hit / remote_hit tracking ==="

# Build 1: cold build — everything executes, pushes to remote cache
clean_caches
run_build "Build 1: Cold build (should execute + store to remote)"

# Build 2: clear local cache — should pull from remote cache (remote_hit)
clean_caches
run_build "Build 2: After clearing local cache (should show remote_hit)"

# Check results via API
check_api
