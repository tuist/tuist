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
for path in .github/actions/cache-volume ci/cache-volume/buildkite ci/cache-volume/gitlab; do
  mkdir -p "$(dirname "$path")"
  cp -R "$source_root/$path" "$path"
done
cp "$source_root/LICENSE.md" .
git add .
git commit -qm 'feat: initial integrations'
original=$(git rev-parse HEAD)
for provider in github buildkite gitlab; do
  git init -q --bare "$fixture/$provider.git"
  git clone -q "$fixture/$provider.git" "$fixture/distributions/$provider"
  git -C "$fixture/distributions/$provider" config user.name test
  git -C "$fixture/distributions/$provider" config user.email test@example.com
  git -C "$fixture/distributions/$provider" checkout -qb main
  git -C "$fixture/distributions/$provider" commit --allow-empty -qm bootstrap
  git -C "$fixture/distributions/$provider" push -q origin main
done
prepare() {
  : > "$fixture/output"
  GITHUB_OUTPUT="$fixture/output" bash "$source_root/ci/cache-volume/prepare-release.sh" "$1" "$fixture/distributions" "$fixture/$2"
}
prepare v1.0.0 initial
bash "$source_root/ci/cache-volume/publish.sh" "$fixture/initial/cache-volume-action" "$fixture/distributions/github" v1.0.0 "$original" >/dev/null
cat > "$fixture/buildkite.git/hooks/pre-receive" <<'HOOK'
#!/usr/bin/env bash
exit 1
HOOK
chmod +x "$fixture/buildkite.git/hooks/pre-receive"
if bash "$source_root/ci/cache-volume/publish.sh" "$fixture/initial/cache-volume-buildkite" "$fixture/distributions/buildkite" v1.0.0 "$original" >/dev/null 2>&1; then
  echo 'Expected a rejected Buildkite push' >&2; exit 1
fi
rm "$fixture/buildkite.git/hooks/pre-receive"
printf '\nLater source\n' >> .github/actions/cache-volume/README.md
git add .
git commit -qm 'feat: later wrapper changes'
# Fresh checkouts model a new dispatch, with no original run artifacts.
for provider in github buildkite gitlab; do
  rm -rf "$fixture/distributions/$provider"
  git clone -q --branch main "$fixture/$provider.git" "$fixture/distributions/$provider"
  git -C "$fixture/distributions/$provider" config user.name test
  git -C "$fixture/distributions/$provider" config user.email test@example.com
done
rm -rf "$fixture/initial"
prepare v1.1.0 recovery
grep -qx "source-commit=$original" "$fixture/output"
grep -qx 'version=v1.0.0' "$fixture/output"
grep -qx 'tag=cache-volume@1.0.0' "$fixture/output"
for entry in github:action buildkite:buildkite gitlab:gitlab; do
  provider=${entry%:*}; package=${entry#*:}
  bash "$source_root/ci/cache-volume/publish.sh" "$fixture/recovery/cache-volume-$package" "$fixture/distributions/$provider" v1.0.0 "$original" >/dev/null
  [[ $(git -C "$fixture/distributions/$provider" show v1.0.0:SOURCE_COMMIT) == "$original" ]]
done
echo 'ok: partial publish recovers original packages after main advances without retained artifacts'
git tag cache-volume@1.0.0 "$original"
prepare v1.1.0 next
grep -qx "source-commit=$(git rev-parse HEAD)" "$fixture/output"
grep -qx 'version=v1.1.0' "$fixture/output"
echo 'ok: later changes release only after the incomplete version is recorded'
