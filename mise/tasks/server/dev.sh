#!/usr/bin/env bash
# mise description="Devs the application"

set -euo pipefail

(cd server && mix phx.server)
