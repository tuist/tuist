#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../../../utilities/root_dir.sh)

swift run --package-path $ROOT_DIR swift-openapi-generator generate --mode types --mode client --output-directory $ROOT_DIR/Sources/TuistCloud/OpenAPI Sources/TuistCloud/OpenAPI/cloud.yml
