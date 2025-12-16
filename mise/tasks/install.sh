#!/bin/bash
#MISE description="Install all necessary dependencies"

set -eo pipefail

# Configure git merge driver for PO files (fallback for developers without Weblate's driver)
git config --local merge.merge-gettext-po.name "Gettext PO merge driver"
git config --local merge.merge-gettext-po.driver "bin/git-merge-po %O %A %B"

if [[ "$OSTYPE" == "darwin"* ]]; then
  if [[ -z "$CI" ]]; then
    tuist install
    tuist setup cache
  fi
fi
