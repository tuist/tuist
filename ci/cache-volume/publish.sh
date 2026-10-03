#!/usr/bin/env bash
set -euo pipefail

package=$(cd "${1:?usage: publish.sh PACKAGE REPOSITORY VERSION SOURCE_COMMIT}" && pwd)
repository=$(cd "${2:?distribution checkout required}" && pwd)
version=${3:?version required}
source_commit=${4:?source commit required}

fail() { echo "$*" >&2; exit 1; }
[[ "$version" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail 'Expected a stable vMAJOR.MINOR.PATCH'
[[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || fail 'Expected a full source commit'
[[ $(cat "$package/SOURCE_COMMIT") == "$source_commit" ]] || fail 'Package does not match the source commit'
[[ -z $(git -C "$repository" status --porcelain) ]] || fail 'Distribution checkout must be clean'
[[ ! -e "$package/.git" && ! -L "$package/.git" ]] || fail 'Unexpected package entry'
[[ -z $(find "$package" -type l -print) ]] || fail 'Unexpected package symlink'

cd "$repository"
existing=false
if git show-ref --verify --quiet "refs/tags/$version"; then
  existing=true
else
  latest=$(git tag -l | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1 || true)
  if [[ -n "$latest" && $(printf '%s\n%s\n' "$latest" "$version" | sort -V | tail -n1) != "$version" ]]; then
    fail 'Refusing to publish behind a newer release'
  fi
fi

# Distributions are generated: remove obsolete tracked entry points as well.
git rm -r --ignore-unmatch .
cp -R "$package/." .
# Artifact downloads do not preserve executable bits.
for executable in attach.sh hooks/pre-command; do
  if [[ -f "$executable" ]]; then chmod +x "$executable"; fi
done
git add --all
tree=$(git write-tree)
if [[ "$existing" == true ]]; then
  [[ "$tree" == "$(git rev-parse "$version^{tree}")" ]] || fail "Immutable release $version contains different content"
  git reset --hard HEAD
  echo "$version already published with identical content"
  exit 0
fi

git config user.name github-actions
git config user.email github-actions@github.com
git commit --allow-empty -m "Release $version"
git tag "$version"
major=${version%%.*}
git tag --force "$major"
git push --atomic origin HEAD:main "refs/tags/$version" "+refs/tags/$major"
echo "Published $version and $major"
