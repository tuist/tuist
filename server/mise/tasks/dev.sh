#!/usr/bin/env bash
#MISE description="Devs the application"

set -euo pipefail

if [ ! -f ../noora/priv/static/noora.js ] || [ ! -f ../noora/priv/static/noora.css ]; then
  pushd .. >/dev/null
  aube install --filter noora
  popd >/dev/null
  pushd ../noora >/dev/null
  aube run build
  popd >/dev/null
fi

mix phx.server
