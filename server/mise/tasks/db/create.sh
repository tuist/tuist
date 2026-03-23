#!/usr/bin/env bash
#MISE description="Creates the database"

set -euo pipefail

mix ecto.create
