#!/usr/bin/env bash
#MISE description="Sets up the database"

set -euo pipefail

mix ecto.load
