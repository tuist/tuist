#!/usr/bin/env bash
# Exercise the stable release guard against real, disposable Git histories.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/tuist-ex-stable-release.sh"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

fail() { echo "$*" >&2; exit 1; }
commit() {
  mkdir -p "$(dirname "$1")"
  printf '%s' "$2" > "$1"
  git add -- "$1"
  git commit -qm 'fix(tuist-ex): test patch'
  git rev-parse HEAD
}
setup() {
  git init -q
  git config user.name 'Release test'
  git config user.email release@example.invalid
  base=$(commit tuist_ex/lib/client.ex stable)
  git tag tuist-ex@0.10.9
  source_sha=$(commit tuist_ex/lib/client.ex 'TLS patch')
  branch=refs/remotes/origin/releases/tuist-ex-0.10.x
  git update-ref "$branch" "$source_sha"
  export GITHUB_REPOSITORY=tuist/tuist GITHUB_REF=refs/heads/main GITHUB_EVENT_NAME=workflow_dispatch
  export GITHUB_OUTPUT="$PWD/output"
  unset APPROVED_BASE_SHA
}
guard() {
  : > "$GITHUB_OUTPUT"
  bash "$SCRIPT" "$@" > stdout 2> stderr
}
accept() {
  guard "$@" || { cat stderr >&2; fail 'Expected guard acceptance'; }
}
reject() {
  if guard "$@"; then fail 'Expected guard rejection'; fi
  [[ ! -s $GITHUB_OUTPUT ]] || fail 'Rejected input emitted release outputs'
}

