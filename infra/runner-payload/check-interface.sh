#!/usr/bin/env bash
#
# Fails when a change touches both runner payload sources and the image-owned
# runner-image files the payload runs against, without bumping
# infra/runner-image/payload-interface. The payload ships hours before the
# image, so it must not run on an image that predates the change.
#
# Usage: check-interface.sh <base-ref>
set -euo pipefail

base="${1:?usage: check-interface.sh <base-ref>}"
repo="$(git rev-parse --show-toplevel)"
cd "$repo"

payload_paths=()
while IFS= read -r path; do
  payload_paths+=(":(glob)${path}")
done < <(jq -r '.components[] | select(.name == "runner-payload") | .include_paths[]' mise/tasks/release/components.json)

changed="$(git diff --name-only "${base}...HEAD")"

payload_changed="$(git diff --name-only "${base}...HEAD" -- "${payload_paths[@]}" ':(glob,exclude)**/*.md' ':(glob,exclude)**/*_test.*')"

image_changed="$(git diff --name-only "${base}...HEAD" -- infra/runner-image \
  "${payload_paths[@]/#:(glob)/:(glob,exclude)}" \
  ':(exclude)infra/runner-image/payload-interface' \
  ':(exclude)infra/runner-image/profiles.json' \
  ':(exclude)infra/runner-image/cliff.toml' \
  ':(exclude)infra/runner-image/CHANGELOG.md' \
  ':(glob,exclude)**/*.md' \
  ':(glob,exclude)**/*_test.*')"

if [ -z "$payload_changed" ] || [ -z "$image_changed" ]; then
  exit 0
fi
if grep -qx 'infra/runner-image/payload-interface' <<< "$changed"; then
  exit 0
fi

{
  echo "::error::This change touches runner payload sources and image-owned runner-image files without bumping infra/runner-image/payload-interface."
  echo "Payload sources:"
  awk '{ print "  " $0 }' <<< "$payload_changed"
  echo "Image-owned files:"
  awk '{ print "  " $0 }' <<< "$image_changed"
  echo "Bump payload-interface: images older than this change then keep their own copies until the new image rolls out."
} >&2
exit 1
