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
  printf '%s\n' "$message" >> "$path"
  git add .
  git commit -qm "$message"
}
setup() {
  mkdir "$fixture/$1"
  cd "$fixture/$1"
  git init -q --initial-branch=main
  git config user.name test
  git config user.email test@example.com
  for path in mise/tasks/release/check.sh mise/tasks/release/components.json ci/runner-caches/cliff.toml; do
    mkdir -p "$(dirname "$path")"
    cp "$source_root/$path" "$path"
  done
  commit 'feat(infra): add runner caches' .github/actions/xcode-cache/action.yml
}
check() {
  : > .git/outputs
  GITHUB_OUTPUT="$PWD/.git/outputs" bash mise/tasks/release/check.sh runner-caches > "$fixture/output" 2>&1
  grep -qx "runner-caches-$1=$2" .git/outputs
}

setup initial
check next-version runner-caches@1.0.0
git tag runner-caches@1.0.0
check should-release false
echo 'ok: initial release is 1.0.0 and unchanged source does not release'

setup unrelated
git tag runner-caches@1.0.0
commit 'feat(infra): change the runner image helper' infra/runner-image/tuist-runner-cache
commit 'feat(cli): unrelated change' cli/unrelated.swift
check should-release false
echo 'ok: changes outside the packages do not release'

setup packages
git tag runner-caches@1.0.0
index=0
for path in .github/actions/module-cache/action.yml .github/actions/gradle-cache/setup.sh \
  ci/runner-caches/xcode-cache/buildkite/plugin.yml ci/runner-caches/gradle-cache/gitlab/gradle-cache.yml \
  ci/cache-volume/publish.sh; do
  index=$((index + 1))
  commit 'fix(infra): update a runner cache' "$path"
  check next-version "runner-caches@1.0.$index"
  git tag "runner-caches@1.0.$index"
done
echo 'ok: every package and the shared publisher trigger a release'

setup features
git tag runner-caches@1.0.0
commit 'feat(infra): new capability' ci/runner-caches/module-cache/gitlab/module-cache.yml
check next-version runner-caches@1.1.0
echo 'ok: features bump the minor version'
