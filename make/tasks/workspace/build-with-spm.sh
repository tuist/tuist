#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../../utilities/root_dir.sh)
DERIVED_DATA_PATH=$($ROOT_DIR/make/utilities/derived_data_path.sh)

swift build --package-path $ROOT_DIR --build-path $ROOT_DIR/.build $@