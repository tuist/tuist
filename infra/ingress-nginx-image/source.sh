#!/usr/bin/env bash
# Fetches the fork tag pinned in fork.env into WORK_DIR/src, checks that it is
# still the pinned commit, holds everything the fork's build downloads to our
# pins, and adds our patches from patches/ after the fork's.
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
# one line matches. Keeps FILE's mode: the fork's build scripts must stay executable.
replace_line() {
  local file=$1 old=$2 new=$3
  awk -v old="$old" -v new="$new" '$0 == old { print new; n++; next } { print } END { exit (n != 1) }' \
    "$file" > "$file.tmp" || { echo "error: expected exactly one line in $file: $old" >&2; exit 1; }
  cat "$file.tmp" > "$file"
  rm "$file.tmp"
}

nginx_rootfs="$src/images/nginx/rootfs"

# Hold the sources the fork fetches by tag or branch to the pins in fork.env
# (see there). The checks run right after each clone, against the commit
# actually fetched; git submodules then follow that commit's gitlinks.
# shellcheck disable=SC2016,SC1003 # single-quoted strings are literal lines of the fork's files
{
  nginx_build="$nginx_rootfs/build.sh"
  modsecurity_checkout='git checkout $MODSECURITY_LIB_VERSION'
  replace_line "$nginx_build" "$modsecurity_checkout" \
    "$modsecurity_checkout\\ntest \"\$(git rev-parse HEAD)\" = $MODSECURITY_COMMIT || { echo \"error: ModSecurity \$MODSECURITY_LIB_VERSION is not MODSECURITY_COMMIT=$MODSECURITY_COMMIT from fork.env\" >&2; exit 1; }"
  crs_clone='git clone -b $OWASP_MODSECURITY_CRS_VERSION https://github.com/coreruleset/coreruleset'
  replace_line "$nginx_build" "$crs_clone" \
    "$crs_clone\\ntest \"\$(git -C coreruleset rev-parse HEAD)\" = $CRS_COMMIT || { echo \"error: OWASP CRS \$OWASP_MODSECURITY_CRS_VERSION is not CRS_COMMIT=$CRS_COMMIT from fork.env\" >&2; exit 1; }"
  # The fork builds ssdeep from the tip of its default branch.
  replace_line "$nginx_build" 'git clone --depth=1 https://github.com/ssdeep-project/ssdeep' \
    "git clone -n https://github.com/ssdeep-project/ssdeep && git -C ssdeep checkout -q $SSDEEP_COMMIT"
  replace_line "$src/images/kube-webhook-certgen/rootfs/Dockerfile" \
    'FROM --platform=$BUILDPLATFORM gcr.io/distroless/static:nonroot' \
    "FROM --platform=\$BUILDPLATFORM $DISTROLESS_IMAGE"
  # The fork adds the openSUSE Leap repository over plain HTTP and auto-imports
  # whatever signing key it presents; fetch it over HTTPS instead.
  replace_line "$nginx_rootfs/Dockerfile" \
    'RUN zypper addrepo -p 105 http://download.opensuse.org/distribution/leap/16.0/repo/oss/ download.opensuse.org-oss && \' \
    'RUN zypper addrepo -p 105 https://download.opensuse.org/distribution/leap/16.0/repo/oss/ download.opensuse.org-oss && \'
}

# The fork's download.sh lists stale sha256 sums and has their check commented
# out. Put ours from sources.sha256 in their place, keyed by each get_src URL
# as written, and turn the check back on. Every get_src must have an entry and
# every entry must be used, so a new or renamed download fails here.
download="$nginx_rootfs/download.sh"
awk '
  FNR == NR { if ($0 !~ /^#/ && NF == 2) sums[$2] = $1; next }
  /^get_src / {
    url = $3; gsub(/"/, "", url)
    if (!(url in sums)) { print "error: no sources.sha256 entry for get_src " url > "/dev/stderr"; bad = 1 }
    $2 = sums[url]; used[url] = 1
  }
  { print }
  END {
    for (u in sums) if (!(u in used)) { print "error: sources.sha256 entry not used by download.sh: " u > "/dev/stderr"; bad = 1 }
    exit bad
  }' "$here/sources.sha256" "$download" > "$download.tmp" || exit 1
cat "$download.tmp" > "$download"
rm "$download.tmp"
# shellcheck disable=SC2016 # literal line of the fork's download.sh
replace_line "$download" '  # echo "$1  $filename" | sha256sum -c - || exit 10' \
  '  echo "$1  $filename" | sha256sum -c - || exit 10'

# images/nginx/rootfs/build.sh applies every file in patches/ in glob order
# with `patch -p1`, so ours go in with a prefix that sorts after the fork's NN_
# names.
patch_dir="$nginx_rootfs/patches"
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

echo "Patch stack: $(grep -c . "$work/patches.txt") patches, ${#ours[@]} of them ours"
