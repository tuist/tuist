#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../../utilities/root_dir.sh)

# Remove directory
rm -rf $ROOT_DIR/cloud

# Removing SPM and Xcode caches
$SCRIPT_DIR/_clean.sh

# Disabling Tuist Cloud
sed -i '' -e 's/let includeTuistCloud = true/let includeTuistCloud = false/' $ROOT_DIR/Package.swift
sed -i '' -e 's/Environment.includeTuistCloud.getBoolean(default: true)/Environment.includeTuistCloud.getBoolean(default: false)/' $ROOT_DIR/Project.swift
