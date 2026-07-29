#!/usr/bin/env bash
#MISE description="Devs the application"

set -euo pipefail

if [ ! -f ../noora/priv/static/noora.js ] || [ ! -f ../noora/priv/static/noora.css ]; then
  pushd ../noora >/dev/null
  aube install
  aube run build
  popd >/dev/null
fi

# Inject dev secrets (e.g. the license) from 1Password via fnox — but only
# when 1Password access is actually available. Contributors without a
# 1Password account fall through to a plain boot, where the missing secrets
# just disable their integrations (OAuth, Stripe, ...) as they did before.
have_1password_access() {
  [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] && return 0
  command -v op >/dev/null 2>&1 && op whoami >/dev/null 2>&1
}

if command -v fnox >/dev/null 2>&1 && [ -f fnox.toml ] && have_1password_access; then
  exec fnox exec -- mix phx.server
else
  exec mix phx.server
fi
