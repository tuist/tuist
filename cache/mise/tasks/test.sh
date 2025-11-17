#!/usr/bin/env bash
#MISE description="Run test suite"
set -euo pipefail

MIX_ENV=test mix test --warnings-as-errors
