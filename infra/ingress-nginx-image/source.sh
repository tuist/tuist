#!/usr/bin/env bash
# Fetches the fork tag pinned in fork.env into WORK_DIR/src, checks that it is
# still the pinned commit, and adds our patches from patches/ after the fork's
# and our tests from tests/ to the fork's nginx tests.
# Writes the resulting patch stack, in application order, to WORK_DIR/patches.txt.
#
#   source.sh WORK_DIR

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=fork.env
source "$here/fork.env"

work=${1:?usage: source.sh WORK_DIR}
mkdir -p "$work"
src="$(cd "$work" && pwd)/src"

# The fork's source is untrusted input: fetch exactly the pinned tag and refuse
# to build if it no longer points at the pinned commit.
rm -rf "$src"
git init -q "$src"
git -C "$src" fetch -q --depth 1 "$FORK_REPOSITORY" "refs/tags/$FORK_TAG:refs/tags/$FORK_TAG"
actual=$(git -C "$src" rev-parse "refs/tags/$FORK_TAG^{commit}")
if [[ "$actual" != "$FORK_COMMIT" ]]; then
  echo "error: $FORK_TAG resolves to $actual, but fork.env pins $FORK_COMMIT" >&2
  exit 1
fi
git -C "$src" -c advice.detachedHead=false checkout -q "$FORK_COMMIT"

# images/nginx/rootfs/build.sh (and tests/build-nginx.sh) apply every file in
# patches/ in `ls` order with `patch -p1`, so ours go in with a prefix that
# sorts after the fork's NN_ names.
patch_dir="$src/images/nginx/rootfs/patches"
shopt -s nullglob
ours=("$here"/patches/*.patch)
shopt -u nullglob
for p in "${ours[@]}"; do
  cp "$p" "$patch_dir/zz-tuist-$(basename "$p")"
done
(cd "$patch_dir" && LC_ALL=C ls) > "$work/patches.txt"
if (( ${#ours[@]} > 0 )) && tail -n "${#ours[@]}" "$work/patches.txt" | grep -qv '^zz-tuist-'; then
  echo "error: our patches do not sort after the fork's:" >&2
  cat "$work/patches.txt" >&2
  exit 1
fi
# Our Test::Nginx regression tests join the fork's tests/t, which its nginx
# test suite (make -C images/nginx test) runs after the upstream suite.
shopt -s nullglob
for t in "$here"/tests/*.t; do
  cp "$t" "$src/images/nginx/tests/t/tuist-$(basename "$t")"
done
shopt -u nullglob

echo "Patch stack: $(grep -c . "$work/patches.txt") patches, ${#ours[@]} of them ours"
