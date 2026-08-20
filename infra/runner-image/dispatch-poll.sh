#!/bin/bash
# POSTs to the Tuist server's runner dispatch endpoint with the
# Pod's projected ServiceAccount token as the Bearer credential
# and execs the GitHub Actions runner with the returned JIT config.
#
# Files (staged by tart-kubelet, read-mounted at
# `/Volumes/My Shared Files/env/`):
#   tuist.env  — env vars from the Pod spec (TUIST_RUNNER_DISPATCH_URL,
#                TUIST_RUNNER_POOL, TUIST_RUNNER_POD_NAME)
#   sa_token   — Pod's projected SA token, minted via TokenRequest
#
# Server contract:
#   POST <url> with header `Authorization: Bearer <sa_token>`
#     200 with body { encoded_jit_config: "...", pool: "...", owner: "...",
#                      cache_endpoint_url?: "...", cache_signing_grant?: "..." }
#       -> export TUIST_CACHE_ENDPOINT when cache_endpoint_url is present,
#          export TUIST_CACHE_SIGNING_GRANT when cache_signing_grant is present,
#          then exec ./run.sh --jitconfig <jit> --disableupdate
#     204  -> no work yet, keep polling
#     401  -> auth failed, abort (the SA was likely GCed already)
#     403  -> server-side authz refused the SA, abort
#     5xx  -> transient; sleep + retry
#
# Once the runner exits, the EXIT trap halts the VM. tart-kubelet
# observes the exit and transitions the Pod to Succeeded; the
# runners-controller's PodGC reaper deletes the assignment +
# cascades Pod + SA.

set -uo pipefail

LOG=/var/log/tuist-runner/poll.log
exec >>"${LOG}" 2>&1

# Host-shared status directory. A fixed mount path, so it is defined
# here rather than beside the cache-volume code that also uses it: the
# EXIT trap below reports through it, and the aborts worth reporting
# (missing /etc/tuist.env, missing or empty SA token) all run before
# that code is reached. Defined before the trap is armed for the same
# reason.
STATUS_SHARE="/Volumes/My Shared Files/status"

# publish_runner_log copies this script's log into the status share on
# the way out, so it survives the VM. `${LOG}` lives inside the ephemeral
# guest and dies with it, which is why a runner that halts without ever
# taking its job leaves an exit code and nothing that explains it: the
# EXIT trap reports 0 both for a finished job and for a runner that gave
# up, so the code alone cannot separate them. tart-kubelet re-emits a
# bounded tail of this file to its own stdout before teardown deletes the
# share, and that reaches Loki via the host log shipper.
#
# A copy from the trap rather than a `tee` alongside `${LOG}`. A tee is
# the obvious shape and the wrong one here: it would still be running
# when the trap fires, so its buffered tail can land after this copy and
# duplicate it, and bash 3.2 (what /bin/bash is on macOS) does not report
# a process substitution's PID in `$!`, so there is no portable way to
# reap it first. Copying after the last line is written is exact.
#
# The cost is that a guest killed without running its trap publishes
# nothing — but that case already reaches the host distinguishably, as
# `TartRunExited` rather than a reported exit code.
#
# Guarded on the share being mounted, exactly like report_runner_exit:
# pools with the cache-volume feature off have no share, and there the
# guest keeps logging only to `${LOG}`.
publish_runner_log() {
  [ -d "${STATUS_SHARE:-}" ] || return 0
  cp "${LOG}" "${STATUS_SHARE}/runner.log" 2>/dev/null || true
}

# report_runner_exit hands this script's exit code to the host through
# the writable status share, for tart-kubelet to publish as the Pod's
# terminated container state.
#
# It is the ONLY way that code leaves the guest. The EXIT trap below
# halts the VM on every path, clean or not, so `tart run` always exits
# zero and the host cannot otherwise tell a finished job from a runner
# that died on boot — every macOS runner death reads as Succeeded with
# no exit code, no reason, and no log. (Linux runners get this for free:
# the container runtime records the real terminated state.)
#
# Reported from inside the trap rather than after `wait` on the runner
# so it also covers the paths that never reach a runner at all: the auth
# aborts, the missing-file exits, an errexit anywhere above. Those are
# exactly the deaths that are hardest to explain after the fact.
#
# Guarded on the share being mounted, which it is not on hosts with the
# cache-volume feature off; an unreported exit degrades to a Pod with no
# exit code rather than failing the halt.
report_runner_exit() {
  [ -d "${STATUS_SHARE:-}" ] || return 0
  printf '%s' "${1}" >"${STATUS_SHARE}/runner-rc" 2>/dev/null || true
}

# Always halt the VM on script exit. tart-kubelet observes `tart run`
# exiting and transitions the Pod to a terminal phase; without this
# trap a non-zero `./run.sh` (errexit), an early `exit 1`
# (auth abort, missing files, etc.), or any other failure path would
# leave macOS up, the Pod stuck Running, and the warm pool never
# refilling. The trap fires once on EXIT so the happy path
# (clean ./run.sh exit) and every error path halt the VM the
# same way.
trap '_rc=$?; report_runner_exit "${_rc}"; echo "$(date -u +%FT%TZ) dispatch-poll: exiting (rc=${_rc}); halting VM"; publish_runner_log; sudo /sbin/shutdown -h now || true; exit "${_rc}"' EXIT

if [ ! -f /etc/tuist.env ]; then
  echo "$(date -u +%FT%TZ) dispatch-poll: /etc/tuist.env missing; aborting"
  exit 1
fi
# shellcheck disable=SC1091
source /etc/tuist.env

: "${TUIST_RUNNER_DISPATCH_URL:?TUIST_RUNNER_DISPATCH_URL not set}"

keep_desktop_interactive() {
  # ByHost screensaver preferences are tied to the cloned VM's
  # runtime host UUID, so the image-build defaults alone are not
  # enough. Re-apply them inside the booted runner session before a
  # job can be probed over VNC.
  sudo pmset -a sleep 0 displaysleep 0 disksleep 0 >/dev/null 2>&1 || true
  sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser -string runner >/dev/null 2>&1 || true
  sudo defaults write /Library/Preferences/.GlobalPreferences com.apple.autologout.AutoLogOutDelay -int 0 >/dev/null 2>&1 || true

  defaults write com.apple.screensaver idleTime -int 0 >/dev/null 2>&1 || true
  defaults write com.apple.screensaver askForPassword -bool false >/dev/null 2>&1 || true
  defaults write com.apple.screensaver askForPasswordDelay -int 0 >/dev/null 2>&1 || true
  defaults -currentHost write com.apple.screensaver idleTime -int 0 >/dev/null 2>&1 || true
  defaults -currentHost write com.apple.screensaver askForPassword -bool false >/dev/null 2>&1 || true
  defaults -currentHost write com.apple.screensaver askForPasswordDelay -int 0 >/dev/null 2>&1 || true
  /usr/bin/killall cfprefsd >/dev/null 2>&1 || true

  if [ -x /usr/bin/caffeinate ]; then
    /usr/bin/caffeinate -dims -w "$$" >/dev/null 2>&1 &
    echo "$(date -u +%FT%TZ) dispatch-poll: desktop sleep and screen lock disabled"
  fi
}

keep_desktop_interactive

# In-VM cluster DNS for the runner-cache path. When the
# runners-controller staged TUIST_CLUSTER_DNS_IP (macOS pools in
# environments whose Mac minis have the tailnet route into the
# cluster), point a macOS scoped resolver for the cluster domain at
# kube-dns so the dispatch-provided cache_endpoint_url
# (`*.svc.cluster.local`) resolves inside the VM. Scoped per-domain:
# only cluster-domain lookups go to kube-dns, everything else keeps
# the vmnet default path. getaddrinfo (curl, the Tuist CLI, JVM, Go's
# darwin cgo resolver) honors /etc/resolver entries via
# mDNSResponder. Best-effort: a failure here degrades to "cache URL
# doesn't resolve" which the build treats like any unreachable
# endpoint — never block the job claim on it.
if [ -n "${TUIST_CLUSTER_DNS_IP:-}" ]; then
  cluster_domain="${TUIST_CLUSTER_DOMAIN:-cluster.local}"
  sudo mkdir -p /etc/resolver 2>/dev/null || true
  if printf 'nameserver %s\n' "${TUIST_CLUSTER_DNS_IP}" | sudo tee "/etc/resolver/${cluster_domain}" >/dev/null 2>&1; then
    echo "$(date -u +%FT%TZ) dispatch-poll: cluster DNS resolver installed (/etc/resolver/${cluster_domain} -> ${TUIST_CLUSTER_DNS_IP})"
  else
    echo "$(date -u +%FT%TZ) dispatch-poll: WARNING could not install /etc/resolver/${cluster_domain}; in-cluster cache URLs will not resolve"
  fi
fi

SA_TOKEN_PATH=/etc/tuist-sa-token
if [ ! -f "${SA_TOKEN_PATH}" ]; then
  echo "$(date -u +%FT%TZ) dispatch-poll: ${SA_TOKEN_PATH} missing; aborting"
  exit 1
