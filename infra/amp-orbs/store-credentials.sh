#!/usr/bin/env bash
# Run interactively once per environment as a Tuist account administrator.
# A fresh isolated login avoids sharing a rotating session with a developer CLI.
set -euo pipefail
case "${1:-}" in
  staging|canary) environment=$1; url="https://$1.tuist.dev" ;;
  production) environment=$1; url=https://tuist.dev ;;
  *) echo "Usage: $0 staging|canary|production" >&2; exit 1 ;;
esac
vault="tuist-k8s-$environment"
item='Amp Orb Tuist Credentials'
umask 077
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
# Read only item identities, never the existing credential contents.
items=$(op item list --vault "$vault" --format json | jq --arg title "$item" '[.[] | select(.title == $title) | .id]')
[[ $(jq length <<< "$items") -le 1 ]] || { echo "More than one $item item exists in $vault; resolve the duplicate first." >&2; exit 1; }
item_id=$(jq -r '.[0] // empty' <<< "$items")
export XDG_CONFIG_HOME="$scratch/config" XDG_STATE_HOME="$scratch/state" XDG_CACHE_HOME="$scratch/cache"
unset TUIST_TOKEN TUIST_CONFIG_TOKEN TUIST_CONFIG_CLOUD_TOKEN TUIST_XDG_CONFIG_HOME TUIST_XDG_STATE_HOME TUIST_XDG_CACHE_HOME
printf 'Sign in to %s as an administrator of the account configured for the provider.\n' "$url"
tuist auth login --url "$url"
credentials="$XDG_CONFIG_HOME/tuist/credentials/${url#https://}.json"
jq -e '(.accessToken | type == "string" and length > 0) and
  (.refreshToken | type == "string" and length > 0) and (.rejected != true)' "$credentials" >/dev/null
# Feed the credential through stdin, never command arguments or terminal output.
jq -n --rawfile credential "$credentials" --arg title "$item" '{
  title: $title, category: "PASSWORD",
  fields: [{id: "password", type: "CONCEALED", purpose: "PASSWORD", label: "password", value: $credential}]
}' > "$scratch/item.json"
if [[ -n "$item_id" ]]; then
  op item edit "$item_id" --vault "$vault" --template "$scratch/item.json" --format json |
    jq '{id, title, vault: .vault.name}'
else
  op item create --vault "$vault" --template "$scratch/item.json" --format json |
    jq '{id, title, vault: .vault.name}'
fi
printf 'Saved a dedicated provider login in %s. The local temporary session was removed.\n' "$vault"
