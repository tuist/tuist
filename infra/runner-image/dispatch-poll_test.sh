#!/bin/bash
# Exercises dispatch-poll.sh's attach of the cache image: the compilation-cache
# store is set up for the job only after the attach-time prune. The functions are
# extracted rather than the script sourced, since sourcing it starts the dispatch
# loop. macOS only: the inventory is read with BSD stat.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
fixtures="$(mktemp -d)"
trap 'chmod -R u+w "${fixtures}"; rm -rf "${fixtures}"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

{
  grep -E '^CAS_[A-Z_]+=' dispatch-poll.sh
  awk '/^[a-z_][a-z0-9_]*\(\) \{$/ { copying = 1 }
       copying { print }
       copying && /^\}$/ { copying = 0 }' dispatch-poll.sh
} > "${fixtures}/functions.sh"
bash -n "${fixtures}/functions.sh"

mkdir -p "${fixtures}/bin" "${fixtures}/status"
printf '#!/bin/bash\nexit 0\n' > "${fixtures}/bin/hdiutil"
chmod +x "${fixtures}/bin/hdiutil"
touch "${fixtures}/cache.img" "${fixtures}/status/cache-ready"
printf '4000' > "${fixtures}/status/cas-enabled"

# A master with no room left for the store until the prune frees some: nothing
# can be created in it, and the prune is what makes it writable again.
store_root="${fixtures}/volume/CompilationCache.noindex"
mkdir -p "${store_root}/builtin/v1.1"
chmod a-w "${store_root}"

env -i HOME="${fixtures}" PATH="${fixtures}/bin:/usr/bin:/bin:/usr/sbin:/sbin" FIXTURES="${fixtures}" \
  /bin/bash -c '
    set -uo pipefail
    source "${FIXTURES}/functions.sh"
    CACHE_SHARE_PRESENT=1
    CACHE_READY_TIMEOUT=1
    CACHE_IMAGE="${FIXTURES}/cache.img"
    CACHE_MOUNTPOINT="${FIXTURES}/volume"
    CACHE_MOUNT=""
    CACHE_IMAGE_ACTIVE=""
    CACHE_INVENTORY_BEFORE=""
    STATUS_SHARE="${FIXTURES}/status"
    CAS_XCCONFIG="${FIXTURES}/cas.xcconfig"
    prune_cas_stores() {
      chmod u+w "${CACHE_MOUNT}/${CAS_STORE_DIR}"
      echo "stores pruned ($1)"
    }
    wait_for_cache_ready
    echo "XCODE_XCCONFIG_FILE=${XCODE_XCCONFIG_FILE:-}"
  ' > "${fixtures}/output" 2>&1

grep -qF "stores pruned (attach)" "${fixtures}/output" || { cat "${fixtures}/output" >&2; fail "expected the attach-time prune to run"; }
if grep -qF "CAS store not writable" "${fixtures}/output"; then
  cat "${fixtures}/output" >&2
  fail "expected the store to be set up after the prune made room for it"
fi
grep -qF "XCODE_XCCONFIG_FILE=${fixtures}/cas.xcconfig" "${fixtures}/output" || { cat "${fixtures}/output" >&2; fail "expected the job to be pointed at the store"; }
echo "ok: the job's store is set up after the attach-time prune"
