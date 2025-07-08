#!/usr/bin/env bash
# mise description="Loads the dumped database schema into the database"

set -euo pipefail

(cd server/ && mix ecto.load)
