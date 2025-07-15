#!/bin/bash
# mise description="Updates the TuistCacheEE submodule to ensure it's up to date"

set -euo pipefail

echo "Updating TuistCacheEE submodule..."
git submodule update --remote cli/TuistCacheEE
echo "TuistCacheEE submodule updated successfully."
