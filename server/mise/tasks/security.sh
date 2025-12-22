#!/usr/bin/env bash
#MISE description="Run security static checks"
#USAGE flag "-l --update-lockfile" help="Update the lockfile .sobelow-skips with new findings that have been verified."

set -euo pipefail

if [ "${usage_update_lockfile:-}" = "true" ]; then
  mix sobelow --format compact --mark-skip-all
else
  mix sobelow --format compact --skip
  trivy fs --exit-code 1 --skip-files "mix.exs,mix.lock" --skip-dirs "priv/static,node_modules,deps" ./
fi
