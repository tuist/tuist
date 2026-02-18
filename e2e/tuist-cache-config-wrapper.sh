#!/usr/bin/env bash
# Wrapper around `tuist` that fixes `cache config --json` on Linux.
# On Linux, tuist 4.146.2 has a bug where the JSON log handler is
# replaced by a file-only logger, so `cache config --json` exits
# with code 0 but produces no stdout output.
#
# This wrapper intercepts `cache config` calls and generates the
# response directly using the server API.
# For all other commands, it passes through to the real tuist binary.

set -euo pipefail

REAL_TUIST="${REAL_TUIST_PATH:-tuist}"

# Check if this is a `cache config` call with --json
is_cache_config=false
has_json=false
has_force_refresh=false
full_handle=""
server_url=""

args=("$@")
i=0
while [ $i -lt ${#args[@]} ]; do
    arg="${args[$i]}"
    case "$arg" in
        cache)
            if [ $((i + 1)) -lt ${#args[@]} ] && [ "${args[$((i + 1))]}" = "config" ]; then
                is_cache_config=true
                i=$((i + 1))
            fi
            ;;
        --json) has_json=true ;;
        --force-refresh) has_force_refresh=true ;;
        --url)
            if [ $((i + 1)) -lt ${#args[@]} ]; then
                i=$((i + 1))
                server_url="${args[$i]}"
            fi
            ;;
        -*)
            # skip other flags
            ;;
        *)
            # Positional arg after "cache config" is the full handle
            if $is_cache_config && [ -z "$full_handle" ]; then
                full_handle="$arg"
            fi
            ;;
    esac
    i=$((i + 1))
done

# If not `cache config --json`, pass through to real tuist
if ! $is_cache_config || ! $has_json; then
    exec "$REAL_TUIST" "$@"
fi

# --- Handle `cache config --json` directly ---

# Determine server URL
if [ -z "$server_url" ]; then
    server_url="${TUIST_URL:-${TUIST_SERVER_URL:-https://tuist.dev}}"
fi

# Read credentials from file system
creds_host=$(echo "$server_url" | sed -E 's|https?://||; s|:[0-9]+||; s|/.*||')
creds_file="$HOME/.config/tuist/credentials/${creds_host}.json"

if [ ! -f "$creds_file" ]; then
    echo "Error: No credentials found at $creds_file. Run 'tuist auth login' first." >&2
    exit 1
fi

# Extract access token from credentials JSON
access_token=$(python3 -c "import json; print(json.load(open('$creds_file'))['accessToken'])" 2>/dev/null || \
               python3 -c "import json; print(json.load(open('$creds_file'))['access_token'])" 2>/dev/null)

if [ -z "$access_token" ]; then
    echo "Error: Could not read access token from $creds_file" >&2
    exit 1
fi

# If no handle was passed, try to read it from tuist.toml in the current directory
if [ -z "$full_handle" ]; then
    if [ -f "tuist.toml" ]; then
        full_handle=$(sed -n 's/^project *= *"\(.*\)"/\1/p' tuist.toml)
    fi
    if [ -z "$full_handle" ]; then
        echo "Error: Full handle is required (e.g., tuist/android-app)" >&2
        exit 1
    fi
fi

account_handle="${full_handle%%/*}"
project_handle="${full_handle#*/}"

# Get cache endpoints from server API
cache_endpoints_response=$(curl -sf \
    -H "Authorization: Bearer $access_token" \
    "${server_url}/api/cache-endpoints?account_handle=${account_handle}" 2>/dev/null) || {
    echo "Error: Failed to get cache endpoints from ${server_url}" >&2
    exit 1
}

# Extract the first cache URL
cache_url=$(python3 -c "import json; urls=json.loads('$cache_endpoints_response').get('urls',[]); print(urls[0] if urls else '')" 2>/dev/null)

if [ -z "$cache_url" ]; then
    echo "Error: No cache endpoints returned by server" >&2
    exit 1
fi

# Output the cache configuration JSON
python3 -c "
import json
config = {
    'url': '$cache_url',
    'token': '$access_token',
    'account_handle': '$account_handle',
    'project_handle': '$project_handle'
}
print(json.dumps(config, indent=2))
"
