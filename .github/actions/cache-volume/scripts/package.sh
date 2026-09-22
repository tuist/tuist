#!/usr/bin/env bash
set -euo pipefail

source_dir=$(cd "$(dirname "$0")/.." && pwd)
repo_root=$(git -C "$source_dir" rev-parse --show-toplevel)
output=${1:?usage: package.sh OUTPUT_DIRECTORY}
# Only create a new directory: never replace a checkout or an earlier package.
mkdir "$output"
cp "$source_dir/action.yml" "$source_dir/attach.sh" "$source_dir/README.md" "$output/"
cp "$repo_root/LICENSE.md" "$output/LICENSE.md"
git -C "$repo_root" rev-parse HEAD > "$output/SOURCE_COMMIT"