fi
SA_TOKEN="$(cat "${SA_TOKEN_PATH}")"
if [ -z "${SA_TOKEN}" ]; then
  echo "$(date -u +%FT%TZ) dispatch-poll: SA token empty; aborting"
  exit 1
fi

SHELL_CLAIM_MARKER="${TUIST_RUNNER_SHELL_CLAIM_MARKER:-/tmp/tuist-runner-shell-claimed}"
export TUIST_RUNNER_SHELL_CLAIM_MARKER="${SHELL_CLAIM_MARKER}"
rm -f "${SHELL_CLAIM_MARKER}" 2>/dev/null || true

shell_agent_lock_active() {
  local lock_dir=/tmp/tuist-runner-shell-agent.lock
  local pid_file="${lock_dir}/pid"
  local lock_pid=""

  if [ ! -d "${lock_dir}" ]; then
    return 1
  fi

  if [ -f "${pid_file}" ]; then
    read -r lock_pid <"${pid_file}" || lock_pid=""
  fi

  if [ -n "${lock_pid}" ] && kill -0 "${lock_pid}" 2>/dev/null; then
    return 0
  fi

  echo "$(date -u +%FT%TZ) dispatch-poll: removing stale runner-shell-agent lock"
  rm -rf "${lock_dir}"
  return 1
}

if shell_agent_lock_active; then
  echo "$(date -u +%FT%TZ) dispatch-poll: runner-shell-agent supervisor already active"
elif [ -x /opt/tuist/runner-shell-agent-supervisor.sh ]; then
  echo "$(date -u +%FT%TZ) dispatch-poll: starting runner-shell-agent supervisor"
  (
    trap - EXIT
    exec /bin/zsh -lc 'exec /opt/tuist/runner-shell-agent-supervisor.sh'
  ) &
  echo "$(date -u +%FT%TZ) dispatch-poll: runner-shell-agent supervisor pid=$!"
else
  echo "$(date -u +%FT%TZ) dispatch-poll: runner-shell-agent missing or not executable"
fi

# Per-account cache volume, materialized after dispatch. tart-kubelet attaches
# an EMPTY per-VM branch directory as a writable virtio-fs share at boot; after
# dispatch binds this VM to an account, the host clonefiles that account's cache
# master image into the branch and writes a cache-ready marker. The guest then
# attaches that image and points the Tuist cache root at the MOUNTPOINT. Absent
# share => feature off / admission declined => cold path, unchanged.
#
# The cache is a disk image rather than files on the share because virtio-fs
# cannot carry a macOS cache: it fails to set extended attributes on symlinks,
# and macOS frameworks are versioned bundles (Resources -> Versions/Current/
# Resources) whose xattrs the CLI's artifact signatures live in. Inside an image
# the filesystem is real APFS, so symlinks, xattrs, ownership and inode
# semantics are native, and exactly one regular file crosses virtio-fs.
CACHE_SHARE="/Volumes/My Shared Files/cache"
CACHE_IMAGE="${CACHE_SHARE}/cache.sparseimage"
CACHE_MOUNTPOINT="/Users/runner/.tuist-cache-volume"
# Set once the boot-time share probe succeeds; gates the post-dispatch attach.
CACHE_SHARE_PRESENT=""
# The mountpoint while the image is attached; cleared on detach, so it doubles
# as "the cache is readable right now".
CACHE_MOUNT=""
# Set from attach until the image is either abandoned (cold fallback) or found
# unsafe to promote; gates the HEAD publish, which outlives the mount.
CACHE_IMAGE_ACTIVE=""
CACHE_INVENTORY_BEFORE=""
# The post-job inventory, captured while the image is still mounted so the HEAD
# publish (which runs after detach, when nothing can be read) can still use it.
CACHE_INVENTORY_AFTER=""
# STATUS_SHARE is defined near the EXIT trap at the top of this script,
# which reports the runner's exit code through it before this section is
# ever reached.
# The Xcode compilation cache (CAS) is FOLDED into the cache image: a top-level
# store dir beside `tuist/` inside the one mounted image. It works because it
# lives on the attached block-device APFS image, not the virtio-fs share (llcas
# mmaps its store and mmap over virtio-fs SIGBUSes). No separate image or mount —
# the guest just points the compiler at <CACHE_MOUNT>/<CAS_STORE_DIR> when the
# host stages the cas-enabled marker. The xcconfig lives on the VM's own disk
# (xcodebuild only reads it).
CAS_STORE_DIR="CompilationCache.noindex"
CAS_XCCONFIG="/Users/runner/.tuist-cas.xcconfig"
CAS_ENABLED_MARKER="cas-enabled"
# Control-plane endpoints (dispatch URL's siblings/child). Neither receives the
# image bytes: the mint endpoint returns a presigned object-storage PUT URL, and
# the image is uploaded DIRECTLY to that URL (see report_volume_head). The
# presigned URL is no longer handed out at dispatch — the guest mints it at
# promote time keyed by its own new inventory digest, which keeps master object
# keys immutable.
VOLUME_HEAD_REPORT_URL="${TUIST_RUNNER_DISPATCH_URL%/dispatch}/volume-head"
VOLUME_HEAD_UPLOAD_URL_MINT_ENDPOINT="${VOLUME_HEAD_REPORT_URL}/upload-url"

# cache_inventory hashes the SORTED ENTRY NAMES (not mtimes) under the cache
# subtrees whose churn means the job actually changed the cache: binaries
# added/evicted, manifests or ProjectDescriptionHelpers compiled. Pure cache
# hits only bump mtimes (they don't add/remove entries), so they don't move
# this hash — matching the reconciler's rule that mtime-only deltas are not
# dirty and must not trigger a promote that could clobber a concurrent writer.
#
# It takes the mountpoint to measure rather than reading CACHE_MOUNT, because the
# two snapshots are read through DIFFERENT mounts: the pre-job one through the
# live read-write mount, and the published one through a read-only re-attach of
# the already-detached image (see capture_settled_inventory).
cache_inventory() {
  local mount="$1"
  [ -n "${mount}" ] || { echo "none"; return 0; }
  local root="${mount}/tuist"
  local cas="${mount}/${CAS_STORE_DIR}"
  # One `~cas/<relpath>\t<size>` line per regular file in the folded CAS store — a
  # content identity, not a size proxy. It catches growth (llcas appends to fixed
  # files, so a compile-only job that only grew the CAS still flips the digest and
  # promotes) AND stays collision-safe: this digest is also the immutable object
  # KEY a promote uploads under, so two branches with different contents must never
  # produce the same digest. MUST match the host's inventoryDigest/casInventoryLines
  # EXACTLY: regular files, dot-paths excluded (`-not -path '*/.*'` ⇔ the host's
  # SkipDir), relpath, a TAB, logical st_size (stat -f %z).
  # LC_ALL=C: byte-order sort, so this agrees with the host's inventoryDigest
  # (Go sort.Strings is byte-wise). The `~cas/` lines sort LAST (0x7E > the
  # alphanumeric subdir names), matching the host's casLinePrefix placement.
  {
    for d in Binaries Manifests ProjectDescriptionHelpers Plugins; do
      /bin/ls -1 "${root}/${d}" 2>/dev/null | sed "s|^|${d}/|"
    done
    ( cd "${cas}" 2>/dev/null && find . -type f -not -path '*/.*' -exec stat -f "%N$(printf '\t')%z" {} + 2>/dev/null ) \
      | sed 's|^\./|~cas/|'
  } | LC_ALL=C sort | shasum | awk '{print $1}'
}

# use_local_cold_cache points the CLI at a private, local cache dir and
# abandons the volume (no promote, no HEAD publish, no inventory diff). Used
# whenever the volume is unusable, so a broken cache can only ever cost the job
# its warm start — never fail it. Exporting TUIST_XDG_CACHE_HOME at a root the
# CLI can't write is worse than not setting it at all: the CLI aborts on its
# first cache write and the whole job dies.
use_local_cold_cache() {
  local reason="$1"
  local local_cache="/Users/runner/.tuist-cache-cold"
  mkdir -p "${local_cache}/tuist" 2>/dev/null || true
  export TUIST_XDG_CACHE_HOME="${local_cache}"
  unset TUIST_CACHE_MAX_BYTES
  CACHE_MOUNT=""
  CACHE_IMAGE_ACTIVE=""
  CACHE_INVENTORY_BEFORE=""
  echo "$(date -u +%FT%TZ) dispatch-poll: cache volume unusable (${reason}); running on a local cold cache"
}

