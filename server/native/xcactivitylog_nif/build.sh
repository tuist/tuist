#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRIV_DIR="${SCRIPT_DIR}/../../priv/native"

cd "$SCRIPT_DIR"

# CI checks out onto a persistent workspace and `actions/checkout` runs
# `git clean -ffdx`, which deletes an in-tree .build and forces a cold Swift
# compile on every run. TUIST_NIF_BUILD_ROOT moves the scratch directory
# outside the workspace so it survives the clean.
if [ -n "${TUIST_NIF_BUILD_ROOT:-}" ]; then
    SCRATCH_PATH="${TUIST_NIF_BUILD_ROOT}/xcactivitylog_nif"
else
    SCRATCH_PATH="${SCRIPT_DIR}/.build"
fi

EXECUTABLE_NAME="xcactivitylog-parser"

echo "==> Building Swift xcactivitylog parser..."
swift build -c release --replace-scm-with-registry --scratch-path "$SCRATCH_PATH" \
    --product "$EXECUTABLE_NAME" 2>&1

SWIFT_BUILD_DIR="${SCRATCH_PATH}/release"

if [ ! -f "$SWIFT_BUILD_DIR/$EXECUTABLE_NAME" ]; then
    echo "ERROR: Could not find $EXECUTABLE_NAME in $SWIFT_BUILD_DIR"
    exit 1
fi

mkdir -p "$PRIV_DIR"
cp "$SWIFT_BUILD_DIR/$EXECUTABLE_NAME" "$PRIV_DIR/$EXECUTABLE_NAME"
chmod +x "$PRIV_DIR/$EXECUTABLE_NAME"

echo "==> Signing parser..."
codesign -s - -f "$PRIV_DIR/$EXECUTABLE_NAME"

echo "==> Parser built successfully!"
echo "    Executable: $PRIV_DIR/$EXECUTABLE_NAME"
