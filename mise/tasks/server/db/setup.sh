#!/usr/bin/env bash
# mise description="Sets up the database"

set -euo pipefail

(cd server && mix ecto.load)
