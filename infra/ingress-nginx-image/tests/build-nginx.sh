#!/bin/bash
# Builds the nginx binary that the nginx-tests suite runs against.
# Adapted from chainguard-forks/ingress-nginx images/nginx/tests/build-nginx.sh
# (commit 29e7c87140a9d88ffd3cf26ff07852bb81dc0a4a, Apache-2.0) for the Rancher
# fork's layout, where the versions live in version.sh and the downloads in
# download.sh.
#
# The nginx version comes from rootfs/version.sh, its sha256 from the get_src
# line in rootfs/download.sh (pinned by source.sh from sources.sha256), and the
# patch loop and core configure flags from rootfs/build.sh, so the test binary
# follows the base image: same source tarball, same patch stack (ours
# included), same core modules. It differs on purpose:
#
#   - the third-party modules (Lua, ModSecurity, njs, ...) are left out; the
#     tests exercise nginx itself,
#   - it is built with AddressSanitizer and NGX_DEBUG_PALLOC (every pool
#     allocation becomes its own malloc, so overruns inside pools are seen),
#     and Test::Nginx fails a test file on any sanitizer report in its log.

set -o errexit
set -o nounset
set -o pipefail

ROOTFS=${ROOTFS:-/src/rootfs}
PREFIX=${PREFIX:-/opt/nginx}
BUILD_SH="${ROOTFS}/build.sh"

NGINX_VERSION=$(sed -n 's/^export NGINX_VERSION=//p' "${ROOTFS}/version.sh")
NGINX_SHA256=$(awk '/^get_src .*nginx\.org\/download\/nginx-/ { print $2; exit }' "${ROOTFS}/download.sh")
WITH_FLAGS=
eval "$(sed -n '/^WITH_FLAGS="/,/"$/p' "${BUILD_SH}")"
WITHOUT_FLAGS=$(grep -oE -- '--without-[a-z0-9_]+' "${BUILD_SH}" | tr '\n' ' ')

if [[ -z "${NGINX_VERSION}" || -z "${NGINX_SHA256}" || -z "${WITH_FLAGS}" || -z "${WITHOUT_FLAGS}" ]]; then
  echo "could not read the nginx version, sha256 or configure flags from ${ROOTFS}" >&2
  exit 3
fi

# same architecture rule as build.sh
if [[ "$(uname -m)" != "aarch64" ]]; then
  WITH_FLAGS+=" --with-file-aio"
fi

BUILD_DIR=$(mktemp -d)
cd "${BUILD_DIR}"
curl -fsSL -o nginx.tar.gz "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"
echo "${NGINX_SHA256}  nginx.tar.gz" | sha256sum -c -
tar -xzf nginx.tar.gz
cd "nginx-${NGINX_VERSION}"

# same order and -p rule as the patch loop in build.sh
applied=0
for PATCH in "${ROOTFS}"/patches/*; do
  echo "Patch: ${PATCH##*/}"
  if [[ "${PATCH}" == *.txt ]]; then
    patch -p0 < "${PATCH}"
  else
    patch -p1 < "${PATCH}"
  fi
  applied=$((applied + 1))
done

# shellcheck disable=SC2086 # the flag lists are meant to split
./configure \
  --prefix="${PREFIX}" \
  ${WITH_FLAGS} \
  ${WITHOUT_FLAGS} \
  --with-cc-opt="-g -O1 -fno-omit-frame-pointer -fsanitize=address -DNGX_DEBUG_PALLOC=1 -Wno-error" \
  --with-ld-opt="-fsanitize=address"
make -j"$(nproc)"
make install

printf 'version=%s\npatches=%s\n' "${NGINX_VERSION}" "${applied}" > "${PREFIX}/build-info"
cat "${PREFIX}/build-info"
"${PREFIX}/sbin/nginx" -V

cd /
rm -rf "${BUILD_DIR}"
