#!/usr/bin/env bash
#MISE description="Drops the database"

set -euo pipefail

mix ecto.drop
