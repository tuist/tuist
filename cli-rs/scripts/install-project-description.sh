#!/usr/bin/env bash
# A plain `swift build` does not emit a ProjectDescription module that manifests can
# compile against. This builds it with library evolution in its own scratch path and
# places the interface and dylib where the CLI looks: next to the binaries, with the
# module under `Modules/`. It affects the Swift `tuist` and the Rust binary alike.
#
# Usage: cli-rs/scripts/install-project-description.sh [debug|release]
set -euo pipefail

CONFIGURATION=${1:-debug}
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRATCH="$REPO_ROOT/.build/project-description-evolution"
cd "$REPO_ROOT"
swift build --configuration "$CONFIGURATION" --replace-scm-with-registry --force-resolved-versions \
    --scratch-path "$SCRATCH" --product ProjectDescription \
    -Xswiftc -enable-library-evolution -Xswiftc -emit-module-interface
INTERFACE_DIR=$(dirname "$(find -L "$SCRATCH" -name ProjectDescription.swiftinterface -path "*$CONFIGURATION*" | head -1)")
PRODUCTS="$REPO_ROOT/.build/$CONFIGURATION"
MODULE="$PRODUCTS/Modules/ProjectDescription.swiftmodule"
ARCH=$(uname -m)
rm -rf "$MODULE"
mkdir -p "$MODULE"
cp "$INTERFACE_DIR/ProjectDescription.swiftinterface" "$MODULE/$ARCH-apple-macos.swiftinterface"
cp "$INTERFACE_DIR/ProjectDescription.private.swiftinterface" "$MODULE/$ARCH-apple-macos.private.swiftinterface"
rm -f "$PRODUCTS/libProjectDescription.dylib"
cp "$SCRATCH/$CONFIGURATION/libProjectDescription.dylib" "$PRODUCTS/libProjectDescription.dylib"
echo "$MODULE"
