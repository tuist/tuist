#!/bin/bash
#MISE description="Updates the TuistCacheEE submodule to ensure it's up to date"

set -euo pipefail

echo "Updating TuistCacheEE submodule..."

if [ -n "${TUIST_GITHUB_TOKEN:-}" ]; then
   echo "Configuring git to use GitHub token for authentication..."
   # Ensure we always clean up, even if an error occurs later
   cleanup() {
       # Remove all matching rewrites to avoid leaving secrets behind
       git config --global --unset-all url."https://${TUIST_GITHUB_TOKEN}@github.com/".insteadOf || true
   }
   trap cleanup EXIT
   # Set the submodule URL with the token globally so it applies to submodule operations
   git config --global --add url."https://${TUIST_GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
fi

# Check if submodule is initialized
if [ ! -f "cli/TuistCacheEE/.git" ]; then
    echo "Initializing TuistCacheEE submodule..."
    git submodule update --init cli/TuistCacheEE
fi

# Force update the submodule regardless of update=none setting
git submodule update --init --checkout --force cli/TuistCacheEE
