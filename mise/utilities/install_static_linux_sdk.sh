#!/usr/bin/env bash

# Installs the Swift Static Linux SDK and prepares the swift:6.2 container to
# link against it. Shared by the Linux release bundle (mise/tasks/cli/bundle-linux.sh)
# and the PR "Linux Build" job so both compile against the same musl SDK.
# Takes an optional target architecture (x86_64 or aarch64, defaulting to the
# host's); the SDK carries sysroots for both, so either can be built from either
# host. Prints the SDK target triple on stdout.

set -e

SDK_ID="swift-6.2.3-RELEASE_static-linux-0.0.1"

ARCH="${1:-$(uname -m)}"
case "$ARCH" in
    x86_64 | amd64) ARCH="x86_64" ;;
    aarch64 | arm64) ARCH="aarch64" ;;
    *)
        echo "ERROR: Unsupported architecture: $ARCH" >&2
        exit 1
        ;;
esac
SDK_TARGET="$ARCH-swift-linux-musl"

# The static SDK yields fully static musl binaries with no shared library
# dependencies, avoiding cross-distro issues (e.g. Ubuntu's CURL_OPENSSL_4 vs
# Fedora's libcurl-minimal).
if swift sdk list | grep -qxF "$SDK_ID"; then
    echo "==> Swift Static Linux SDK already installed" >&2
else
    echo "==> Installing Swift Static Linux SDK" >&2
    swift sdk install "https://download.swift.org/swift-6.2.3-release/static-sdk/swift-6.2.3-RELEASE/$SDK_ID.artifactbundle.tar.gz" \
        --checksum f30ec724d824ef43b5546e02ca06a8682dafab4b26a99fbb0e858c347e507a2c >&2
fi

# The musl SDK provides its own minimal static libraries, but the linker also finds
# the system's glibc-based .a files (libcurl with libidn2/libldap/libssh deps,
# libc/libm/zlib with internal glibc symbols, libxml2 with ICU/glibc symbols). Removing these
# forces the linker to use only the musl SDK's versions.
echo "==> Removing conflicting system static libraries" >&2
rm -f /usr/lib/*/libc.a /usr/lib/*/libm.a /usr/lib/*/libm-*.a /usr/lib/*/libcurl.a \
    /usr/lib/*/libxml2.a /usr/lib/*/libz.a

# ZIPFoundation and Kanna declare zlib and libxml2 as pkg-config system libraries.
# SwiftPM keeps the host's library directory (/usr/lib/<host-triple>) from the host's
# .pc files, so a cross-compiled link picks up archives of the wrong architecture.
# The SDK's own .pc files cannot replace them: SwiftPM rewrites any -I/-L path that
# contains ".sdk", which mangles every path inside the SDK's musl-*.sdk/<arch> root.
# The sysroot already provides both libraries, and libxml2's headers become reachable
# from its default include directory, where the pkg-config -I would have pointed.
echo "==> Removing host pkg-config files for zlib and libxml2" >&2
rm -f /usr/lib/*/pkgconfig/zlib.pc /usr/lib/*/pkgconfig/libxml-2.0.pc /usr/share/pkgconfig/zlib.pc
SDK_ROOT=$(swift sdk configure --show-configuration "$SDK_ID" "$SDK_TARGET" | sed -n 's/^sdkRootPath: //p')
ln -sfn libxml2/libxml "$SDK_ROOT/usr/include/libxml"

echo "$SDK_TARGET"
