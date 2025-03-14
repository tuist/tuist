#!/usr/bin/env bash
# mise description="Edit the project using Tuist"

set -euo pipefail

swift build --package-path $MISE_PROJECT_ROOT
$MISE_PROJECT_ROOT/.build/debug/tuist edit --path $MISE_PROJECT_ROOT --only-current-directory