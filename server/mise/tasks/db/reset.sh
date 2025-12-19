#!/usr/bin/env bash
#MISE description="Re-creates and migrates the database and seeds it with data"

set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

if [ -n "${CI:-}" ]; then
  $SCRIPT_DIR/create.sh
  $SCRIPT_DIR/load.sh
else
  $SCRIPT_DIR/drop.sh
  $SCRIPT_DIR/create.sh
  $SCRIPT_DIR/load.sh
  $SCRIPT_DIR/migrate.sh
  if [ "${MIX_ENV:-}" = "test" ]; then
      exit 0
  fi
  $SCRIPT_DIR/seed.sh
fi
