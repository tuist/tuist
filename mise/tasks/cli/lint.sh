#!/usr/bin/env bash
#MISE description="Lint the CLI"
#USAGE flag "-f --fix" help="Automatically fix linting issues where possible"

set -eo pipefail

# Resolve repo root (lint.sh lives in mise/tasks/cli)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Resolve the pinned SwiftFormat version from mise.toml (fallback to explicit version if parsing fails)
SWIFTFORMAT_VERSION=$(awk -F'"' '/swiftformat/ {print $2; exit}' "$REPO_ROOT/mise.toml" 2>/dev/null || true)
SWIFTFORMAT_VERSION=${SWIFTFORMAT_VERSION:-0.57.2}

# Compute the installed binary path directly to avoid PATH/shim surprises
MISE_DATA_DIR="${MISE_DATA_DIR:-$HOME/.local/share/mise}"
SWIFTFORMAT_BIN="$MISE_DATA_DIR/installs/swiftformat/${SWIFTFORMAT_VERSION}/bin/swiftformat"

# Ensure the binary exists; if not, install it explicitly
if [ ! -x "$SWIFTFORMAT_BIN" ]; then
    echo "SwiftFormat ${SWIFTFORMAT_VERSION} not found; installing via mise..."
    mise install "swiftformat@${SWIFTFORMAT_VERSION}"
fi

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
