#!/usr/bin/env bash
# Round-trips a custom cache volume between two jobs. `seed` writes this run's
# id and a checksummed payload into the volume, which the host publishes once
# the job ends. `verify` runs in a later job and requires that it attached that
# saved copy. A volume that is unavailable falls back to a job-local directory
# and the job still succeeds, so both modes first require a real APFS mount.
#
# Usage: volume.sh seed|verify <path>. Env: CACHE_HIT (the action's output),
# PUBLISH_WAIT_SECONDS (verify only, for the failure message).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

mode="$1"
target="$2"
run="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}"

[ -L "${target}" ] || fail "Cache volumes" "${target} is not the action's symlink to a mounted volume, so the job fell back to a job-local directory"
device="$(df -P "${target}/" | awk 'NR == 2 { print $1 }')"
case "${device}" in
  /dev/disk*) ;;
  *) fail "Cache volumes" "${target} is on ${device}, not a disk image, so the job fell back to a job-local directory" ;;
esac
filesystem="$(diskutil info -plist "${device}" | plutil -extract FilesystemType raw -)"
[ "${filesystem}" = apfs ] || fail "Cache volumes" "${target} is ${filesystem}, not APFS"

case "${mode}" in
  seed)
    previous="$(cat "${target}/run" 2>/dev/null || echo none)"
    printf '%s' "${run}" > "${target}/run"
    head -c 1048576 /dev/urandom > "${target}/payload"
    (cd "${target}" && shasum -a 256 payload > payload.sha256)
    sync
    pass "Seeded the volume on ${device} with run ${run} (cache-hit=${CACHE_HIT:-unknown}, previous copy from run ${previous})"
    ;;
  verify)
    [ "${CACHE_HIT:-}" = true ] || fail "Cache volumes" "the verify job attached no saved copy (cache-hit=${CACHE_HIT:-unset})"
    saved="$(cat "${target}/run" 2>/dev/null || echo none)"
    # Overlapping probe runs share the volume, so a run that seeded after this
    # one may have published over it. Run ids and attempts only grow, so any
    # copy at or after this run's proves publication works; only an older one
    # is stale.
    if [ "${saved}" = "${run}" ]; then
      origin="this run's seed job"
    elif [[ "${saved}" =~ ^([0-9]+)-([0-9]+)$ ]] && [[ "${run}" =~ ^([0-9]+)-([0-9]+)$ ]] &&
      { [ "${saved%-*}" -gt "${run%-*}" ] || { [ "${saved%-*}" -eq "${run%-*}" ] && [ "${saved##*-}" -gt "${run##*-}" ]; }; }; then
      origin="run ${saved}, which seeded after this one"
    else
      fail "Cache volumes" "the verify job attached the copy saved by run ${saved}, which predates this run's seed job (${run}): the seed job's changes were discarded or not published within ${PUBLISH_WAIT_SECONDS:-?}s"
    fi
    (cd "${target}" && shasum -a 256 -c -s payload.sha256) || fail "Cache volumes" "the saved payload does not match the checksum the seed job wrote"
    pass "Attached the copy saved by ${origin}, payload intact"
    ;;
  *)
    echo "usage: volume.sh seed|verify <path>" >&2
    exit 2
    ;;
esac
