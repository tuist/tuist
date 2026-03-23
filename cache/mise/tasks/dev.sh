#!/usr/bin/env bash
#MISE description="Devs the cache application"

set -euo pipefail

"${MISE_PROJECT_ROOT}/mise/utilities/ensure_dev_instance.sh"

mix phx.server
