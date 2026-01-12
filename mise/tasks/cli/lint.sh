#!/usr/bin/env bash
#MISE description="Lint the CLI"
#USAGE flag "-f --fix" help="Automatically fix linting issues where possible"

set -eo pipefail

# Resolve repo root (lint.sh lives in mise/tasks/cli)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Resolve the pinned SwiftFormat tool name/version from mise.toml (case-insensitive match on swiftformat)
SWIFT_INFO=$(python3 - <<'PY'
import tomllib, re, pathlib
tools = tomllib.load(open(pathlib.Path(__file__).resolve().parents[2] / "mise.toml", "rb")).get("tools", {})
for k, v in tools.items():
    if re.search(r"swiftformat", k, re.IGNORECASE):
        print(f"{k} {v}")
        break
PY
)
SWIFTFORMAT_TOOL=$(echo "$SWIFT_INFO" | awk '{print $1}')
SWIFTFORMAT_VERSION=$(echo "$SWIFT_INFO" | awk '{print $2}')
SWIFTFORMAT_TOOL=${SWIFTFORMAT_TOOL:-swiftformat}
SWIFTFORMAT_VERSION=${SWIFTFORMAT_VERSION:-0.57.2}

# Helper to resolve the installed SwiftFormat path from mise
resolve_swiftformat_bin() {
    local root bin tool
    for tool in "$SWIFTFORMAT_TOOL" swiftformat; do
        root=$(mise where "${tool}@${SWIFTFORMAT_VERSION}" 2>/dev/null || true)
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
    done
    echo ""
}

# Ensure the binary exists; if not, install it explicitly and resolve again
SWIFTFORMAT_BIN="$(resolve_swiftformat_bin)"
if [ -z "$SWIFTFORMAT_BIN" ]; then
    echo "SwiftFormat ${SWIFTFORMAT_VERSION} not found; installing via mise..."
    mise install "${SWIFTFORMAT_TOOL}@${SWIFTFORMAT_VERSION}" || mise install "swiftformat@${SWIFTFORMAT_VERSION}"
    SWIFTFORMAT_BIN="$(resolve_swiftformat_bin)"
fi

if [ -z "$SWIFTFORMAT_BIN" ]; then
    echo "SwiftFormat ${SWIFTFORMAT_VERSION} could not be located after install."
    exit 1
fi

echo "MISE_DATA_DIR=${MISE_DATA_DIR:-unset}"
echo "Resolved swiftformat tool=${SWIFTFORMAT_TOOL}"
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
