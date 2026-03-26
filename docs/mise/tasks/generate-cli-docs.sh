#!/usr/bin/env bash
#MISE description="Generates the markdown documentation for the cli files"

set -euo pipefail

./scripts/generate-cli-docs.mjs
