#!/usr/bin/env bash
# Tests production-source-guard.sh against a local repository.

set -euo pipefail

guard="$(cd "$(dirname "$0")" && pwd)/production-source-guard.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

origin="$scratch/origin"
git init --quiet -b main "$origin"
# Serve partial clones like GitHub, so the guard's --filter=tree:0 fetch and
# lazy-fetch refusal are exercised rather than falling back to a full fetch.
git -C "$origin" config uploadpack.allowFilter true
git -C "$origin" config uploadpack.allowAnySHA1InWant true
commit() { git -C "$origin" -c user.name=t -c user.email=t@t commit --quiet --allow-empty -m "$1"; git -C "$origin" rev-parse HEAD; }
old_main="$(commit one)"
main_tip="$(commit two)"
git -C "$origin" checkout --quiet -b feature
branch_only="$(commit unreviewed)"
git -C "$origin" checkout --quiet main
# Unreferenced but present in the repository, like a fork pull request's head.
git -C "$origin" checkout --quiet --detach
dangling="$(commit dangling)"
git -C "$origin" checkout --quiet main

failures=0
expect() {
  local want="$1" name="$2"
  shift 2
  if PRODUCTION_SOURCE_REMOTE="$origin" bash "$guard" "$@" >"$scratch/out" 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$want" ]; then
    echo "ok - $name"
  else
    echo "not ok - $name (expected $want, got $got)"
    sed 's/^/  /' "$scratch/out"
    failures=$((failures + 1))
  fi
}

expect pass 'main tip' refs/heads/main "$main_tip"
expect pass 'older main commit (rollback)' refs/heads/main "$old_main"
expect fail 'commit only on a branch' refs/heads/main "$branch_only"
expect fail 'commit no ref points at' refs/heads/main "$dangling"
expect fail 'unknown commit' refs/heads/main "$(printf 'f%.0s' {1..40})"
expect fail 'run from a branch' refs/heads/feature "$main_tip"
expect fail 'abbreviated SHA' refs/heads/main "${main_tip:0:12}"
expect fail 'branch name instead of a SHA' refs/heads/main feature

expect pass 'image tags built from main, unset ones skipped' refs/heads/main "$main_tip" \
  "image_tag=sha-${old_main:0:12}" "registry_image_tag=sha-$main_tip" "sandboxd_image_tag="
expect fail 'image tag built from a branch' refs/heads/main "$main_tip" \
  "image_tag=sha-${main_tip:0:12}" "registry_image_tag=sha-${branch_only:0:12}"
expect fail 'image tag built from a dangling commit' refs/heads/main "$main_tip" \
  "image_tag=sha-${dangling:0:12}"
expect fail 'image tag that names no commit' refs/heads/main "$main_tip" "image_tag=latest"
expect fail 'image tag with too short a prefix' refs/heads/main "$main_tip" "image_tag=sha-${main_tip:0:8}"

# Maintenance must not outlive the disposable repository and race its cleanup.
# Trace real Git processes: a tiny fixture otherwise rarely hits that race.
trace="$scratch/trace.json"
GIT_TRACE2_EVENT="$trace" expect pass 'main check without background maintenance' refs/heads/main "$main_tip"
if grep -Eq '"event":"start".*"argv":\[.*"maintenance"' "$trace"; then
  echo 'not ok - disposable repository launched maintenance'
  failures=$((failures + 1))
else
  echo 'ok - disposable repository did not launch maintenance'
fi

[ "$failures" -eq 0 ]
