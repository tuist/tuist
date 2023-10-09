#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../../utilities/root_dir.sh)
DERIVED_DATA_PATH=$($ROOT_DIR/make/utilities/derived_data_path.sh)

rm -rf $ROOT_DIR/.build
for dir in "$DERIVED_DATA_PATH"/tuist-*; do
    # Check if it is a directory before deleting
    if [[ -d "$dir" ]]; then
        echo "Deleting directory: $dir"
        rm -rf "$dir"
    fi
done
for dir in "$DERIVED_DATA_PATH"/Tuist-*; do
    # Check if it is a directory before deleting
    if [[ -d "$dir" ]]; then
        echo "Deleting directory: $dir"
        rm -rf "$dir"
    fi
done
