#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRIV_DIR="${SCRIPT_DIR}/../../priv/native"

cd "$SCRIPT_DIR"

echo "==> Building Swift NIF library..."
swift build -c release --replace-scm-with-registry 2>&1

# Find the built dynamic library
SWIFT_BUILD_DIR=".build/release"
if [ "$(uname)" = "Darwin" ]; then
    DYLIB_NAME="libXCActivityLogNIF.dylib"
else
    DYLIB_NAME="libXCActivityLogNIF.so"
fi

if [ ! -f "$SWIFT_BUILD_DIR/$DYLIB_NAME" ]; then
    echo "ERROR: Could not find $DYLIB_NAME in $SWIFT_BUILD_DIR"
    exit 1
fi

echo "==> Compiling C NIF bridge..."

# Find Erlang NIF headers
ERL_INCLUDE=$(erl -eval 'io:format("~s/erts-~s/include", [code:root_dir(), erlang:system_info(version)])' -s init stop -noshell 2>/dev/null)
if [ -z "$ERL_INCLUDE" ]; then
    echo "ERROR: Could not find Erlang include directory"
    exit 1
fi

echo "    Erlang includes: $ERL_INCLUDE"

# Compile and link the NIF
if [ "$(uname)" = "Darwin" ]; then
    cc -shared -undefined dynamic_lookup \
        -o "$PRIV_DIR/xcactivitylog_nif.so" \
        nif_bridge.c \
        -I"$ERL_INCLUDE" \
        -L"$SWIFT_BUILD_DIR" \
        -lXCActivityLogNIF \
        -Wl,-rpath,"@loader_path"

    # Copy the Swift dylib next to the NIF .so
    cp "$SWIFT_BUILD_DIR/$DYLIB_NAME" "$PRIV_DIR/$DYLIB_NAME"

    # Also copy any Swift runtime libraries that might be needed
    SWIFT_LIB_DIR=$(swift -print-target-info 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['paths']['runtimeLibraryPaths'][0])" 2>/dev/null || true)
    if [ -n "$SWIFT_LIB_DIR" ]; then
        echo "    Swift runtime: $SWIFT_LIB_DIR"
    fi
else
    cc -shared -fPIC \
        -o "$PRIV_DIR/xcactivitylog_nif.so" \
        nif_bridge.c \
        -I"$ERL_INCLUDE" \
        -L"$SWIFT_BUILD_DIR" \
        -lXCActivityLogNIF \
        -Wl,-rpath,'$ORIGIN'

    cp "$SWIFT_BUILD_DIR/$DYLIB_NAME" "$PRIV_DIR/$DYLIB_NAME"
fi

echo "==> NIF built successfully!"
echo "    NIF: $PRIV_DIR/xcactivitylog_nif.so"
echo "    Lib: $PRIV_DIR/$DYLIB_NAME"
