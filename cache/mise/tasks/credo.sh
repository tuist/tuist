#!/usr/bin/env bash
#MISE description="Run Credo"
set -euo pipefail

mix credo --strict
