#!/usr/bin/env bash
#MISE description="Collect coverage for earlier commits on main by dispatching the Coverage workflow once per commit"
#USAGE arg "<range>" help="Commits on main, as a revision range (e.g. abc123..def456) or a single commit"
#USAGE flag "--dry-run" help="List the commits without dispatching anything"

# Each commit runs the full test suites on two macOS runners, for up to two
# hours, and those runners are shared with pull request CI. So commits go one
# at a time: the next is dispatched once the previous run finishes, and a range
# of N commits takes up to 2N hours. Leave it running.
#
# The workflow tests the commit's sources with main's runner image and tools,
# but its .xcode-version and local actions are the commit's own. Commits before
# the move to Xcode 27 pin an Xcode that image does not have.
readonly OLDEST="f834b57656"

set -euo pipefail

readonly RANGE="${usage_range:?}"
readonly DRY_RUN="${usage_dry_run:-false}"

git fetch --quiet origin main

commits=()
if [[ "$RANGE" == *..* ]]; then
  while IFS= read -r sha; do commits+=("$sha"); done < <(git rev-list --first-parent --reverse "$RANGE")
else
  commits=("$(git rev-parse --verify "$RANGE^{commit}")")
fi

if [[ ${#commits[@]} -eq 0 ]]; then
  echo "error: $RANGE has no commits" >&2
  exit 64
fi

for sha in "${commits[@]}"; do
  if ! git merge-base --is-ancestor "$sha" origin/main; then
    echo "error: $sha is not on main" >&2
    exit 64
  fi
  if ! git merge-base --is-ancestor "$OLDEST" "$sha"; then
    echo "error: $sha predates $OLDEST, the move to Xcode 27" >&2
    exit 64
  fi
done

echo "${#commits[@]} commit(s):"
git log --no-walk=unsorted --format='  %h %ad %s' --date=short "${commits[@]}"

if [[ "$DRY_RUN" == "true" ]]; then
  exit 0
fi

for sha in "${commits[@]}"; do
  output=$(gh workflow run coverage.yml --repo tuist/tuist --ref main -f sha="$sha")
  url=$(grep -oE 'https://github.com/[^ ]+/actions/runs/[0-9]+' <<< "$output" | tail -1 || true)
  if [[ -z "$url" ]]; then
    echo "error: no run URL for $sha in: $output" >&2
    exit 1
  fi
  echo "$(git rev-parse --short "$sha"): $url"
  if ! gh run watch "${url##*/}" --repo tuist/tuist --interval 60 --exit-status > /dev/null; then
    echo "  failed, continuing with the next commit"
  fi
done
