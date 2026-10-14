#!/usr/bin/env bash
#MISE description="Bundles the CLI for Linux"
#USAGE flag "-v --linux-vm" help="Build and bundle in a Linux container (for local testing)"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${MISE_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

# If --linux-vm is set and we're not already in a container, re-invoke in container
if [ "$usage_linux_vm" = "true" ]; then
    if command -v podman &>/dev/null; then
        CONTAINER_ENGINE="podman"
    else
        CONTAINER_ENGINE="docker"
    fi

    # Bootstrap variables must expand inside the container, not on the host.
    # shellcheck disable=SC2016
    exec $CONTAINER_ENGINE run --rm \
        --volume "$PROJECT_ROOT:/package" \
        --workdir "/package" \
        --env MISE_PROJECT_ROOT=/package \
        swift:6.2 \
        /bin/bash -lc '
            set -euo pipefail
            apt-get update -qq
            apt-get install -y --no-install-recommends build-essential cmake musl-tools pkg-config curl
            toolchain=$(awk -F "\"" "/^rust =/ {print \$2}" cas-plugin/mise.toml)
            test -n "$toolchain"
            curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain "$toolchain"
            export PATH="$HOME/.cargo/bin:$PATH"
            exec ./mise/tasks/cli/bundle-linux.sh
        '
fi

# Bundling logic (runs natively on Linux or inside container)
BUILD_DIRECTORY=$PROJECT_ROOT/build
BUILD_PATH="${BUILD_PATH:-.build}"

echo "==> Building Linux release into $BUILD_DIRECTORY"

rm -rf $BUILD_DIRECTORY
mkdir -p $BUILD_DIRECTORY

# Install Swift Static Linux SDK for fully static musl-based binaries.
# This eliminates all shared library dependencies and cross-distro compatibility issues
# (e.g. Ubuntu's CURL_OPENSSL_4 vs Fedora's libcurl-minimal).
echo "==> Installing Swift Static Linux SDK"
swift sdk install https://download.swift.org/swift-6.2.3-release/static-sdk/swift-6.2.3-RELEASE/swift-6.2.3-RELEASE_static-linux-0.0.1.artifactbundle.tar.gz \
    --checksum f30ec724d824ef43b5546e02ca06a8682dafab4b26a99fbb0e858c347e507a2c

ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    SDK_TARGET="x86_64-swift-linux-musl"
elif [ "$ARCH" = "aarch64" ]; then
    SDK_TARGET="aarch64-swift-linux-musl"
else
    echo "ERROR: Unsupported architecture: $ARCH" >&2
    exit 1
fi

# Build before the Swift SDK cleanup removes system musl/glibc archives.
echo "==> Building the internal Cargo cache runtime"
RUST_TARGET="${ARCH}-unknown-linux-musl"
rustup target add "$RUST_TARGET"
env CC_x86_64_unknown_linux_musl=musl-gcc CC_aarch64_unknown_linux_musl=musl-gcc \
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER=musl-gcc \
    CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=musl-gcc \
    cargo build --locked --release --manifest-path "$PROJECT_ROOT/cli/native/cargo-cache/Cargo.toml" \
    -p tuist-cargo-cache --bin tuist-cargo-cache --target "$RUST_TARGET" --target-dir "$BUILD_PATH/cargo-cache"
cp "$BUILD_PATH/cargo-cache/$RUST_TARGET/release/tuist-cargo-cache" "$BUILD_DIRECTORY/tuist-cargo-cache"
strip --strip-unneeded "$BUILD_DIRECTORY/tuist-cargo-cache"
cp "$PROJECT_ROOT/cli/native/cargo-cache/LICENSE" "$BUILD_DIRECTORY/cargo-cache-LICENSE"
cp "$PROJECT_ROOT/cli/native/cargo-cache/NOTICE" "$BUILD_DIRECTORY/cargo-cache-NOTICE"

# Remove system static archives that conflict with the musl SDK.
# The musl SDK provides its own minimal static libraries, but the linker also finds
# the system's glibc-based .a files (libcurl with libidn2/libldap/libssh deps,
# libc/libm/zlib with internal glibc symbols, libxml2 with ICU/glibc symbols). Removing these
# forces the linker to use only the musl SDK's versions.
echo "==> Removing conflicting system static libraries"
rm -f /usr/lib/*/libc.a /usr/lib/*/libm.a /usr/lib/*/libm-*.a /usr/lib/*/libcurl.a \
    /usr/lib/*/libxml2.a /usr/lib/*/libz.a

echo "==> Building tuist executable (static musl, $SDK_TARGET)"
swift build --product tuist --configuration release --build-path "$BUILD_PATH" --replace-scm-with-registry --swift-sdk "$SDK_TARGET"

BIN_PATH=$(swift build --product tuist --configuration release --build-path "$BUILD_PATH" --swift-sdk "$SDK_TARGET" --show-bin-path)
echo "==> Copying binary from $BIN_PATH"
cp "$BIN_PATH/tuist" $BUILD_DIRECTORY/tuist

echo "==> Stripping release binary"
strip --strip-unneeded "$BUILD_DIRECTORY/tuist"

echo "==> Bundling for $ARCH"

(
    cd $BUILD_DIRECTORY

    echo "==> Creating tuist-linux-${ARCH}.tar.gz"
    tar -czvf "tuist-linux-${ARCH}.tar.gz" tuist tuist-cargo-cache cargo-cache-LICENSE cargo-cache-NOTICE
    rm tuist tuist-cargo-cache cargo-cache-LICENSE cargo-cache-NOTICE

    echo "==> Generating checksums"
    : >SHASUMS256.txt
    : >SHASUMS512.txt

    for file in *.tar.gz; do
        echo "$(sha256sum "$file" | awk '{print $1}')  ./$file" >>SHASUMS256.txt
        echo "$(sha512sum "$file" | awk '{print $1}')  ./$file" >>SHASUMS512.txt
    done
)

echo "==> Done"
