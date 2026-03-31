#!/usr/bin/env bash
#MISE description "Build the Swift NIF library and C bridge"
#MISE raw=true
set -euo pipefail

NIF_DIR="native/xcresult_nif"
PRIV_DIR="priv/native"

echo "==> Building Swift NIF library..."
(cd "$NIF_DIR" && swift build -c release --replace-scm-with-registry 2>&1)

SWIFT_BUILD_DIR="$NIF_DIR/.build/release"
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

mkdir -p "$PRIV_DIR"

cc -shared -undefined dynamic_lookup \
    -o "$PRIV_DIR/xcresult_nif.so" \
    "$NIF_DIR/nif_bridge.c" \
    -I"$ERL_INCLUDE" \
    -L"$SWIFT_BUILD_DIR" \
    -lXCResultNIF \
    -Wl,-rpath,"@loader_path"

cp "$SWIFT_BUILD_DIR/$DYLIB_NAME" "$PRIV_DIR/$DYLIB_NAME"

echo "==> NIF built successfully!"
