#!/bin/bash
#MISE description="Build the 'tuistfixturegenerator' tool"
set -euo pipefail

swift build --package-path $MISE_PROJECT_ROOT --target tuistfixturegenerator $@
