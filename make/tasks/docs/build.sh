#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../../utilities/root_dir.sh)

if [ ! -d $ROOT_DIR/.build/documentation ]; then
  mkdir -p $ROOT_DIR/.build/documentation
fi

swift package --package-path $ROOT_DIR/docs --allow-writing-to-directory .build/documentation generate-documentation --target tuist --disable-indexing --output-path .build/documentation --transform-for-static-hosting
cp $ROOT_DIR/assets/favicon.ico .build/documentation/favicon.ico
cp $ROOT_DIR/assets/favicon.svg .build/documentation/favicon.svg