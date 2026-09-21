#!/usr/bin/env bash
# Builds the Rust binary and places it as `tuist-rs` next to the SwiftPM build of
# TuistEmbed, ProjectDescription, and the Swift `tuist`, which is the layout it needs.
#
# Usage: cli-rs/scripts/dev-install.sh [debug|release]
set -euo pipefail

CONFIGURATION=${1:-debug}
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$REPO_ROOT/cli-rs"
if [ "$CONFIGURATION" = release ]; then
    TUIST_EMBED_SWIFT_CONFIGURATION=release cargo build --release
else
    cargo build
fi
DESTINATION="$REPO_ROOT/.build/$CONFIGURATION/tuist-rs"
# Replace rather than overwrite: macOS kills a signed binary rewritten in place.
rm -f "$DESTINATION"
cp "target/$CONFIGURATION/tuist" "$DESTINATION"
echo "$DESTINATION"
