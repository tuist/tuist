#!/usr/bin/env bash
# mise description="Run security static checks"
#USAGE flag "-l --update-lockfile" help="Update the lockfile .sobelow-skips with new findings that have been verified."

if [ "$usage_update_lockfile" = "true" ]; then
  (cd server && mix sobelow --format compact --mark-skip-all)
else
  (cd server && mix sobelow --format compact --skip)
  (cd server && trivy fs --exit-code 1 --skip-files "mix.exs,mix.lock" --skip-dirs "priv/static,node_modules,deps" ./)
fi
