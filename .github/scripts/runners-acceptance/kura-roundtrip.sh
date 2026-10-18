#!/usr/bin/env bash
# Proves the cache endpoint dispatch handed this job serves an authenticated
# write and read, using a token minted from the job's GitHub OIDC identity the
# way the CLI mints one. A Kura that answers /up but cannot validate tokens (its
# introspection call to the server fails) passes a health check and fails here.
#
# Env: TUIST_URL, ACCOUNT_HANDLE, and optionally EXPECTED_CACHE_HOST (the host
# dispatch must hand this site's jobs) and TUIST_CACHE_ENDPOINT.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

[ -n "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ] || fail "Server auth" "the job has no GitHub OIDC token (needs id-token: write)"
oidc="$(curl -sS -m 15 -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=tuist" | sed -n 's/.*"value":"\([^"]*\)".*/\1/p')"
[ -n "${oidc}" ] || fail "Server auth" "GitHub issued no OIDC token"
code="$(curl -sS -m 15 -o "${work}/token" -w '%{http_code}' -X POST -H 'content-type: application/json' \
  -d "{\"token\":\"${oidc}\"}" "${TUIST_URL}/api/auth/oidc/token" || true)"
token="$(sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p' "${work}/token")"
[ -n "${token}" ] || fail "Server auth" "${TUIST_URL} minted no token for this repository's OIDC identity (HTTP ${code}): $(head -c 300 "${work}/token")"
pass "Server ${TUIST_URL} minted a token from the job's OIDC identity"

endpoint="${TUIST_CACHE_ENDPOINT:-}"
if [ -n "${EXPECTED_CACHE_HOST:-}" ]; then
  [ -n "${endpoint}" ] || fail "Dispatch" "dispatch handed this job no cache endpoint; this site's jobs must get ${EXPECTED_CACHE_HOST}"
  host="$(cache_endpoint_host "${endpoint}")"
  [ "${host}" = "${EXPECTED_CACHE_HOST}" ] || fail "Dispatch" "dispatch handed this job ${endpoint}; this site's jobs must get ${EXPECTED_CACHE_HOST}"
fi
if [ -z "${endpoint}" ]; then
  curl -sS -m 15 -o "${work}/endpoints" -H "Authorization: Bearer ${token}" -H 'x-tuist-cli-version: x.y.z' \
    "${TUIST_URL}/api/cache/endpoints?account_handle=${ACCOUNT_HANDLE}" || true
  endpoint="$(sed -n 's/.*"endpoints":\["\([^"]*\)".*/\1/p' "${work}/endpoints")"
  [ -n "${endpoint}" ] || fail "Dispatch" "dispatch handed no cache endpoint and ${TUIST_URL} resolved none: $(head -c 300 "${work}/endpoints")"
  pass "Dispatch handed no private cache endpoint; using the server-resolved ${endpoint}"
else
  pass "Dispatch handed cache endpoint ${endpoint}"
fi
endpoint="${endpoint%/}"

code="$(curl -sS -m 10 -o "${work}/up" -w '%{http_code}' "${endpoint}/up" 2> "${work}/up.err" || true)"
[ "${code}" = 200 ] || fail "Kura reachability" "GET ${endpoint}/up returned HTTP ${code}: $(cat "${work}/up.err" "${work}/up" 2>/dev/null | head -c 300)"
pass "GET ${endpoint}/up answered 200"

classify() {
  local operation="$1" code="$2" body="$3"
  case "${code}" in
    2*) return 0 ;;
    000) fail "Kura data path" "${operation} did not complete: $(head -c 300 "${body}.err" 2>/dev/null)" ;;
  esac
  if grep -qiE 'authentication backend|backend.unavailable' "${body}" 2>/dev/null; then
    fail "Kura auth" "${operation} returned HTTP ${code}: Kura cannot validate tokens, so its introspection call to the server is failing: $(head -c 300 "${body}")"
  fi
  case "${code}" in
    401 | 403) fail "Kura auth" "${operation} rejected the server-minted token with HTTP ${code}: $(head -c 300 "${body}")" ;;
    *) fail "Kura data path" "${operation} returned HTTP ${code}: $(head -c 300 "${body}")" ;;
  esac
}

key="runners-acceptance-$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
query="tenant_id=${ACCOUNT_HANDLE}&namespace_id=${ACCOUNT_HANDLE}"
head -c 1048576 /dev/urandom > "${work}/blob"
started=$(date +%s)
code="$(curl -sS -m 30 -o "${work}/put" -w '%{http_code}' -X POST -H "Authorization: Bearer ${token}" \
  -H 'content-type: application/octet-stream' --data-binary @"${work}/blob" \
  "${endpoint}/api/cache/cas/${key}?${query}" 2> "${work}/put.err" || true)"
classify "POST /api/cache/cas" "${code}" "${work}/put"
code="$(curl -sS -m 30 -o "${work}/got" -w '%{http_code}' -H "Authorization: Bearer ${token}" \
  "${endpoint}/api/cache/cas/${key}?${query}" 2> "${work}/got.err" || true)"
classify "GET /api/cache/cas" "${code}" "${work}/got"
cmp -s "${work}/blob" "${work}/got" || fail "Kura data path" "GET /api/cache/cas returned different bytes than were written"
pass "Wrote and read back a 1 MiB blob through ${endpoint} in $(($(date +%s) - started))s"

echo "TUIST_ACCEPTANCE_CACHE_ENDPOINT=${endpoint}" >> "${GITHUB_ENV:-/dev/null}"
