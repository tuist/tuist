#!/usr/bin/env bash
# Verifies across the language boundary that a cache token minted by the Tuist
# server authorizes on a cache node locally, without introspection.
#
# The server mints a real token, signed with the secret the extension tests
# verify with, and the kura test reads it back and runs it through the same
# authorization path a live request takes. Neither side constructs the token
# the other expects, so a drift in claim shape, algorithm or issuer fails here.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Spelled as an explicit template rather than `-t cache-token-e2e`, which BSD
# mktemp accepts as a prefix but GNU rejects for having too few X's, so the
# script died on the Linux runner before reaching either half.
token_path="$(mktemp "${TMPDIR:-/tmp}/cache-token-e2e.XXXXXX")"
trap 'rm -f "$token_path"' EXIT

echo "==> minting a cache token from the server"
(
  cd "$root/server"
  CACHE_TOKEN_OUT="$token_path" \
    TUIST_SECRET_KEY_TOKENS="tuist-guardian-secret" \
    mix test test/tuist/cache_e2e_token_test.exs --include e2e_cache_token
)

echo "==> verifying it authorizes on a cache node"
(
  cd "$root/kura"
  CACHE_TOKEN_E2E_PATH="$token_path" cargo test --lib server_minted -- --nocapture
)

echo "==> ok"
