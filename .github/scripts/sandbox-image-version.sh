#!/usr/bin/env bash
set -euo pipefail

# Use the last image-input change reachable from the checked-out deployment,
# not the server commit: unrelated deploys must not replace every sandboxd Pod.
source_sha=$(git log -1 --format=%H HEAD -- \
  infra/sandbox-image \
  .github/workflows/sandbox-image.yml \
  .github/scripts/sandbox-image-version.sh)
if [[ ! "$source_sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Cannot resolve sandbox template source commit" >&2
  exit 1
fi
printf 'sha-%s\n' "${source_sha:0:12}"
