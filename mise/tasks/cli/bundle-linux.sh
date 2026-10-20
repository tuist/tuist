#!/usr/bin/env bash
#MISE description="Bundles the CLI for Linux"
#USAGE flag "-v --linux-vm" help="Build and bundle in a Linux container (for local testing)"
#USAGE flag "-a --arch <arch>" help="Target architecture (x86_64 or aarch64). Defaults to the host architecture; the other one is cross-compiled."

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="${MISE_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

ARCH="${usage_arch:-${TUIST_LINUX_ARCH:-$(uname -m)}}"
case "$ARCH" in
    x86_64|amd64) ARCH="x86_64" ;;
    aarch64|arm64) ARCH="aarch64" ;;
    *)
        echo "ERROR: Unsupported architecture: $ARCH" >&2
        exit 1
        ;;
esac

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
        --env TUIST_LINUX_ARCH="$ARCH" \
        swift:6.2 \
        /bin/bash -lc '
            set -euo pipefail
            apt-get update -qq
            apt-get install -y --no-install-recommends build-essential cmake pkg-config curl xz-utils
            case "$(uname -m)" in
                x86_64) mise_arch=x64 ;;
                aarch64) mise_arch=arm64 ;;
                *) exit 1 ;;
            esac
            mkdir -p "$HOME/.local"
            curl --fail --location --silent --show-error \
                "https://github.com/jdx/mise/releases/download/v2026.5.15/mise-v2026.5.15-linux-${mise_arch}.tar.gz" \
                | tar -xz -C "$HOME/.local"
            export PATH="$HOME/.local/mise/bin:$PATH"
            export MISE_TRUSTED_CONFIG_PATHS=/package
            mise install --cd /package/cas-plugin rust
            mise exec --cd /package/cas-plugin -- /bin/bash -c "cd /package; exec /package/mise/tasks/cli/bundle-linux.sh"
        '
fi

# Bundling logic (runs natively on Linux or inside container)
BUILD_DIRECTORY=$PROJECT_ROOT/build
BUILD_PATH="${BUILD_PATH:-.build}"

echo "==> Building Linux release into $BUILD_DIRECTORY"

rm -rf $BUILD_DIRECTORY
mkdir -p $BUILD_DIRECTORY

echo "==> Building the internal Cargo cache runtime"
mkdir -p "$BUILD_PATH"
bash "$PROJECT_ROOT/mise/utilities/build_cargo_cache_linux.sh" \
    "$ARCH" "$(realpath "$BUILD_PATH")/cargo-cache" "$BUILD_DIRECTORY"

SDK_TARGET=$("$PROJECT_ROOT/mise/utilities/install_static_linux_sdk.sh" "$ARCH")

echo "==> Building tuist executable (static musl, $SDK_TARGET)"
swift build --product tuist --configuration release --build-path "$BUILD_PATH" --replace-scm-with-registry --swift-sdk "$SDK_TARGET"

BIN_PATH=$(swift build --product tuist --configuration release --build-path "$BUILD_PATH" --swift-sdk "$SDK_TARGET" --show-bin-path)
echo "==> Copying binary from $BIN_PATH"
cp "$BIN_PATH/tuist" $BUILD_DIRECTORY/tuist

# Binutils' strip only understands the host architecture; llvm-objcopy from the
# Swift toolchain handles both.
echo "==> Stripping release binary"
llvm-objcopy --strip-unneeded "$BUILD_DIRECTORY/tuist"

echo "==> Verifying the binary is a static $ARCH executable"
HEADERS=$(llvm-objdump --file-headers --private-headers "$BUILD_DIRECTORY/tuist")
if ! grep -q "^architecture: $ARCH$" <<< "$HEADERS"; then
    echo "ERROR: tuist is not an $ARCH executable" >&2
    echo "$HEADERS" >&2
    exit 1
fi
if grep -q "INTERP" <<< "$HEADERS"; then
    echo "ERROR: tuist requests a dynamic loader; expected a static executable" >&2
    exit 1
fi

echo "==> Bundling for $ARCH"

(
    cd $BUILD_DIRECTORY

    echo "==> Creating tuist-linux-${ARCH}.tar.gz"
    tar -czvf "tuist-linux-${ARCH}.tar.gz" tuist tuist-cargo-cache cargo-cache-LICENSE cargo-cache-NOTICE
    rm tuist tuist-cargo-cache cargo-cache-LICENSE cargo-cache-NOTICE

    echo "==> Generating checksums"
    : > SHASUMS256.txt
    : > SHASUMS512.txt

    for file in *.tar.gz; do
        echo "$(sha256sum "$file" | awk '{print $1}')  ./$file" >> SHASUMS256.txt
        echo "$(sha512sum "$file" | awk '{print $1}')  ./$file" >> SHASUMS512.txt
    done
)

echo "==> Done"
