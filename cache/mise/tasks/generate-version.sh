#!/usr/bin/env bash
#MISE description="Generate version for cache deployments"

set -euo pipefail

# Get the latest cache@x.y.z tag
latest_tag=$(git tag -l "cache@*" | sort -V | tail -n 1)

if [ -z "$latest_tag" ]; then
    # No cache tags found, use default
    echo "0.1.0"
else
    # Extract version from tag (remove "cache@" prefix)
    version="${latest_tag#cache@}"
    echo "$version"
fi
