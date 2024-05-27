#!/usr/bin/env bash
# mise description="Generate the project using Tuist"

set -euo pipefail

swift build --package-path $MISE_PROJECT_ROOT
$MISE_PROJECT_ROOT/.build/debug/tuist install --path $MISE_PROJECT_ROOT
$MISE_PROJECT_ROOT/.build/debug/tuist generate --path $MISE_PROJECT_ROOT $@
