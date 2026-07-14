#!/bin/bash
# Runs all search indexers: DocC API reference, GitHub issues and pull requests,
# and GitHub releases.
# Called by cron inside the container. DocSearch scraper is excluded
# because it requires a separate Docker container with network access.
set -euo pipefail

echo "==> Indexing DocC (ProjectDescription)..."
/opt/docsearch/index-docc
echo "==> Done with DocC indexer"

echo "==> Indexing GitHub issues and PRs..."
/opt/docsearch/index-github
echo "==> Done with GitHub indexer"

echo "==> Indexing GitHub releases..."
/opt/docsearch/index-github-releases
echo "==> Done with GitHub releases indexer"
