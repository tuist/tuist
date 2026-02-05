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

echo "==> Building tuist executable"
swift build --target tuist --configuration release --build-path "$BUILD_PATH" --replace-scm-with-registry

BIN_PATH=$(swift build --target tuist --configuration release --build-path "$BUILD_PATH" --show-bin-path)
echo "==> Copying binary from $BIN_PATH"
cp "$BIN_PATH/tuist" $BUILD_DIRECTORY/tuist

ARCH=$(uname -m)

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
