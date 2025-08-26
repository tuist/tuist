#!/usr/bin/env bash
# mise description="Drops the database"

set -euo pipefail

mix ecto.drop
