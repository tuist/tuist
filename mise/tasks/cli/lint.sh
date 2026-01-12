#!/usr/bin/env bash
#MISE description="Lint the CLI"
#USAGE flag "-f --fix" help="Automatically fix linting issues where possible"

set -eo pipefail

# Resolve the pinned SwiftFormat version from mise and force invocation through it
SWIFTFORMAT_VERSION=$(mise ls --current | awk '/^swiftformat/ {print $2; exit}')
swiftformat() {
    mise x "swiftformat@${SWIFTFORMAT_VERSION:-latest}" -- swiftformat "$@"
}

echo "SwiftFormat version (mise):"
swiftformat --version
echo "SwiftFormat path (mise):"
swiftformat -h >/dev/null 2>&1 # warm-up to ensure binary is fetched
swiftformat --version >/dev/null 2>&1 # ensure binary ready
mise x "swiftformat@${SWIFTFORMAT_VERSION:-latest}" -- which swiftformat

if [ "$usage_fix" = "true" ]; then    # Fix mode: apply automatic fixes
    swiftformat cli/ app/
    swiftlint lint --fix --quiet --config .swiftlint.yml cli/Sources
else
    # Check mode: only report issues without fixing
    swiftformat cli/ app/ --lint
    swiftlint lint --quiet --config .swiftlint.yml cli/Sources
    tuist inspect implicit-imports
fi
