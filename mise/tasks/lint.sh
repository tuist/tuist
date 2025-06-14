#!/bin/bash
# mise description="Lint the workspace"
set -euo pipefail

swiftformat cli/ app/ --lint
swiftlint lint --quiet --config .swiftlint.yml cli/Sources
tuist inspect implicit-imports --path cli/
