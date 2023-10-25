#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../../../utilities/root_dir.sh)

swift build --package-path $ROOT_DIR --target tuistfixturegenerator $@