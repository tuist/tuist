#!/usr/bin/env bash
#MISE description="Generate version for server deployments"

set -euo pipefail

# Get the latest server@x.y.z tag
latest_tag=$(git tag -l "server@*" | sort -V | tail -n 1)

if [ -z "$latest_tag" ]; then
    # No server tags found, use default
    echo "0.1.0"
else
    # Extract version from tag (remove "server@" prefix)
    version="${latest_tag#server@}"
    echo "$version"
fi
