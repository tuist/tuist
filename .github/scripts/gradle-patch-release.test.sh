#!/usr/bin/env bash
# Real-Git controls and actual workflow shell; no credentials or publication.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
planner=${PLANNER:-$root/.github/scripts/gradle-patch-release.sh}
workflow=${WORKFLOW:-$root/.github/workflows/gradle-release.yml}
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
repo="$scratch/repo"
remote="$scratch/remote.git"
mkdir -p "$repo/gradle"
count=0
rejections=0
fail() { cat "$scratch/log" >&2; echo "FAIL: $*" >&2; exit 1; }
ok() { count=$((count + 1)); echo "ok $count: $*"; }
g() { git -C "$repo" "$@" >"$scratch/log" 2>&1 || fail "git $*"; }
commit() {
  printf '%s\n' "$2" > "$repo/$1"
  g add .
  g commit -qm "$2"
}
plan() {
  : > "$scratch/output"
  (cd "$repo" && env GITHUB_EVENT_NAME=workflow_dispatch GITHUB_REF=refs/heads/main \
    SOURCE_SHA="$source" PATCH_VERSION=0.18.1 GITHUB_OUTPUT="$scratch/output" "$@" bash "$planner")
}
reject() {
  if plan "$@" >"$scratch/log" 2>&1; then fail "Accepted invalid plan: $*"; fi
  [[ ! -s "$scratch/output" ]] || fail 'Rejected plan enabled publication'
  rejections=$((rejections + 1))
}

g init --bare "$remote"
g init -b main
g config user.email fixture@example.invalid
g config user.name Fixture
g config commit.gpgsign false
g config core.hooksPath /dev/null
g remote add origin "$remote"
commit gradle/plugin stable
stable=$(git -C "$repo" rev-parse HEAD)
g tag gradle@0.18.0
g push -q origin main --tags
g switch -c releases/gradle-0.18.x
source=$stable
reject # Missing remote release branch.
g push -q origin HEAD
reject # Unchanged baseline.
commit gradle/plugin 'fix(gradle): TLS'
source=$(git -C "$repo" rev-parse HEAD)
reject # Unmerged source is not the release branch head.
g push -q origin HEAD
plan >"$scratch/log" 2>&1 || fail 'Rejected merged stable-source patch'
printf 'gradle-should-release=true\ngradle-next-version=gradle@0.18.1\ngradle-next-version-number=0.18.1\nsource-sha=%s\n' \
  "$source" > "$scratch/expected"
cmp "$scratch/expected" "$scratch/output" || fail 'Incorrect accepted outputs'
ok 'merged Gradle-only patch emits exact plan; missing branch, unchanged and unmerged source fail'

# shellcheck disable=SC2016 # Injection is literal untrusted input, never executed.
for version in '' 0.18.0 0.18.2 0.19.0 1.0.0 gradle@0.18.1 \
  0.18.1-rc.1 0.18.1+build 00.18.1 $'0.18.1\nextra' '$(echo injected)'; do
  reject "PATCH_VERSION=$version"
done
for sha in '' "${source:0:12}" main "$stable" ffffffffffffffffffffffffffffffffffffffff "$source"$'\nextra'; do
  reject "SOURCE_SHA=$sha"
done
reject GITHUB_EVENT_NAME=push
reject GITHUB_REF=refs/heads/releases/gradle-0.18.x
reject GITHUB_REF=refs/heads/feature
ok 'malformed, missing, stale and injected versions/SHAs and wrong events/refs fail without outputs'

# Extract the actual workflow shell, substituting only fixture version outputs.
yq -er '.jobs.release.steps[] | select(.name == "Revalidate stable patch and pin source") | .run' \
  "$workflow" > "$scratch/pin.sh"
yq -er '.jobs.release.steps[] | select(.run != null) | select(.run | contains("publishPlugins")) | .run' \
  "$workflow" > "$scratch/publish.sh"
