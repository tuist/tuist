#!/usr/bin/env bash
#MISE description="Run Grafana + Prometheus locally with the plugin scraping staging.tuist.dev"
set -euo pipefail

STAGING_URL="https://staging.tuist.dev"
STAGING_CREDS="${HOME}/.config/tuist/credentials/staging.tuist.dev.json"
TOKEN_NAME="grafana-local-dev"

# Resolve the developer's Tuist handle from the local CLI session. We refresh
# first so an expired access token in the credentials file doesn't blow up
# the POST below.
if ! command -v tuist >/dev/null 2>&1; then
  echo "ERROR: tuist CLI is required on PATH. Install it via mise or brew." >&2
  exit 1
fi

TUIST_HANDLE=$(tuist auth whoami --url "${STAGING_URL}" 2>/dev/null || true)
if [ -z "${TUIST_HANDLE}" ]; then
  echo "ERROR: not logged in to ${STAGING_URL}. Run:" >&2
  echo "  tuist auth login --url ${STAGING_URL}" >&2
  exit 1
fi

if [ ! -f "${STAGING_CREDS}" ]; then
  echo "ERROR: staging credentials not found at ${STAGING_CREDS}" >&2
  exit 1
fi

mkdir -p .secrets
umask 077

# Mint (or rotate) a short-lived `account:metrics:read` token scoped to this
# developer's account. Pipe straight to the secrets file — the raw token
# never appears in shell history or logs.
ACCESS=$(jq -r .accessToken "${STAGING_CREDS}")
curl -sS -o /dev/null -X DELETE \
  -H "Authorization: Bearer ${ACCESS}" \
  "${STAGING_URL}/api/accounts/${TUIST_HANDLE}/tokens/${TOKEN_NAME}" || true

curl -sS -X POST \
  -H "Authorization: Bearer ${ACCESS}" \
  -H "Content-Type: application/json" \
  -d "{\"scopes\":[\"account:metrics:read\"],\"name\":\"${TOKEN_NAME}\"}" \
  "${STAGING_URL}/api/accounts/${TUIST_HANDLE}/tokens" \
  | jq -r '.token // empty' > .secrets/tuist-metrics-token
chmod 600 .secrets/tuist-metrics-token

if ! head -c 5 .secrets/tuist-metrics-token | grep -q '^tuist'; then
  echo "ERROR: failed to mint a staging metrics token." >&2
  echo "       Verify your staging session with 'tuist auth whoami --url ${STAGING_URL}'." >&2
  exit 1
fi

# Render the Prometheus config with the handle substituted in. Cheaper than
# passing the handle as an env var, and Prometheus doesn't expand env vars
# in its config file anyway.
sed "s|__TUIST_HANDLE__|${TUIST_HANDLE}|g" prometheus.yml.tmpl > .secrets/prometheus.yml
umask 022

# Build once up-front so `dist/` exists before docker-compose mounts it.
pnpm run build

pnpm run dev &
WEBPACK_PID=$!

cleanup() {
  kill $WEBPACK_PID 2>/dev/null || true
  docker compose down --remove-orphans 2>/dev/null || true
}
trap cleanup EXIT

docker compose up --force-recreate
