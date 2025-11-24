#!/bin/bash
#MISE description="Install all necessary dependencies"

set -eo pipefail

if [[ "$OSTYPE" == "darwin"* ]]; then
  tuist install --force-resolved-versions
  tuist setup cache
fi