# attach_cache_image mounts the host-materialized cache image and points the CLI
# at the MOUNTPOINT — the share itself only ever holds the image file.
#
# `-owners off` maps everything inside the image to the attaching user, so the
# host/guest uid split (this guest is `runner` uid 502; the host's console user
# is 501) never reaches the cache: the guest is the OWNER of every file. That
# retires the host-side tree-walking chmod (from #11884) entirely.
#
# Ownership is not the whole story, though: `-owners off` does NOT touch mode
# bits, so a cached artifact carried in at mode 0444 stays unwritable even by its
# owner, and the CLI re-signs artifacts in place (an xattr write needs W_OK). A
# warm master can hold such a file from a prior run, so relax owner-write across
# the mounted tree — `u+rwX` gives dirs traversal/create and files owner-write,
# and because the guest owns everything here it is uid-independent. Native APFS
# metadata, so it is cheap and reliably succeeds (unlike a cross-uid chmod over
# virtio-fs); best-effort, since a stray file the CLI never touches is harmless.
# `-noverify` skips a checksum pass over a multi-GB image we just cloned locally;
# `-nobrowse` keeps it out of the Finder namespace.
#
# Called only after cache-ready: the image does not exist until the host
# materializes the dispatched account's master into the branch.
attach_cache_image() {
  local err
  if [ ! -f "${CACHE_IMAGE}" ]; then
    cache_diag "no cache image at ${CACHE_IMAGE}"
    return 1
  fi
  mkdir -p "${CACHE_MOUNTPOINT}" 2>/dev/null || true
  if ! err=$(hdiutil attach "${CACHE_IMAGE}" -owners off -nobrowse -noverify -quiet \
    -mountpoint "${CACHE_MOUNTPOINT}" 2>&1); then
    cache_diag "hdiutil attach ${CACHE_IMAGE}: ${err}"
    return 1
  fi
  CACHE_MOUNT="${CACHE_MOUNTPOINT}"
  CACHE_IMAGE_ACTIVE=1
  # Make every inherited artifact owner-writable so the CLI can re-sign in place.
  # Empty (cold) images have no tuist/ yet, so guard on its presence.
  if [ -d "${CACHE_MOUNT}/tuist" ]; then
    chmod -R u+rwX "${CACHE_MOUNT}/tuist" 2>/dev/null || \
      echo "$(date -u +%FT%TZ) dispatch-poll: WARNING could not fully relax cache tree modes"
  fi
  export TUIST_XDG_CACHE_HOME="${CACHE_MOUNT}"
  # Byte budget for the CLI's per-generate LRU self-prune: the host stages the
  # per-branch cap (≈80% of a master's provisioned size) into the status share
  # so a full working set degrades to a hot tier (LRU keeps the most-used
  # artifacts local, the tail misses to the remote) instead of churning at
  # ENOSPC when the image hits its cap.
  local budget
  budget=$(cat "${STATUS_SHARE}/cache-max-bytes" 2>/dev/null)
  if [ -n "${budget}" ] && [ "${budget}" -gt 0 ] 2>/dev/null; then
    export TUIST_CACHE_MAX_BYTES="${budget}"
  fi
  echo "$(date -u +%FT%TZ) dispatch-poll: cache image mounted at ${CACHE_MOUNT}; TUIST_XDG_CACHE_HOME set (budget=${TUIST_CACHE_MAX_BYTES:-none})"
  # The CAS store is folded into this image; point the compiler at it (if enabled).
  setup_cas_store
  return 0
}

# CACHE_DETACH_ATTEMPTS bounds the polite detach before forcing. A straggler
# process (a lingering build daemon, a Spotlight scan) can hold a file open for
# a moment after the runner exits.
CACHE_DETACH_ATTEMPTS=5

# detach_cache_image unmounts the image so the host can promote it. This is
# load-bearing and must run BEFORE the host reads the file: promotion clones the
# image, and the host cannot distinguish a torn snapshot from a good one, so a
# mount torn down by the VM halting would poison the account's master and every
# job that later clones it.
detach_cache_image() {
  [ -n "${CACHE_MOUNT}" ] || return 0
  local waited=0
  while [ "${waited}" -lt "${CACHE_DETACH_ATTEMPTS}" ]; do
    if hdiutil detach "${CACHE_MOUNT}" -quiet 2>/dev/null; then
      CACHE_MOUNT=""
      echo "$(date -u +%FT%TZ) dispatch-poll: cache image detached"
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  if hdiutil detach "${CACHE_MOUNT}" -force -quiet 2>/dev/null; then
    CACHE_MOUNT=""
    echo "$(date -u +%FT%TZ) dispatch-poll: cache image force-detached after ${waited}s"
    return 0
  fi
  CACHE_MOUNT=""
  return 1
}

# mark_cache_not_promotable withdraws this job's cache image from both promotion
# and publication. An image we could not detach may be mid-write, and there is
# no way to tell from here — so the account keeps its existing master (this job
# costs it one job's warmth) rather than risk a torn master reaching this host
# and, via the HEAD, every other host too.
#
# cache-dirty was never written (it is withheld until a clean detach), so its
# absence alone already makes the host discard; writing an explicit "0" is
# belt-and-suspenders. Clearing CACHE_IMAGE_ACTIVE also no-ops report_volume_head.
mark_cache_not_promotable() {
  local why="$1"
  CACHE_IMAGE_ACTIVE=""
  printf '0' >"${STATUS_SHARE}/cache-dirty" 2>/dev/null || true
  echo "$(date -u +%FT%TZ) dispatch-poll: WARNING cache image not promotable (${why}); host will discard this branch"
}

# cache_diag records WHY the cache volume was rejected: the real errno plus the
# ownership/mode of the share and the image. If the fallback ever fires, this is
# the evidence and no one has to guess which layer failed.
cache_diag() {
  local why="$1"
  echo "$(date -u +%FT%TZ) dispatch-poll: cache-volume check failed: ${why}"
  echo "$(date -u +%FT%TZ) dispatch-poll: whoami=$(id -un 2>/dev/null) uid=$(id -u 2>/dev/null)"
  ls -ld "${CACHE_SHARE}" "${CACHE_IMAGE}" 2>&1 | while read -r l; do
    echo "$(date -u +%FT%TZ) dispatch-poll: cache-volume stat: ${l}"
  done
}

# probe_cache_share records whether the host attached a cache-volume share at
# boot. Nothing is mounted yet: the image only exists once the host materializes
# the dispatched account's master into the branch, so the attach happens in
# wait_for_cache_ready. Absent share => feature off / admission declined => cold
# path. Never blocks.
probe_cache_share() {
  if [ ! -d "${CACHE_SHARE}" ]; then
    echo "$(date -u +%FT%TZ) dispatch-poll: no cache share; running on the status-quo cold path"
    return 0
  fi
  CACHE_SHARE_PRESENT=1
  echo "$(date -u +%FT%TZ) dispatch-poll: cache share present at ${CACHE_SHARE}; image attaches after dispatch"
}


# setup_cas_store points every xcodebuild in the job at the folded CAS store
# inside the mounted cache image, when the host staged the cas-enabled marker.
# Called after attach_cache_image (CACHE_MOUNT set); the store rides the one
# image, so there is nothing to attach and nothing to detach separately — the
# cache image's own quiesced detach + not-promotable-on-failed-detach gate cover
# it. Absent marker / unwritable store => the compilation cache falls to the
# VM-local default (cold, dies with the VM). Never blocks the job.
#
# The CAS location rides XCODE_XCCONFIG_FILE, not a build setting Tuist writes
# into a project: the common case is a plain `xcodebuild build` against a project
# Tuist never generated and never wraps, which a project mapper (generate-only)
# and `tuist xcodebuild` (wrapper-only) both miss. An xcconfig injected through
# the environment is the one layer every xcodebuild invocation honors. (Measured
# on staging: COMPILATION_CACHE_* as plain env vars does NOTHING; via
# XCODE_XCCONFIG_FILE a raw build caches and replays warm.) It deliberately does
# NOT set COMPILATION_CACHE_ENABLE_CACHING — enabling the cache stays the
# project's opt-in; this only says WHERE an already-caching build keeps its store.
#
# PRECEDENCE, measured — XCODE_XCCONFIG_FILE OVERRIDES project/target settings
# (swift-build's `environmentConfigPath`), so this FORCES the CAS location; the
# escape hatch is a workflow's OWN xcconfig, `#include`d LAST below, so anything
# it sets (the CAS path included) wins over these defaults.
setup_cas_store() {
  [ -n "${CACHE_MOUNT}" ] || return 0
  # The marker carries the CAS's coordinated byte budget (empty/absent = the host
  # disabled the feature). Reclaim of a stale store left by a previously enabled
  # run happens at teardown, not here — see reclaim_cas_if_disabled.
  local cas_limit_bytes
  cas_limit_bytes=$(cat "${STATUS_SHARE}/${CAS_ENABLED_MARKER}" 2>/dev/null)
  if [ -z "${cas_limit_bytes}" ]; then
    echo "$(date -u +%FT%TZ) dispatch-poll: CAS not enabled; compilation cache runs VM-local"
    return 0
  fi
  # A non-numeric budget is a staging bug; without a trustworthy bound we would
  # point the compiler at the shared image with an UNBOUNDED store that could
  # prune the binary cache to ENOSPC, so fall back to VM-local rather than guess.
  case "${cas_limit_bytes}" in ''|*[!0-9]*)
    echo "$(date -u +%FT%TZ) dispatch-poll: WARNING CAS budget marker not numeric (${cas_limit_bytes}); compilation cache runs VM-local"
    return 0 ;;
  esac
  local store="${CACHE_MOUNT}/${CAS_STORE_DIR}"
  mkdir -p "${store}" 2>/dev/null || true
  # Never export a store the build can't write. `mkdir -p` says nothing about an
  # ALREADY-EXISTING dir, so prove writability rather than assume it.
  if ! touch "${store}/.writable" 2>/dev/null; then
    echo "$(date -u +%FT%TZ) dispatch-poll: WARNING CAS store not writable; compilation cache runs VM-local"
    return 0
  fi
  rm -f "${store}/.writable" 2>/dev/null || true
  {
    printf 'COMPILATION_CACHE_CAS_PATH = %s\n' "${store}"
    printf 'COMPILATION_CACHE_KEEP_CAS_DIRECTORY = YES\n'
    # Bound the store to the host-computed byte budget so llcas prunes before the
    # image can hit ENOSPC. LIMIT_SIZE (not LIMIT_PERCENT): Swift Build's percent
    # is against the current cache-db size plus free space, so as the binary cache
    # fills the shared image the percent's denominator shrinks and the CAS prunes
    # toward far less than intended. An absolute byte budget is invariant to the
    # binary cache's fill; it is the coordinated other half of TUIST_CACHE_MAX_BYTES
    # (both from the host's cacheImageSplit) so the two pruners cannot over-commit
    # the one shared image.
    printf 'COMPILATION_CACHE_LIMIT_SIZE = %s\n' "${cas_limit_bytes}"
    # A pre-existing user xcconfig is chained LAST: the variable is a single slot,
    # so carry theirs rather than clobber it, and including it after our defaults
    # means anything they set explicitly (the CAS path included) wins.
    if [ -n "${XCODE_XCCONFIG_FILE:-}" ] && [ -f "${XCODE_XCCONFIG_FILE}" ]; then
      printf '#include "%s"\n' "${XCODE_XCCONFIG_FILE}"
    fi
  } > "${CAS_XCCONFIG}"
  export XCODE_XCCONFIG_FILE="${CAS_XCCONFIG}"
  echo "$(date -u +%FT%TZ) dispatch-poll: CAS store at ${store}; XCODE_XCCONFIG_FILE -> ${CAS_XCCONFIG}"
}

