#!/usr/bin/env bash
#MISE description="Loads the dumped database schema into the database"

set -euo pipefail

mix ecto.load
