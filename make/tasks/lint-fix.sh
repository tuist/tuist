#!/bin/bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../utilities/root_dir.sh)

$ROOT_DIR/projects/fourier/vendor/swiftformat/swiftformat $ROOT_DIR
$ROOT_DIR/projects/fourier/vendor/swiftlint/swiftlint --fix --quiet --config $ROOT_DIR/.swiftlint.yml $ROOT_DIR/Sources
