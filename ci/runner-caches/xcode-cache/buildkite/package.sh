#!/usr/bin/env bash
set -euo pipefail
source_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(git -C "$source_dir" rev-parse --show-toplevel)
output=${1:?usage: package.sh OUTPUT_DIRECTORY}
mkdir "$output"
mkdir "$output/hooks"
cp "$source_dir/plugin.yml" "$source_dir/README.md" "$output/"
cp "$source_dir/hooks/pre-command" "$output/hooks/"
chmod +x "$output/hooks/pre-command"
cp "$repo_root/LICENSE.md" "$output/LICENSE.md"
git -C "$repo_root" rev-parse HEAD > "$output/SOURCE_COMMIT"
