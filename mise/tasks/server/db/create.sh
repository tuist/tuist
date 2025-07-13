#!/usr/bin/env bash
# mise description="Creates the database"

set -euo pipefail

(cd server && mix ecto.create)
