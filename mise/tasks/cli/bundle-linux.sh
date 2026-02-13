#!/usr/bin/env bash
#MISE description="Bundles the CLI for Linux"
#USAGE flag "-v --linux-vm" help="Build and bundle in a Linux container (for local testing)"

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="${MISE_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

# If --linux-vm is set and we're not already in a container, re-invoke in container
if [ "$usage_linux_vm" = "true" ]; then
    if command -v podman &> /dev/null; then
        CONTAINER_ENGINE="podman"
    else
        CONTAINER_ENGINE="docker"
    fi

    exec $CONTAINER_ENGINE run --rm \
        --volume "$PROJECT_ROOT:/package" \
        --workdir "/package" \
        --env MISE_PROJECT_ROOT=/package \
        swift:6.1 \
        ./mise/tasks/cli/bundle-linux.sh
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
swift sdk install https://download.swift.org/swift-6.1.2-release/static-sdk/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE_static-linux-0.0.1.artifactbundle.tar.gz \
    --checksum df0b40b9b582598e7e3d70c82ab503fd6fbfdff71fd17e7f1ab37115a0665b3b

ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    SDK_TARGET="x86_64-swift-linux-musl"
elif [ "$ARCH" = "aarch64" ]; then
    SDK_TARGET="aarch64-swift-linux-musl"
else
    echo "ERROR: Unsupported architecture: $ARCH" >&2
    exit 1
fi

echo "==> Building tuist executable (static musl, $SDK_TARGET)"
swift build --product tuist --configuration release --build-path "$BUILD_PATH" --replace-scm-with-registry --swift-sdk "$SDK_TARGET" -Xswiftc -static-executable

BIN_PATH=$(swift build --product tuist --configuration release --build-path "$BUILD_PATH" --swift-sdk "$SDK_TARGET" -Xswiftc -static-executable --show-bin-path)
echo "==> Copying binary from $BIN_PATH"
cp "$BIN_PATH/tuist" $BUILD_DIRECTORY/tuist

echo "==> Bundling for $ARCH"

(
    cd $BUILD_DIRECTORY

    echo "==> Creating tuist-linux-${ARCH}.tar.gz"
    tar -czvf "tuist-linux-${ARCH}.tar.gz" tuist
    rm tuist

    echo "==> Generating checksums"
    : > SHASUMS256.txt
    : > SHASUMS512.txt

    for file in *.tar.gz; do
        echo "$(sha256sum "$file" | awk '{print $1}')  ./$file" >> SHASUMS256.txt
        echo "$(sha512sum "$file" | awk '{print $1}')  ./$file" >> SHASUMS512.txt
    done
)

echo "==> Done"
