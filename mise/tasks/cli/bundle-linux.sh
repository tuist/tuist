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
        ./mise/tasks/cli/bundle-linux.sh
fi

# Bundling logic (runs natively on Linux or inside container)
BUILD_DIRECTORY=$PROJECT_ROOT/build
BUILD_PATH="${BUILD_PATH:-.build}"
SDK_ID="swift-6.2.3-RELEASE_static-linux-0.0.1"
SDK_TARGET="${ARCH}-swift-linux-musl"

echo "==> Building Linux release into $BUILD_DIRECTORY"

rm -rf $BUILD_DIRECTORY
mkdir -p $BUILD_DIRECTORY

# Install Swift Static Linux SDK for fully static musl-based binaries.
# This eliminates all shared library dependencies and cross-distro compatibility issues
# (e.g. Ubuntu's CURL_OPENSSL_4 vs Fedora's libcurl-minimal).
# The SDK carries the sysroots of both architectures, so either one can be built from
# either host.
echo "==> Installing Swift Static Linux SDK"
swift sdk install "https://download.swift.org/swift-6.2.3-release/static-sdk/swift-6.2.3-RELEASE/$SDK_ID.artifactbundle.tar.gz" \
    --checksum f30ec724d824ef43b5546e02ca06a8682dafab4b26a99fbb0e858c347e507a2c

# Remove system static archives that conflict with the musl SDK.
# The musl SDK provides its own minimal static libraries, but the linker also finds
# the system's glibc-based .a files (libcurl with libidn2/libldap/libssh deps,
# libc/libm/zlib with internal glibc symbols, libxml2 with ICU/glibc symbols). Removing these
# forces the linker to use only the musl SDK's versions.
echo "==> Removing conflicting system static libraries"
rm -f /usr/lib/*/libc.a /usr/lib/*/libm.a /usr/lib/*/libm-*.a /usr/lib/*/libcurl.a \
    /usr/lib/*/libxml2.a /usr/lib/*/libz.a

# ZIPFoundation and Kanna declare zlib and libxml2 as pkg-config system libraries. The
# host's .pc files would put the host's library directory (/usr/lib/<host-triple>) on the
# link line, where a cross-compiled link picks up archives of the wrong architecture. The
# SDK's sysroot already provides both libraries; libxml2's headers only need its include
# directory.
echo "==> Removing host pkg-config files for zlib and libxml2"
rm -f /usr/lib/*/pkgconfig/zlib.pc /usr/lib/*/pkgconfig/libxml-2.0.pc /usr/share/pkgconfig/zlib.pc
SDK_ROOT=$(swift sdk configure --show-configuration "$SDK_ID" "$SDK_TARGET" | sed -n 's/^sdkRootPath: //p')

echo "==> Building tuist executable (static musl, $SDK_TARGET)"
swift build --product tuist --configuration release --build-path "$BUILD_PATH" --replace-scm-with-registry --swift-sdk "$SDK_TARGET" \
    -Xcc -I"$SDK_ROOT/usr/include/libxml2"

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
