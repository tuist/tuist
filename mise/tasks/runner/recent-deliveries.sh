#!/usr/bin/env bash
#MISE description="List (and optionally redeliver) recent webhook deliveries for the Tuist GitHub App"
#USAGE flag "--env <env>" help="Target environment: production | canary | staging" default="production"
#USAGE flag "--since <iso8601>" help="Only show deliveries delivered_at >= this ISO8601 timestamp (e.g. 2026-05-19T15:20:00Z)"
#USAGE flag "--workflow-job-id <id>" help="Only show deliveries whose payload references this workflow_job_id"
#USAGE flag "--limit <n>" help="Max deliveries to fetch (paginates 100 at a time)" default="200"
#USAGE flag "--redeliver <delivery_id>" help="Redeliver the given delivery_id and exit"
#USAGE flag "--account <op_account>" help="1Password account to query" default="tuist.1password.com"

set -euo pipefail

log()  { printf '[runner:recent-deliveries] %s\n' "$*" >&2; }
fail() { printf '[runner:recent-deliveries] ERROR: %s\n' "$*" >&2; exit 1; }

ENV="${usage_env:-production}"
SINCE="${usage_since:-}"
WORKFLOW_JOB_ID="${usage_workflow_job_id:-}"
LIMIT="${usage_limit:-200}"
REDELIVER="${usage_redeliver:-}"
OP_ACCOUNT="${usage_account:-tuist.1password.com}"

case "$ENV" in
    production|canary|staging) ;;
    *) fail "--env must be one of: production, canary, staging (got: $ENV)";;
esac

readonly VAULT="tuist-k8s-${ENV}"
readonly ITEM="GITHUB_APP"

command -v op      >/dev/null || fail "1Password CLI ('op') not found"
command -v openssl >/dev/null || fail "openssl not found"
command -v jq      >/dev/null || fail "jq not found"
command -v curl    >/dev/null || fail "curl not found"

PEM_FILE="$(mktemp -t tuist-gh-app.XXXXXX.pem)"
chmod 600 "$PEM_FILE"
trap 'rm -f "$PEM_FILE"' EXIT

log "Pulling App credentials from 1Password vault: $VAULT"
APP_ID="$(op read --account "$OP_ACCOUNT" "op://${VAULT}/${ITEM}/app_id" | tr -d '[:space:]')"
op read --account "$OP_ACCOUNT" "op://${VAULT}/${ITEM}/private-key.pem" >"$PEM_FILE"

[[ -n "$APP_ID" ]]    || fail "Empty app_id read from 1Password"
[[ -s "$PEM_FILE" ]]  || fail "Empty private key read from 1Password"

# --- mint a 9-minute RS256 JWT (GitHub caps at 10 min) -----------------------

b64url() { openssl base64 -A | tr -d '=' | tr '/+' '_-'; }

NOW="$(date +%s)"
EXP="$((NOW + 540))"
HEADER='{"alg":"RS256","typ":"JWT"}'
CLAIMS="{\"iat\":${NOW},\"exp\":${EXP},\"iss\":\"${APP_ID}\"}"

HEADER_B64="$(printf '%s' "$HEADER" | b64url)"
CLAIMS_B64="$(printf '%s' "$CLAIMS" | b64url)"
UNSIGNED="${HEADER_B64}.${CLAIMS_B64}"
SIG_B64="$(printf '%s' "$UNSIGNED" | openssl dgst -sha256 -sign "$PEM_FILE" -binary | b64url)"
JWT="${UNSIGNED}.${SIG_B64}"

# Strip the bearer token from any subshell traces — `set -x` would leak it.
gh_api() {
    local method="$1" path="$2"
    curl -sSf \
        -X "$method" \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${JWT}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com${path}"
}

# --- redeliver short-circuit -------------------------------------------------

if [[ -n "$REDELIVER" ]]; then
    log "Redelivering delivery_id=$REDELIVER"
    gh_api POST "/app/hook/deliveries/${REDELIVER}/attempts" >/dev/null
    log "Requested redelivery."
    exit 0