command=$(cat "$scratch/publish.sh")
# shellcheck disable=SC2016 # Literal GitHub expressions, not shell expansions.
command=${command//'${{ needs.check.outputs.next-version }}'/gradle@0.18.1}
# shellcheck disable=SC2016
command=${command//'${{ needs.check.outputs.next-version-number }}'/0.18.1}
publish_directory=$(yq -er '.jobs.release.steps[] | select(.run != null) | select(.run | contains("publishPlugins")) | .working-directory' "$workflow")

# Simulate trusted-main controls disappearing from the selected stable checkout.
g switch main
mkdir -p "$repo/.github/scripts"
cp "$planner" "$repo/.github/scripts/gradle-patch-release.sh"
g add .
g commit -qm 'trusted main controls'
(cd "$repo" && GITHUB_EVENT_NAME=workflow_dispatch GITHUB_REF=refs/heads/main \
  SOURCE_SHA="$source" PATCH_VERSION=0.18.1 GITHUB_OUTPUT="$scratch/output" \
  RUNNER_TEMP="$scratch" bash -e -o pipefail "$scratch/pin.sh") >"$scratch/log" 2>&1 || fail 'Source pin shell failed'
cmp "$planner" "$scratch/gradle-patch-release.sh" || fail 'Lost trusted main guard'
[[ ! -e "$repo/.github/scripts/gradle-patch-release.sh" ]] || fail 'Guard unexpectedly came from stable source'
[[ $(git -C "$repo" rev-parse HEAD) == "$source" ]] || fail 'Wrong pinned source'
ok 'actual source-pin shell retains trusted main guard outside the selected checkout'

valid_source=$source
g switch releases/gradle-0.18.x
commit gradle/plugin 'fix(gradle): corrected TLS source'
g push -q origin HEAD
g checkout --detach "$valid_source"
publish() {
  (cd "$repo/$publish_directory" && GITHUB_EVENT_NAME=workflow_dispatch GITHUB_REF=refs/heads/main \
    SOURCE_SHA="$valid_source" PATCH_VERSION=0.18.1 GITHUB_WORKSPACE="$repo" RUNNER_TEMP="$scratch" \
    GITHUB_OUTPUT="$scratch/publication-output" CREDENTIAL_ACCESS="$scratch/credential-access" \
    BASH_ENV=/dev/null OP_SERVICE_ACCOUNT_TOKEN='' bash -e -o pipefail -c \
    'op() { touch "$CREDENTIAL_ACCESS"; return 1; }
'"$command")
}
if publish >"$scratch/log" 2>&1; then fail 'Publisher accepted changed release branch'; fi
[[ ! -e "$scratch/credential-access" ]] || fail 'Changed source reached credentials'
grep -q 'source_sha must be the current head' "$scratch/log" || fail 'Wrong branch-change rejection'
[[ $(git -C "$repo" rev-parse HEAD) == "$valid_source" ]] || fail 'Silently substituted source'
ok 'actual publisher rejects branch changes after planning, before credentials, without replacing tested source'

g switch releases/gradle-0.18.x
g reset --hard "$valid_source"
g push -q --force origin HEAD
if publish >"$scratch/log" 2>&1; then fail 'Credential stub did not stop publication'; fi
[[ -e "$scratch/credential-access" ]] || fail 'Unchanged-tip positive control never reached credential stub'
rm "$scratch/credential-access"
ok 'unchanged-tip positive control reaches credential stub and stops before publication'

source=$valid_source
commit unrelated 'unrelated source'
source=$(git -C "$repo" rev-parse HEAD)
g push -q origin HEAD
reject
g reset --hard "$valid_source"
g push -q --force origin HEAD
g checkout --orphan unrelated-history
g rm -rf .
mkdir -p "$repo/gradle"
commit gradle/plugin 'not based on stable'
source=$(git -C "$repo" rev-parse HEAD)
g push -q --force origin HEAD:releases/gradle-0.18.x
reject
g push -q --force origin "$valid_source:releases/gradle-0.18.x"
source=$valid_source
ok 'unrelated files and Gradle-only unrelated history fail'

git --git-dir="$remote" tag gradle@0.18.1 "$source"
reject
reject PATCH_VERSION=0.18.2
if publish >"$scratch/log" 2>&1; then fail 'Publisher accepted existing remote tag'; fi
[[ ! -e "$scratch/credential-access" ]] || fail 'Existing tag reached credentials'
grep -q 'Tag gradle@0.18.1 already exists on origin' "$scratch/log" || fail 'Wrong tag-collision rejection'
ok 'new stable tag invalidates plan; empty next patch and actual publisher tag collisions fail'

echo "$count controls passed; $rejections invalid plans rejected without release outputs"
