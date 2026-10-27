#!/usr/bin/env bash
set -euo pipefail

source_repo=$(git rev-parse --show-toplevel)
version=${1:?usage: prepare-release.sh VERSION DISTRIBUTION OUTPUT}
distribution=$(cd "${2:?distribution checkout required}" && pwd)
output=${3:?output directory required}
[[ "$version" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || exit 1
source_commit=$(git rev-parse HEAD)
pending_version=''

# A published distribution remains authoritative if recording its monorepo release failed.
while IFS= read -r tag; do
  [[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || continue
  if git show-ref --verify --quiet "refs/tags/install-action@${tag#v}"; then continue; fi
  commit=$(git -C "$distribution" show "$tag:SOURCE_COMMIT")
  [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo 'Invalid published source commit' >&2; exit 1; }
  git merge-base --is-ancestor "$commit" HEAD || { echo 'Published source is not an ancestor of this release run' >&2; exit 1; }
  [[ -z "$pending_version" ]] || { echo 'Multiple unrecorded distribution releases' >&2; exit 1; }
  pending_version=$tag
  source_commit=$commit
done < <(git -C "$distribution" tag -l 'v*')
if [[ -n "$pending_version" ]]; then version=$pending_version; fi

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
git clone --quiet --shared --no-checkout "$source_repo" "$scratch/source"
git -C "$scratch/source" checkout --quiet --detach "$source_commit"
bash "$scratch/source/.github/actions/install/scripts/package.sh" "$output"
printf 'version=%s\nsource-commit=%s\ntag=install-action@%s\n' "$version" "$source_commit" "${version#v}" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT required}"
