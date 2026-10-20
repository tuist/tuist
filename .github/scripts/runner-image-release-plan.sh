#!/usr/bin/env bash
#
# Plans a macOS runner image release. A profile in profiles.json is rebuilt
# when the image's sources changed in a releasable commit, when the previous
# release did not carry it, or when its Xcode base (macos-<codename>-xcode, see
# macos-image-names.sh) digest moved. Every other profile keeps its previous
# image under the new version. A rebuilt profile carries the builder labels its
# guest macOS needs.
#
# Env:
#   SHOULD_RELEASE       `release:check runner-image` verdict for HEAD
#   NEXT_VERSION_NUMBER  `release:check runner-image` next version
#
# Requires git with tags, jq, gh, and oras logged in to ghcr.io.
set -euo pipefail

profiles_file="infra/runner-image/profiles.json"
names=".github/scripts/macos-image-names.sh"

latest_tag="$(git tag -l | grep -E '^runner-image@[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1 || true)"
previous="${latest_tag#runner-image@}"

previous_manifest='[]'
sources_changed=true
if [ -n "$latest_tag" ]; then
  previous_manifest="$(gh release download "$latest_tag" --pattern build-manifest.json --output - 2>/dev/null || echo '[]')"
  changed_sources="$(git diff --name-only "$latest_tag" HEAD -- infra/runner-image infra/linux-runner-image/cmd/tuist-cache-volume .github/actions/build-runner-image-binaries \
    ':(exclude)infra/runner-image/profiles.json' \
    ':(exclude)infra/runner-image/cliff.toml' \
    ':(glob,exclude)infra/runner-image/**/*.md')"
  if [ "$SHOULD_RELEASE" != "true" ] || [ -z "$changed_sources" ]; then
    sources_changed=false
  fi
fi

manifest='[]'
while IFS= read -r xcode; do
  profile_names="$("$names" profile "$xcode")"
  xcode_repository="$(sed -n 's/^xcode_repository=//p' <<< "$profile_names")"
  xcode_tag="$(sed -n 's/^xcode_tag=//p' <<< "$profile_names")"
  runs_on="$(sed -n 's/^runs_on=//p' <<< "$profile_names")"
  digest="$(oras resolve "${xcode_repository}:${xcode_tag}")"
  previous_digest="$(jq -r --arg xcode "$xcode" 'map(select(.xcode == $xcode))[0].base_digest // ""' <<< "$previous_manifest")"
  if [ "$sources_changed" = "true" ] || [ "$previous_digest" != "$digest" ]; then
    action=build
  else
    action=carry
  fi
  manifest="$(jq -c --arg xcode "$xcode" --arg digest "$digest" --arg action "$action" \
    --arg repository "$xcode_repository" --argjson runs_on "$runs_on" \
    '. + [{xcode: $xcode, base_digest: $digest, action: $action, repository: $repository, runs_on: $runs_on}]' <<< "$manifest")"
done < <(jq -r '.[]' "$profiles_file")

build_count="$(jq '[.[] | select(.action == "build")] | length' <<< "$manifest")"

release=true
if [ "$SHOULD_RELEASE" = "true" ]; then
  version="$NEXT_VERSION_NUMBER"
elif [ "$build_count" -gt 0 ]; then
  IFS=. read -r major minor patch <<< "$previous"
  version="${major}.${minor}.$((patch + 1))"
else
  release=false
  version="$previous"
fi

matrix="$(jq -c \
  '{include: [.[] | select(.action == "build") | {xcode, base: "\(.repository)@\(.base_digest)", runs_on}]}' <<< "$manifest")"
carry="$(jq -c '[.[] | select(.action == "carry") | .xcode]' <<< "$manifest")"
build_manifest="$(jq -c '[.[] | {xcode, base_digest}]' <<< "$manifest")"

summary="$(
  echo "Runner image release: ${release} (${previous:-none} -> ${version})"
  jq -r '.[] | "- \(.xcode): \(.action) (\(.base_digest))"' <<< "$manifest"
)"
echo "$summary"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "$summary" >> "$GITHUB_STEP_SUMMARY"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "release=${release}"
    echo "version=${version}"
    echo "previous=${previous}"
    echo "build-count=${build_count}"
    echo "matrix=${matrix}"
    echo "carry=${carry}"
    echo "manifest=${build_manifest}"
  } >> "$GITHUB_OUTPUT"
fi
