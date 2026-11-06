#!/usr/bin/env bash
set -euo pipefail

source_repo=$(git rev-parse --show-toplevel)
version=${1:?usage: prepare-release.sh VERSION DISTRIBUTIONS OUTPUT}
distributions=$(cd "${2:?distribution checkouts required}" && pwd)
output=${3:?output directory required}
[[ "$version" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || exit 1
source_commit=$(git rev-parse HEAD)
pending_version=''
pending_source=''

# A partial coordinated release is authoritative even after main advances.
# Recover it before choosing a new version or building new package contents.
while IFS=$'\t' read -r repository _; do
  while IFS= read -r tag; do
    [[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || continue
    if git show-ref --verify --quiet "refs/tags/runner-caches@${tag#v}"; then continue; fi
    commit=$(git -C "$distributions/$repository" show "$tag:SOURCE_COMMIT")
    [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo 'Invalid published source commit' >&2; exit 1; }
    git merge-base --is-ancestor "$commit" HEAD || { echo 'Published source is not an ancestor of this release run' >&2; exit 1; }
    if [[ -n "$pending_version" && ( "$tag" != "$pending_version" || "$commit" != "$pending_source" ) ]]; then
      echo 'Conflicting incomplete distribution releases' >&2
      exit 1
    fi
    pending_version=$tag
    pending_source=$commit
  done < <(git -C "$distributions/$repository" tag -l 'v*')
done < "$source_repo/ci/runner-caches/distributions"
if [[ -n "$pending_version" ]]; then
  version=$pending_version
  source_commit=$pending_source
fi

mkdir "$output"
output=$(cd "$output" && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
git clone --quiet --shared --no-checkout "$source_repo" "$scratch/source"
git -C "$scratch/source" checkout --quiet --detach "$source_commit"
while IFS=$'\t' read -r repository package; do
  bash "$scratch/source/$package" "$output/$repository"
done < "$scratch/source/ci/runner-caches/distributions"
printf 'version=%s\nsource-commit=%s\ntag=runner-caches@%s\n' "$version" "$source_commit" "${version#v}" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT required}"