# reclaim_cas_if_disabled removes a leftover CAS store from the image when the
# feature is OFF (no marker), so masters that were promoted while it was on stop
# cloning and uploading dead CAS bytes (which also eat binary-cache capacity).
# Runs at TEARDOWN, after the pre-job inventory was snapshotted WITH the store
# present, so the removal registers as an inventory change (the store's ~cas/
# lines drop out) → dirty → the cleaned image promotes and other hosts converge
# to it. A no-op when
# the feature is on or no store is present. Best-effort; never blocks teardown.
reclaim_cas_if_disabled() {
  [ -n "${CACHE_MOUNT}" ] || return 0
  [ -f "${STATUS_SHARE}/${CAS_ENABLED_MARKER}" ] && return 0
  local store="${CACHE_MOUNT}/${CAS_STORE_DIR}"
  [ -d "${store}" ] || return 0
  rm -rf "${store}" 2>/dev/null || true
  echo "$(date -u +%FT%TZ) dispatch-poll: CAS disabled; reclaimed stale store from image"
}

# CAS_DRAIN_TIMEOUT bounds the wait for this job's compilation-cache
# publications to reach the remote cache before the image they live in is
# measured and promoted. It holds the VM (and its warm-pool slot) open for its
# duration, so it is a ceiling and not a budget to spend: a healthy job has
# published continuously while it built and passes this gate in milliseconds.
# For scale, teardown already allows 600s for the master image upload.
CAS_DRAIN_TIMEOUT=120

# The proxy's own socket default (`$HOME/.local/state/tuist/cas-proxy.sock`),
# spelled out rather than left to the client: this shell is not the job's, and
# an unset HOME would send the client looking under /tmp for a socket that is
# not there — which reads as "no proxy" and silently costs the precise wait.
CAS_PROXY_SOCKET="${HOME:-/Users/runner}/.local/state/tuist/cas-proxy.sock"

# cas_spool_dirs lists the publication spools inside the mounted image. The
# plugin keeps one per CAS directory it opens (`<cas dir>/tuist-spool`) and the
# compiler picks the subdirectory under COMPILATION_CACHE_CAS_PATH, so discover
# them rather than assume the layout. No spool is the ordinary case and makes
# the gate a no-op: a plain `xcodebuild` job runs Xcode's builtin lane, which
# has no remote and nothing to publish.
cas_spool_dirs() {
  [ -n "${CACHE_MOUNT}" ] || return 0
  find "${CACHE_MOUNT}/${CAS_STORE_DIR}" -type d -name tuist-spool 2>/dev/null
}

# cas_spool_records counts what a spool still owes the remote. A record is
# deleted only by a publication that SUCCEEDED, so the count is exactly the set
# of associations no other host could ever satisfy. `.tags` sidecars are not
# records — the proxy's own accounting skips them for the same reason.
cas_spool_records() {
  find "$1" -type f ! -name '*.tags' 2>/dev/null | wc -l | tr -d ' '
}

# cas_proxy_client finds the binary that can ask the running proxy to drain,
# so the gate waits on the publisher itself instead of sampling a directory.
#
# The launch agent `tuist setup cache` installed is the reliable pointer: its
# `Program` IS the tuist whose bundle serves this machine's socket, and the
# proxy binary ships beside it. Nothing found (a job that never ran `tuist setup
# cache`, or a tuist this shell cannot see) is not a failure — the gate falls
# back to watching the spool, which proves the same thing more slowly.
cas_proxy_client() {
  local candidate program plist
  plist="${HOME:-/Users/runner}/Library/LaunchAgents/tuist.cas-proxy.plist"
  program=""
  if [ -r "${plist}" ]; then
    program=$(/usr/libexec/PlistBuddy -c 'Print :Program' "${plist}" 2>/dev/null)
  fi
  for candidate in \
    "${TUIST_CAS_PROXY_PATH:-}" \
    "$(command -v tuist-cas-proxy 2>/dev/null)" \
    "${program:+$(dirname "${program}")/tuist-cas-proxy}" \
    "${program:+$(dirname "${program}")/lib/tuist-cas-proxy}"; do
    if [ -n "${candidate}" ] && [ -x "${candidate}" ]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  return 1
}

# drain_cas_publications holds teardown until every compilation-cache
# publication this job recorded has reached the remote, and reports whether it
# got there. A non-zero return withdraws the image from promotion.
#
# This is what makes a promoted master honest. The CAS store is folded into the
# image, so the master carries the local `key -> value` associations this job
# wrote — while the objects behind them are uploaded ASYNCHRONOUSLY, through the
# plugin's spool. Every host that later clones the master inherits those
# associations, and its only repair path for an object the store does not hold
# is the remote. So an association whose blobs were still queued when the VM
# halted is one NO host can ever satisfy, and nothing retracts it: the compiler's
# CAS ABI has no delete, and re-putting the key with a different value is
# refused. It fails every later build of that key until the store generation
# rolls. Five such CI failures over five days, one key failing on two separate
# days in different workflows, is what this gate is for.
#
# It must run BEFORE capture_settled_inventory, which computes the digest that
# becomes this image's immutable object key: draining afterwards would stamp an
# image already carrying associations the remote cannot back. And before the
# detach, since the spool lives inside the image and the publisher needs to read
# it.
#
# Skipped when the job failed: a non-zero rc never promotes (report_cache_dirty
# and report_volume_head both gate on it), so there is no master to keep honest
# and no reason to hold the slot.
#
# Best-effort by nature, which is why it does not replace the plugin's read-side
# guard: a host that panics, or a job cancelled mid-upload, promotes without ever
# reaching this.
drain_cas_publications() {
  local rc="${1:-1}"
  [ "${rc}" = "0" ] || return 0
  [ -n "${CACHE_MOUNT}" ] || return 0
  local spools
  spools=$(cas_spool_dirs)
  [ -n "${spools}" ] || return 0

  local client deadline status spool cas_path budget owed
  client=$(cas_proxy_client) || client=""
  deadline=$(( $(date +%s) + CAS_DRAIN_TIMEOUT ))
  status=0

  # A heredoc and not a pipe: a `while read` behind a pipe runs in a subshell,
  # and `status` would never leave it — the gate would pass on every job.
  while IFS= read -r spool; do
    [ -n "${spool}" ] || continue
    cas_path=$(dirname "${spool}")
    budget=$(( deadline - $(date +%s) ))
    [ "${budget}" -lt 1 ] && budget=1
    owed=""
    if [ -n "${client}" ]; then
      # `env -u TUIST_CAS_REMOTE_GRPC_URL` is the version-skew guard, not a
      # tidiness one. A proxy binary older than the drain op does not recognise
      # `--drain` and falls through to its SERVE path, which unlinks the
      # machine's socket and binds its own — killing the live proxy from a
      # teardown script. Without that variable it exits before reaching the bind,
      # every time, and the gate reads it as "could not ask".
      env -u TUIST_CAS_REMOTE_GRPC_URL "${client}" --drain "${cas_path}" \
        --socket "${CAS_PROXY_SOCKET}" \
        --timeout-ms "$(( budget * 1000 ))"
      # 0 drained, 3 records remain. Every other code is "could not ask" — an
      # unreachable proxy, one too old to know the op, or a shim that never got
      # as far as running the binary — which is NOT an answer and must neither
      # read as drained nor as a verdict. 3 and not 1 for exactly that reason:
      # 1 is what a failing wrapper returns.
      case "$?" in
        0) owed=0 ;;
        3) owed=$(cas_spool_records "${spool}") ;;
      esac
    fi
    # No client, or none that could answer: watch the spool itself. It proves
    # the same thing (a record only disappears when its publication landed),
    # just at polling granularity.
    if [ -z "${owed}" ]; then
      while :; do
        owed=$(cas_spool_records "${spool}")
        [ "${owed}" = "0" ] && break
        [ "$(date +%s)" -ge "${deadline}" ] && break
        sleep 2
      done
    fi
    if [ "${owed}" != "0" ]; then
      echo "$(date -u +%FT%TZ) dispatch-poll: WARNING ${owed} CAS publication(s) under ${cas_path} did not reach the cache within ${CAS_DRAIN_TIMEOUT}s"
      status=1
    else
      echo "$(date -u +%FT%TZ) dispatch-poll: CAS publications drained for ${cas_path}"
    fi
  done <<EOF
