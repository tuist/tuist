#!/usr/bin/env bash
# Run from condukt/. Never replace assets or move an existing release tag.
set -euo pipefail
: "${RELEASE_VERSION:?}" "${RELEASE_TAG:?}" "${SOURCE_SHA:?}" "${GITHUB_REPOSITORY:?}" "${RUNNER_TEMP:?}"
[[ "$RELEASE_TAG" == "condukt@$RELEASE_VERSION" ]]
[[ "$(git rev-parse HEAD)" == "$SOURCE_SHA" ]]
nif_manifest=$(python3 ../.github/scripts/condukt-artifacts.py "$RELEASE_VERSION" nif-artifacts)
mapfile -t nif_files <<< "$nif_manifest"
package="condukt-$RELEASE_VERSION.tar"
test -s "$package"

# ls-remote failures must not be mistaken for an absent tag.
remote_tag=$(git ls-remote --tags origin "refs/tags/$RELEASE_TAG" "refs/tags/$RELEASE_TAG^{}")
if [[ -n "$remote_tag" ]]; then
  git fetch origin "refs/tags/$RELEASE_TAG"
  [[ "$(git rev-parse 'FETCH_HEAD^{commit}')" == "$SOURCE_SHA" ]] || {
    echo "Existing release tag belongs to another source; refusing to publish" >&2
    exit 1
  }
fi

# Inspect status explicitly so authorization/network failures cannot create a
# second release or be treated as a missing one.
response="$RUNNER_TEMP/condukt-release-response"
status=0
gh api --include "repos/$GITHUB_REPOSITORY/releases/tags/$RELEASE_TAG" > "$response" || status=$?
if [[ "$status" == 0 ]]; then
  # A draft without a source tag is not a recoverable published release.
  [[ -n "$remote_tag" ]]
  # A retry can proceed only with byte-identical existing assets. No --clobber.
  existing=$(mktemp -d "$RUNNER_TEMP/condukt-existing-XXXXXX")
  gh release download "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" --dir "$existing"
  for file in "${nif_files[@]}" "$package"; do
    cmp "$file" "$existing/$(basename "$file")"
  done
  rm -rf "$existing"
elif grep -q '^HTTP/[^ ]* 404' "$response"; then
  gh release create "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" \
    --target "$SOURCE_SHA" --title "Condukt $RELEASE_VERSION" --latest=false \
    --notes-file "$RUNNER_TEMP/condukt-release.md" "${nif_files[@]}" "$package"
else
  echo "Cannot determine existing release state; refusing to publish" >&2
  exit 1
fi

# Exercise the public consumer URLs and verify bytes, not just upload success.
for file in "${nif_files[@]}"; do
  url="https://github.com/$GITHUB_REPOSITORY/releases/download/$RELEASE_TAG/$(basename "$file")"
  curl --fail --silent --show-error --location "$url" --output "$RUNNER_TEMP/condukt-download"
  cmp "$file" "$RUNNER_TEMP/condukt-download"
done
