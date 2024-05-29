#!/usr/bin/env bash
# mise description="Test the project using Tuist"

set -euo pipefail

swift build --package-path $MISE_PROJECT_ROOT
$MISE_PROJECT_ROOT/.build/debug/tuist install --path $MISE_PROJECT_ROOT
$MISE_PROJECT_ROOT/.build/debug/tuist test --path $MISE_PROJECT_ROOT $@