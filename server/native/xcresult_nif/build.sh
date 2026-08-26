#!/bin/bash
set -euo pipefail

# Builds the xcresult Swift NIF for macOS. Unlike xcactivitylog_nif (built
# on Linux inside the server Dockerfile), this NIF only ships in the macOS
# release artifact deployed to the Scaleway Mac mini that consumes the
# `:process_xcresult` Oban queue. The xcresult parser leans on
# `xcresulttool` from Xcode, which has no Linux equivalent — the Linux
# server / build-processor pods never load this NIF.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRIV_DIR="${SCRIPT_DIR}/../../priv/native"

cd "$SCRIPT_DIR"

mkdir -p "$PRIV_DIR"

# CI sets this to a path outside the workspace, which `git clean -ffdx`
# would otherwise wipe between runs.
if [ -n "${TUIST_NIF_BUILD_ROOT:-}" ]; then
    SCRATCH_PATH="${TUIST_NIF_BUILD_ROOT}/xcresult_nif"
else
    SCRATCH_PATH="${SCRIPT_DIR}/.build"
fi

echo "==> Building Swift NIF library..."
swift build -c release --replace-scm-with-registry --scratch-path "$SCRATCH_PATH" 2>&1

SWIFT_BUILD_DIR="${SCRATCH_PATH}/release"
DYLIB_NAME="libXCResultNIF.dylib"

if [ ! -f "$SWIFT_BUILD_DIR/$DYLIB_NAME" ]; then
    echo "ERROR: Could not find $DYLIB_NAME in $SWIFT_BUILD_DIR"
    exit 1
fi

echo "==> Compiling C NIF bridge..."

ERL_INCLUDE=$(erl -eval 'io:format("~s/erts-~s/include", [code:root_dir(), erlang:system_info(version)])' -s init stop -noshell 2>/dev/null)
if [ -z "$ERL_INCLUDE" ]; then
    echo "ERROR: Could not find Erlang include directory"
    exit 1
fi

cc -shared -undefined dynamic_lookup \
    -o "$PRIV_DIR/xcresult_nif.so" \
    nif_bridge.c \
    -I"$ERL_INCLUDE" \
    -L"$SWIFT_BUILD_DIR" \
    -lXCResultNIF \
    -Wl,-rpath,"@loader_path"

cp "$SWIFT_BUILD_DIR/$DYLIB_NAME" "$PRIV_DIR/$DYLIB_NAME"

echo "==> Signing NIF binaries..."
codesign -s - -f "$PRIV_DIR/xcresult_nif.so"
codesign -s - -f "$PRIV_DIR/$DYLIB_NAME"

echo "==> NIF built successfully!"
echo "    NIF: $PRIV_DIR/xcresult_nif.so"
echo "    Lib: $PRIV_DIR/$DYLIB_NAME"
