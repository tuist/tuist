#!/usr/bin/env bash
# mise description="Creates the database"

set -euo pipefail

mix ecto.create