${spools}
EOF
  return "${status}"
}

# CACHE_READY_TIMEOUT bounds the wait for the host's cache-ready signal — the
# most a job's start can be delayed by the cache. The host materializes from its
# LOCAL master (a CoW clonefile, ~tens of ms, no network) before signalling;
# freshness convergence (the only slow, download-bound step) runs in the
# background off this path, so cache-ready normally lands within a second of the
# host observing the dispatch. The ceiling only has to absorb reconcile
# scheduling jitter (a missed watch falls back to the reconciler's ~30s
# periodic requeue), so 60s is comfortable headroom. On timeout the guest
# assumes the host is wedged and starts on a local cold cache rather than the
# share, so it never blocks the job longer than this and a late host swap can't
# corrupt the run.
CACHE_READY_TIMEOUT=60

# wait_for_cache_ready blocks (bounded) until the host signals it has
# materialized the dispatched account's cache master into the branch (or
# determined there is none — a cold first job, for which the host still leaves an
# EMPTY image, since the guest can only attach what is there). Only then does it
# attach: before the signal there is no image, and mid-materialization the host
# is still swapping the file. Also snapshots the pre-job inventory so
# report_cache_dirty can tell a real change from a pure-hit run.
#
# On timeout the host may STILL be materializing and could swap the image out
# from under a running job, so the guest abandons the volume for a local, private
# cold cache dir (a late host swap of the now-abandoned branch is then harmless).
# Never blocks the job.
wait_for_cache_ready() {
  [ -n "${CACHE_SHARE_PRESENT}" ] || return 0
  local waited=0
  while [ "${waited}" -lt "${CACHE_READY_TIMEOUT}" ]; do
    if [ -f "${STATUS_SHARE}/cache-ready" ]; then
      echo "$(date -u +%FT%TZ) dispatch-poll: cache-ready after ${waited}s"
      if ! attach_cache_image; then
        use_local_cold_cache "cannot attach ${CACHE_IMAGE}"
        return 0
      fi
      CACHE_INVENTORY_BEFORE=$(cache_inventory "${CACHE_MOUNT}")
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  use_local_cold_cache "cache-ready not signalled within ${CACHE_READY_TIMEOUT}s"
}

# sample_cache_fill records the image's post-job fill % (binary cache + CAS +
# overhead) for the host's fill histogram — the signal for whether the reserve is
# holding or the volume is running near ENOSPC. Must run while the image is still
# MOUNTED, since `df` reports on a mount. `df -P` for the portable one-line
# format; column 5 is Use%.
sample_cache_fill() {
  [ -n "${CACHE_MOUNT}" ] || return 0
  [ -d "${STATUS_SHARE}" ] || return 0
  local fill
  fill=$(df -P "${CACHE_MOUNT}" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
  case "${fill}" in ''|*[!0-9]*) fill="" ;; esac
  [ -n "${fill}" ] && printf '%s' "${fill}" > "${STATUS_SHARE}/cache-fill-percent" 2>/dev/null || true
}

# Where the detached image is re-attached to be measured. Deliberately not
# CACHE_MOUNTPOINT: that one is the job's read-write mount, and reusing it would
# make a leaked read-only attach indistinguishable from a live cache.
CACHE_VERIFY_MOUNTPOINT="/Users/runner/.tuist-cache-verify"

# capture_settled_inventory computes the digest this job publishes, measured on
# the image as it will be UPLOADED: it re-attaches the already-detached file
# READ-ONLY and reads that, into CACHE_INVENTORY_AFTER — used by
# report_cache_dirty (to detect a change) and report_volume_head (as the new
# HEAD's tree_digest and the master object's key).
#
# It must NOT be measured through the job's live mount, which is what this
# replaced. The digest is a claim about the bytes the upload sends — it is both
# the HEAD's tree_digest and the immutable object key — so anything that writes to
# the image between measuring and detaching breaks that claim permanently. The
# window is real rather than theoretical: detach_cache_image polls and then FORCES
# exactly because processes outlive the runner (a lingering build service, or the
# compilation cache's own asynchronous store flush/prune, which is size-capped and
# so busiest for the largest caches), and every ~cas/ line carries a file SIZE, so
# a single late append is enough to move the digest. A HEAD published from a
# pre-detach snapshot then names bytes no host can reproduce: convergence
# downloads the object, computes a different digest, and declines — and no promote
# can build on that HEAD either (base 0 is rejected while a HEAD exists, and a host
# left at an older generation is rejected for a stale base), so the account can
# neither adopt it nor replace it, on any host, indefinitely.
#
# Read-only, so measuring cannot alter what it measures, and an image too torn to
# mount read-only fails HERE instead of becoming every host's master. A non-zero
# return withdraws the branch from both promotion and publication.
capture_settled_inventory() {
  [ -n "${CACHE_IMAGE_ACTIVE}" ] || return 0
  mkdir -p "${CACHE_VERIFY_MOUNTPOINT}" 2>/dev/null || true
  local err
  if ! err=$(hdiutil attach "${CACHE_IMAGE}" -readonly -owners off -nobrowse -noverify -quiet \
    -mountpoint "${CACHE_VERIFY_MOUNTPOINT}" 2>&1); then
    echo "$(date -u +%FT%TZ) dispatch-poll: WARNING settled cache image would not attach read-only: ${err}"
    return 1
  fi
  CACHE_INVENTORY_AFTER=$(cache_inventory "${CACHE_VERIFY_MOUNTPOINT}")
  # Detach before the upload reads the file: a read-only attach cannot corrupt it,
  # but leaving one pinned serves no purpose once the digest is taken.
  hdiutil detach "${CACHE_VERIFY_MOUNTPOINT}" -quiet 2>/dev/null ||
    hdiutil detach "${CACHE_VERIFY_MOUNTPOINT}" -force -quiet 2>/dev/null || true
  [ -n "${CACHE_INVENTORY_AFTER}" ] || return 1
  echo "$(date -u +%FT%TZ) dispatch-poll: settled cache inventory digest=${CACHE_INVENTORY_AFTER}"
  return 0
}

# report_cache_dirty writes the guest's dirty marker into the writable status
# share so the reconciler can decide promote-vs-discard. "1" iff the job
# succeeded (runner rc == 0) AND the cache inventory changed; "0" for a
# read-only / pure-hit job OR a job whose runner exited non-zero (infra failure,
# cancellation, runner crash).
#
# It MUST run AFTER a successful detach. The marker is what authorizes the host
# to promote, and the host promotes by cloning the image file without being able
# to tell a mid-write image from a settled one. Writing "1" while the image were
# still mounted would let a clean VM halt in that window promote a torn image. So
# a mounted, un-detached, or failed-to-detach image is left with NO cache-dirty
# marker at all, and absence makes the reconciler discard the branch — the safe
# default for every teardown that does not reach a clean detach (early exit,
# detach failure). It reads the inventory capture_settled_inventory took off the
# detached image, so "dirty" describes the bytes that would actually be promoted.
#
# Gating on rc carries the job result to the host so a failed run never promotes
# its branch to the account's master — the host's own `tart run` clean-exit
# signal reflects the VM halting, not the job's conclusion, so it can't make
# this call on its own. (rc is the runner-process exit: it catches infra/runner
# failures and cancellations; a job whose steps fail while the runner exits 0
# still promotes, which is acceptable — those artifacts are content-addressed
# and signature-validated, so they warm rather than corrupt.) Mirrors the rc
# gate in report_volume_head so local promote and HEAD publish agree.

report_cache_dirty() {
  [ -d "${STATUS_SHARE}" ] || return 0
  local rc="${1:-1}" dirty=0
  if [ "${rc}" = "0" ] && [ -n "${CACHE_INVENTORY_AFTER}" ] && \
    [ "${CACHE_INVENTORY_AFTER}" != "${CACHE_INVENTORY_BEFORE}" ]; then
    dirty=1
  fi
  printf '%s' "${dirty}" > "${STATUS_SHARE}/cache-dirty" 2>/dev/null || true
  echo "$(date -u +%FT%TZ) dispatch-poll: cache dirty=${dirty} (rc=${rc}) digest=${CACHE_INVENTORY_AFTER} reported to host"
}

