#!/bin/bash
# mise description="Generates the markdown documentation for the cli files"

set -euo pipefail

./scripts/generate-cli-docs.mjs
