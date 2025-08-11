#!/bin/bash
# mise description="Updates the TuistCacheEE submodule to ensure it's up to date"

set -euo pipefail

echo "Updating TuistCacheEE submodule..."

# Check if submodule is initialized
if [ ! -f "cli/TuistCacheEE/.git" ]; then
    echo "Initializing TuistCacheEE submodule..."
    git submodule update --init cli/TuistCacheEE
fi

# Force update the submodule regardless of update=none setting
git submodule update --init --remote --force cli/TuistCacheEE
echo "TuistCacheEE submodule updated successfully."