# stage_volume_head writes the account's cache-volume HEAD (from the dispatch
# response) into the status share so the host can converge a stale master toward
# it before materializing, and remembers the presigned upload URL for publishing
# this job's result. Best-effort: an absent block just means no convergence.
stage_volume_head() {
  [ -d "${STATUS_SHARE}" ] || return 0
  local gen digest download
  gen=$(sed -n 's/.*"generation"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' /tmp/dispatch.json)
  digest=$(sed -n 's/.*"digest"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /tmp/dispatch.json)
  download=$(sed -n 's/.*"download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /tmp/dispatch.json)
  [ -n "${download}" ] || return 0
  printf '{"generation":%s,"digest":"%s","download_url":"%s"}' \
    "${gen:-0}" "${digest}" "${download}" >"${STATUS_SHARE}/volume-head.json" 2>/dev/null || true
}

# read_base_generation returns the HEAD generation this VM's branch was cloned
# from — staged by the host into the status share at materialize. It is the
# fast-forward base the server checks the promote against: the server advances the
# HEAD only if it is still at this generation. Absent or non-numeric (a cold
# branch with no local master, or a host that did not stage it) reads as 0, which
# the server accepts only when the account has no HEAD yet.
read_base_generation() {
  local gen=""
  if [ -r "${STATUS_SHARE}/cache-base-generation" ]; then
    gen=$(tr -cd '0-9' < "${STATUS_SHARE}/cache-base-generation" 2>/dev/null)
  fi
  printf '%s' "${gen:-0}"
}

# read_unverifiable_head returns the HEAD digest this host downloaded during the
# job and found the stored object does not reproduce — staged by the host's
# background convergence, empty when convergence had nothing to report (the usual
# case).
#
# It rides the promote report because a HEAD that no host can verify is otherwise
# permanent: convergence declines it, and no promote can build on it either — this
# host's base is 0 if it holds no master and stale if it holds an older one, and
# both lose the fast-forward. The server takes this as the evidence that lets the
# promote retire that lineage instead.
#
# Sanitised to the digest alphabet and length the server expects, so nothing from
# the share can escape into the request body.
read_unverifiable_head() {
  local digest=""
  if [ -r "${STATUS_SHARE}/volume-head-unverifiable" ]; then
    digest=$(tr -cd 'a-f0-9' < "${STATUS_SHARE}/volume-head-unverifiable" 2>/dev/null)
  fi
  [ "${#digest}" = "40" ] || digest=""
  printf '%s' "${digest}"
}

# read_node_name returns this host's Kubernetes Node name, staged by the host into
# the status share when the VM was created. It rides the promote report purely as
# attribution: it is the only record of WHICH host published a given HEAD
# generation, which is the first thing you want when a HEAD turns out to be one no
# host can reproduce and the account's cache is frozen fleet-wide.
#
# Deliberately the Node name and not TUIST_RUNNER_POD_NAME, which the guest also
# holds: the Pod is deleted minutes after the job, whereas the Node name is what
# `tuist.dev/cache-master-<account_id>` advertisements and the volume affinities
# are keyed on, so it still resolves to the host holding that master. An
# unstaged name reports empty rather than falling back to the Pod name — empty
# means "not reported", and a column holding two kinds of name identifies neither.
#
# Sanitised to the DNS-subdomain alphabet and length a Node name can have, so
# nothing from a share can escape into the request body.
read_node_name() {
  local node=""
  if [ -r "${STATUS_SHARE}/node-name" ]; then
    node=$(tr -cd 'A-Za-z0-9.-' < "${STATUS_SHARE}/node-name" 2>/dev/null | cut -c1-253)
  fi
  printf '%s' "${node}"
}

# write_promote_result relays the promote outcome to the host so it can tell a
# genuine fast-forward REJECTION (409 — a stale base another host advanced past,
# real cross-host contention) apart from an upload/network/control-plane FAILURE.
# Conflating the two would make a storage outage look like cache races on the
# dashboard. The host reads this to pick the metric bucket and, on "accepted",
# the generation to install the branch at. Values: "accepted <gen>", "conflict",
# or "error".
write_promote_result() {
  [ -d "${STATUS_SHARE}" ] || return 0
  printf '%s' "$1" > "${STATUS_SHARE}/cache-promote-result" 2>/dev/null || true
}

# VOLUME_HEAD_UPLOAD_TIMEOUT bounds the master upload. The image is sparse, so
# this transfers the cache actually written rather than the provisioned cap, but
# that is still GBs on a full working set — hence a far larger ceiling than the
# old zip's. It runs at teardown and holds the VM (and its warm-pool slot) open
# for its duration, so it stays bounded rather than generous-and-unbounded.
VOLUME_HEAD_UPLOAD_TIMEOUT=600

# report_volume_head publishes this job's warm set as the account's new HEAD on a
# successful, cache-changing job, in three steps:
#   1. mint a presigned PUT URL keyed by THIS job's inventory digest, sending the
#      base generation so the server can pre-empt a promote that cannot win,
#   2. PUT the settled image to it,
#   3. bump the account's HEAD to that digest.
#
# The digest-keyed object is content-addressed and immutable: a concurrent
# promote of a DIFFERENT digest writes a DIFFERENT object, so it never clobbers
# the object the current HEAD points at — the bug that let a behind host download
# a master whose inventory no longer matched the HEAD digest and abandon
# convergence, stranding the warm set on the one host that promoted it. HEAD is
# bumped only AFTER the PUT succeeds, so a converging host that reads the new HEAD
# always finds the object.
#
# The image is uploaded AS-IS, with no archiving step: it already carries the
# symlinks, xattrs and modes the cache needs, which is the whole reason the cache
# is an image. It must run AFTER detach_cache_image — a still-mounted image can
# be mid-write, and what gets uploaded here becomes every other host's master.
# Best-effort; never blocks teardown.
report_volume_head() {
  local rc="${1:-1}"
  [ "${rc}" = "0" ] || return 0
  [ -n "${CACHE_IMAGE_ACTIVE}" ] || return 0
  [ -n "${CACHE_INVENTORY_AFTER}" ] || return 0
  [ "${CACHE_INVENTORY_AFTER}" != "${CACHE_INVENTORY_BEFORE}" ] || return 0

  local base_generation unverifiable node_name promote_body
  base_generation=$(read_base_generation)
  # One body for both requests: the mint's pre-flight has to evaluate the same
  # inputs as the bump it precedes, or a promote the bump would accept gets a 409
  # here and never reaches it. That matters most for exactly the case the
  # unverifiable digest exists for — a promote retiring a HEAD no host can adopt,
  # which the pre-flight would otherwise turn away forever on a base (cold or
  # stale) that can never catch up.
  unverifiable=$(read_unverifiable_head)
  node_name=$(read_node_name)
  promote_body="{\"tree_digest\":\"${CACHE_INVENTORY_AFTER}\",\"base_generation\":${base_generation},\"unverifiable_digest\":\"${unverifiable}\",\"node_name\":\"${node_name}\"}"
  if [ -n "${unverifiable}" ]; then
    echo "$(date -u +%FT%TZ) dispatch-poll: reporting HEAD ${unverifiable} as unverifiable on this host"
  fi

  # Mint the content-addressed upload URL for this digest. The server binds it to
  # the account this Pod ran (server-stamped label) and rejects a non-hex digest,
  # so the guest cannot target another account or escape its prefix.
  #
  # The base generation rides along so the server can PRE-EMPT the upload: most
  # promotes lose the fast-forward under cross-host contention, and paying for a
  # multi-GB PUT first meant that loss still held the VM (and the host's slot)
  # open for the whole transfer. A 409 here means the base has already been
  # advanced past, so this promote is certain to be rejected and there is nothing
  # to gain by uploading. It is only an optimization — the bump below stays the
  # authority, and another host can still win in the window between the two — so
  # every other outcome falls through to the upload-then-arbitrate path.
  #
  # Status captured explicitly instead of `curl -f` so the 409 is distinguishable
  # from a transport failure, which must NOT be recorded as contention.
  local mint_body mint_http upload_url
  mint_body=$(mktemp 2>/dev/null || echo "/tmp/volhead-mint.$$")
  mint_http=$(curl -sS --connect-timeout 10 --max-time 30 -X POST \
    -H "Authorization: Bearer ${SA_TOKEN}" -H "Content-Type: application/json" \
    --data "${promote_body}" \
    -o "${mint_body}" -w '%{http_code}' \
    "${VOLUME_HEAD_UPLOAD_URL_MINT_ENDPOINT}" 2>/dev/null)
  if [ "${mint_http}" = "409" ]; then
    rm -f "${mint_body}" 2>/dev/null || true
    write_promote_result "conflict"
    echo "$(date -u +%FT%TZ) dispatch-poll: volume HEAD already advanced past base=${base_generation}; image not uploaded"
    return 0
  fi
  upload_url=$(sed -n 's/.*"upload_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${mint_body}" 2>/dev/null)
  rm -f "${mint_body}" 2>/dev/null || true
  if [ -z "${upload_url}" ]; then
    echo "$(date -u +%FT%TZ) dispatch-poll: no master upload URL (http=${mint_http:-000}); HEAD not advanced"
    write_promote_result "error"
    return 0
  fi

  # This runs at teardown, after run.sh, before the EXIT trap halts the VM, so
  # every request MUST be bounded — an object-storage stall here would otherwise
  # hang the script, keep the VM up, and stop the warm pool refilling. On any
  # timeout, HEAD just isn't advanced (best-effort) and teardown proceeds.
  #
  # No -L on the PUT: the presigned upload URL is written directly (no redirect),
  # so refuse to follow redirects — otherwise a compromised/misconfigured storage
  # endpoint could 307 the upload to an internal address and receive the image
  # body (SSRF), the write-side twin of the download guard. The server has
  # already checked the URL host is public before handing it over.
  # Time the PUT — the volume upload blocks teardown, so the VM cannot halt and
  # the host cannot reclaim the slot until it finishes. Report the duration to the
  # host (volume-upload-ms) so we can watch how long uploads hold slots and keep
  # the volume sized so it stays fast. perl for ms precision (BSD date has no %N).
  local upload_start upload_end
  upload_start=$(perl -MTime::HiRes -e 'printf "%d", Time::HiRes::time()*1000' 2>/dev/null || echo 0)
  if ! curl -fsS --connect-timeout 10 --max-time "${VOLUME_HEAD_UPLOAD_TIMEOUT}" \
    -X PUT --upload-file "${CACHE_IMAGE}" "${upload_url}" >/dev/null 2>&1; then
    echo "$(date -u +%FT%TZ) dispatch-poll: master image upload failed/timed out; HEAD not advanced"
    write_promote_result "error"
    return 0
  fi
  upload_end=$(perl -MTime::HiRes -e 'printf "%d", Time::HiRes::time()*1000' 2>/dev/null || echo 0)
  if [ -d "${STATUS_SHARE}" ] && [ "${upload_end}" -gt "${upload_start}" ] 2>/dev/null; then
    printf '%s' "$(( upload_end - upload_start ))" > "${STATUS_SHARE}/volume-upload-ms" 2>/dev/null || true
  fi
  # Only now advance the HEAD: the object at the digest key exists, so a
  # converging host that reads this HEAD will find it.
  #
  # The bump is a fast-forward compare-and-swap keyed by the base generation this
  # job's branch was cloned from (staged by the host at materialize). The server
  # accepts only if the HEAD is still at that base and returns the accepted
  # generation (200); a stale base is a 409. Capture the HTTP status explicitly —
  # WITHOUT curl -f, which would collapse a 409 and a transport error into the
  # same failure — so the host can distinguish a genuine fast-forward rejection
  # (cross-host contention) from an upload/network/control-plane failure. On 200
  # the host installs the branch as its local master at the accepted generation;
  # on 409 or error it discards and re-converges. The mint above pre-empts the
  # common stale-base case, but this is still where the outcome is decided: the
  # HEAD can have moved during the upload that just ran.
  local body http_code promoted_generation
  body=$(mktemp 2>/dev/null || echo "/tmp/volhead-report.$$")
  http_code=$(curl -sS --connect-timeout 10 --max-time 15 -X POST \
    -H "Authorization: Bearer ${SA_TOKEN}" -H "Content-Type: application/json" \
    --data "${promote_body}" \
    -o "${body}" -w '%{http_code}' \
    "${VOLUME_HEAD_REPORT_URL}" 2>/dev/null)
  case "${http_code}" in
    200)
      promoted_generation=$(sed -n 's/.*"generation"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "${body}")
      write_promote_result "accepted ${promoted_generation:-0}"
      echo "$(date -u +%FT%TZ) dispatch-poll: published volume HEAD (digest=${CACHE_INVENTORY_AFTER} generation=${promoted_generation:-0})"
      ;;
    409)
      write_promote_result "conflict"
      echo "$(date -u +%FT%TZ) dispatch-poll: volume HEAD fast-forward rejected (stale base=${base_generation}); branch not promoted"
      ;;
    *)
      write_promote_result "error"
      echo "$(date -u +%FT%TZ) dispatch-poll: volume HEAD report failed/unreachable (http=${http_code:-000}); branch not promoted"
      ;;
  esac
  rm -f "${body}" 2>/dev/null || true
}

# Probe before polling: the share is attached at boot, independent of which
# account dispatch later assigns. The image inside it only appears once the host
# materializes, so the attach itself waits for cache-ready.
probe_cache_share

# 2 s polling interval is the practical floor for "feels live" to
# a customer staring at their CI dashboard without burning the
# dispatch endpoint. Average pickup latency is ~1 s after a
# webhook lands; server-side load is still trivial at this rate
# (a few QPS per warm Pod, multiplied by host count).
interval=2
attempt=0

while true; do
  attempt=$((attempt + 1))
  # `-f` is intentionally omitted: with it, curl exits non-zero on
  # 4xx/5xx, the `|| http="000"` clause fires, and the real status
  # never reaches the case statement. We need 401/403/5xx as
  # numeric statuses so the case can branch on them. stderr is
  # redirected so curl's "The requested URL returned error: …" line
  # doesn't end up in the captured %{http_code}. The `|| http="000"`
  # fallback now fires only on transport failure (DNS, TCP, TLS,
  # timeout), where %{http_code} is "000" anyway.
  http=$(curl -sS -o /tmp/dispatch.json -w '%{http_code}' \
    --max-time 10 \
    --request POST \
    --header "Authorization: Bearer ${SA_TOKEN}" \
    --header "Content-Type: application/json" \
    --data '{}' \
    "${TUIST_RUNNER_DISPATCH_URL}" 2>/dev/null) || http="000"

  case "${http}" in
    200)
      # Pure-bash JSON field extraction — keeps the runner image
      # free of a Python (or jq) dependency. Safe because
      # `encoded_jit_config` is base64 (no quotes, no backslashes,
      # no newlines), so the value can't contain a `"` that would
      # confuse `[^"]*`. The server emits compact JSON; the
      # optional whitespace lets a future pretty-printer not
      # break this path.
      jit=$(sed -n 's/.*"encoded_jit_config"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /tmp/dispatch.json)
      if [ -z "${jit}" ]; then
        echo "$(date -u +%FT%TZ) dispatch-poll: 200 but empty encoded_jit_config; retrying"
        sleep "${interval}"
        continue
      fi
      printf '%s\n' "$(date -u +%FT%TZ)" >"${SHELL_CLAIM_MARKER}" 2>/dev/null || true
      # Optional: route the job's Tuist cache at the account's private
      # runner-cache Kura node (in-cluster, near this runner) when the
      # server includes it. Exported here so the GitHub Actions runner —
      # and therefore every job step — inherits it; the Tuist CLI honors
      # TUIST_CACHE_ENDPOINT as a cache-endpoint override. Same value-
      # safety as the JIT extraction: the URL is a plain http(s) URL
      # with no embedded quotes.
      cache_endpoint=$(sed -n 's/.*"cache_endpoint_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /tmp/dispatch.json)
      if [ -n "${cache_endpoint}" ]; then
        echo "$(date -u +%FT%TZ) dispatch-poll: routing cache to runner-local endpoint ${cache_endpoint}"
        export TUIST_CACHE_ENDPOINT="${cache_endpoint}"
      fi
      # Server-signed cache grant: a short-lived token scoping cache
      # artifact signatures to this account instead of the machine MAC, so a
      # warm volume's binaries validate as local hits across VMs. Same value-
      # safety as the JIT (a base64url token, no embedded quotes). The Tuist EE
      # CLI verifies it offline against a baked-in public key; absent/invalid/
      # expired falls back to the MAC default, so this is purely additive.
      cache_grant=$(sed -n 's/.*"cache_signing_grant"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /tmp/dispatch.json)
      if [ -n "${cache_grant}" ]; then
        echo "$(date -u +%FT%TZ) dispatch-poll: cache signing grant delivered"
        export TUIST_CACHE_SIGNING_GRANT="${cache_grant}"
      fi
      # Stage the account's volume HEAD for the host to converge a stale master
      # toward before it materializes into this VM's branch.
      stage_volume_head
      echo "$(date -u +%FT%TZ) dispatch-poll: dispatched, starting runner"
      # Dispatch bound this VM to an account; the host is clonefiling that
      # account's cache master into the branch share now. Wait (bounded) for
      # the cache-ready signal before the runner touches the cache, then
      # snapshot the pre-job inventory. Cold path on timeout; never blocks.
      wait_for_cache_ready
      # Force an NTP step before the job runs. A golden-base VM can be
      # handed a job within seconds of boot — before macOS `timed` has
      # synced the guest clock, which can start minutes behind. The
      # GitHub runner stamps step times and metrics-poll stamps samples
      # off this clock, so an unsynced VM lands the two on different
      # timelines (the step timeline only drifts into alignment once
      # `timed` catches up mid-job). `sntp -sS` steps a large offset via
      # clock_settime (and slews a sub-50ms one); the network is already
      # up here since dispatch just succeeded. Best-effort: on failure
      # `timed` still converges, just later.
      if sudo /usr/bin/sntp -sS -t 5 time.apple.com >/dev/null 2>&1; then
        echo "$(date -u +%FT%TZ) dispatch-poll: clock stepped to NTP before runner start"
      else
        echo "$(date -u +%FT%TZ) dispatch-poll: WARNING NTP step failed; relying on timed"
      fi
      # Fork the machine-metrics sampler so it runs for the job's
      # duration and POSTs CPU/memory/network/disk to the server. It
      # dies with the VM when the EXIT trap halts us after the runner
      # exits. Best-effort — never blocks the job from starting.
      if [ -x /opt/tuist/metrics-poll.sh ]; then
        /opt/tuist/metrics-poll.sh &
      fi
      cd /Users/runner/actions-runner
      # Idle watchdog. GitHub assigns a queued job to any label-eligible
      # runner, not necessarily the one the server minted it for, so
      # this runner can register and then wait indefinitely for a job
      # GitHub ran on a sibling, holding the VM and its warm-pool slot
      # idle. The watchdog terminates it after
      # TUIST_RUNNER_IDLE_TIMEOUT_SECONDS; the EXIT trap then halts the
      # VM and the reconciler recycles it. A runner holding a job has
      # written the JOB_STARTED marker (via the runner's own hook) and
      # is never touched. 0 / unset disables the watchdog.
      # The job-start signal must be irreversible: /tmp is writable by
      # the workflow, so a job that removes the marker (a broad
      # `rm -rf /tmp/*` cleanup is enough) must not be able to make
      # itself look idle and get killed mid-run. Two independent
      # latches: the hook cancels the watchdog outright (it runs before
      # any workflow step, so job code never sees a live watchdog), and
      # the watchdog polls and stands down the moment it observes work
      # rather than reading the marker once at the deadline. Neither can
      # be undone from inside the job.
      JOB_STARTED_MARKER=/tmp/tuist-runner-job-started
      JOB_STARTED_HOOK=/tmp/tuist-runner-job-started-hook.sh
      WATCHDOG_PID_FILE=/tmp/tuist-runner-watchdog.pid
      rm -f "${JOB_STARTED_MARKER}" "${WATCHDOG_PID_FILE}"
      cat >"${JOB_STARTED_HOOK}" <<HOOK
#!/bin/bash
touch "${JOB_STARTED_MARKER}" 2>/dev/null || true
_wpid="\$(cat "${WATCHDOG_PID_FILE}" 2>/dev/null || true)"
[ -n "\${_wpid}" ] && kill "\${_wpid}" 2>/dev/null || true
exit 0
HOOK
      chmod +x "${JOB_STARTED_HOOK}"
      export ACTIONS_RUNNER_HOOK_JOB_STARTED="${JOB_STARTED_HOOK}"
      idle_timeout="${TUIST_RUNNER_IDLE_TIMEOUT_SECONDS:-0}"

      # `--jitconfig` implies ephemeral: the runner accepts one job
      # and exits. `--disableupdate` pins the runner to whatever
      # version is baked into the image; we bump that via Renovate
      # PRs against `runner_version` in runner.pkr.hcl, which the
      # release-runner-image flow turns into a fresh image + digest
      # bump. Auto-update would self-upgrade the runner mid-VM, which
      # is opaque (the version that ran a job isn't the version we
      # baked in) and can race with GitHub's deprecation message on
      # cold boot. The EXIT trap above halts the VM regardless of
      # rc — the trap is what tart-kubelet ultimately observes, so
      # both clean and crash paths refill the warm pool the same way.
      #
      # Logs are captured server-side from GitHub's Actions Logs
      # API on `workflow_job: completed` (see
      # `Tuist.Runners.Workers.FetchLogsWorker`); the runner VM
      # writes nothing to the ingest path.
      ./run.sh --jitconfig "${jit}" --disableupdate &
      runner_pid=$!
      if [ "${idle_timeout}" -gt 0 ] 2>/dev/null; then
        (
          waited=0
          while [ "${waited}" -lt "${idle_timeout}" ]; do
            # Latch and stand down for good the first time work is observed.
            [ -e "${JOB_STARTED_MARKER}" ] && exit 0
            kill -0 "${runner_pid}" 2>/dev/null || exit 0
            sleep 1
            waited=$((waited + 1))
          done
          # The marker alone leaves a narrow race: the hook fires when the
          # Worker STARTS the job, a second or more after the Listener has
          # acknowledged the assignment, and an ephemeral runner killed
          # post-acknowledgment marks the job failed rather than re-queuing
          # it. The Runner.Worker process exists from the moment the
          # Listener dispatches, before the hook runs.
          if [ ! -e "${JOB_STARTED_MARKER}" ] && ! pgrep -f "Runner.Worker" >/dev/null 2>&1 &&
            kill -0 "${runner_pid}" 2>/dev/null; then
            echo "$(date -u +%FT%TZ) dispatch-poll: no job assigned within ${idle_timeout}s; terminating idle runner"
            kill -TERM "${runner_pid}" 2>/dev/null || true
          fi
        ) &
        watchdog_pid=$!
        printf '%s' "${watchdog_pid}" >"${WATCHDOG_PID_FILE}" 2>/dev/null || true
      fi
      wait "${runner_pid}"
      rc=$?
      # The runner is gone, so the idle watchdog has nothing left to police.
      [ -n "${watchdog_pid:-}" ] && kill "${watchdog_pid}" 2>/dev/null || true
      # Cache teardown. The order here is load-bearing:
      #   0. wait for the compilation cache's asynchronous publications to reach
      #      the remote, while the spool is still mounted and the publisher can
      #      still read it. The image carries the associations those uploads
      #      exist to back, so promoting ahead of them hands every host that
      #      clones this master keys naming objects nothing can produce;
      #   1. sample the signals that need a live mount (fill %), but withhold the
      #      promotion-authorizing dirty marker;
      #   2. detach, so the image is a settled filesystem rather than a torn
      #      snapshot — the host clones this file to promote it and cannot tell
      #      the two apart, so letting the VM halt tear the mount down would
      #      poison the account's master and every job that later clones it;
      #   3. measure the SETTLED image (read-only re-attach) for the digest this
      #      job publishes, so the HEAD names the bytes that get uploaded and not
      #      a state a straggler wrote past;
      #   4. ONLY then authorize promotion (dirty marker) and upload the settled
      #      image as the account's new HEAD. A detach failure, an unmeasurable
      #      image, or an early exit leaves no dirty marker, so the host discards.
      # rc gates promotion — a failed run never advances the master.
      # If the CAS feature was turned off, drop its stale store from the image
      # BEFORE the image is measured, so the removal promotes a cleaned master
      # instead of masters carrying dead CAS bytes forever.
      reclaim_cas_if_disabled
      # After the reclaim: a store that was just dropped has no spool left to
      # wait on, so a disabled-CAS teardown never pays for this gate.
      if ! drain_cas_publications "${rc}"; then
        mark_cache_not_promotable "CAS publications did not reach the cache"
      fi
      sample_cache_fill
      if ! detach_cache_image; then
        mark_cache_not_promotable "detach failed"
      elif ! capture_settled_inventory; then
        mark_cache_not_promotable "settled image could not be measured"
      else
        report_cache_dirty "${rc}"
        report_volume_head "${rc}"
      fi
      # Final metrics sample before the EXIT trap halts the VM. The
      # looping sampler is killed mid-sleep by the shutdown, so the last
      # interval — including "Complete job" — otherwise has no data point
      # and the chart stops short of the job's end. One synchronous
      # sample now, while the network is still up, closes that gap.
      # Best-effort; never affects the runner's exit code.
      [ -x /opt/tuist/metrics-poll.sh ] && /opt/tuist/metrics-poll.sh --once || true
      exit "${rc}"
      ;;
    204)
      # Server has nothing for us yet. Keep polling — the VM is
      # booted and registered with the dispatch endpoint via its
      # SA token; when a customer workflow_job arrives, our next
      # poll will return 200 with the JIT bound to that customer.
      # Quiet log every 30th tick (~once per minute at 2 s
      # interval) so the file doesn't balloon while idle.
      [ $((attempt % 30)) -eq 0 ] && echo "$(date -u +%FT%TZ) dispatch-poll: warm standby (attempt=${attempt})"
      sleep "${interval}"
      ;;
    401|403)
      echo "$(date -u +%FT%TZ) dispatch-poll: ${http} unauthorized; aborting"
      exit 1
      ;;
    410)
      # Server signalled drain — this Pod's image no longer matches
      # the RunnerPool's spec.image (chart digest-pin rolled). Exit
      # cleanly so the EXIT trap halts the VM and tart-kubelet flips
      # the Pod to Succeeded; the reconciler then replaces it with
      # one on the current image. The check only runs on idle polls,
      # so in-flight customer work is never interrupted.
      echo "$(date -u +%FT%TZ) dispatch-poll: 410 drain — stale image, exiting cleanly"
      exit 0
      ;;
    *)
      echo "$(date -u +%FT%TZ) dispatch-poll: HTTP ${http} (attempt=${attempt}); retrying"
      sleep "${interval}"
      ;;
  esac
done
