#!/usr/bin/env bash
# Refuse a production deploy unless it was started from main, deploys a
# commit main already contains, and every pre-built image override it names
# was built from a commit on main. A run from main can still name any commit in
# its commit_sha input, or any image a branch build pushed, so checking
# github.ref alone lets unreviewed code reach production.
#
# Usage: production-source-guard.sh <github-ref> <deploy-sha> [name=tag ...]
# Each name=tag is a pre-built image override whose builds tag images
# sha-<12 hex of the source commit>; empty tags are skipped, and a set tag must
# have that form and name a commit on main. Overrides in other forms (release
# semvers, digests) cannot be traced to a commit and are not passed here. Tags
# are mutable, so this narrows the path rather than closing it; the
# server-k8s-production environment's branch and reviewer rules remain the
# control.
#
# PRODUCTION_SOURCE_REMOTE overrides the repository to fetch (tests pass a
# local path). The repository is public, so the fetch needs no credentials.

set -euo pipefail

ref="$1"
sha="$2"
shift 2
remote="${PRODUCTION_SOURCE_REMOTE:-https://github.com/${GITHUB_REPOSITORY:?}}"

fail() {
  echo "::error::$1" >&2
  exit 1
}

[ "$ref" = refs/heads/main ] ||
  fail "Production deploys must run from refs/heads/main. Current ref: $ref"

# A full SHA, never a branch name or abbreviation: deploy jobs check out this
# value against the whole repository, where an abbreviation could resolve to a
# different commit than the one checked here.
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] ||
  fail "Production deploys need a full 40-character commit SHA, got '$sha'."

repo="$(mktemp -d)"
trap 'rm -rf "$repo"' EXIT
git init --quiet --bare "$repo"
git -C "$repo" remote add origin "$remote"
# Commits only: main's full history without trees or blobs.
# This disposable repository needs no maintenance; detached writers can race
# the EXIT trap that removes it.
git -C "$repo" fetch --quiet --no-tags --no-auto-maintenance --filter=tree:0 origin \
  +refs/heads/main:refs/remotes/origin/main

# Never fetch the deploy commit on demand: it either arrived with main's
# history or it is not on main.
export GIT_NO_LAZY_FETCH=1
if git -C "$repo" cat-file -e "$sha^{commit}" 2>/dev/null &&
  git -C "$repo" merge-base --is-ancestor "$sha" refs/remotes/origin/main; then
  echo "Deploying $sha, which main contains."
else
  fail "Commit $sha is not on main. Merge it before deploying it to production."
fi

main_commits="$repo/main-commits"
git -C "$repo" rev-list refs/remotes/origin/main > "$main_commits"

for override in "$@"; do
  name="${override%%=*}"
  tag="${override#*=}"
  [ -n "$tag" ] || continue
  [[ "$tag" =~ ^sha-([0-9a-f]{12,40})$ ]] ||
    fail "$name '$tag' does not name a commit (expected sha-<12 or more hex>)."
  grep -q "^${BASH_REMATCH[1]}" "$main_commits" ||
    fail "$name '$tag' was not built from a commit on main."
  echo "$name '$tag' was built from a commit on main."
done
