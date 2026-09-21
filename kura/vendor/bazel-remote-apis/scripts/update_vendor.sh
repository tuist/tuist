#!/usr/bin/env bash

set -o errexit  # Exit immediately if a pipeline ... exits with a non-zero status
set -o pipefail # ... return value of a pipeline is the value of the last (rightmost) command to exit with a non-zero status
set -o nounset  # Treat unset variables ... as an error

export PATH=$PATH:`pwd`/vendor/github.com/brettlangdon/git-vendor/bin

# vendored repos
bzl_re_api_repo_name=bazel-remote-apis
ggl_api_repo_name=googleapis

function update_bzl_re_api_repo() {
  local new_ref=$1; shift
  local remote_tags="$@"

  git vendor update ${bzl_re_api_repo_name} ${new_ref}

  local googleapis_zip_url=$(grep -Po 'https://github.com/googleapis/googleapis/archive/.+\.zip' vendor/github.com/bazelbuild/remote-apis/WORKSPACE)
  local googleapis_commit=${googleapis_zip_url%.zip}
  googleapis_commit=${googleapis_commit##*/}

  git vendor update ${ggl_api_repo_name} ${googleapis_commit}

  cargo build --features codegen

  if [[ -z $(git diff --name-only -- src/) ]]; then
    echo No changes in generated code, not publishing
    return
  fi

  cargo set-version --bump minor
  new_ver=$(cargo read-manifest | jq -r '.version')
  git add Cargo.lock Cargo.toml src
  if [[ -z ${remote_tags} ]]; then
    git commit -m "${new_ver}"
  else
    git commit -m "${new_ver}: remote apis tags: ${remote_tags}"
  fi
  git tag ${new_ver}
  cargo publish
}

# bzl_re_api_repo_url=https://github.com/bazelbuild/remote-apis.git
bzl_re_api_repo_url=$(git vendor list ${bzl_re_api_repo_name} \
  | grep repo: | awk '{print $2}')
# bzl_re_api_repo_ref=main
bzl_re_api_repo_ref=$(git vendor list ${bzl_re_api_repo_name} \
  | grep ref: | awk '{print $2}')
# bzl_re_api_repo_added_in_commit=123adbc...
# this is commit in bazel-remote-apis-rust
bzl_re_api_repo_added_in_commit=$(git vendor list ${bzl_re_api_repo_name} \
  | grep commit: | awk '{print $2}')

# split commit in remote vendored repo
bzl_re_api_repo_commit=$(git rev-list --skip=1 --max-count=1 --no-commit-header \
  --format="%(trailers:key=git-subtree-split,valueonly)" \
  ${bzl_re_api_repo_added_in_commit})

bzl_re_api_repo_last_commit=$(git ls-remote ${bzl_re_api_repo_url} \
  ${bzl_re_api_repo_ref} | awk '{print $1}')

echo Vendored repo ${bzl_re_api_repo_url}, ref ${bzl_re_api_repo_ref}, from commit ${bzl_re_api_repo_commit}, last commit ${bzl_re_api_repo_last_commit}

if [[ ${bzl_re_api_repo_commit} == ${bzl_re_api_repo_last_commit} ]]; then
  echo Vendored repo is up-to-date, exiting ...
  exit 0
fi

declare -A bzl_re_api_repo_commit_tags
while read commit tag; do
  if [[ -v bzl_re_api_repo_commit_tags[${commit}] ]]; then
    bzl_re_api_repo_commit_tags[${commit}]+=" ${tag}"
  else
    bzl_re_api_repo_commit_tags[${commit}]=${tag}
  fi
done < <(git ls-remote --tags ${bzl_re_api_repo_url} | sed 's%refs/tags/%%')

bzl_re_api_repo_log_dir=$(mktemp --tmpdir --directory ${bzl_re_api_repo_name}.XXXX)
git clone --filter=blob:none --no-checkout --single-branch --branch ${bzl_re_api_repo_ref} ${bzl_re_api_repo_url} ${bzl_re_api_repo_log_dir}
bzl_re_api_repo_next_commits=$(git --git-dir=${bzl_re_api_repo_log_dir}/.git log --reverse --format=%H ${bzl_re_api_repo_commit}..${bzl_re_api_repo_last_commit}~1)

for c in ${bzl_re_api_repo_next_commits}; do
  if [[ -v bzl_re_api_repo_commit_tags[${c}] ]]; then
    update_bzl_re_api_repo $c ${bzl_re_api_repo_commit_tags[${c}]}
  fi
done

update_bzl_re_api_repo ${bzl_re_api_repo_ref} ${bzl_re_api_repo_commit_tags[${bzl_re_api_repo_last_commit}]:-}
