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

# A top-level 404 disables Cloudflare Pages' implicit SPA fallback. Existing
# symbols have generated HTML; unknown symbols must not return the root with 200.
# The source-rendered export keeps this Swift-only build independent of Phoenix.
cp "$MISE_PROJECT_ROOT/assets/marketing/404.html" "$MISE_PROJECT_ROOT/.build/documentation/404.html"

echo "/ /documentation/projectdescription/project 301" > "$MISE_PROJECT_ROOT/.build/documentation/_redirects"

echo "Documentation generated at $MISE_PROJECT_ROOT/.build/documentation"
