#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../../utilities/root_dir.sh)

swift run --package-path $ROOT_DIR/vendor swiftformat $ROOT_DIR
swift run --package-path $ROOT_DIR/vendor swiftlint lint --fix --quiet --config $ROOT_DIR/.swiftlint.yml $ROOT_DIR/Sources
