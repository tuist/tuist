#!/usr/bin/env bash
set -euo pipefail

source_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
command -v git-cliff >/dev/null
command -v jq >/dev/null

commit() {
  local message=$1 path=$2
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$message" > "$path"
  git add .
  git commit -qm "$message"
}
setup() {
  mkdir "$fixture/$1"
  cd "$fixture/$1"
  git init -q --initial-branch=main
  git config user.name test
  git config user.email test@example.com
  for path in mise/tasks/release/check.sh mise/tasks/release/components.json ci/cache-volume/cliff.toml; do
    mkdir -p "$(dirname "$path")"
    cp "$source_root/$path" "$path"
  done
  commit 'feat(server): add cache volumes' ci/cache-volume/gitlab/cache-volume.yml
}
check() {
  : > .git/outputs
  GITHUB_OUTPUT="$PWD/.git/outputs" bash mise/tasks/release/check.sh cache-volume > "$fixture/output" 2>&1
  grep -qx "cache-volume-$1=$2" .git/outputs
}

setup initial
check next-version cache-volume@1.0.0
git tag cache-volume@1.0.0
check should-release false
echo 'ok: initial release is 1.0.0 and unchanged source does not release'

setup unrelated
git tag cache-volume@1.0.0
commit 'feat(cli): unrelated change' cli/unrelated.swift
check should-release false
echo 'ok: unrelated changes do not release'

setup providers
git tag cache-volume@1.0.0
index=0
for path in .github/actions/cache-volume/action.yml ci/cache-volume/buildkite/plugin.yml ci/cache-volume/gitlab/cache-volume.yml; do
  index=$((index + 1))
  commit 'fix(server): update integration' "$path"
  check next-version "cache-volume@1.0.$index"
  git tag "cache-volume@1.0.$index"
done
echo 'ok: each provider triggers a patch release'

setup breaking
git tag cache-volume@1.0.0
commit 'feat(server): new capability' ci/cache-volume/gitlab/cache-volume.yml
check next-version cache-volume@1.1.0
git tag cache-volume@1.1.0
commit 'feat(server)!: change contract' ci/cache-volume/gitlab/cache-volume.yml
check next-version cache-volume@2.0.0
echo 'ok: features and breaking changes bump minor and major versions'

setup workflow
git tag cache-volume@1.0.0
commit 'ci(server): fix publishing' .github/workflows/cache-volume-action.yml
check next-version cache-volume@1.0.1
echo 'ok: release workflow changes trigger a patch release'
