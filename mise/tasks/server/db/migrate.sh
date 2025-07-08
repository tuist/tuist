#!/usr/bin/env bash
# mise description="Migrates the database"

set -euo pipefail

(cd server && mix ecto.migrate)
