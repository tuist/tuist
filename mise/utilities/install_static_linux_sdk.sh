#!/usr/bin/env bash

# Installs the Swift Static Linux SDK and prepares the swift:6.2 container to
# link against it. Shared by the Linux release bundle (mise/tasks/cli/bundle-linux.sh)
# and the PR "Linux Build" job so both compile against the same musl SDK.
# Prints the SDK target triple for the host architecture on stdout.

set -e

# The static SDK yields fully static musl binaries with no shared library
# dependencies, avoiding cross-distro issues (e.g. Ubuntu's CURL_OPENSSL_4 vs
# Fedora's libcurl-minimal).
echo "==> Installing Swift Static Linux SDK" >&2
swift sdk install https://download.swift.org/swift-6.2.3-release/static-sdk/swift-6.2.3-RELEASE/swift-6.2.3-RELEASE_static-linux-0.0.1.artifactbundle.tar.gz \
    --checksum f30ec724d824ef43b5546e02ca06a8682dafab4b26a99fbb0e858c347e507a2c >&2

# The musl SDK provides its own minimal static libraries, but the linker also finds
# the system's glibc-based .a files (libcurl with libidn2/libldap/libssh deps,
# libc/libm/zlib with internal glibc symbols, libxml2 with ICU/glibc symbols). Removing these
# forces the linker to use only the musl SDK's versions.
echo "==> Removing conflicting system static libraries" >&2
rm -f /usr/lib/*/libc.a /usr/lib/*/libm.a /usr/lib/*/libm-*.a /usr/lib/*/libcurl.a \
    /usr/lib/*/libxml2.a /usr/lib/*/libz.a

ARCH=$(uname -m)
case "$ARCH" in
    x86_64 | aarch64)
        echo "$ARCH-swift-linux-musl"
        ;;
    *)
        echo "ERROR: Unsupported architecture: $ARCH" >&2
        exit 1
        ;;
esac
