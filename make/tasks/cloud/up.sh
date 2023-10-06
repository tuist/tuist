#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../../utilities/root_dir.sh)

# Variables
REPO_URL="https://github.com/tuist/TuistCloud"
CLONE_DIR=$ROOT_DIR/TuistCloud
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

PACKAGE_SWIFT_PATH=$ROOT_DIR/Package.swift
PROJECT_SWIFT_PATH=$ROOT_DIR/Project.swift

# Enabling Tuist Cloud
sed -i '' -e 's/let includeTuistCloud = false/let includeTuistCloud = true/' $PACKAGE_SWIFT_PATH
sed -i '' -e 's/Environment.includeTuistCloud.getBoolean(default: false)/Environment.includeTuistCloud.getBoolean(default: true)/' $PROJECT_SWIFT_PATH

# Create the pre-commit file in the hooks directory
HOOKS_DIR=$ROOT_DIR/.git/hooks
FORBIDDEN_PACKAGE_SWIFT_LINE="let includeTuistCloud = true"
FORBIDDEN_PROJECT_SWIFT_LINE="Environment.includeTuistCloud.getBoolean(default: true)"

cat > "${HOOKS_DIR}/pre-commit" <<EOF
#!/bin/bash

# Check if the forbidden line is in the first target file
if grep -Fq "$FORBIDDEN_PACKAGE_SWIFT_LINE" "$PACKAGE_SWIFT_PATH"; then
    echo "Error: $PACKAGE_SWIFT_PATH must NOT contain: $FORBIDDEN_PACKAGE_SWIFT_LINE"
    echo "Ensure that Tuist Cloud changes are persisted upstream and run make cloud/down"
    exit 1
fi

# Check if the expected line is in the second target file
if grep -Fq "$FORBIDDEN_PROJECT_SWIFT_LINE" "$PROJECT_SWIFT_PATH"; then
    echo "Error: $PROJECT_SWIFT_PATH must NOT contain: $FORBIDDEN_PROJECT_SWIFT_LINE"
    echo "Ensure that Tuist Cloud changes are persisted upstream and run make cloud/down"
    exit 1
fi
EOF

# Make the pre-commit hook executable
chmod +x "${HOOKS_DIR}/pre-commit"

echo "Pre-commit hook has been installed."