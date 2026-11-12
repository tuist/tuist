#!/bin/bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
DEST="$ROOT/.build/nsh-threads"
VERSION="0.3.0"
SHA256="34fdd2ec43d5e22986723e7633acf9223e365bd5bace1a502b5ae24fb75c266c"

if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    echo "The Threads UI preview requires an Apple Silicon Mac." >&2
    exit 1
fi

if [[ ! -x "$DEST/nsh/bin/nsh" ]]; then
    mkdir -p "$DEST"
    ARCHIVE="$(mktemp -t tuist-nsh)"
    trap 'rm -f "$ARCHIVE"' EXIT
    curl --fail --location --retry 2 \
        "https://github.com/longbridge/nsh/releases/download/v$VERSION/nsh-macos-arm64.tar.gz" \
        -o "$ARCHIVE"
    echo "$SHA256  $ARCHIVE" | shasum -a 256 --check
    tar -xzf "$ARCHIVE" -C "$DEST" \
        nsh/bin nsh/embed/ios/NativeShell.xcframework nsh/LICENSE-APACHE
fi

"$DEST/nsh/bin/nsh" build "$ROOT/app/Development/ThreadUI/App.tsx" --release --out "$DEST/ui"
cp "$DEST/nsh/LICENSE-APACHE" "$DEST/ui/NativeShell-LICENSE.txt"
echo "Generate the preview with: TUIST_THREAD_RICH_UI=true tuist generate --path app --no-open --no-binary-cache"
