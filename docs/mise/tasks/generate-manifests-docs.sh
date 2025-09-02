#!/usr/bin/env bash
#MISE description="Generates the markdown documentation for the manifest files"

set -euo pipefail

./scripts/generate-manifest-docs.mjs
