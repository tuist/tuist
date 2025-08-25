#!/usr/bin/env bash
# mise description="Sets up the database"

set -euo pipefail

mix ecto.load
