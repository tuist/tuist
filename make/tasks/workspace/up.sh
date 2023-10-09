#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../../utilities/root_dir.sh)
REPO_URL="https://github.com/tuist/TuistCloud"
CLONE_DIR=$ROOT_DIR/TuistCloud
COMMIT_SHA=$(cat $ROOT_DIR/.tuist-cloud-version) 

# Assigns a default value
: "${TUIST_INCLUDE_TUIST_CLOUD:=0}"

if [[ "${TUIST_INCLUDE_TUIST_CLOUD}" == "1" ]]; then    
    # Check if 'cloud' directory exists
    if [ ! -d "$CLONE_DIR" ]; then
        echo "Directory $CLONE_DIR does not exist. Cloning the repository..."
        git clone "$REPO_URL" "$CLONE_DIR"
    else
        echo "Directory $CLONE_DIR already exists. Skipping clone."
    fi

    # Discard all local changes and checkout the specific commit SHA
    echo "Checking out commit $COMMIT_SHA and discarding all local changes..."
    git --git-dir="$CLONE_DIR/.git" --work-tree="$CLONE_DIR" reset --hard "$COMMIT_SHA"

    # Removing SPM and Xcode caches
    $SCRIPT_DIR/clean.sh
else
    rm -rf $CLONE_DIR

    # Removing SPM and Xcode caches
    $SCRIPT_DIR/clean.sh
fi