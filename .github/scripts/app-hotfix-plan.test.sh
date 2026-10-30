#!/usr/bin/env bash
# Credential-free planner contracts against real disposable Git history.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
planner=${PLANNER:-$script_dir/app-hotfix-plan.sh}
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
count=0
branch=releases/app-0.27.1

fail() { echo "FAIL: $*" >&2; exit 1; }
g() { git -C "$repo" "$@" 2>/dev/null; }
feed() {
  local version=${1:-0.27.1} build=${2:-1791997442} url=${3:-}
  url=${url:-https://github.com/tuist/tuist/releases/download/app@$version/Tuist.dmg}
  cat > "$repo/appcast.xml" <<EOF
<?xml version="1.0"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
<item><sparkle:shortVersionString>$version</sparkle:shortVersionString>
<sparkle:version>$build</sparkle:version><enclosure url="$url"/></item>
<item><sparkle:shortVersionString>0.20.2</sparkle:shortVersionString>
<sparkle:version>0.20.2</sparkle:version></item></channel></rss>
EOF
}
setup() {
  repo="$scratch/case-$count"
  mkdir "$repo"
  g init --quiet
  g config user.name Fixture
  g config user.email fixture@example.invalid
  g commit --quiet --allow-empty -m Stable
  base=$(g rev-parse HEAD)
  g tag app@0.27.1
  g commit --quiet --allow-empty -m 'TLS backport'
  source=$(g rev-parse HEAD)
  g init --quiet --bare "$repo/remote.git"
  g remote add origin "$repo/remote.git"
  g push origin "$source:refs/heads/$branch"
  feed
}
plan() {
  (cd "$repo" && bash "$planner" -- "${1:-app@0.27.1}" "${2:-$source}" "$repo/appcast.xml")
}
reject() {
  if plan "$@" > "$scratch/output" 2> "$scratch/error"; then fail "Accepted invalid plan: $*"; fi
  if grep -qx 'app-should-release=true' "$scratch/output"; then fail 'Rejected plan emitted release outputs'; fi
}
ok() { count=$((count + 1)); echo "ok $count: $*"; }

setup
plan > "$scratch/output"
for expected in 'app-should-release=true' 'app-next-version=app@0.27.2' \
  'app-next-version-number=0.27.2' "source-sha=$source" "release-branch=$branch"; do
  grep -qx "$expected" "$scratch/output" || fail "Missing $expected"
done
build=$(sed -n 's/^build-number=//p' "$scratch/output")
[[ $build -gt 1791997442 ]] || fail 'Build did not advance'
ok 'plans a patch, not a main minor, at the immutable merged tip'

setup
# shellcheck disable=SC2016 # Deliberately pass a literal GitHub expression.
for sha in main "${source:0:12}" --help '${{ secrets.TOKEN }}' "$source"$'\nfoo=bar'; do reject app@0.27.1 "$sha"; done
for tag in main 'app@0.27.1^' app@00.27.1 $'app@0.27.1\nfoo=bar'; do reject "$tag"; done
ok 'rejects mutable, option, expression and multiline inputs'

setup
g push --force origin "$base:refs/heads/$branch"
reject app@0.27.1 "$base"
g switch --orphan unrelated
g commit --quiet --allow-empty -m 'Other product'
unrelated=$(g rev-parse HEAD)
g push --force origin "$unrelated:refs/heads/$branch"
reject app@0.27.1 "$unrelated"
ok 'rejects unchanged and unrelated sources'

setup
g push --force origin "$base:refs/heads/$branch"
reject
g push origin "$source:refs/heads/$branch"
plan > /dev/null
g commit --quiet --allow-empty -m 'Unrelated main features'
reject app@0.27.1 "$(g rev-parse HEAD)"
ok 'rejects unmerged hotfixes and main descendants'

setup
plan > /dev/null
# Mutate the remote independently so the checkout retains its old fetched tip.
git --git-dir="$repo/remote.git" update-ref "refs/heads/$branch" "$base"
reject
g push origin "$source:refs/heads/$branch"
plan > /dev/null
git --git-dir="$repo/remote.git" update-ref -d "refs/heads/$branch"
reject
ok 'refetches replaced or deleted remote tips'

setup
g tag app@0.27.2 "$source"
reject
ok 'rejects existing patch tags instead of replacing contents'

setup
feed 0.28.0
reject
feed 0.26.9
reject
ok 'rejects a stale baseline even when old items remain'

setup
feed 0.27.1 "$(( $(date +%s) + 600 ))"
reject
feed 0.27.1 not-a-build
reject
ok 'rejects future or nonnumeric live builds'

setup
for contents in '<rss><channel/></rss>' 'not XML' '<rss><channel><item/></channel></rss>'; do
  printf '%s\n' "$contents" > "$repo/appcast.xml"
  reject
done
feed
printf '<second/>' >> "$repo/appcast.xml"
reject
feed 0.27.1 1791997442 https://example.invalid/main/Tuist.dmg
reject
ok 'rejects empty, malformed and wrong-payload feeds'

echo "$count planner controls passed"
