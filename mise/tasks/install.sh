#!/bin/bash
#MISE description="Install all necessary dependencies"

set -eo pipefail

if [[ "$OSTYPE" == "darwin"* ]]; then
  if [[ -z "$CI" ]]; then
    tuist install
    tuist setup cache
  fi
fi
