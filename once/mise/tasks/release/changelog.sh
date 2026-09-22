#!/usr/bin/env bash
#MISE description="Regenerate once/CHANGELOG.md from conventional commits"
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"

git cliff --include-path 'once/**/*' --config cliff.toml --repository "${repo_root}" --bump --output CHANGELOG.md
