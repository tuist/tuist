#!/usr/bin/env bash
# mise description="Lint the workspace using SwiftFormat, SwiftLint, and Tuist implicit imports analysis"
# USAGE flag "--fix" help="Automatically fix linting issues where possible"

set -euo pipefail

if [ "${usage_fix:-}" = "true" ]; then
    # Fix mode: apply automatic fixes
    swiftformat cli/ app/
    swiftlint lint --fix --quiet --config .swiftlint.yml cli/Sources
else
    # Check mode: only report issues without fixing
    swiftformat cli/ app/ --lint
    swiftlint lint --quiet --config .swiftlint.yml cli/Sources
    tuist inspect implicit-imports
fi
