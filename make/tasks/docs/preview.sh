#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../../utilities/root_dir.sh)

swift package --package-path $ROOT_DIR --disable-sandbox preview-documentation --target tuist  --hosting-base-path /