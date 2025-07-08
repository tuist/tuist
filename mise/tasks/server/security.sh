#!/usr/bin/env bash
# mise description="Run security static checks"
#USAGE flag "-l --update-lockfile" help="Update the lockfile .sobelow-skips with new findings that have been verified."

if [ "$usage_update_lockfile" = "true" ]; then
  (cd server && mix sobelow --format compact --mark-skip-all)
else
  (cd server && mix sobelow --format compact --skip)
  trivy fs --exit-code 1 --skip-files "server/mix.exs,server/mix.lock" --skip-dirs "server/priv/static,node_modules,deps" ./
fi
