#!/usr/bin/env bash
#MISE description="Run Credo on the slack app"
set -euo pipefail

mix credo --strict
