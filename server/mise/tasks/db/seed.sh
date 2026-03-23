#!/usr/bin/env bash
#MISE description="Seeds data into the database for local development"

set -euo pipefail

"${MISE_PROJECT_ROOT}/mise/utilities/ensure_dev_instance.sh"

mix run priv/repo/timezone.exs
mix run priv/repo/seeds.exs
