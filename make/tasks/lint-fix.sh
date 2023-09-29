#!/bin/bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../utilities/root_dir.sh)

$ROOT_DIR/projects/fourier/vendor/swiftformat/swiftformat $ROOT_DIR
$ROOT_DIR/projects/fourier/vendor/swiftlint/swiftlint --fix --path $ROOT_DIR/Sources --quiet --config $ROOT_DIR/.swiftlint.yml