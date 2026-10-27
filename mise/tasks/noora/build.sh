#!/usr/bin/env bash
#MISE description="Build the Noora web package"
set -euo pipefail
cd noora
aube install
aube run build
mix compile --warnings-as-errors
