#!/bin/bash

# This bash script returns the path to the requested Xcode version:
# ./xcode_path.sh --version 15.0
# When no path is provided, it returns the path to the Xcode version
# selected in the environment.

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/root_dir.sh)

source $ROOT_DIR/make/utilities/setup.sh

# Check for jq
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is not installed" >&2
    exit 1
fi

# Check arguments
if [[ "$1" != "--version" ]] || [[ -z "$2" ]]; then
    echo "Usage: $0 --version <version_or_path>" >&2
    exit 1
fi

version="$2"

if [[ "$version" == *.app ]]; then
    # Version contains ".app", assume it's a path
    echo "$version"
else
    # Version does not contain ".app", assume it's a version number
    xcode_infos_json=$(system_profiler -json SPDeveloperToolsDataType)
        
    xcodes_path=$(echo "$xcode_infos_json" | jq -r \
        --arg version "$version" \
        '.SPDeveloperToolsDataType[]
        | select(.spdevtools_version | startswith($version))
        | .spdevtools_path'
    )
        
    # Check if we found a path
    if [ -z "$xcodes_path" ]; then
        echo "$(format_error "The requested Xcode version '$version' is not available")" >&2
        exit 1
    else
        echo "$xcodes_path"
    fi
fi
