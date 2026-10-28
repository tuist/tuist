#!/usr/bin/env bash
# Test which runner images a release rebuilds and which it carries over.

set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/runner-image-release-plan.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

old="sha256:$(printf 'a%.0s' {1..64})"
new="sha256:$(printf 'b%.0s' {1..64})"

mkdir -p "$scratch/bin" "$scratch/repo/infra/runner-image"
echo '["26.6", "27.1"]' > "$scratch/repo/infra/runner-image/profiles.json"

# `git tag -l` lists $scratch/tags, `git diff` prints $scratch/changed.
cat > "$scratch/bin/git" <<BASH
#!/usr/bin/env bash
case "\$1" in
  tag) cat "$scratch/tags" ;;
  diff) cat "$scratch/changed" ;;
  *) exit 1 ;;
esac
BASH
cat > "$scratch/bin/gh" <<BASH
#!/usr/bin/env bash
cat "$scratch/previous-manifest.json"
BASH
# Bases resolve to the digest in $scratch/base-<tag>, and a runner image tag
# resolves only when it is listed in $scratch/published.
cat > "$scratch/bin/oras" <<BASH
#!/usr/bin/env bash
ref="\$2"
case "\$ref" in
  ghcr.io/tuist/macos-tahoe-xcode:*) cat "$scratch/base-\${ref##*:}" ;;
  ghcr.io/tuist/tuist-runner:*) grep -qx "\${ref##*:}" "$scratch/published" && echo "$old" ;;
  *) exit 1 ;;
esac
BASH
chmod +x "$scratch/bin/"*

# $1 and $2 the 26.6 and 27.1 base digests the previous release built on, the
# rest the runner image tags it published. Its 26.6 entry predates
# `standalone_base_digest`.
previous_release() {
  echo "runner-image@0.50.0" > "$scratch/tags"
  jq -cn --arg a "$1" --arg b "$2" '[
    {xcode: "26.6", base_digest: $a, stacked: true},
    {xcode: "27.1", base_digest: $b, standalone_base_digest: $b, stacked: true}
  ]' > "$scratch/previous-manifest.json"
  printf '%s\n' "${@:3}" > "$scratch/published"
}

# $1 SHOULD_RELEASE, $2 BUILD_STANDALONE.
plan() {
  rm -f "$scratch/output"
  (cd "$scratch/repo" && PATH="$scratch/bin:$PATH" GITHUB_OUTPUT="$scratch/output" \
    SHOULD_RELEASE="$1" NEXT_VERSION_NUMBER=0.51.0 BUILD_STANDALONE="$2" bash "$SCRIPT" >/dev/null)
}

output() {
  sed -n "s/^$1=//p" "$scratch/output"
}

# $1 output, $2 expected value, $3 description.
expect() {
  local actual
  actual="$(output "$1")"
  if [ "$actual" != "$2" ]; then
    echo "Expected $1=$2 for $3, got $actual." >&2
    exit 1
  fi
}

both_published=(macos-26-6-0.50.0 macos-27-1-0.50.0)
echo "$new" > "$scratch/base-26-6"
echo "$old" > "$scratch/base-27-1"

previous_release "$old" "$old" "${both_published[@]}"
echo infra/runner-image/dispatch-poll.sh > "$scratch/changed"
plan true false
expect release true "a source change"
expect version 0.51.0 "a source change"
expect stacked-build-count 2 "a source change"
expect stacked-carry '[]' "a source change"
expect build-count 0 "a source change without standalone images"
expect carry '["26.6","27.1"]' "a source change without standalone images"
expect manifest "[{\"xcode\":\"26.6\",\"base_digest\":\"$new\",\"standalone_base_digest\":\"$old\",\"stacked\":true},{\"xcode\":\"27.1\",\"base_digest\":\"$old\",\"standalone_base_digest\":\"$old\",\"stacked\":true}]" \
  "standalone images carried over a moved base"
if [ "$(sed -n '/^stacked-bases<<EOF$/,/^EOF$/p' "$scratch/output" | sed '1d;$d')" != "$(printf 'ghcr.io/tuist/macos-tahoe-xcode@%s\nghcr.io/tuist/macos-tahoe-xcode@%s' "$new" "$old")" ]; then
  echo "Expected the stacked bases in build order." >&2
  exit 1
fi

plan true true
expect build-count 2 "a release that builds standalone images"
expect carry '[]' "a release that builds standalone images"

: > "$scratch/changed"
plan false false
expect release true "a moved base"
expect version 0.50.1 "a moved base"
expect stacked-matrix "{\"include\":[{\"xcode\":\"26.6\",\"base\":\"ghcr.io/tuist/macos-tahoe-xcode@$new\"}]}" "a moved base"
expect stacked-carry '["27.1"]' "a moved base"
expect build-count 0 "a moved base"

previous_release "$new" "$old" "${both_published[@]}"
plan false false
expect release false "nothing to rebuild"

previous_release "$new" "$old" macos-26-6-0.50.0
plan false false
expect release true "a profile without a standalone image to carry"
expect stacked-build-count 0 "a profile without a standalone image to carry"
expect matrix "{\"include\":[{\"xcode\":\"27.1\",\"base\":\"ghcr.io/tuist/macos-tahoe-xcode@$old\"}]}" "a profile without a standalone image to carry"
expect carry '["26.6"]' "a profile without a standalone image to carry"

echo "The runner image release plan rebuilds what it should."
