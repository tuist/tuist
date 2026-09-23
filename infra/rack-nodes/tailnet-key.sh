#!/usr/bin/env bash
# Mints the tailnet join key an install stick carries: single-use,
# pre-authorized, not ephemeral, carrying the host's tags, expiring after
# `hours`. Minted from the OAuth client the operator also holds, which never
# leaves 1Password for the stick. Prints the key's ID, a tab, and the key.
# Sourced: mint_tailnet_key <vault> <item> <tags-json> <hours> <host>

mint_tailnet_key() {
  local vault="$1" item="$2" tags="$3" hours="$4" host="$5"
  local api="${TAILSCALE_API:-https://api.tailscale.com/api/v2}"
  local client_id token body response

  client_id="$(op read "op://$vault/$item/client-id")" || return 1
  token="$(op read "op://$vault/$item/client-secret" |
    curl -fsS -X POST "$api/oauth/token" \
      --data-urlencode "client_id=$client_id" \
      --data-urlencode "client_secret@-" | jq -r '.access_token // empty')"
  if [ -z "$token" ]; then
    echo "error: could not exchange the $item OAuth client for a token" >&2
    return 1
  fi

  body="$(jq -nc --argjson tags "$tags" --argjson seconds "$((hours * 3600))" --arg description "rack install $host" '{
    capabilities: {devices: {create: {reusable: false, ephemeral: false, preauthorized: true, tags: $tags}}},
    expirySeconds: $seconds,
    description: $description
  }')"
  response="$(printf 'header = "Authorization: Bearer %s"\n' "$token" |
    curl -fsS -X POST "$api/tailnet/-/keys" --config - \
      -H "Content-Type: application/json" --data-binary "$body")" || {
    echo "error: Tailscale refused to mint a join key for $host with tags $tags" >&2
    return 1
  }
  jq -r '"\(.id)\t\(.key)"' <<<"$response"
}
