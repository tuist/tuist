#!/usr/bin/env bash
#MISE description="Build the Noora web package"
set -euo pipefail
cd noora && pnpm run build && mix compile --warnings-as-errors
