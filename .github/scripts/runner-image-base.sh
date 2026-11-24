#!/usr/bin/env bash
#
# Prints the Layer 1 base (`<repository>:<tag>`) a macOS runner image profile
# builds on.
#
# A profile is an Xcode slug (`27.2`, `27.3-beta`) on a macOS 26 Tahoe guest,
# built on ghcr.io/tuist/macos-tahoe-xcode, or an Xcode slug with a
# `-macos-<major>` suffix (`27.2-macos-27`) on that macOS release's guest,
# built on its own base repository. base-xcode-versions.json can point a
# profile at another Xcode's base (an RC base for a stable profile); its value
# keeps the profile's guest suffix.
#
# Usage: runner-image-base.sh <profile> [base-xcode-versions.json]

set -euo pipefail

profile="$1"
base_versions_file="${2:-infra/runner-image/base-xcode-versions.json}"

base="$(jq -r --arg profile "$profile" '.[$profile] // $profile' "$base_versions_file")"
case "$base" in
  *-macos-27)
    repository=ghcr.io/tuist/macos-golden-gate-xcode
    base="${base%-macos-27}"
    ;;
  *-macos-*)
    echo "runner-image-base: no base repository for the guest of profile ${profile}" >&2
    exit 1
    ;;
  *)
    repository=ghcr.io/tuist/macos-tahoe-xcode
    ;;
esac
echo "${repository}:${base//./-}"
