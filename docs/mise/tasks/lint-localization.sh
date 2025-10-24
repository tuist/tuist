#!/bin/bash
set -euo pipefail

node -C "$MISE_PROJECT_ROOT" scripts/lint-localization.mjs
