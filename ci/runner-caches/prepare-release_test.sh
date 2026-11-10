#!/usr/bin/env bash
set -euo pipefail
source_root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir "$fixture/source" "$fixture/distributions"
cd "$fixture/source"
git init -q --initial-branch=main
git config user.name test
git config user.email test@example.com
for path in .github/actions/xcode-cache .github/actions/module-cache .github/actions/gradle-cache ci/runner-caches; do
  mkdir -p "$(dirname "$path")"
  cp -R "$source_root/$path" "$path"
done
cp "$source_root/LICENSE.md" .
git add .
git commit -qm 'feat: initial runner caches'
original=$(git rev-parse HEAD)
repositories=$(cut -f1 ci/runner-caches/distributions)
[[ $(wc -l <<< "$repositories") -eq 9 ]]

checkout() {
  rm -rf "$fixture/distributions/$1"
  git clone -q --branch main "$fixture/$1.git" "$fixture/distributions/$1"
  git -C "$fixture/distributions/$1" config user.name test
  git -C "$fixture/distributions/$1" config user.email test@example.com
}
for repository in $repositories; do
  git init -q --bare "$fixture/$repository.git"
  git clone -q "$fixture/$repository.git" "$fixture/bootstrap" 2>/dev/null
  git -C "$fixture/bootstrap" -c user.name=test -c user.email=test@example.com commit --allow-empty -qm bootstrap
  git -C "$fixture/bootstrap" push -q origin HEAD:main
  rm -rf "$fixture/bootstrap"
  checkout "$repository"
done
prepare() {
  : > "$fixture/output"
  GITHUB_OUTPUT="$fixture/output" bash "$source_root/ci/runner-caches/prepare-release.sh" "$1" "$fixture/distributions" "$fixture/$2"
}
publish() {
  bash "$source_root/ci/cache-volume/publish.sh" "$fixture/$1/$2" "$fixture/distributions/$2" "$3" "$4" >/dev/null 2>&1
}

prepare v1.0.0 initial
[[ $(ls "$fixture/initial" | LC_ALL=C sort) == $(LC_ALL=C sort <<< "$repositories") ]]
[[ -x "$fixture/initial/gradle-cache-buildkite-plugin/hooks/pre-command" ]]
[[ -f "$fixture/initial/xcode-cache-gitlab/xcode-cache.yml" ]]
[[ -f "$fixture/initial/module-cache/activate.sh" ]]
echo 'ok: every distribution is packaged from the source commit'

publish initial xcode-cache v1.0.0 "$original"
cat > "$fixture/module-cache.git/hooks/pre-receive" <<'HOOK'
#!/usr/bin/env bash
exit 1
HOOK
chmod +x "$fixture/module-cache.git/hooks/pre-receive"
if publish initial module-cache v1.0.0 "$original" 2>/dev/null; then
  echo 'Expected a rejected push' >&2; exit 1
fi
rm "$fixture/module-cache.git/hooks/pre-receive"

printf '\nLater source\n' >> .github/actions/xcode-cache/README.md
git add .
git commit -qm 'feat: later wrapper changes'
# Fresh checkouts model a new dispatch, with no original run artifacts.
for repository in $repositories; do checkout "$repository"; done
rm -rf "$fixture/initial"
prepare v1.1.0 recovery
grep -qx "source-commit=$original" "$fixture/output"
grep -qx 'version=v1.0.0' "$fixture/output"
grep -qx 'tag=runner-caches@1.0.0' "$fixture/output"
for repository in $repositories; do
  publish recovery "$repository" v1.0.0 "$original"
  [[ $(git -C "$fixture/distributions/$repository" show v1.0.0:SOURCE_COMMIT) == "$original" ]]
done
echo 'ok: a partial publish recovers the original packages after main advances'

git tag runner-caches@1.0.0 "$original"
prepare v1.1.0 next
grep -qx "source-commit=$(git rev-parse HEAD)" "$fixture/output"
grep -qx 'version=v1.1.0' "$fixture/output"
echo 'ok: later changes release only after the incomplete version is recorded'
