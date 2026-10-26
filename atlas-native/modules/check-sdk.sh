#!/usr/bin/env bash
set -euo pipefail

sdk="$1"
binary="$2"
metadata=$(xcrun vtool -show-build "$binary")
printf '%s\n' "$metadata"
expected=$(xcrun --sdk "$sdk" --show-sdk-version)
echo "Require SDK $expected and minimum iOS 17.0: $binary"
test "$(awk '$1 == "sdk" { print $2 }' <<< "$metadata")" = "$expected"
test "$(awk '$1 == "minos" { print $2 }' <<< "$metadata")" = "17.0"
