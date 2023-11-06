#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../../utilities/root_dir.sh)
source $ROOT_DIR/make/utilities/setup.sh

path=$(pwd)
projects=""
targets=""
sources=""

# Function to display usage
usage() {
  echo "Usage: $0 --path <path> --projects <projects> --targets <targets> --sources <sources>"
  exit 1
}

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --path) path="$2"; shift ;;
    --projects) projects="$2"; shift ;;
    --targets) targets="$2"; shift ;;
    --sources) sources="$2"; shift ;;
    *) echo "Unknown parameter passed: $1"; usage ;;
  esac
  shift
done

if [ -z "$projects" ] || [ -z "$targets" ] || [ -z "$sources" ]; then
    usage
fi

echo "$(format_section "Generating fixture")"

echo "Path: $path"
echo "Projects: $projects"
echo "Targets: $targets"
echo "Sources: $sources"

swift run --package-path $ROOT_DIR tuistfixturegenerator generate --path $path --projects $projects --targets $targets --sources $sources