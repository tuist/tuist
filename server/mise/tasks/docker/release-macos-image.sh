#!/usr/bin/env bash
#MISE description="Releases the macOS image"

set -euo pipefail

echo "Make sure you are authenticated against the GitHub registry: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry"

version=$(mise/tasks/generate-version.sh)
docker build server -t ghcr.io/tuist/tuist-macos:$version -t ghcr.io/tuist/tuist-macos:latest
docker push ghcr.io/tuist/tuist-macos:$version
docker push ghcr.io/tuist/tuist-macos:latest
