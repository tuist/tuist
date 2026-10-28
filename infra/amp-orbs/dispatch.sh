#!/usr/bin/env bash
# Invoked by `amp orb provider /absolute/path/to/dispatch.sh`.
set -euo pipefail

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
trap 'rm -f "$request"' EXIT
jq -n '{operation: env.ORB_OPERATION} +
    (if env.ORB_OPERATION == "spawn" then {
        orb_token: env.ORB_TOKEN,
        template: (env.TUIST_ORB_TEMPLATE // "default"),
        vcpus: ((env.TUIST_ORB_VCPUS // "2") | tonumber),
        memory_mb: ((env.TUIST_ORB_MEMORY_MB // "4096") | tonumber),
        workspace_gb: ((env.TUIST_ORB_WORKSPACE_GB // "10") | tonumber)
    } + (if (env.AMP_URL // "") != "" then {amp_url: env.AMP_URL} else {} end)
    else {} end)' > "$request"

# No automatic POST retry: Amp can replay the job against the server's
# durable identity. Leave time inside Amp's five-minute dispatch deadline.
status=$(jq -nr '"header = " + ("Authorization: Bearer " + env.TUIST_TOKEN | @json)' |
    curl --config - --silent --show-error --max-time 240 --connect-timeout 10 \
        --output /dev/null --write-out '%{http_code}' \
        --header 'Content-Type: application/json' --data-binary "@$request" \
        "$endpoint")
if [[ "$status" != 204 ]]; then
    echo "Tuist Orb $ORB_OPERATION failed (HTTP $status)." >&2
    exit 1
fi
