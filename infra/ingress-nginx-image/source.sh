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

# Replaces the one line of FILE equal to OLD with NEW, failing unless exactly
# one line matches. Keeps FILE's mode: the fork's build.sh must stay executable.
replace_line() {
  local file=$1 old=$2 new=$3
  awk -v old="$old" -v new="$new" '$0 == old { print new; n++; next } { print } END { exit (n != 1) }' \
    "$file" > "$file.tmp" || { echo "error: expected exactly one line in $file: $old" >&2; exit 1; }
  cat "$file.tmp" > "$file"
  rm "$file.tmp"
}

# Hold the sources the fork fetches by tag to the pins in fork.env (see there).
# The checks run right after each clone, against the commit actually fetched;
# git submodules then follow that commit's gitlinks.
# shellcheck disable=SC2016 # single-quoted strings are literal lines of the fork's files
{
  nginx_build="$src/images/nginx/rootfs/build.sh"
  modsecurity_checkout='git checkout $MODSECURITY_LIB_VERSION'
  replace_line "$nginx_build" "$modsecurity_checkout" \
    "$modsecurity_checkout\\ntest \"\$(git rev-parse HEAD)\" = $MODSECURITY_COMMIT || { echo \"error: ModSecurity \$MODSECURITY_LIB_VERSION is not MODSECURITY_COMMIT=$MODSECURITY_COMMIT from fork.env\" >&2; exit 1; }"
  crs_clone='git clone -b $OWASP_MODSECURITY_CRS_VERSION https://github.com/coreruleset/coreruleset'
  replace_line "$nginx_build" "$crs_clone" \
    "$crs_clone\\ntest \"\$(git -C coreruleset rev-parse HEAD)\" = $CRS_COMMIT || { echo \"error: OWASP CRS \$OWASP_MODSECURITY_CRS_VERSION is not CRS_COMMIT=$CRS_COMMIT from fork.env\" >&2; exit 1; }"
  replace_line "$src/images/kube-webhook-certgen/rootfs/Dockerfile" \
    'FROM --platform=$BUILDPLATFORM gcr.io/distroless/static:nonroot' \
    "FROM --platform=\$BUILDPLATFORM $DISTROLESS_IMAGE"
}

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
