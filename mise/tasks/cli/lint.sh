#!/usr/bin/env bash
#MISE description="Lint the CLI"
#USAGE flag "-f --fix" help="Automatically fix linting issues where possible"

set -eo pipefail

if [ "$usage_fix" = "true" ]; then    # Fix mode: apply automatic fixes
    swiftformat cli/ app/
    swiftlint lint --fix --quiet --config .swiftlint.yml cli/Sources
else
    # Check mode: only report issues without fixing
    swiftformat cli/ app/ --lint
    swiftlint lint --quiet --config .swiftlint.yml cli/Sources
    tuist inspect implicit-imports
fi
