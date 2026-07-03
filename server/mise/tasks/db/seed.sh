#!/usr/bin/env bash
#MISE description="Seeds data into the database for local development"

set -euo pipefail

mix run priv/repo/timezone.exs

# The seeds read dev secrets from fnox/1Password (e.g. the Okta SSO config in
# priv/repo/seeds.exs), so run them under `fnox exec` when 1Password access is
# available. Contributors without it seed plainly — those steps skip gracefully
# (the seed prints "Skipping Okta SSO seed", etc.).
have_1password_access() {
  [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] && return 0
  command -v op >/dev/null 2>&1 && op whoami >/dev/null 2>&1
}

if command -v fnox >/dev/null 2>&1 && [ -f fnox.toml ] && have_1password_access; then
  exec fnox exec -- mix run priv/repo/seeds.exs
else
  exec mix run priv/repo/seeds.exs
fi
