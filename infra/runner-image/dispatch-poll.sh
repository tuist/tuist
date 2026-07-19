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

# Always halt the VM on script exit. tart-kubelet observes `tart run`
# exiting and transitions the Pod to a terminal phase; without this
# trap a non-zero `./run.sh` (errexit), an early `exit 1`
# (auth abort, missing files, etc.), or any other failure path would
# leave macOS up, the Pod stuck Running, and the warm pool never
# refilling. The trap fires once on EXIT so the happy path
# (clean ./run.sh exit) and every error path halt the VM the
# same way.
trap '_rc=$?; echo "$(date -u +%FT%TZ) dispatch-poll: exiting (rc=${_rc}); halting VM"; sudo /sbin/shutdown -h now || true; exit "${_rc}"' EXIT

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
STATUS_SHARE="/Volumes/My Shared Files/status"
# Presigned PUT URL for this account's master archive (from the dispatch
# response); the HEAD report endpoint is the dispatch URL's sibling.
VOLUME_HEAD_UPLOAD=""
VOLUME_HEAD_REPORT_URL="${TUIST_RUNNER_DISPATCH_URL%/dispatch}/volume-head"

# cache_inventory hashes the SORTED ENTRY NAMES (not mtimes) under the cache
# subtrees whose churn means the job actually changed the cache: binaries
# added/evicted, manifests or ProjectDescriptionHelpers compiled. Pure cache
# hits only bump mtimes (they don't add/remove entries), so they don't move
# this hash — matching the reconciler's rule that mtime-only deltas are not
# dirty and must not trigger a promote that could clobber a concurrent writer.
cache_inventory() {
  [ -n "${CACHE_MOUNT}" ] || { echo "none"; return 0; }
  local root="${CACHE_MOUNT}/tuist"
  # LC_ALL=C: byte-order sort, so this agrees with the host's inventoryDigest
  # (Go sort.Strings is byte-wise). A locale collation here would order mixed-case
  # or punctuated hash names differently and make every convergence digest-mismatch.
  {
    for d in Binaries Manifests ProjectDescriptionHelpers Plugins; do
      /bin/ls -1 "${root}/${d}" 2>/dev/null | sed "s|^|${d}/|"
    done
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
      CACHE_INVENTORY_BEFORE=$(cache_inventory)
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  use_local_cold_cache "cache-ready not signalled within ${CACHE_READY_TIMEOUT}s"
}

# capture_cache_state snapshots the post-job inventory while the image is still
# MOUNTED — after the detach nothing inside it is readable. It records the
# inventory digest (which the host records beside a promoted master; the host
# cannot compute it itself without attaching) and remembers the inventory in
# CACHE_INVENTORY_AFTER for report_cache_dirty.
#
# It writes NO promotion authorization: cache-digest is only ever read by the
# host WHEN it promotes, so staging it before the detach is harmless. The marker
# that actually authorizes promotion (cache-dirty) is deliberately withheld until
# report_cache_dirty runs post-detach.
capture_cache_state() {
  [ -n "${CACHE_MOUNT}" ] || return 0
  [ -d "${STATUS_SHARE}" ] || return 0
  CACHE_INVENTORY_AFTER=$(cache_inventory)
  printf '%s' "${CACHE_INVENTORY_AFTER}" > "${STATUS_SHARE}/cache-digest" 2>/dev/null || true
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
# detach failure). It reads the inventory captured pre-detach by
# capture_cache_state, since the image is gone by now.
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
  VOLUME_HEAD_UPLOAD=$(sed -n 's/.*"upload_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /tmp/dispatch.json)
  [ -n "${download}" ] || return 0
  printf '{"generation":%s,"digest":"%s","download_url":"%s"}' \
    "${gen:-0}" "${digest}" "${download}" >"${STATUS_SHARE}/volume-head.json" 2>/dev/null || true
}

# VOLUME_HEAD_UPLOAD_TIMEOUT bounds the master upload. The image is sparse, so
# this transfers the cache actually written rather than the provisioned cap, but
# that is still GBs on a full working set — hence a far larger ceiling than the
# old zip's. It runs at teardown and holds the VM (and its warm-pool slot) open
# for its duration, so it stays bounded rather than generous-and-unbounded.
VOLUME_HEAD_UPLOAD_TIMEOUT=600

# report_volume_head publishes this job's warm set as the account's new HEAD on a
# successful, cache-changing job: it uploads the cache image to the presigned
# master URL and bumps the account's HEAD to the new inventory digest.
#
# The image is uploaded AS-IS, with no archiving step: it already carries the
# symlinks, xattrs and modes the cache needs, which is the whole reason the cache
# is an image. It must run AFTER detach_cache_image — a still-mounted image can
# be mid-write, and what gets uploaded here becomes every other host's master.
# Best-effort; never blocks teardown.
report_volume_head() {
  local rc="${1:-1}"
  [ "${rc}" = "0" ] || return 0
  [ -n "${CACHE_IMAGE_ACTIVE}" ] && [ -n "${VOLUME_HEAD_UPLOAD}" ] || return 0
  [ -n "${CACHE_INVENTORY_AFTER}" ] || return 0
  [ "${CACHE_INVENTORY_AFTER}" != "${CACHE_INVENTORY_BEFORE}" ] || return 0
  # This runs at teardown, after run.sh, before the EXIT trap halts the VM, so
  # both requests MUST be bounded — an object-storage stall here would otherwise
  # hang the script, keep the VM up, and stop the warm pool refilling. On any
  # timeout, HEAD just isn't advanced (best-effort) and teardown proceeds.
  #
  # No -L on the PUT: the presigned upload URL is written directly (no redirect),
  # so refuse to follow redirects — otherwise a compromised/misconfigured storage
  # endpoint could 307 the upload to an internal address and receive the image
  # body (SSRF), the write-side twin of the download guard.
  if ! curl -fsS --connect-timeout 10 --max-time "${VOLUME_HEAD_UPLOAD_TIMEOUT}" \
    -X PUT --upload-file "${CACHE_IMAGE}" "${VOLUME_HEAD_UPLOAD}" >/dev/null 2>&1; then
    echo "$(date -u +%FT%TZ) dispatch-poll: master image upload failed/timed out; HEAD not advanced"
    return 0
  fi
  curl -fsS --connect-timeout 10 --max-time 15 -X POST \
    -H "Authorization: Bearer ${SA_TOKEN}" -H "Content-Type: application/json" \
    --data "{\"tree_digest\":\"${CACHE_INVENTORY_AFTER}\"}" "${VOLUME_HEAD_REPORT_URL}" >/dev/null 2>&1 || true
  echo "$(date -u +%FT%TZ) dispatch-poll: published volume HEAD (digest=${CACHE_INVENTORY_AFTER})"
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
      [ -n "${watchdog_pid:-}" ] && kill "${watchdog_pid}" 2>/dev/null || true
      # Cache teardown. The order here is load-bearing:
      #   1. capture the inventory + digest, which only works while the image is
      #      still MOUNTED, but withhold the promotion-authorizing dirty marker;
      #   2. detach, so the image is a settled filesystem rather than a torn
      #      snapshot — the host clones this file to promote it and cannot tell
      #      the two apart, so letting the VM halt tear the mount down would
      #      poison the account's master and every job that later clones it;
      #   3. ONLY after a clean detach, authorize promotion (dirty marker) and
      #      upload the settled image as the account's new HEAD. A detach failure
      #      or an early exit leaves no dirty marker, so the host discards.
      # rc gates promotion — a failed run never advances the master.
      capture_cache_state
      if detach_cache_image; then
        report_cache_dirty "${rc}"
        report_volume_head "${rc}"
      else
        mark_cache_not_promotable "detach failed"
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
