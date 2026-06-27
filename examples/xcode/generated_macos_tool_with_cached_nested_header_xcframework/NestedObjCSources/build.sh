#!/bin/bash -e

# Builds two static (`.a`) Objective-C library xcframeworks whose public headers
# live in `Headers/<Module>/` subdirectories and re-import each other using the
# framework-prefixed form `#import <Module/X.h>`:
#
#   NestedObjC.xcframework      — stand-in for ARCore's ARCoreGARSession
#   NestedObjCKit.xcframework   — stand-in for ARCore's ARCoreGeospatial; its
#                                 headers import `<NestedObjC/...>` (a cross-module
#                                 import), mirroring ARCoreGeospatial -> ARCoreGARSession.
#
# Both broke when consumed through Tuist's binary cache behind a dynamic framework.
# The bug is in clang header-search / module-map handling and is platform-agnostic,
# so these are built for macOS to keep the acceptance test runnable without a
# simulator. Run from the `NestedObjCSources` directory.

cd "$(dirname "$0")"

MAC_SDK="$(xcrun --sdk macosx --show-sdk-path)"
SRCROOT="$(pwd)"

build_xcframework() {
  local name="$1"
  local work
  work="$(mktemp -d)"
  local out="../$name.xcframework"
  rm -rf "$out"

  # Public headers + module map assembled under a `<Module>/` subdirectory so the
  # slice ends up as `Headers/<name>/{module.modulemap,<name>.h,...}`.
  local headers="$work/Headers"
  mkdir -p "$headers/$name"
  cp "$name"/*.h "$headers/$name/"
  cp "$name/module.modulemap" "$headers/$name/"

  # `-I$SRCROOT` lets a module's sources resolve cross-module imports such as
  # NestedObjCKit's `#import <NestedObjC/Anchor.h>`.
  xcrun --sdk macosx clang -c "$name.m" \
    -arch arm64 -target arm64-apple-macos11 -isysroot "$MAC_SDK" \
    -I"$SRCROOT" -fobjc-arc -o "$work/mac-arm64.o"
  xcrun --sdk macosx clang -c "$name.m" \
    -arch x86_64 -target x86_64-apple-macos11 -isysroot "$MAC_SDK" \
    -I"$SRCROOT" -fobjc-arc -o "$work/mac-x86_64.o"
  xcrun libtool -static -o "$work/lib$name.a" "$work/mac-arm64.o" "$work/mac-x86_64.o"

  xcrun xcodebuild -create-xcframework \
    -library "$work/lib$name.a" -headers "$headers" \
    -output "$out"

  rm -rf "$work"
  echo "Built $out"
}

build_xcframework NestedObjC
build_xcframework NestedObjCKit
