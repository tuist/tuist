#!/bin/sh
# Content-addressed, host-local build; never replaces the installed CI runtime.
set -eu
root=${1:?build destination}
assets=${2:?source assets}
test ! -e "$root/ready"
mkdir -p "$root"
if [ ! -d "$root/source/.git" ]; then
  git clone --depth 1 --branch 2.41.1 https://github.com/cirruslabs/tart.git "$root/source"
fi
cd "$root/source"
test "$(git rev-parse HEAD)" = 543453404cd1b15c1338b6b70e162d000c8ba5e2
# Always start from the pinned sources after an interrupted build.
git checkout -- Sources/tart/CI/CI.swift Sources/tart/Commands/Run.swift
git apply "$assets/tart.patch"
cp "$assets/ResidentControl.swift" Sources/tart/ResidentControl.swift
swift build -c release --jobs 1
mkdir -p "$root/tart.app/Contents/MacOS"
cp .build/release/tart "$root/tart.app/Contents/MacOS/tart"
cp Resources/Info.plist "$root/tart.app/Contents/Info.plist"
codesign --force --sign - --entitlements Resources/tart-dev.entitlements "$root/tart.app"
touch "$root/ready"
