#!/bin/bash

: ${FEATURE:=}

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../../utilities/root_dir.sh)
FEATURES_DIRECTORY=$ROOT_DIR/features

args=(--format pretty --strict-undefined)
args+=(--require "$FEATURES_DIRECTORY")

if [ -z "$FEATURE" ]; then
  args+=("$FEATURES_DIRECTORY")
else
  args+=("$FEATURE")
fi

(
    cd $ROOT_DIR
    bundle exec cucumber "${args[@]}"
)
