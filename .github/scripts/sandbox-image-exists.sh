#!/usr/bin/env bash
set -euo pipefail

# Authentication/network failures must not be mistaken for an absent image:
# rebuilding in that case could overwrite an already published source tag.
error_file=$(mktemp)
trap 'rm -f "$error_file"' EXIT
if docker buildx imagetools inspect "$1" >/dev/null 2>"$error_file"; then
  echo true
elif grep -qiE 'manifest unknown|: not found' "$error_file"; then
  echo false
else
  cat "$error_file" >&2
  exit 1
fi
