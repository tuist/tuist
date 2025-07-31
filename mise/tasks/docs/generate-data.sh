#!/bin/bash
# mise description="Generates all documentation data (manifests and CLI)"

set -euo pipefail

echo "🔨 Generating documentation data..."

echo "📄 Generating manifest data..."
$MISE_PROJECT_ROOT/docs/scripts/generate-manifest-data.mjs

echo "🖥️  Generating CLI data..."
$MISE_PROJECT_ROOT/docs/scripts/generate-cli-data.mjs

echo "✅ All documentation data generated successfully!"