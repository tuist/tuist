#!/usr/bin/env bash
set -euo pipefail

branch=l10n/update-translations
if git ls-remote --exit-code --heads origin "$branch" > /dev/null; then
  git fetch origin "$branch"
else
  result=$?
  if [[ $result == 2 ]]; then
    exit 0
  fi
  exit "$result"
fi

checkpoint=$(git rev-parse FETCH_HEAD)
base=$(git merge-base HEAD "$checkpoint")
patch=$(mktemp)
trap 'rm -f "$patch"' EXIT

git diff --binary "$base" "$checkpoint" -- \
  '.l10n/' 'server/priv/gettext/**/*.po' 'server/priv/docs/**/*.md' \
  ':(exclude)server/priv/docs/en/**' > "$patch"

if [[ -s $patch ]]; then
  # A three-way merge preserves newer main changes and stops before spending
  # on conflicts that need a person to resolve.
  git apply --3way "$patch"
fi