fi

# --- fetch deliveries paginated ---------------------------------------------
#
# The endpoint returns up to 100 per page; pagination is via a cursor in the
# Link header (rel="next") whose query string carries `cursor=<base64>`. We
# follow cursors until we hit `LIMIT` deliveries or the result drops below
# `SINCE`.

decode_link_cursor() {
    awk -F'[,;]' '{
        for (i = 1; i <= NF; i++) {
            if ($i ~ /rel="next"/) {
                for (j = i - 1; j >= 1; j--) {
                    if (match($j, /<[^>]+>/)) {
                        link = substr($j, RSTART + 1, RLENGTH - 2);
                        if (match(link, /cursor=[^&>]+/)) {
                            print substr(link, RSTART + 7, RLENGTH - 7);
                            exit;
                        }
                    }
                }
            }
        }
    }'
}

log "Fetching deliveries (limit=$LIMIT, since=${SINCE:-<none>}, workflow_job_id=${WORKFLOW_JOB_ID:-<any>})"

deliveries='[]'
cursor=""
fetched=0
stop=0

while (( fetched < LIMIT && stop == 0 )); do
    headers_file="$(mktemp -t tuist-gh-deliveries-headers.XXXXXX)"
    path="/app/hook/deliveries?per_page=100"
    [[ -n "$cursor" ]] && path="${path}&cursor=${cursor}"

    body="$(curl -sSf \
        -D "$headers_file" \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${JWT}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com${path}")"

    page_count="$(printf '%s' "$body" | jq 'length')"
    fetched=$((fetched + page_count))

    # Truncate to remaining budget.
    if (( fetched > LIMIT )); then
        keep=$((page_count - (fetched - LIMIT)))
        body="$(printf '%s' "$body" | jq --argjson n "$keep" '.[:$n]')"
        fetched=$LIMIT
    fi

    deliveries="$(jq -s 'add' <(printf '%s' "$deliveries") <(printf '%s' "$body"))"

    # If --since is set and the oldest delivery on this page is already older
    # than the cutoff, stop paginating — subsequent pages only go further back.
    if [[ -n "$SINCE" && "$page_count" -gt 0 ]]; then
        oldest="$(printf '%s' "$body" | jq -r 'last.delivered_at')"
        if [[ "$oldest" < "$SINCE" ]]; then
            stop=1
        fi
    fi

    cursor="$(< "$headers_file" tr -d '\r' | grep -i '^link:' | decode_link_cursor || true)"
    rm -f "$headers_file"
    [[ -z "$cursor" ]] && stop=1
done

# --- client-side filters ----------------------------------------------------

filter='.'
if [[ -n "$SINCE" ]]; then
    filter="$filter | map(select(.delivered_at >= \"$SINCE\"))"
fi
if [[ -n "$WORKFLOW_JOB_ID" ]]; then
    # The deliveries-LIST endpoint doesn't return the payload, only metadata.
    # Filtering by workflow_job_id requires fetching each delivery's full
    # body and matching on `request.payload.workflow_job.id`.
    log "Resolving payloads to filter by workflow_job_id (this is one API call per delivery — be patient)"
    resolved='[]'
    while IFS= read -r id; do
        [[ -z "$id" ]] && continue
        full="$(gh_api GET "/app/hook/deliveries/${id}")"
        match="$(printf '%s' "$full" | jq --argjson wjid "$WORKFLOW_JOB_ID" \
            'if (.request.payload.workflow_job.id // empty) == $wjid then . else empty end')"
        if [[ -n "$match" ]]; then
            resolved="$(jq -s 'add' <(printf '%s' "$resolved") <(printf '[%s]' "$match"))"
        fi
    done < <(printf '%s' "$deliveries" | jq -r ".[] | .id")
    deliveries="$resolved"
    filter='.'
fi

printf '%s' "$deliveries" | jq "$filter | map({id, guid, delivered_at, redelivery, duration, status, status_code, event, action, installation_id, repository_id})"
