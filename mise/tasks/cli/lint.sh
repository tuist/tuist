#!/usr/bin/env bash
#MISE description="Lint the CLI"
#USAGE flag "-f --fix" help="Automatically fix linting issues where possible"

set -eo pipefail

# Resolve repo root (lint.sh lives in mise/tasks/cli)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Resolve the pinned SwiftFormat version from mise.toml (fallback to explicit version if parsing fails)
SWIFTFORMAT_VERSION=$(awk -F'"' '/swiftformat/ {print $2; exit}' "$REPO_ROOT/mise.toml" 2>/dev/null || true)
SWIFTFORMAT_VERSION=${SWIFTFORMAT_VERSION:-0.57.2}

# Helper to resolve the installed SwiftFormat path from mise
resolve_swiftformat_bin() {
    local root bin
    root=$(mise where "swiftformat@${SWIFTFORMAT_VERSION}" 2>/dev/null || true)
    if [ -n "$root" ]; then
        bin="$root/bin/swiftformat"
        if [ -x "$bin" ]; then
            echo "$bin"
            return
        fi
        bin=$(find "$root" -name swiftformat -type f 2>/dev/null | head -n 1)
        if [ -n "$bin" ]; then
            echo "$bin"
            return
        fi
    fi
    echo ""
}

# Ensure the binary exists; if not, install it explicitly and resolve again
SWIFTFORMAT_BIN="$(resolve_swiftformat_bin)"
if [ -z "$SWIFTFORMAT_BIN" ]; then
    echo "SwiftFormat ${SWIFTFORMAT_VERSION} not found; installing via mise..."
    mise install "swiftformat@${SWIFTFORMAT_VERSION}"
    SWIFTFORMAT_BIN="$(resolve_swiftformat_bin)"
fi

if [ -z "$SWIFTFORMAT_BIN" ]; then
    echo "SwiftFormat ${SWIFTFORMAT_VERSION} could not be located after install."
    exit 1
fi

echo "MISE_DATA_DIR=${MISE_DATA_DIR:-unset}"
echo "Resolved swiftformat version=${SWIFTFORMAT_VERSION}"
echo "Resolved swiftformat path=${SWIFTFORMAT_BIN}"
ls -l "$SWIFTFORMAT_BIN" 2>/dev/null || true

swiftformat() {
    "$SWIFTFORMAT_BIN" "$@"
}

echo "SwiftFormat version (mise):"
swiftformat --version
echo "SwiftFormat path (mise):"
echo "$SWIFTFORMAT_BIN"

if [ "$usage_fix" = "true" ]; then    # Fix mode: apply automatic fixes
    swiftformat cli/ app/
    swiftlint lint --fix --quiet --config .swiftlint.yml cli/Sources
else
    # Check mode: only report issues without fixing
    swiftformat cli/ app/ --lint
    swiftlint lint --quiet --config .swiftlint.yml cli/Sources
    tuist inspect implicit-imports
fi
