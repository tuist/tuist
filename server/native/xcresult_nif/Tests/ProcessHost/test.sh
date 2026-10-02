#!/bin/bash
set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc -parse-as-library \
    "$PACKAGE_DIR/Sources/XCResultParser/XCResultTool.swift" \
    "$PACKAGE_DIR/Tests/ProcessHost/Probe.swift" \
    -o "$TEST_DIR/probe"
"$TEST_DIR/probe" default
"$TEST_DIR/probe" ignored
