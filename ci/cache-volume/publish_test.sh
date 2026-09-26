#!/usr/bin/env bash
set -euo pipefail

source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
source_commit=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

setup() {
  local root="$fixture/$1"
  mkdir -p "$root"
  remote="$root/remote.git"
  repository="$root/distribution"
  package="$root/package"
  git init -q --bare --initial-branch=main "$remote"
  git clone -q "$remote" "$repository"
  git -C "$repository" config user.name test
  git -C "$repository" config user.email test@example.com
  echo bootstrap > "$repository/obsolete"
  git -C "$repository" add .
  git -C "$repository" commit -qm Initial
  git -C "$repository" push -q origin main
  mkdir -p "$package/hooks"
  printf '%s\n' "$source_commit" > "$package/SOURCE_COMMIT"
  echo Integration > "$package/README.md"
  printf '#!/bin/sh\nexit 0\n' > "$package/hooks/pre-command"
}

publish() { bash "$source_dir/publish.sh" "$package" "$repository" "$1" "$source_commit"; }
retry_checkout() {
  repository="$(dirname "$repository")/retry"
  git clone -q "$remote" "$repository"
}
expect_failure() {
  local version=$1 diagnostic=$2
  if publish "$version" > "$fixture/error" 2>&1; then
    echo "FAIL: publication of $version unexpectedly succeeded" >&2; exit 1
  fi
  grep -q "$diagnostic" "$fixture/error"
}

setup initial
publish v1.0.0 > "$fixture/output" 2>&1
commit=$(git -C "$remote" rev-parse main)
[[ $(git -C "$remote" rev-parse v1.0.0) == "$commit" ]]
[[ $(git -C "$remote" rev-parse v1) == "$commit" ]]
[[ $(git -C "$remote" ls-tree main hooks/pre-command) == 100755* ]]
[[ -z $(git -C "$remote" ls-tree main obsolete) ]]
echo 'ok: publication pushes main and both tags and restores executable hooks'

retry_checkout
publish v1.0.0 > "$fixture/output" 2>&1
[[ $(git -C "$remote" rev-parse main) == "$commit" ]]
echo 'ok: retry after partial coordinated publication is idempotent'

echo Different > "$package/README.md"
expect_failure v1.0.0 'Immutable release'
[[ $(git -C "$remote" rev-parse v1.0.0) == "$commit" ]]
echo 'ok: immutable tags reject changed contents even with the same source SHA'

setup rollback
publish v1.0.0 > "$fixture/output" 2>&1
echo 'New version' > "$package/README.md"
publish v1.0.1 > "$fixture/output" 2>&1
commit=$(git -C "$remote" rev-parse v1)
echo Integration > "$package/README.md"
retry_checkout
publish v1.0.0 > "$fixture/output" 2>&1
[[ $(git -C "$remote" rev-parse v1) == "$commit" ]]
echo 'ok: retrying an older release does not roll back its major alias'

setup stale
publish v1.0.2 > "$fixture/output" 2>&1
expect_failure v1.0.1 'newer release'
echo 'ok: new tags cannot be published behind a newer release'

setup major
publish v1.0.0 > "$fixture/output" 2>&1
commit=$(git -C "$remote" rev-parse v1)
publish v2.0.0 > "$fixture/output" 2>&1
[[ $(git -C "$remote" rev-parse v1) == "$commit" ]]
[[ $(git -C "$remote" rev-parse v2) == "$(git -C "$remote" rev-parse v2.0.0)" ]]
echo 'ok: a new major preserves the previous major alias'

setup invalid
echo bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb > "$package/SOURCE_COMMIT"
expect_failure v1.0.0 'source commit'
expect_failure 'v1;echo unexpected' 'stable'
echo 'ok: package source and stable version are validated'

setup atomic
commit=$(git -C "$remote" rev-parse main)
printf '#!/bin/sh\n[ "$1" != refs/tags/v1 ]\n' > "$remote/hooks/update"
chmod +x "$remote/hooks/update"
expect_failure v1.0.0 'hook declined'
[[ $(git -C "$remote" rev-parse main) == "$commit" ]]
[[ -z $(git -C "$remote" tag --list) ]]
rm "$remote/hooks/update"
retry_checkout
publish v1.0.0 > "$fixture/output" 2>&1
[[ $(git -C "$remote" rev-parse main) == "$(git -C "$remote" rev-parse v1)" ]]
echo 'ok: rejected atomic pushes leave no partial remote state and can be retried'

bash "$source_dir/gitlab/package.sh" "$fixture/gitlab-package"
[[ $(ls -A "$fixture/gitlab-package" | LC_ALL=C sort) == $'LICENSE.md\nREADME.md\nSOURCE_COMMIT\ncache-volume.yml' ]]
[[ $(cat "$fixture/gitlab-package/SOURCE_COMMIT") == "$(git -C "$source_dir" rev-parse HEAD)" ]]
echo 'ok: GitLab package is self-contained and records its source'
