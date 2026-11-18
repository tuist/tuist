#!/usr/bin/env bash
# Resolve an image-only recovery to an already published, immutable source.
set -euo pipefail

version="${RECOVERY_VERSION:?RECOVERY_VERSION is required}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Expected a stable version" >&2; exit 1; }
tag="condukt@$version"
latest="$(git tag --list 'condukt@*' --sort=-version:refname | sed -n '1p')"
[[ "$tag" == "$latest" ]] || { echo "Recovery must target the latest Condukt tag ($latest)" >&2; exit 1; }
source_sha="$(git rev-parse "refs/tags/$tag^{commit}")"

# A tag alone is not evidence that package publication completed.
gh release view "$tag" --repo "$GITHUB_REPOSITORY" --json isDraft --jq '.isDraft' | grep -qx false
curl --fail --silent --show-error --location "https://hex.pm/api/packages/condukt/releases/$version" \
  | jq -e --arg version "$version" '.version == $version and .has_docs == true and .retirement == null' >/dev/null

{
  echo "version=$version"
  echo "source-sha=$source_sha"
  echo "egress-only=true"
} >> "$GITHUB_OUTPUT"
