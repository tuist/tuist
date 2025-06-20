#!/usr/bin/env bash
#MISE description="Lint the workspace"
#USAGE flag "-f --fix" help="Automatically fix linting issues where possible"
set -eo pipefail

# Lint all components of the project
mise run cli:lint "$@"