test_accepts_only_next_patch_and_emits_pinned_source() {
  git tag tuist-ex@0.99.0-canary.1
  git tag tuist-ex@0.9.99
  accept "$source_sha" tuist-ex@0.10.9 0.10.10
  cat > expected <<EOF
tuist-ex-should-release=true
tuist-ex-next-version=tuist-ex@0.10.10
tuist-ex-next-version-number=0.10.10
source-sha=$source_sha
base-tag=tuist-ex@0.10.9
base-sha=$base
EOF
  diff -u expected "$GITHUB_OUTPUT"
  # Numeric tag ordering and next-patch arithmetic must not overflow Bash integers.
  git tag tuist-ex@0.10.999999999999999999999 "$base"
  accept "$source_sha" tuist-ex@0.10.999999999999999999999 0.10.1000000000000000000000
  reject "$source_sha" tuist-ex@0.10.999999999999999999999 0.10.1000000000000000000001
}
test_rejects_missing_mutable_and_injected_inputs() {
  local value
  reject
  reject "$source_sha"
  reject "$source_sha" tuist-ex@0.10.9
  reject "$source_sha" tuist-ex@0.10.9 0.10.10 extra
  for value in '' main "${source_sha:0:12}" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa$'\noutput=bad' --help; do
    reject "$value" tuist-ex@0.10.9 0.10.10
  done
  for value in '' 0.10.9 tuist-ex@0.10.09 tuist-ex@0.10.9-rc.1 $'tuist-ex@0.10.9\n'; do
    reject "$source_sha" "$value" 0.10.10
  done
  for value in '' 0.10.9 0.10.11 0.11.0 1.0.0 0.10.10-rc.1 $'0.10.10\n'; do
    reject "$source_sha" tuist-ex@0.10.9 "$value"
  done
}
test_requires_main_dispatch_in_upstream_repository() {
  GITHUB_EVENT_NAME=push reject "$source_sha" tuist-ex@0.10.9 0.10.10
  GITHUB_EVENT_NAME=pull_request reject "$source_sha" tuist-ex@0.10.9 0.10.10
  GITHUB_REF=refs/heads/releases/tuist-ex-0.10.x reject "$source_sha" tuist-ex@0.10.9 0.10.10
  GITHUB_REPOSITORY=fork/tuist reject "$source_sha" tuist-ex@0.10.9 0.10.10
}
test_rejects_unmerged_pr_and_stale_release_tip() {
  local newer
  newer=$(commit tuist_ex/lib/client.ex 'another patch')
  reject "$newer" tuist-ex@0.10.9 0.10.10
  git update-ref "$branch" "$newer"
  reject "$source_sha" tuist-ex@0.10.9 0.10.10
}
test_rejects_missing_branch_and_wrong_line() {
  git update-ref -d "$branch"
  git update-ref refs/remotes/origin/releases/tuist-ex-0.11.x "$source_sha"
  reject "$source_sha" tuist-ex@0.10.9 0.10.10
}
test_rejects_unchanged_or_non_descendant_source() {
  git update-ref "$branch" "$base"
  reject "$base" tuist-ex@0.10.9 0.10.10
  git checkout -q --orphan unrelated
  local unrelated
  unrelated=$(commit tuist_ex/lib/client.ex 'unrelated tree')
  git update-ref "$branch" "$unrelated"
  reject "$unrelated" tuist-ex@0.10.9 0.10.10
}
test_rejects_stale_base_and_existing_target_tag() {
  git tag tuist-ex@0.11.0
  reject "$source_sha" tuist-ex@0.10.9 0.10.10
  git tag -d tuist-ex@0.11.0 > /dev/null
  git tag tuist-ex@0.10.10 "$base"
  reject "$source_sha" tuist-ex@0.10.9 0.10.10
}
test_recheck_rejects_replaced_base_even_when_new_base_is_a_source_ancestor() {
  local newer
  newer=$(commit tuist_ex/lib/client.ex 'second patch')
  git update-ref "$branch" "$newer"
  accept "$newer" tuist-ex@0.10.9 0.10.10
  APPROVED_BASE_SHA=$base accept "$newer" tuist-ex@0.10.9 0.10.10
  APPROVED_BASE_SHA='' reject "$newer" tuist-ex@0.10.9 0.10.10
  git tag --force tuist-ex@0.10.9 "$source_sha" > /dev/null
  # The name, latest-version, ancestry and SDK-only checks still pass.
  accept "$newer" tuist-ex@0.10.9 0.10.10
  APPROVED_BASE_SHA=$base reject "$newer" tuist-ex@0.10.9 0.10.10
}
test_rejects_other_product_or_automation_changes() {
  local path newer
  for path in server/lib/app.ex mise/tasks/release/components.json .github/workflows/tuist-ex-release.yml $'server/tuist_ex/\nclient.ex'; do
    newer=$(commit "$path" 'unrelated change')
    git update-ref "$branch" "$newer"
    reject "$newer" tuist-ex@0.10.9 0.10.10
    git reset -q --hard "$source_sha"
  done
}
test_allows_sdk_validation_backport_but_not_validation_only_release() {
  local newer
  newer=$(commit .github/workflows/tuist-ex.yml 'minimum OTP TLS coverage')
  git update-ref "$branch" "$newer"
  accept "$newer" tuist-ex@0.10.9 0.10.10
  newer=$(commit $'tuist_ex/lib/\nclient.ex' 'SDK filename with newline')
  git update-ref "$branch" "$newer"
  accept "$newer" tuist-ex@0.10.9 0.10.10
  git reset -q --hard "$base"
  newer=$(commit .github/workflows/tuist-ex.yml 'validation only')
  git update-ref "$branch" "$newer"
  reject "$newer" tuist-ex@0.10.9 0.10.10
}

tests=(
  test_accepts_only_next_patch_and_emits_pinned_source
  test_rejects_missing_mutable_and_injected_inputs
  test_requires_main_dispatch_in_upstream_repository
  test_rejects_unmerged_pr_and_stale_release_tip
  test_rejects_missing_branch_and_wrong_line
  test_rejects_unchanged_or_non_descendant_source
  test_rejects_stale_base_and_existing_target_tag
  test_recheck_rejects_replaced_base_even_when_new_base_is_a_source_ancestor
  test_rejects_other_product_or_automation_changes
  test_allows_sdk_validation_backport_but_not_validation_only_release
)
for test in "${tests[@]}"; do
  mkdir "$scratch/$test"
  (
    cd "$scratch/$test"
    setup
    "$test"
  )
  echo "PASS $test"
done
echo "${#tests[@]} stable release boundary tests passed"
