#!/usr/bin/env bash
#MISE description="Run LLM-based translations for .po files"

set -euo pipefail

elixir "${MISE_PROJECT_ROOT}/translate.exs" "$@"
