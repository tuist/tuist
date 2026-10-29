#!/usr/bin/env bash
#
# Plans a macOS runner image release. Every profile in profiles.json gets two
# images: a stacked one (`:macos-<xcode>-<semver>-stacked`, the runner layer as
# an overlay on its base), which every runner pool runs, and a standalone one
# (`:macos-<xcode>-<semver>`), which only hosts older than macOS 27 can boot.
#
# A profile's stacked image is rebuilt when the image's sources changed in a
# releasable commit, when its macos-tahoe-xcode base digest moved, or when the
# previous release published none for it. Its standalone image is rebuilt only
# when BUILD_STANDALONE is true or the previous release published none for it.
# Every other image keeps its previous release's image under the new version.
#
# Env:
#   SHOULD_RELEASE       `release:check runner-image` verdict for HEAD
#   NEXT_VERSION_NUMBER  `release:check runner-image` next version
#   BUILD_STANDALONE     `true` to rebuild every standalone image
#
# Requires git with tags, jq, gh, and oras logged in to ghcr.io.
set -euo pipefail

profiles_file="infra/runner-image/profiles.json"
base_versions_file="infra/runner-image/base-xcode-versions.json"
base_repository="ghcr.io/tuist/macos-tahoe-xcode"
runner_repository="ghcr.io/tuist/tuist-runner"

latest_tag="$(git tag -l | grep -E '^runner-image@[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1 || true)"
previous="${latest_tag#runner-image@}"

previous_manifest='[]'
sources_changed=true
if [ -n "$latest_tag" ]; then
  previous_manifest="$(gh release download "$latest_tag" --pattern build-manifest.json --output - 2>/dev/null || echo '[]')"
  changed_sources="$(git diff --name-only "$latest_tag" HEAD -- infra/runner-image infra/linux-runner-image/cmd/tuist-cache-volume .github/actions/build-runner-image-binaries \
    infra/certificate-trust/policy.json infra/certificate-trust/pem-store.sh infra/certificate-trust/macos-guest-trust.sh infra/certificate-trust/controls/ \
    ':(exclude)infra/runner-image/profiles.json' \
    ':(exclude)infra/runner-image/base-xcode-versions.json' \
    ':(exclude)infra/runner-image/cliff.toml' \
    ':(glob,exclude)infra/runner-image/**/*.md')"
  if [ "$SHOULD_RELEASE" != "true" ] || [ -z "$changed_sources" ]; then
    sources_changed=false
  fi
fi

manifest='[]'
while IFS= read -r xcode; do
  profile="macos-${xcode//./-}"
  base_xcode="$(jq -r --arg xcode "$xcode" '.[$xcode] // $xcode' "$base_versions_file")"
  digest="$(oras resolve "${base_repository}:${base_xcode//./-}")"
  previous_entry="$(jq -c --arg xcode "$xcode" 'map(select(.xcode == $xcode))[0] // {}' <<< "$previous_manifest")"
  previous_digest="$(jq -r '.base_digest // ""' <<< "$previous_entry")"
  previous_stacked="$(jq -r '.stacked // false' <<< "$previous_entry")"
  if [ "$sources_changed" = "true" ] || [ "$previous_digest" != "$digest" ] || [ "$previous_stacked" != "true" ]; then
    stacked_action=build
  else
    stacked_action=carry
  fi
  if [ "${BUILD_STANDALONE:-false}" = "true" ] || [ -z "$previous" ] ||
    ! oras resolve "${runner_repository}:${profile}-${previous}" >/dev/null 2>&1; then
    action=build
    standalone_digest="$digest"
  else
    action=carry
    standalone_digest="$(jq -r --arg digest "$previous_digest" '.standalone_base_digest // $digest' <<< "$previous_entry")"
  fi
  manifest="$(jq -c --arg xcode "$xcode" --arg digest "$digest" --arg standalone_digest "$standalone_digest" \
    --arg action "$action" --arg stacked_action "$stacked_action" \
    '. + [{xcode: $xcode, base_digest: $digest, standalone_base_digest: $standalone_digest, action: $action, stacked_action: $stacked_action}]' <<< "$manifest")"
done < <(jq -r '.[]' "$profiles_file")

build_count="$(jq '[.[] | select(.action == "build")] | length' <<< "$manifest")"
stacked_build_count="$(jq '[.[] | select(.stacked_action == "build")] | length' <<< "$manifest")"

release=true
if [ "$SHOULD_RELEASE" = "true" ]; then
  version="$NEXT_VERSION_NUMBER"
elif [ "$build_count" -gt 0 ] || [ "$stacked_build_count" -gt 0 ]; then
  IFS=. read -r major minor patch <<< "$previous"
  version="${major}.${minor}.$((patch + 1))"
else
  release=false
  version="$previous"
fi

matrix="$(jq -c --arg repository "$base_repository" \
  '{include: [.[] | select(.action == "build") | {xcode, base: "\($repository)@\(.base_digest)"}]}' <<< "$manifest")"
carry="$(jq -c '[.[] | select(.action == "carry") | .xcode]' <<< "$manifest")"
stacked_matrix="$(jq -c --arg repository "$base_repository" \
  '{include: [.[] | select(.stacked_action == "build") | {xcode, base: "\($repository)@\(.base_digest)"}]}' <<< "$manifest")"
stacked_carry="$(jq -c '[.[] | select(.stacked_action == "carry") | .xcode]' <<< "$manifest")"
# The bases of the stacked builds, which the stacked builder keeps cached
# between them, in the order the builds run.
stacked_bases="$(jq -r '.include[].base' <<< "$stacked_matrix")"
build_manifest="$(jq -c '[.[] | {xcode, base_digest, standalone_base_digest, stacked: true}]' <<< "$manifest")"

summary="$(
  echo "Runner image release: ${release} (${previous:-none} -> ${version})"
  jq -r '.[] | "- \(.xcode): stacked \(.stacked_action) (\(.base_digest)), standalone \(.action) (\(.standalone_base_digest))"' <<< "$manifest"
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
    echo "stacked-build-count=${stacked_build_count}"
    echo "stacked-matrix=${stacked_matrix}"
    echo "stacked-carry=${stacked_carry}"
    echo "stacked-bases<<EOF"
    echo "$stacked_bases"
    echo "EOF"
    echo "manifest=${build_manifest}"
  } >> "$GITHUB_OUTPUT"
fi
