#!/bin/sh
# Build only in a new scratch checkout; never replace the fleet's Tart binary.
set -eu
destination=${1:?usage: build-profile-tart.sh /absolute/new/scratch-directory [resident]}
case "${2:-}" in ''|resident) ;; *) echo 'optional build mode must be resident' >&2; exit 1 ;; esac
case "$destination" in /*) ;; *) echo 'scratch path must be absolute' >&2; exit 1 ;; esac
test ! -e "$destination"
patch_dir=$(cd "$(dirname "$0")" && pwd)
git clone --depth 1 --branch 2.41.1 https://github.com/cirruslabs/tart.git "$destination"
cd "$destination"
test "$(git rev-parse HEAD)" = 543453404cd1b15c1338b6b70e162d000c8ba5e2
git apply --check "$patch_dir/tart-2.41.1-profile.patch"
git apply "$patch_dir/tart-2.41.1-profile.patch"
if [ "${2:-}" = resident ]; then
  git apply --check "$patch_dir/tart-2.41.1-resident.patch"
  git apply "$patch_dir/tart-2.41.1-resident.patch"
  cp "$patch_dir/ResidentBenchmark.swift" Sources/tart/ResidentBenchmark.swift
  cp "$patch_dir/EarlyResumeProbe.swift" Sources/tart/EarlyResumeProbe.swift
fi
swift build -c release --jobs 4
mkdir -p profile-tart.app/Contents/MacOS
cp -c .build/release/tart profile-tart.app/Contents/MacOS/tart
cp Resources/Info.plist profile-tart.app/Contents/Info.plist
codesign --force --sign - --entitlements Resources/tart-dev.entitlements profile-tart.app
printf '\nProfiling binary: %s/profile-tart.app/Contents/MacOS/tart\n' "$destination"
printf 'Enable boundaries with TUIST_TART_PROFILE=1. Keep the source and patch with the results.\n'
