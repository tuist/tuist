#!/usr/bin/env bash
# Exercise the planner and publication gate against disposable Git remotes.
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/stable-image-patch.sh"
scratch=$(mktemp -d)
trap 'if [[ $? != 0 ]]; then cat "$scratch/log" >&2; fi; rm -rf "$scratch"' EXIT

fail() {
  echo "$*" >&2
  exit 1
}

git_work() { git -C "$work" "$@"; }

commit() {
  mkdir -p "$(dirname "$work/$1")"
  printf '%s\n' "$2" >"$work/$1"
  git_work add .
  git_work commit -qm 'fixture change'
  source_sha=$(git_work rev-parse HEAD)
}

setup() {
  root="$scratch/$component-$test_name"
  work="$root/work"
  remote="$root/remote.git"
  controls="$root/controls"
  output="$root/outputs"
  mkdir -p "$work"
  git_work init -q --initial-branch=main
  git_work config user.name Fixture
  git_work config user.email fixture@example.invalid
  git_work config commit.gpgsign false
  git_work config core.hooksPath /dev/null
  commit "$component/code" initial
  seed=$source_sha
  commit "$component/code" stable
  base_sha=$source_sha
  tag="$component@$stable"
  git_work tag "$tag"
  line=${stable%.*}
  major=${line%.*}
  minor=${line#*.}
  branch="releases/$component-$line.x"
  git_work switch -qc "$branch"
  commit "$component/code" patched
  git init -q --bare "$remote"
  git_work remote add origin "$remote"
  git_work push -q origin "$branch" --tags
  git clone -q --branch "$branch" "$remote" "$controls"
}

invoke() {
  rm -f "$output"
  (
    cd "$controls"
    unset APPROVED_BASE_SHA EXPECTED_VERSION
    env GITHUB_REPOSITORY=tuist/tuist GITHUB_REF=refs/heads/main \
      GITHUB_EVENT_NAME=workflow_dispatch GITHUB_OUTPUT="$output" "$@" \
      bash "$script" "$component" "$source_sha" "$tag"
  ) >"$root/stdout" 2>"$root/stderr"
}

accept() {
  invoke "$@" || {
    cat "$root/stderr" >&2
    fail 'Rejected a valid patch'
  }
  printf 'version=%s\nsha=%s\nbase_tag=%s\nbase_sha=%s\nbranch=%s\n' \
    "$patch" "$source_sha" "$tag" "$base_sha" "$branch" >"$root/expected"
  diff -u "$root/expected" "$output"
}

reject() {
  local message=$1
  shift
  if invoke "$@"; then fail 'Accepted an invalid patch'; fi
  [[ ! -e $output ]] || fail 'A rejected release emitted publication outputs'
  grep -Fq "$message" "$root/stderr" || {
    cat "$root/stderr" >&2
    fail "Missing rejection: $message"
  }
}

derives_next_patch_and_pins_exact_source_and_base() {
  accept "APPROVED_BASE_SHA=$base_sha" "EXPECTED_VERSION=$patch"
  # Decimal carry and comparison must not wrap at Bash's integer limit.
  local pair
  for pair in 9:10 99:100 9223372036854775807:9223372036854775808; do
    tag="$component@$line.${pair%:*}"
    patch="$line.${pair#*:}"
    git_work tag "$tag" "$base_sha"
    git_work push -q origin --tags
    accept "APPROVED_BASE_SHA=$base_sha" "EXPECTED_VERSION=$patch"
  done
}

rejects_other_repository_ref_and_event() {
  reject 'dispatched from' GITHUB_REPOSITORY=fork/tuist
  reject 'dispatched from' GITHUB_REF=refs/heads/topic
  reject 'dispatched from' GITHUB_EVENT_NAME=pull_request
}

rejects_unmerged_source() {
  commit "$component/code" unmerged
  reject 'merged stable branch tip'
}

refetches_replaced_branch_instead_of_accepting_stale_local_tip() {
  local old_source=$source_sha
  commit "$component/code" replacement
  git_work push -q origin "$branch"
  source_sha=$old_source
  reject 'merged stable branch tip'
}

rejects_deleted_branch_even_with_stale_local_ref() {
  git_work push -q origin --delete "$branch"
  reject ''
}

rejects_replaced_base_even_when_replacement_is_still_an_ancestor() {
  git_work tag --force "$tag" "$seed"
  git_work push -q --force origin "refs/tags/$tag"
  reject 'base changed' "APPROVED_BASE_SHA=$base_sha"
}

rejects_missing_approved_base_and_wrong_planned_version() {
  reject 'base changed' APPROVED_BASE_SHA=
  reject 'Planned patch version changed' EXPECTED_VERSION=99.1.8
}

allows_maintained_line_after_newer_minor_and_major_releases() {
  local old_source=$source_sha
  git_work switch -q main
  commit "$component/code" 'newer line'
  git_work tag "$component@$major.$((minor + 1)).0"
  git_work tag "$component@$((major + 1)).0.0"
  git_work push -q origin --tags
  source_sha=$old_source
  accept
  accept "APPROVED_BASE_SHA=$base_sha" "EXPECTED_VERSION=$patch"
}

rejects_newly_published_patch_without_relying_on_local_tags() {
  git_work tag "$component@$major.$((minor + 1)).0"
  git_work tag "$component@$patch"
  git_work push -q origin --tags
  reject 'latest published stable'
}

rejects_no_change_and_unrelated_component_changes() {
  local old_source=$source_sha
  git_work push -q --force origin "$base_sha:refs/heads/$branch"
  source_sha=$base_sha
  reject 'contain a patch'
  source_sha=$old_source
  commit app/unrelated 'not part of this patch'
  git_work push -q --force origin "$branch"
  reject 'outside its component'
}

rejects_source_on_a_different_history() {
  git_work switch -q --orphan unrelated
  commit "$component/code" 'different history'
  git_work push -q --force origin "HEAD:refs/heads/$branch"
  reject 'must be an ancestor'
}

allows_shared_trust_inputs_but_not_the_other_products_dependencies() {
  commit infra/certificate-trust/policy.json 'fixture policy'
  commit infra/certificate-trust/pem-store.sh 'fixture store'
  git_work push -q origin "$branch"
  accept
  commit tuist_common/mix.exs 'shared Elixir dependency'
  git_work push -q origin "$branch"
  if [[ $component == server ]]; then accept; else reject 'outside its component'; fi
}

allows_component_validation_but_rejects_unrelated_trust_tooling() {
  commit "$component/"$'code with\nnewlines' 'valid component path'
  commit ".github/workflows/$component.yml" validation
  git_work push -q origin "$branch"
  accept
  commit infra/certificate-trust/deploy.sh 'not a source input'
  git_work push -q origin "$branch"
  reject 'outside its component'
}

tests=(
  derives_next_patch_and_pins_exact_source_and_base
  rejects_other_repository_ref_and_event
  rejects_unmerged_source
  refetches_replaced_branch_instead_of_accepting_stale_local_tip
  rejects_deleted_branch_even_with_stale_local_ref
  rejects_replaced_base_even_when_replacement_is_still_an_ancestor
  rejects_missing_approved_base_and_wrong_planned_version
  allows_maintained_line_after_newer_minor_and_major_releases
  rejects_newly_published_patch_without_relying_on_local_tags
  rejects_no_change_and_unrelated_component_changes
  rejects_source_on_a_different_history
  allows_shared_trust_inputs_but_not_the_other_products_dependencies
  allows_component_validation_but_rejects_unrelated_trust_tooling
)

count=0
for component in server kura; do
  if [[ $component == server ]]; then
    stable=1.355.2
    patch=1.355.3
  else
    stable=0.59.4
    patch=0.59.5
  fi
  for test_name in "${tests[@]}"; do
    printf '%s: %s ... ' "$component" "$test_name"
    (
      setup
      "$test_name"
    ) >"$scratch/log" 2>&1
    echo PASS
    count=$((count + 1))
  done
done
echo "$count real-Git backport controls passed."
