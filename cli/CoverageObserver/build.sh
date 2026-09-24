#!/usr/bin/env bash
# Builds the coverage observer next to the `tuist` executable that will inject it:
#   libtuist_coverage_observer.dylib            macOS (arm64 + x86_64)
#   libtuist_coverage_observer_iossimulator.dylib  iOS simulator (arm64 + x86_64)
#
#   build.sh <output directory>
set -euo pipefail

output=${1:?usage: build.sh <output directory>}
source=$(cd "$(dirname "$0")" && pwd)/TuistCoverageObserver.m
mkdir -p "$output"

build() {
    local sdk=$1 name=$2
    shift 2
    local slices=()
    for target in "$@"; do
        local slice
        slice=$(mktemp -t tuist_coverage_observer)
        xcrun --sdk "$sdk" clang -dynamiclib -fobjc-arc -O2 -Wall -Wno-arc-performSelector-leaks \
            -target "$target" -framework Foundation \
            -install_name "$name" -o "$slice" "$source"
        slices+=("$slice")
    done
    lipo -create "${slices[@]}" -output "$output/$name"
    rm -f "${slices[@]}"
}

build macosx libtuist_coverage_observer.dylib arm64-apple-macos11.0 x86_64-apple-macos11.0
build iphonesimulator libtuist_coverage_observer_iossimulator.dylib arm64-apple-ios14.0-simulator x86_64-apple-ios14.0-simulator
