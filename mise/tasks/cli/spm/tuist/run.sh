#!/usr/bin/env bash
#MISE description="Run the project using Tuist"

set -euo pipefail

swift build --package-path $MISE_PROJECT_ROOT
$MISE_PROJECT_ROOT/.build/debug/tuist $@
