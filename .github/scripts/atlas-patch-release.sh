#!/usr/bin/env bash
# Explicit recovery for merged Atlas changes excluded by conventional scope filters.
set -euo pipefail

fail() { echo "$*" >&2; exit 1; }
[[ ${GITHUB_REPOSITORY:-} == tuist/tuist && ${GITHUB_REF:-} == refs/heads/main &&
  ${GITHUB_EVENT_NAME:-} == workflow_dispatch ]] || fail 'Atlas recovery requires a main dispatch in tuist/tuist'
[[ $# == 3 ]] || fail 'Provide the latest tag, exact next patch and recovery reason'
base=$1 version=$2 reason=$3
[[ $reason =~ [^[:space:]] && ${#reason} -le 500 && ! $reason =~ [[:cntrl:]] ]] ||
  fail 'Provide a nonblank, single-line recovery reason of at most 500 characters (no credentials)'
[[ ${GITHUB_SHA:-} =~ ^[0-9a-f]{40}$ && $(git rev-parse HEAD) == "$GITHUB_SHA" ]] ||
  fail 'Checkout must match the immutable main dispatch SHA'
git merge-base --is-ancestor "$GITHUB_SHA" refs/remotes/origin/main

semver='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
[[ $base =~ ^atlas@$semver$ ]] || fail 'Base must be an exact stable atlas@ tag'
major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]}
# Increment decimal text without integer overflow, as in the stable SDK guard.
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
[[ $version == "$major.$minor.$next_patch" ]] || fail 'Only the exact next patch is allowed'
latest=$(git tag --list | LC_ALL=C grep -E "^atlas@$semver$" | sort -V | tail -n1)
[[ $latest == "$base" ]] || fail 'Base is no longer the latest stable Atlas tag'
! git show-ref --verify --quiet "refs/tags/atlas@$version" || fail 'Target tag already exists'
base_sha=$(git rev-parse "refs/tags/$base^{commit}")
if [[ ${APPROVED_BASE_SHA+x} ]]; then
  [[ $base_sha == "$APPROVED_BASE_SHA" ]] || fail 'Base tag changed after planning'
fi
git merge-base --is-ancestor "$base_sha" "$GITHUB_SHA"
[[ $base_sha != "$GITHUB_SHA" ]] || fail 'No changes after the base release'

{
  echo 'atlas-should-release=true'
  echo "atlas-next-version=atlas@$version"
  echo "atlas-next-version-number=$version"
  echo "base-sha=$base_sha"
} >> "$GITHUB_OUTPUT"
# Structured, bounded operator input cannot inject workflow commands. Never put
# credentials in the reason; this record is visible in the public Actions log.
jq -n --arg actor "${GITHUB_ACTOR:-}" --arg source "$GITHUB_SHA" \
  --arg base "$base" --arg version "$version" --arg reason "$reason" \
  '{actor: $actor, source: $source, base: $base, version: $version, reason: $reason}'
