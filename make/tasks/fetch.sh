#!/bin/bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../utilities/root_dir.sh)

swift build --package-path $ROOT_DIR
$ROOT_DIR/.build/debug/tuist fetch --path $ROOT_DIR