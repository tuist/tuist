#!/usr/bin/env bash
# Invoked by `amp orb provider /absolute/path/to/dispatch.sh`.
set -euo pipefail
SECONDS=0

# Stop retrying admission after 150 seconds, leaving two minutes to boot.
# The whole dispatch (including authentication and HTTP) stays below Amp's
# five-minute deadline. Operators may shorten, but never extend, the wait.
wait_seconds=${TUIST_ORB_CAPACITY_WAIT_SECONDS:-150}
if [[ ! "$wait_seconds" =~ ^(0|[1-9][0-9]{0,2})$ ]] || (( wait_seconds > 150 )); then
    echo 'TUIST_ORB_CAPACITY_WAIT_SECONDS must be an integer between 0 and 150.' >&2; exit 1;
fi

: "${TUIST_URL:?Set the Tuist server URL}"

: "${ORB_ID:?Amp must supply ORB_ID}"
: "${ORB_OPERATION:?Amp must supply ORB_OPERATION}"
[[ "$TUIST_URL" == https://* || "$TUIST_URL" == http://localhost:* || "$TUIST_URL" == http://127.0.0.1:* ]] || {
    echo 'TUIST_URL must use HTTPS (HTTP is allowed only for local validation).' >&2; exit 1;
}
[[ "$ORB_ID" =~ ^[a-zA-Z0-9_-]+$ ]] || {
    echo 'Invalid account handle or Orb ID.' >&2; exit 1;
}
case "$ORB_OPERATION" in
    spawn) : "${ORB_TOKEN:?Amp must supply ORB_TOKEN for spawn}" ;;
    pause|delete) ;;
    *) echo 'Unsupported Orb operation.' >&2; exit 1 ;;
esac
if [[ -n "${ORB_SNAPSHOT_ID:-}" && ! "$ORB_SNAPSHOT_ID" =~ ^[A-Za-z0-9._:-]{1,255}$ ]]; then
    echo 'Invalid Orb snapshot ID.' >&2; exit 1
fi

# ORB_IMAGE is a template name, not an OCI image: sandboxd only boots
# installed Firecracker templates. Never silently substitute another image.
if [[ "$ORB_OPERATION" == spawn && "${ORB_IMAGE:-}" != "${TUIST_ORB_TEMPLATE:-default}" ]]; then
    echo 'Set ORB_IMAGE to the installed template name (default: default) in the provider environment.' >&2
    exit 1
fi

# Managed providers read their rotating workload identity for EVERY dispatch.
# The server derives the account binding from its verified ServiceAccount.
if [[ -n "${TUIST_WORKLOAD_TOKEN_FILE:-}" ]]; then
    TUIST_TOKEN=$(cat "$TUIST_WORKLOAD_TOKEN_FILE")
    endpoint="${TUIST_URL%/}/api/internal/amp-orbs/$ORB_ID"
else
    # Standalone adapters may still use the explicitly authorized account API.
    : "${TUIST_ACCOUNT:?Set the account handle}"
    [[ "$TUIST_ACCOUNT" =~ ^[a-zA-Z0-9_-]+$ ]] || exit 1
    if [[ -z "${TUIST_TOKEN:-}" ]]; then
        TUIST_TOKEN=$(timeout 30 tuist auth token --url "$TUIST_URL")
    fi
    endpoint="${TUIST_URL%/}/api/accounts/$TUIST_ACCOUNT/sandboxes/amp-orbs/$ORB_ID"
fi
export TUIST_TOKEN
: "${TUIST_TOKEN:?Tuist authentication returned no token}"

# Keep credentials out of curl's argv and logs. jq reads environment values;
# only the request body lives briefly in a mode-0600 temporary file.
umask 077
request=$(mktemp)
headers=$(mktemp)
trap 'rm -f "$request" "$headers"' EXIT
# ORB_SNAPSHOT_ID names Amp's project snapshot: a pause saves the Orb's disks
# under it, and a spawn of a new Orb starts from it when Tuist holds one.
jq -n '{operation: env.ORB_OPERATION} +
    (if (env.ORB_SNAPSHOT_ID // "") != "" and env.ORB_OPERATION != "delete"
        then {snapshot_id: env.ORB_SNAPSHOT_ID} else {} end) +
    (if env.ORB_OPERATION == "spawn" then {
        orb_token: env.ORB_TOKEN,
        template: (env.TUIST_ORB_TEMPLATE // "default"),
        vcpus: ((env.TUIST_ORB_VCPUS // "2") | tonumber),
        memory_mb: ((env.TUIST_ORB_MEMORY_MB // "4096") | tonumber),
        workspace_gb: ((env.TUIST_ORB_WORKSPACE_GB // "10") | tonumber)
    } + (if (env.AMP_URL // "") != "" then {amp_url: env.AMP_URL} else {} end)
    else {} end)' > "$request"

# Retry only explicit admission refusals, never ambiguous transport failures
# or generic 503s (which can follow VM creation or bootstrap). Each request
# releases server locks before we sleep; the durable Orb ID fences retries.
delay=2
waiting=false
while true; do
    remaining=$((270 - SECONDS))
    (( remaining > 0 )) || { echo 'Tuist Orb dispatch timed out.' >&2; exit 1; }
    (( remaining <= 240 )) || remaining=240
    if [[ -n "${TUIST_WORKLOAD_TOKEN_FILE:-}" ]]; then
        TUIST_TOKEN=$(cat "$TUIST_WORKLOAD_TOKEN_FILE")
        : "${TUIST_TOKEN:?Tuist authentication returned no token}"
    fi
    status=$(jq -nr '"header = " + ("Authorization: Bearer " + env.TUIST_TOKEN | @json)' |
        curl --config - --silent --show-error --max-time "$remaining" --connect-timeout 10 \
            --dump-header "$headers" --output /dev/null --write-out '%{http_code}' \
            --header 'Content-Type: application/json' --data-binary "@$request" \
            "$endpoint")
    [[ "$status" != 204 ]] || exit 0

    if [[ "$ORB_OPERATION" == spawn && "$status" =~ ^(409|429|503)$ ]] &&
        grep -Eiq $'^x-tuist-orb-retry: admission\r?$' "$headers"; then
        wait_remaining=$((wait_seconds - SECONDS))
        if (( wait_remaining <= 0 )); then
            echo 'Timed out waiting for sandbox capacity or account CPU/RAM budget. Please retry shortly.' >&2
            exit 1
        fi
        if [[ "$waiting" == false ]]; then
            echo 'Waiting for sandbox capacity or account CPU/RAM budget…' >&2
            waiting=true
        fi
        sleep_seconds=$((delay + RANDOM % 3))
        (( sleep_seconds <= wait_remaining )) || sleep_seconds=$wait_remaining
        sleep "$sleep_seconds"
        if (( SECONDS >= wait_seconds )); then
            echo 'Timed out waiting for sandbox capacity or account CPU/RAM budget. Please retry shortly.' >&2
            exit 1
        fi
        delay=$((delay * 2))
        (( delay <= 10 )) || delay=10
        continue
    fi
    if [[ "$ORB_OPERATION" == spawn && "$status" == 429 ]] &&
        grep -Eiq $'^x-tuist-orb-refusal: sandbox-limit\r?$' "$headers"; then
        echo 'The Tuist account reached its sandbox limit, and paused Orbs count toward it. Delete threads you no longer need, then retry.' >&2
        exit 1
    fi
    echo "Tuist Orb $ORB_OPERATION failed (HTTP $status)." >&2
    exit 1
done
