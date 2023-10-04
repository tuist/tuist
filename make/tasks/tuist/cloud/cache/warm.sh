#!/bin/bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../../../../utilities/root_dir.sh)

DEFAULT_CLOUD_URL="https://cloud.tuist.io"
DEFAULT_CLOUD_TOKEN=$TUIST_CONFIG_CLOUD_TOKEN

CLOUD_URL="$DEFAULT_CLOUD_URL"
CLOUD_TOKEN="$CLOUD_TOKEN"

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --cloud-url) CLOUD_URL="$2"; shift ;;
        --cloud-token) CLOUD_TOKEN="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# swift build --package-path $ROOT_DIR

if [[ -n "$CLOUD_TOKEN" ]]; then
    TUIST_CLOUD_URL=$CLOUD_URL TUIST_CONFIG_CLOUD_TOKEN=$CLOUD_TOKEN $ROOT_DIR/.build/debug/tuist cache warm --path $ROOT_DIR --dependencies-only --xcframeworks
else
    TUIST_CLOUD_URL=$CLOUD_URL $ROOT_DIR/.build/debug/tuist cache warm --path $ROOT_DIR --dependencies-only --xcframeworks
fi

