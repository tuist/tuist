#!/usr/bin/env bash
set -euo pipefail

workspace="${GITHUB_WORKSPACE:?}/.build"
test -L "$workspace"
destination="$workspace/native-manifest-cache/swiftpm"
source="$HOME/Library/Caches/org.swift.swiftpm/manifests"
mkdir -p "$destination" "$(dirname "$source")"

if [[ -L "$source" && "$(readlink "$source")" == "$destination" ]]; then
  exit 0
fi

if [[ -e "$source" || -L "$source" ]]; then
  backup=$(mktemp -d "${RUNNER_TEMP:?}/swiftpm-manifests.XXXXXX")
  mv "$source" "$backup/manifests"
fi
ln -s "$destination" "$source"
