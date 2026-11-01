#!/usr/bin/env bash
# Validate a manually selected stable Gradle patch, without publishing anything.
# Run from the repository root, using the trusted workflow revision's script even
# after switching source. The publisher retains that copy outside the checkout.
set -euo pipefail

fail() { echo "$*" >&2; exit 1; }

[[ "${GITHUB_EVENT_NAME:-}" == workflow_dispatch && "${GITHUB_REF:-}" == refs/heads/main ]] ||
  fail "Stable patches must be dispatched using the workflow on main."
[[ "${SOURCE_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || fail "source_sha must be a full lowercase commit SHA."
[[ "${PATCH_VERSION:-}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
  fail "patch_version must be an unprefixed stable version."

# Refresh before BOTH planning and publishing; never accept an outdated version plan.
git fetch --tags origin
latest=$(git tag -l 'gradle@*' | grep -E '^gradle@[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1)
[[ -n "$latest" ]] || fail "A stable Gradle tag is required."
IFS=. read -r major minor patch <<< "${latest#gradle@}"
expected="$major.$minor.$((patch + 1))"
[[ "$PATCH_VERSION" == "$expected" ]] || fail "Expected the next stable patch: $expected."
git show-ref --verify --quiet "refs/tags/gradle@$PATCH_VERSION" && fail "The patch tag already exists."

branch="releases/gradle-$major.$minor.x"
git fetch --no-tags origin "+refs/heads/$branch:refs/remotes/origin/$branch"
[[ "$(git rev-parse "refs/remotes/origin/$branch^{commit}")" == "$SOURCE_SHA" ]] ||
  fail "source_sha must be the current head of $branch (merge the source PR first)."
git merge-base --is-ancestor "$latest" "$SOURCE_SHA" || fail "Source must descend from $latest."
git diff --quiet "$latest" "$SOURCE_SHA" -- . ':(exclude)gradle/**' ||
  fail "Stable Gradle source must not include changes outside gradle/."
if git diff --quiet "$latest" "$SOURCE_SHA" -- gradle; then
  fail "Source has no Gradle changes since $latest."
fi

printf 'Stable Gradle patch: %s -> gradle@%s from %s (%s)\n' "$latest" "$PATCH_VERSION" "$SOURCE_SHA" "$branch"
{
  echo "gradle-should-release=true"
  echo "gradle-next-version=gradle@$PATCH_VERSION"
  echo "gradle-next-version-number=$PATCH_VERSION"
  echo "source-sha=$SOURCE_SHA"
} >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
