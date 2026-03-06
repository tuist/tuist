#!/usr/bin/env bash
#MISE description="Build ProjectDescription DocC documentation"

set -euo pipefail

swift package --package-path "$MISE_PROJECT_ROOT" \
  --replace-scm-with-registry \
  --allow-writing-to-directory "$MISE_PROJECT_ROOT/.build/documentation" \
  generate-documentation \
  --product ProjectDescription \
  --disable-indexing \
  --output-path "$MISE_PROJECT_ROOT/.build/documentation" \
  --transform-for-static-hosting \
  --hosting-base-path ""

echo "/ /documentation/projectdescription/project 301" > "$MISE_PROJECT_ROOT/.build/documentation/_redirects"

echo "Documentation generated at $MISE_PROJECT_ROOT/.build/documentation"
