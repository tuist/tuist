#!/bin/bash
#MISE description="Install all necessary dependencies"

set -eo pipefail

if [[ "$OSTYPE" == "darwin"* ]]; then
  if [[ -z "$CI" ]]; then
    tuist install
  fi
  tuist setup cache
fi
