#!/usr/bin/env bash
# Validate a server or Kura patch without executing its source.
set -euo pipefail
export LC_ALL=C

fail() {
  echo "$*" >&2
  exit 1
}

[[ ${GITHUB_REPOSITORY:-} == tuist/tuist && ${GITHUB_REF:-} == refs/heads/main && ${GITHUB_EVENT_NAME:-} == workflow_dispatch ]] ||
  fail 'Stable patches must be dispatched from tuist/tuist main'
[[ $# == 3 ]] || fail 'Provide component, source SHA and stable base tag'
component=$1
source_sha=$2
base=$3
[[ $component == server || $component == kura ]] || fail 'Only server and Kura image patches are supported'
[[ $source_sha =~ ^[0-9a-f]{40}$ ]] || fail 'Source must be a full immutable commit SHA'
semver='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
[[ $base =~ ^${component}@${semver}$ ]] || fail 'Base must be an exact stable tag for the selected component'
major=${BASH_REMATCH[1]}
minor=${BASH_REMATCH[2]}
patch=${BASH_REMATCH[3]}
# Preserve decimal version arithmetic without Bash's machine-integer limit.
if [[ $patch =~ ^([0-9]*)([0-8])(9*)$ ]]; then
  next_patch="${BASH_REMATCH[1]}$((BASH_REMATCH[2] + 1))${BASH_REMATCH[3]//9/0}"
else
  next_patch="1${patch//9/0}"
fi
version="$major.$minor.$next_patch"
if [[ ${EXPECTED_VERSION+x} ]]; then
  [[ $EXPECTED_VERSION == "$version" ]] || fail 'Planned patch version changed'
fi

# Inspect remote tags, not the checkout's possibly stale tag cache.
remote_tags=$(git ls-remote --tags --refs origin "refs/tags/$component@*")
latest=
latest_patch=
target_exists=false
while IFS=$'\t' read -r _ ref; do
  tag=${ref#refs/tags/}
  [[ $tag != "$component@$version" ]] || target_exists=true
  if [[ $tag =~ ^${component}@${semver}$ ]]; then
    [[ ${BASH_REMATCH[1]} == "$major" && ${BASH_REMATCH[2]} == "$minor" ]] || continue
    candidate=${BASH_REMATCH[3]}
    if [[ -z $latest || ${#candidate} -gt ${#latest_patch} ||
      (${#candidate} -eq ${#latest_patch} && $candidate > $latest_patch) ]]; then
      latest=$tag
      latest_patch=$candidate
    fi
  fi
done <<<"$remote_tags"
[[ $latest == "$base" ]] || fail 'Base must be the latest published stable tag on the selected release line'
[[ $target_exists == false ]] || fail 'Target tag already exists; never replace a release'

branch="releases/$component-$major.$minor.x"
remote="refs/remotes/origin/$branch"
git fetch --force --no-tags origin \
  "+refs/tags/$base:refs/tags/$base" "+refs/heads/$branch:$remote"
[[ $(git rev-parse "$remote^{commit}") == "$source_sha" ]] || fail 'Source must equal the current merged stable branch tip'
base_sha=$(git rev-parse "refs/tags/$base^{commit}")
if [[ ${APPROVED_BASE_SHA+x} ]]; then
  [[ $APPROVED_BASE_SHA == "$base_sha" ]] || fail 'Stable base changed since planning'
fi
[[ $source_sha != "$base_sha" ]] || fail 'Source must contain a patch after the stable tag'
git merge-base --is-ancestor "$base_sha" "$source_sha" || fail 'Stable tag must be an ancestor of the selected source'

# NUL-delimited paths preserve spaces/newlines. Materialize the diff first so
# a Git failure cannot be hidden by a process substitution's exit status.
changed=$(mktemp)
trap 'rm -f "$changed"' EXIT
git diff --no-renames --name-only -z "$base_sha" "$source_sha" >"$changed"
component_changed=false
outside_component=false
while IFS= read -r -d '' path; do
  case "$path" in
  "$component"/*) component_changed=true ;;
  tuist_common/*)
    [[ $component == server ]] || outside_component=true
    ;;
  infra/certificate-trust/policy.json | infra/certificate-trust/pem-store.sh | ".github/workflows/$component.yml") ;;
  *) outside_component=true ;;
  esac
done <"$changed"
[[ $component_changed == true ]] || fail 'No component changes to publish'
[[ $outside_component == false ]] || fail 'Stable patch includes changes outside its component, trust policy and validation'

printf 'version=%s\nsha=%s\nbase_tag=%s\nbase_sha=%s\nbranch=%s\n' \
  "$version" "$source_sha" "$base" "$base_sha" "$branch" >>"$GITHUB_OUTPUT"
echo "Validated $base ($base_sha) -> $component@$version from $source_sha"
