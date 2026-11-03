#!/usr/bin/env bash
set -euo pipefail

# Use the last daemon-input change reachable from the checked-out deployment,
# not the server commit: a new tag restarts sandboxd on every node, pausing
# and restoring each running sandbox. Documentation never enters the image.
source_sha=$(git log -1 --format=%H HEAD -- \
  infra/sandboxd \
  ':(exclude,glob)infra/sandboxd/**/*.md' \
  .github/workflows/sandboxd-image.yml \
  .github/scripts/sandboxd-image-version.sh)
if [[ ! "$source_sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Cannot resolve sandboxd source commit" >&2
  exit 1
fi
printf 'sha-%s\n' "${source_sha:0:12}"
