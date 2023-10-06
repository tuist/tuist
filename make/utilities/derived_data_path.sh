#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

DERIVED_DATA_PATH=$(defaults read com.apple.dt.Xcode IDECustomDerivedDataLocation 2>/dev/null)

# Check if the path is set
if [ -z "$DERIVED_DATA_PATH" ]; then
    echo "$HOME/Library/Developer/Xcode/DerivedData/"
else
    echo "$DERIVED_DATA_PATH"
fi