#!/usr/bin/env bash
set -euo pipefail

source_root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
command -v git-cliff >/dev/null
command -v jq >/dev/null

mkdir "$fixture/source"
cd "$fixture/source"
git init -q --initial-branch=main
git config user.name test
git config user.email test@example.com
mkdir -p .github/actions mise/tasks/release ci/cache-volume
cp -R "$source_root/.github/actions/install" .github/actions/
cp "$source_root/mise/tasks/release/"{check.sh,components.json} mise/tasks/release/
cp "$source_root/ci/cache-volume/publish.sh" ci/cache-volume/
cp "$source_root/LICENSE.md" .
git add .
git commit -qm 'feat(cli): add install action'
original=$(git rev-parse HEAD)

check() {
  : > .git/outputs
  GITHUB_OUTPUT="$PWD/.git/outputs" bash mise/tasks/release/check.sh install-action > "$fixture/check.log" 2>&1
  if ! grep -qx "install-action-$1=$2" .git/outputs; then
    cat "$fixture/check.log" .git/outputs >&2
    return 1
  fi
}
change() {
  mkdir -p "$(dirname "$2")"
  printf '\n%s\n' "$1" >> "$2"
  git add .
  git commit -qm "$1"
}
check next-version install-action@1.0.0
check should-release true
git tag install-action@1.0.0
check should-release false
change 'feat(server): unrelated change' server/unrelated.txt
check should-release false
index=0
for path in .github/actions/install/README.md .github/workflows/install-action.yml ci/cache-volume/publish.sh mise/tasks/release/check.sh; do
  index=$((index + 1))
  change '# fix(cli): release input' "$path"
  # Use a conventional commit while keeping executable fixture files valid.
  git commit --amend -qm 'fix(cli): release input'
  check next-version "install-action@1.0.$index"
  git tag "install-action@1.0.$index"
done
change 'feat(cli): new capability' .github/actions/install/README.md
check next-version install-action@1.1.0
git tag install-action@1.1.0
change 'feat(cli)!: change contract' .github/actions/install/README.md
check next-version install-action@2.0.0
echo 'ok: initial version, no-op/unrelated changes, release paths, and semantic version bumps'

# Start fresh to model a distribution push succeeding before the monorepo tag is recorded.
git checkout -q -b recovery "$original"
git tag -l 'install-action@*' | xargs git tag -d >/dev/null
git init -q --bare "$fixture/distribution.git"
git clone -q "$fixture/distribution.git" "$fixture/distribution"
git -C "$fixture/distribution" config user.name test
git -C "$fixture/distribution" config user.email test@example.com
git -C "$fixture/distribution" checkout -qb main
git -C "$fixture/distribution" commit --allow-empty -qm bootstrap
git -C "$fixture/distribution" push -q origin main
prepare() {
  : > "$fixture/output"
  GITHUB_OUTPUT="$fixture/output" bash "$source_root/.github/actions/install/scripts/prepare-release.sh" "$1" "$fixture/distribution" "$fixture/$2"
}
publish() {
  bash "$source_root/ci/cache-volume/publish.sh" "$fixture/$1" "$fixture/distribution" "$2" "$3" > "$fixture/publish.log" 2>&1
}
prepare v1.0.0 initial
publish initial v1.0.0 "$original"
change 'feat(cli): later changes' .github/actions/install/README.md
new_source=$(git rev-parse HEAD)
rm -rf "$fixture/initial" "$fixture/distribution"
git clone -q --branch main "$fixture/distribution.git" "$fixture/distribution"
prepare v1.1.0 recovered
grep -qx 'version=v1.0.0' "$fixture/output"
grep -qx 'tag=install-action@1.0.0' "$fixture/output"
grep -qx "source-commit=$original" "$fixture/output"
publish recovered v1.0.0 "$original"
[[ $(git -C "$fixture/distribution" show v1.0.0:SOURCE_COMMIT) == "$original" ]]
grep -q 'already published with identical content' "$fixture/publish.log"
echo 'ok: recovery repackages original source after main advances, without saved artifacts'

git tag install-action@1.0.0 "$original"
check next-version install-action@1.1.0
prepare v1.1.0 next
grep -qx "source-commit=$new_source" "$fixture/output"
publish next v1.1.0 "$new_source"
[[ $(git -C "$fixture/distribution" rev-parse v1) == "$(git -C "$fixture/distribution" rev-parse v1.1.0)" ]]
echo 'ok: new changes publish after recovery and advance the major alias'

git checkout -q --detach "$original"
if prepare v1.1.0 stale > "$fixture/stale.log" 2>&1; then
  echo 'Expected a stale source to fail recovery' >&2; exit 1
fi
grep -q 'not an ancestor' "$fixture/stale.log"
echo 'ok: stale release runs cannot recover newer source'
