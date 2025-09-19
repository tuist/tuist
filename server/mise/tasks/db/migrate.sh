#!/usr/bin/env bash
#MISE description="Migrates the database"

set -euo pipefail

 mix ecto.migrate
