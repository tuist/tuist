#!/usr/bin/env bash
# Plan a macOS-only patch from the merged stable tip and live Sparkle feed.
set -euo pipefail

fail() {
  echo "Cannot plan macOS hotfix: $*" >&2
  exit 1
}

if [[ ${1:-} == -- ]]; then shift; fi
[[ $# == 3 ]] || fail 'Expected stable tag, full source SHA and live appcast path'
stable_tag=$1
source_sha=$2
appcast=$3
semver='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
[[ $stable_tag =~ ^app@${semver}$ && $source_sha =~ ^[0-9a-f]{40}$ ]] ||
  fail 'Use an exact app@X.Y.Z stable tag and a full lowercase source SHA'

base=$(git rev-parse --verify "refs/tags/$stable_tag^{commit}")
release_branch="releases/app-${stable_tag#app@}"
git fetch --no-tags origin "+refs/heads/$release_branch:refs/remotes/origin/$release_branch"
[[ $(git rev-parse --verify "refs/remotes/origin/$release_branch") == "$source_sha" ]] ||
  fail 'Source must be the current merged stable release branch tip'
[[ $(git rev-parse --verify "$source_sha^{commit}") == "$source_sha" ]] || fail 'Source must identify a commit'
git merge-base --is-ancestor "$base" "$source_sha"
[[ $source_sha != "$base" ]] || fail 'Source contains no hotfix'

IFS=. read -r major minor patch <<< "${stable_tag#app@}"
next_version="$major.$minor.$((10#$patch + 1))"
[[ -z $(git tag --list "app@$next_version") ]] ||
  fail 'Next patch tag already exists; recover the original release instead'

build_number=$(date +%s)
namespace='http://www.andymatuschak.org/xml-namespaces/sparkle:'
# Resolve namespace URIs, not a particular XML prefix; normalize one/many items.
items=$(yq -p=xml --xml-strict-mode --xml-raw-token=false \
  --xml-skip-proc-inst --xml-skip-directives -o=json '.' "$appcast" |
  jq -ce 'select(keys == ["rss"]) | [.rss.channel.item // empty] | flatten | select(length > 0)') || fail 'Live feed is empty or malformed'
jq -e --arg ns "$namespace" --arg version "${stable_tag#app@}" \
  --arg url "https://github.com/tuist/tuist/releases/download/$stable_tag/Tuist.dmg" \
  --argjson build "$build_number" '
  def version: if test("^[0-9]+(\\.[0-9]+){2}$") then split(".") | map(tonumber) else error("Invalid live version") end;
  (map(.[$ns + "shortVersionString"] | version) | max) as $newest_version |
  first(.[] | select((.[$ns + "shortVersionString"] | version) == $newest_version)) as $newest |
  $newest_version == ($version | version) and
  $newest.enclosure["+@url"] == $url and
  ($newest[$ns + "version"] | test("^[0-9]+$")) and
  all(.[] | .[$ns + "version"] // "";
    if test("^[0-9]+$") then tonumber < $build else true end)
' <<< "$items" >/dev/null || fail 'Stable tag, payload URL or monotonic build does not match the live feed'

printf '%s\n' \
  'app-should-release=true' \
  "app-next-version=app@$next_version" \
  "app-next-version-number=$next_version" \
  "source-sha=$source_sha" \
  "release-branch=$release_branch" \
  "build-number=$build_number"
