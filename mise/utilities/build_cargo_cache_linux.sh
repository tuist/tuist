#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARCH="${1:?Expected x86_64 or aarch64}"
TARGET_DIR="${2:?Expected an absolute target directory}"
DESTINATION="${3:?Expected a destination directory}"
case "$ARCH" in
    x86_64|aarch64) ;;
    *) echo "Unsupported Cargo cache architecture: $ARCH" >&2; exit 1 ;;
esac
RUST_TARGET="${ARCH}-unknown-linux-musl"
RUST_TOOLCHAIN=$(awk -F '"' '/^rust =/ {print $2}' "$PROJECT_ROOT/cas-plugin/mise.toml")
test -n "$RUST_TOOLCHAIN"
rustup target add --toolchain "$RUST_TOOLCHAIN" "$RUST_TARGET"
# Zig supplies the target's C compiler and linker even when the release runner is
# amd64 and the requested archive is arm64. Host musl-gcc cannot cross-compile it.
mise exec --cd "$PROJECT_ROOT/cli/native/cargo-cache" "rust@$RUST_TOOLCHAIN" -- cargo zigbuild \
    --locked --release --manifest-path "$PROJECT_ROOT/cli/native/cargo-cache/Cargo.toml" \
    -p tuist-cargo-cache --bin tuist-cargo-cache --target "$RUST_TARGET" --target-dir "$TARGET_DIR"
mkdir -p "$DESTINATION"
cp "$TARGET_DIR/$RUST_TARGET/release/tuist-cargo-cache" "$DESTINATION/tuist-cargo-cache"
HEADERS=$(llvm-objdump --file-headers --private-headers "$DESTINATION/tuist-cargo-cache")
if ! grep -q "^architecture: $ARCH$" <<< "$HEADERS" || grep -q "INTERP" <<< "$HEADERS"; then
    echo "ERROR: Cargo cache helper must be a static $ARCH executable" >&2
    echo "$HEADERS" >&2
    exit 1
fi
cp "$PROJECT_ROOT/cli/native/cargo-cache/LICENSE" "$DESTINATION/cargo-cache-LICENSE"
cp "$PROJECT_ROOT/cli/native/cargo-cache/NOTICE" "$DESTINATION/cargo-cache-NOTICE"
