#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../../utilities/root_dir.sh)
FIXTURES_DIRECTORY=$ROOT_DIR/projects/tuist/fixtures
source $ROOT_DIR/make/utilities/setup.sh

temp_dir=$(mktemp -d)

# Define a cleanup function
cleanup() {
  echo "Deleting the temporary directory..."
  rm -rf "$temp_dir"
  echo "Temporary directory deleted."
}

echo "$(format_section "Building the fixture generator and benchmark tools")"
swift build --package-path $ROOT_DIR --product tuistfixturegenerator -c release
swift build --package-path $ROOT_DIR --product tuistbenchmark -c release

echo "$(format_section "Generating a Tuist project with 50 projects")"
DIRECTORY_50_PROJECTS=$temp_dir/50_projects
$ROOT_DIR/.build/release/tuistfixturegenerator generate --path $DIRECTORY_50_PROJECTS --projects 50
echo "$(format_section "Generating a Tuist project with 2 projects and 2000 sources")"
DIRECTORY_2000_SOURCES=$temp_dir/50_projects
$ROOT_DIR/.build/release/tuistfixturegenerator generate --path $DIRECTORY_2000_SOURCES --projects 2 --sources 2000

FIXTURES_JSON_PATH=$temp_dir/fixtures.json
FIXTURES_LIST=($DIRECTORY_50_PROJECTS $DIRECTORY_2000_SOURCES $FIXTURES_DIRECTORY/ios_app_with_static_frameworks $FIXTURES_DIRECTORY/ios_app_with_framework_and_resources $FIXTURES_DIRECTORY/ios_app_with_transitive_framework $FIXTURES_DIRECTORY/ios_app_with_xcframeworks)

echo "$(format_section "Writing the fixtures.json file")"
FIXTURES_JSON=$(jq -n --argjson arr "$(printf '%s\n' "${FIXTURES_LIST[@]}" | jq -R . | jq -s .)" '{"paths": $arr}')

echo $FIXTURES_JSON > $FIXTURES_JSON_PATH

echo "$(format_section "Building tuist and tuistenv")"
swift build --package-path $ROOT_DIR --product tuist -c release
swift build --package-path $ROOT_DIR --product tuistenv -c release
swift build --package-path $ROOT_DIR --product ProjectDescription -c release

echo "$(format_section "Benchmarking")"
$ROOT_DIR/.build/release/tuistbenchmark benchmark -b $ROOT_DIR/.build/release/tuist -r $ROOT_DIR/.build/release/tuistenv --fixture-list $FIXTURES_JSON_PATH --format markdown