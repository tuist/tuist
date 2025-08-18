#!/bin/bash
# mise description="Generates the markdown documentation for the manifest files"

set -euo pipefail

./scripts/generate-manifest-docs.mjs
