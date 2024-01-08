#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../../utilities/root_dir.sh)

swift package --package-path $ROOT_DIR --allow-writing-to-directory .build/documentation generate-documentation --target tuist --disable-indexing --output-path .build/documentation --transform-for-static-hosting
cp $ROOT_DIR/assets/favicon.ico $ROOT_DIR/.build/documentation/favicon.ico
cp $ROOT_DIR/assets/favicon.svg $ROOT_DIR/.build/documentation/favicon.svg

cat <<EOL > $ROOT_DIR/.build/documentation/netlify.toml
[[redirects]]
  from = "/index.html"
  to = "/documentation/tuist"
  status = 301

[[redirects]]
  from = "/"
  to = "/documentation/tuist"
  status = 301
EOL