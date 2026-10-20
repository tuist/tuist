#!/usr/bin/env bash
set -euo pipefail

app="${1:?Pass the delivery app bundle to version}"
version="${ATLAS_BUILD_VERSION:-$(date +%s)}"
[[ "$version" =~ ^[1-9][0-9]*$ ]] || { echo "Expected a positive integer build version" >&2; exit 1; }
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$app/Info.plist"
