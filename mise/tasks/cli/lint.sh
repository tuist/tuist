#!/usr/bin/env bash
#MISE description="Lint the CLI"
#USAGE flag "-f --fix" help="Automatically fix linting issues where possible"

set -eo pipefail

# Resolve the pinned SwiftFormat version from mise.toml (fallback to explicit version if parsing fails)
SWIFTFORMAT_VERSION=$(awk -F'"' '/swiftformat/ {print $2; exit}' "$(dirname "$0")/../mise.toml" 2>/dev/null || true)
SWIFTFORMAT_VERSION=${SWIFTFORMAT_VERSION:-0.57.2}
swiftformat() {
    mise x "swiftformat@${SWIFTFORMAT_VERSION}" -- swiftformat "$@"
}

echo "SwiftFormat version (mise):"
swiftformat --version
echo "SwiftFormat path (mise):"
mise x "swiftformat@${SWIFTFORMAT_VERSION}" -- which swiftformat

if [ "$usage_fix" = "true" ]; then    # Fix mode: apply automatic fixes
    swiftformat cli/ app/
    swiftlint lint --fix --quiet --config .swiftlint.yml cli/Sources
else
    # Check mode: only report issues without fixing
    swiftformat cli/ app/ --lint
    swiftlint lint --quiet --config .swiftlint.yml cli/Sources
    tuist inspect implicit-imports
fi
