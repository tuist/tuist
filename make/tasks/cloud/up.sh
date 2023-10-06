#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../../utilities/root_dir.sh)

# Variables
REPO_URL="https://github.com/tuist/cloud"
CLONE_DIR=$ROOT_DIR/cloud
COMMIT_SHA=$(cat $ROOT_DIR/.tuist-cloud-version) 

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
$SCRIPT_DIR/_clean.sh

# Enabling Tuist Cloud
sed -i '' -e 's/let includeTuistCloud = false/let includeTuistCloud = true/' $ROOT_DIR/Package.swift
sed -i '' -e 's/Environment.includeTuistCloud.getBoolean(default: false)/Environment.includeTuistCloud.getBoolean(default: true)/' $ROOT_DIR/Project.swift
