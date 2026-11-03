#!/usr/bin/env bash
# Exercise actual release conditions and shell without credentials or publication.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
workflow=${WORKFLOW:-$root/.github/workflows/app-release.yml}
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
yq -o=json '.' "$workflow" > "$scratch/workflow.json"
count=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { count=$((count + 1)); echo "ok $count: $*"; }

condition() {
  local job=$1 event=$2 changed=${3:-} result=${4:-success} cancelled=${5:-false}
  local expression name value
  expression=$(jq -er --arg job "$job" '.jobs[$job].if' "$scratch/workflow.json") || fail 'Missing job condition'
  # Evaluate the actual expression with fixed fixture values, not a copy of its gates.
  expression=${expression//always()/true == true}
  expression=${expression//cancelled()/ ( "$cancelled" == true ) }
  expression=${expression//github.event_name/"$event"}
  for name in check-releases release-app release-ios release-android; do
    value=success
    if [[ $name == "$changed" ]]; then value=$result; fi
    if [[ $event == workflow_dispatch && ( $name == release-ios || $name == release-android ) ]]; then value=skipped; fi
    expression=${expression//needs.$name.result/"$value"}
    expression=${expression//needs.$name.outputs.app-should-release/"true"}
  done
  eval "[[ $expression ]]"
}
expect_condition() {
  local expected=$1 actual=false
  shift
  if condition "$@"; then actual=true; fi
  [[ $actual == "$expected" ]] || fail "Expected condition $expected: $*"
}

expect_condition false release-ios workflow_dispatch
expect_condition false release-android workflow_dispatch
expect_condition true publish-app workflow_dispatch
for name in check-releases release-app; do
  for result in failure cancelled skipped; do expect_condition false publish-app workflow_dispatch "$name" "$result"; done
done
expect_condition false publish-app workflow_dispatch '' success true
ok 'manual hotfix skips stores and requires successful planner/macOS without cancellation'

expect_condition true release-ios push
expect_condition true release-android push
expect_condition true publish-app push
for name in release-app release-ios release-android; do
  for result in failure cancelled skipped; do expect_condition false publish-app push "$name" "$result"; done
done
ok 'ordinary push retains all three platform success gates'

# shellcheck disable=SC2016 # Assert literal GitHub expressions, never interpolate them.
jq -e '
  . as $root |
  all(["release-app", "publish-app"][]; . as $job |
    any($root.jobs[$job].steps[]; .uses == "actions/checkout@v4" and .with.ref == "${{ needs.check-releases.outputs.source-sha }}")) and
  any(.jobs["publish-app"].steps[]; .name == "Create App GitHub Release" and
    .with.target_commitish == "${{ needs.check-releases.outputs.source-sha }}" and
    .with.token == "${{ secrets.TUIST_RELEASE_GITHUB_TOKEN || github.token }}")
' "$scratch/workflow.json" >/dev/null || fail 'Lost immutable build/tag source or explicit release-token fallback'
jq -er '.jobs["check-releases"].if' "$scratch/workflow.json" |
  grep -Fq "github.ref == 'refs/heads/main'" || fail 'Lost main-only planning guard'
ok 'build/tag source stays immutable with explicit release-token fallback and main-only planning'

jq -e '.concurrency.group == "app-release-refs/heads/main" and .concurrency["cancel-in-progress"] == false' \
  "$scratch/workflow.json" >/dev/null || fail 'Lost the legacy main concurrency lock or disabled serialization'
ok 'old and new app workflows share the legacy main lock without cancellation'

repo="$scratch/source-guard"
mkdir "$repo"
g() { git -C "$repo" "$@" 2>/dev/null; }
g init --quiet
g config user.name Fixture
g config user.email fixture@example.invalid
g commit --quiet --allow-empty -m Stable
base=$(g rev-parse HEAD)
g commit --quiet --allow-empty -m 'TLS backport'
source=$(g rev-parse HEAD)
g init --quiet --bare "$repo/remote.git"
g remote add origin "$repo/remote.git"
branch=releases/app-0.27.1
g push origin "$base:refs/heads/$branch"
jq -e '.jobs["publish-app"].steps | map(.name) | index("Revalidate merged hotfix source and tag") as $i |
  .[$i + 1] == "Create App GitHub Release"' "$scratch/workflow.json" >/dev/null
jq -er '.jobs["publish-app"].steps[] | select(.name == "Revalidate merged hotfix source and tag") | .run' \
  "$scratch/workflow.json" > "$scratch/source-guard.sh"
guard() {
  (cd "$repo" && SOURCE_SHA=$source RELEASE_BRANCH=$branch RELEASE_TAG=app@0.27.2 RUNNER_TEMP=$scratch \
    bash -e "$scratch/source-guard.sh")
}
reject_guard() {
  if guard > "$scratch/output" 2>&1; then fail 'Pre-publication shell accepted an unmerged/replaced/deleted tip'; fi
}
reject_guard
g push origin "$source:refs/heads/$branch"
guard > "$scratch/output" 2>&1
# A different writer moves/deletes the remote; do not refresh local tracking refs.
git --git-dir="$repo/remote.git" update-ref "refs/heads/$branch" "$base"
reject_guard
g push origin "$source:refs/heads/$branch"
guard > "$scratch/output" 2>&1
git --git-dir="$repo/remote.git" update-ref -d "refs/heads/$branch"
reject_guard
ok 'actual pre-publication shell refetches the merged tip immediately before publishing'

repo="$scratch/appcast"
mkdir -p "$repo/app/build/artifacts"
printf '%s\n' '"CFBundleVersion": "1793260800",' > "$repo/app/Project.swift"
printf fixture > "$repo/app/build/artifacts/Tuist.dmg"
jq -er '.jobs["release-app"].steps[] | select(.name == "Validate Sparkle appcast") | .run' \
  "$scratch/workflow.json" > "$scratch/appcast-gate.sh"
item() {
  local version=$1 build=$2 url=${3:-} length=${4:-7} signature=${5-fixture-signature}
  url=${url:-https://github.com/tuist/tuist/releases/download/app@$version/Tuist.dmg}
  printf '<item><sparkle:shortVersionString>%s</sparkle:shortVersionString><sparkle:version>%s</sparkle:version><enclosure url="%s" length="%s" sparkle:edSignature="%s"/></item>' \
    "$version" "$build" "$url" "$length" "$signature"
}
candidate=$(item 0.27.2 1793260800)
older=$(item 0.27.1 1791997442)
appcast_gate() {
  local items=$1 prefix=${2:-sparkle}
  items=${items//sparkle:/$prefix:}
  printf '<?xml version="1.0"?>\n<rss xmlns:%s="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>%s</channel></rss>\n' \
    "$prefix" "$items" > "$repo/app/appcast.xml"
  (cd "$repo" && RELEASE_TAG=app@0.27.2 bash -e "$scratch/appcast-gate.sh")
}
reject_appcast() {
  if appcast_gate "$1" > "$scratch/output" 2>&1; then fail "Appcast shell accepted invalid metadata: $1"; fi
}
appcast_gate "$candidate$older"
appcast_gate "$candidate" updates
for contents in "$older" "$candidate$candidate" "$(item 0.27.2 1793260799)" \
  "$(item 0.27.2 1793260800 https://example.invalid/wrong.dmg)" \
  "$(item 0.27.2 1793260800 '' 8)" "$(item 0.27.2 1793260800 '' 7 '')" \
  "$candidate$(item 0.28.0 1793260801)" "$candidate$(item 0.28.0 1791997443)"; do
  reject_appcast "$contents"
done
ok 'actual appcast shell rejects stale, duplicate, mismatched, unsigned and downgrading metadata'

echo "$count workflow controls passed"
