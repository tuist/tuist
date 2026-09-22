#!/usr/bin/env bash
# Regenerates cli-rs/spec/tuist.spec.json from the Swift CLI's own command tree.
# With --check, fails instead of writing when the checked-in spec is out of date.
#
# Usage: cli-rs/scripts/update-spec.sh <swift-tuist-binary> [--check]
set -euo pipefail

BINARY=$1
MODE=${2:-write}
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SPEC="$REPO_ROOT/cli-rs/spec/tuist.spec.json"
EMPTY=$(mktemp -d)
GENERATED=$(mktemp)
trap 'rm -rf "$EMPTY" "$GENERATED"' EXIT

"$BINARY" --experimental-dump-help --path "$EMPTY" >"$GENERATED"

if [ "$MODE" = --check ]; then
    if ! cmp -s "$GENERATED" "$SPEC"; then
        echo "cli-rs/spec/tuist.spec.json is out of date; run cli-rs/scripts/update-spec.sh" >&2
        diff <(python3 -m json.tool "$SPEC") <(python3 -m json.tool "$GENERATED") | head -20 >&2
        exit 1
    fi
    echo "spec is up to date"
else
    cp "$GENERATED" "$SPEC"
    echo "wrote $SPEC"
fi
