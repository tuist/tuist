#!/usr/bin/env bash
# mise description="Migrates the database"

set -euo pipefail

 mix ecto.migrate
