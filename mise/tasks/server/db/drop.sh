#!/usr/bin/env bash
# mise description="Drops the database"

set -euo pipefail

(cd server && mix ecto.drop)
