#!/usr/bin/env bash
# Exercise recovery against real Git histories, without credentials or publishing.
set -euo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/atlas-patch-release.sh"
WORKFLOW="$(dirname "$SCRIPT")/../workflows/atlas-release.yml"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
fail() { echo "$*" >&2; exit 1; }
setup() {
  git init -q
  git config user.name 'Release test'
  git config user.email release@example.invalid
  git commit --allow-empty -qm 'fix(atlas): base'
  base=$(git rev-parse HEAD)
  git tag atlas@0.76.9
  git commit --allow-empty -qm 'feat(pulse): rename Atlas integration'
  GITHUB_SHA=$(git rev-parse HEAD)
  export GITHUB_SHA
  git update-ref refs/remotes/origin/main "$GITHUB_SHA"
  export GITHUB_REPOSITORY=tuist/tuist GITHUB_REF=refs/heads/main GITHUB_EVENT_NAME=workflow_dispatch
  export GITHUB_OUTPUT="$PWD/output"
  unset APPROVED_BASE_SHA
}
guard() {
  : > "$GITHUB_OUTPUT"
  bash "$SCRIPT" "$@" > stdout 2> stderr
}
accept() { guard "$@" || { cat stderr >&2; fail 'Expected acceptance'; }; }
reject() {
  if guard "$@"; then fail 'Expected rejection'; fi
  [[ ! -s $GITHUB_OUTPUT ]] || fail 'Rejected request emitted release outputs'
}
test_next_patch_and_public_audit() {
  git tag atlas@0.99.0-canary.1
  git tag atlas@0.75.99
  accept atlas@0.76.9 0.76.10 'Recover the merged Pulse rename'
  printf 'atlas-should-release=true\natlas-next-version=atlas@0.76.10\natlas-next-version-number=0.76.10\nbase-sha=%s\n' "$base" > expected
  diff -u expected "$GITHUB_OUTPUT"
  jq -e --arg sha "$GITHUB_SHA" '.source == $sha and .reason == "Recover the merged Pulse rename"' stdout >/dev/null
}
test_invalid_inputs_and_context() {
  reject
  reject atlas@0.76.9 0.76.10
  local version reason
  for version in '' 0.76.9 0.76.11 0.77.0 1.0.0 0.76.10-rc.1 $'0.76.10\ninject=true'; do
    reject atlas@0.76.9 "$version" recovery
  done
  for reason in '' '   ' $'recovery\n::error::inject' "$(printf '%501s' x)"; do
    reject atlas@0.76.9 0.76.10 "$reason"
  done
  reject atlas@0.76.09 0.76.10 recovery
  GITHUB_REF=refs/heads/feature reject atlas@0.76.9 0.76.10 recovery
  GITHUB_EVENT_NAME=push reject atlas@0.76.9 0.76.10 recovery
  GITHUB_REPOSITORY=fork/tuist reject atlas@0.76.9 0.76.10 recovery
  GITHUB_SHA="$base" reject atlas@0.76.9 0.76.10 recovery
  git update-ref refs/remotes/origin/main "$base"
  reject atlas@0.76.9 0.76.10 recovery
}
test_stale_dispatch_and_moved_base() {
  accept atlas@0.76.9 0.76.10 recovery
  APPROVED_BASE_SHA="$base" accept atlas@0.76.9 0.76.10 recovery
  APPROVED_BASE_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa reject atlas@0.76.9 0.76.10 recovery
  git tag atlas@0.76.10
  reject atlas@0.76.9 0.76.10 recovery
  git tag -d atlas@0.76.10 >/dev/null
  git tag atlas@0.77.0
  reject atlas@0.76.9 0.76.10 recovery
}
test_source_requires_descendant_changes() {
  git checkout -q --detach "$base"
  export GITHUB_SHA=$base
  reject atlas@0.76.9 0.76.10 recovery
  git checkout -q --orphan unrelated
  git commit --allow-empty -qm 'fix(atlas): unrelated'
  GITHUB_SHA=$(git rev-parse HEAD)
  export GITHUB_SHA
  git update-ref refs/remotes/origin/main "$GITHUB_SHA"
  reject atlas@0.76.9 0.76.10 recovery
}
test_remote_tag_refresh_rejects_deleted_and_moved_bases() {
  local remote="$PWD/remote.git" refresh
  git init --bare -q "$remote"
  git remote add origin "$remote"
  git push -q origin HEAD:refs/heads/main --tags
  accept atlas@0.76.9 0.76.10 recovery
  # Exercise the workflow's actual prepublication fetch, not a test-only copy.
  refresh=$(sed -n '/^          git fetch origin /p' "$WORKFLOW")
  [[ -n $refresh ]] || fail 'Missing prepublication fetch'
  git --git-dir="$remote" update-ref -d refs/tags/atlas@0.76.9
  bash -e -c "$refresh" >/dev/null 2>&1
  APPROVED_BASE_SHA="$base" reject atlas@0.76.9 0.76.10 recovery

  git tag atlas@0.76.9 "$base"
  git push -q origin refs/tags/atlas@0.76.9
  git --git-dir="$remote" update-ref refs/tags/atlas@0.76.9 "$GITHUB_SHA"
  # A moved tag must either stop fetch or fail the approved-base check.
  if bash -e -c "$refresh" >/dev/null 2>&1; then
    APPROVED_BASE_SHA="$base" reject atlas@0.76.9 0.76.10 recovery
  fi
}
for test in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do
  mkdir "$scratch/$test"
  (cd "$scratch/$test"; setup; "$test")
  echo "PASS $test"
done
