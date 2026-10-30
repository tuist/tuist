#!/usr/bin/env bash
# Validate a stable SDK patch source; never check out or execute that source.
set -euo pipefail

fail() { echo "$*" >&2; exit 1; }

[[ ${GITHUB_REPOSITORY:-} == tuist/tuist && ${GITHUB_REF:-} == refs/heads/main &&
  ${GITHUB_EVENT_NAME:-} == workflow_dispatch ]] || fail 'Stable releases must be dispatched from tuist/tuist main'
[[ $# == 3 ]] || fail 'Provide source SHA, base tag and patch version together'
source_sha=$1 base=$2 version=$3
[[ $source_sha =~ ^[0-9a-f]{40}$ ]] || fail 'Source must be a full immutable commit SHA'
semver='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
[[ $base =~ ^tuist-ex@$semver$ ]] || fail 'Base must be an exact stable tuist-ex@ tag'
major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]}

# Increment decimal text without shell-integer overflow or octal interpretation.
next_patch=$patch suffix=
while [[ $next_patch == *9 ]]; do
  next_patch=${next_patch%9}
  suffix=0$suffix
done
if [[ -n $next_patch ]]; then
  last=${next_patch: -1}
  next_patch=${next_patch%?}$((last + 1))$suffix
else
  next_patch=1$suffix
fi
[[ $version == "$major.$minor.$next_patch" ]] || fail 'Only the next patch version is allowed'

tags=$(git tag --list 'tuist-ex@*')
stable=()
while IFS= read -r tag; do
  if [[ $tag =~ ^tuist-ex@$semver$ ]]; then
    stable+=("$tag")
  fi
done <<< "$tags"
latest=$(printf '%s\n' "${stable[@]}" | LC_ALL=C sort -V | tail -n1)
[[ $latest == "$base" ]] || fail 'Base must be the latest stable SDK tag'
while IFS= read -r tag; do
  [[ $tag != "tuist-ex@$version" ]] || fail 'Target tag already exists; never replace a release'
done <<< "$tags"
branch="refs/remotes/origin/releases/tuist-ex-$major.$minor.x"
tip=$(git rev-parse "$branch^{commit}")
[[ $tip == "$source_sha" ]] || fail 'Source must be the current stable release branch tip, not a PR or main SHA'
base_sha=$(git rev-parse "refs/tags/$base^{commit}")
if [[ ${APPROVED_BASE_SHA+x} ]]; then
  [[ $APPROVED_BASE_SHA =~ ^[0-9a-f]{40}$ && $base_sha == "$APPROVED_BASE_SHA" ]] ||
    fail 'Stable base tag changed since planning; refusing publication'
fi
[[ $source_sha != "$base_sha" ]] || fail 'Source must contain a patch after the stable tag'
git merge-base --is-ancestor "$base_sha" "$source_sha"

# Keep NUL-delimited paths and propagate Git failure before emitting any outputs.
changed=$(mktemp)
trap 'rm -f "$changed"' EXIT
git diff --name-only -z "$base_sha" "$source_sha" > "$changed"
sdk_changed=false
while IFS= read -r -d '' path; do
  case "$path" in
    tuist_ex/*) sdk_changed=true ;;
    .github/workflows/tuist-ex.yml) ;;
    *) fail 'Stable source includes changes outside the SDK and its validation' ;;
  esac
done < "$changed"
[[ $sdk_changed == true ]] || fail 'No SDK changes to publish'
{
  echo 'tuist-ex-should-release=true'
  echo "tuist-ex-next-version=tuist-ex@$version"
  echo "tuist-ex-next-version-number=$version"
  echo "source-sha=$source_sha"
  echo "base-tag=$base"
  echo "base-sha=$base_sha"
} >> "$GITHUB_OUTPUT"
echo "Validated $base ($base_sha) -> tuist-ex@$version from $source_sha"
