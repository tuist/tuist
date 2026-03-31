#!/usr/bin/env bash
set -euo pipefail

SERVER_URL="https://staging.tuist.dev"
AUTH_EMAIL="tuistrocks@tuist.dev"
AUTH_PASSWORD="tuistrocks"
ACCOUNT_HANDLE="tuist"
PROJECT_HANDLE="tuist"

AUTH_RESPONSE=$(curl -fsS "$SERVER_URL/api/auth" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$AUTH_EMAIL\",\"password\":\"$AUTH_PASSWORD\"}")
ACCESS_TOKEN=$(printf '%s' "$AUTH_RESPONSE" | jq -r '.access_token // empty')

if [ -z "$ACCESS_TOKEN" ]; then
  echo "::error::Failed to obtain access token"
  exit 1
fi

TOKEN_NAME="cache-load-test"
EXPIRES_AT=$(date -u -d '+6 hours' '+%Y-%m-%dT%H:%M:%SZ')
DELETE_STATUS=$(curl -sS -o /dev/null -w '%{http_code}' \
  "$SERVER_URL/api/accounts/$ACCOUNT_HANDLE/tokens/$TOKEN_NAME" \
  -X DELETE \
  -H "Authorization: Bearer $ACCESS_TOKEN")

if [ "$DELETE_STATUS" != "204" ] && [ "$DELETE_STATUS" != "404" ]; then
  echo "::error::Failed to delete existing account token (status $DELETE_STATUS)"
  exit 1
fi

ACCOUNT_TOKEN_RESPONSE=$(curl -fsS "$SERVER_URL/api/accounts/$ACCOUNT_HANDLE/tokens" \
  -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  -d "$(jq -cn \
    --arg name "$TOKEN_NAME" \
    --arg expires_at "$EXPIRES_AT" \
    --arg project_handle "$PROJECT_HANDLE" \
    '{scopes:["project:cache:read","project:cache:write"], name:$name, expires_at:$expires_at, project_handles:[$project_handle]}')")
CACHE_AUTH_TOKEN=$(printf '%s' "$ACCOUNT_TOKEN_RESPONSE" | jq -r '.token // empty')

if [ -z "$CACHE_AUTH_TOKEN" ]; then
  echo "::error::Failed to obtain account token"
  exit 1
fi

echo "::add-mask::$ACCESS_TOKEN"
echo "::add-mask::$CACHE_AUTH_TOKEN"
echo "CACHE_AUTH_TOKEN=$CACHE_AUTH_TOKEN" >> "$GITHUB_ENV"
