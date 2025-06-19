#!/bin/bash
# mise description="Lint the workspace fixing issues"
set -euo pipefail

swiftformat cli/ app/
swiftlint lint --fix --quiet --config .swiftlint.yml cli/Sources
