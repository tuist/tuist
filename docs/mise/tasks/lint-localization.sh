#!/bin/bash
set -euo pipefail

cd "$MISE_PROJECT_ROOT"
node scripts/lint-localization.mjs
