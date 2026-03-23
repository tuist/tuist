#!/usr/bin/env bash
#MISE description="Migrates the database"

set -euo pipefail

"${MISE_PROJECT_ROOT}/mise/utilities/ensure_dev_instance.sh"

mix ecto.migrate
