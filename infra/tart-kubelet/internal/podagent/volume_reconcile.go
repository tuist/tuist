package podagent

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// runnerAccountLabel is the Pod label the Tuist server stamps at dispatch with
// the account id the job belongs to (see server serve_claim). It is the
// authoritative "which account did this VM actually run" signal used to
// promote a cache-volume branch to the right master.
const runnerAccountLabel = "tuist.dev/runner-account"

// runnerCacheVolumeLabel is the Pod label the Tuist server stamps at dispatch,
// in the same patch as runnerAccountLabel, with the job's cache volume. Like the
// account it is invisible to the guest, so a job cannot pick another
// repository's volume. Absent means ReservedTuistCacheVolume.
const runnerCacheVolumeLabel = "tuist.dev/runner-cache-volume"

// runnerCacheUntrustedLabel marks a Pod whose job the server could not
// positively confirm as trusted (same-repo, non-fork). When present, the host
// skips cache-volume materialize and promotion, so an untrusted fork job neither
// reads the account's warm master nor writes into it. Fail-closed on the server:
// any uncertainty stamps this label.
const runnerCacheUntrustedLabel = "tuist.dev/runner-cache-untrusted"

// RunnerAccountFromPod returns the account id the server stamped on a Pod at
// dispatch, or "" when unset. Exported so state recovery in package main can
// reconstruct a recovered VM's SourceAccount without duplicating the label key.
func RunnerAccountFromPod(pod *corev1.Pod) string {
	if pod == nil {
		return ""
	}
	return pod.Labels[runnerAccountLabel]
}

// RunnerCacheVolumeFromPod returns the Pod's cache volume, or false when the
// label is not a volume name and the job must not touch any master.
func RunnerCacheVolumeFromPod(pod *corev1.Pod) (string, bool) {
	if pod == nil {
		return ReservedTuistCacheVolume, true
	}
	volume, ok := pod.Labels[runnerCacheVolumeLabel]
	if !ok {
		return ReservedTuistCacheVolume, true
	}
	if !isVolumeName(volume) {
		return "", false
	}
	return volume, true
}

// RunnerCacheUntrusted reports whether the server marked this Pod's job as
// untrusted (a fork it could not confirm as same-repo). Exported so state
// recovery in package main can preserve the untrusted decision.
func RunnerCacheUntrusted(pod *corev1.Pod) bool {
	return pod != nil && pod.Labels[runnerCacheUntrustedLabel] == "true"
}

// ReattachVolumeForPod reconstructs the cache-volume attachment for a VM that
// survived a kubelet restart, on the volume the pod's label names. It preserves
// the untrusted decision: SourceAccount is set from the account label ONLY for a
// trusted pod with a well-formed volume. Any other branch is reattached (so its
// live virtio-fs mount isn't swept and it's cleaned at job end) but keeps
// SourceAccount empty, so Finalize's SourceAccount==account guard discards it —
// recovery can never revive attacker-controlled content into a master. Both
// recoverState and the createPod adoption path use this.
func ReattachVolumeForPod(volumes *VolumeManager, pod *corev1.Pod, vm string) (VolumeAttachment, bool) {
	volume, validVolume := RunnerCacheVolumeFromPod(pod)
	if !validVolume {
		volume = ReservedTuistCacheVolume
	}
	att, ok := volumes.ReattachBranch(volume, vm)
	if !ok {
		return VolumeAttachment{}, false
	}
	if validVolume && !RunnerCacheUntrusted(pod) {
		att.SourceAccount = RunnerAccountFromPod(pod)
	}
	return att, true
}

// dirtyMarkerFile is the file the guest writes into the writable status share
// at job end: "1" when the job changed the cache (artifacts added/evicted,
// manifests or helpers compiled), "0" for a pure-hit/read-only job. Its
// absence means the guest never completed (crashed job) and the branch is
// discarded.
const dirtyMarkerFile = "cache-dirty"

// runnerExitFile is the file the guest writes into the writable status
// share from its EXIT trap, carrying dispatch-poll.sh's exit code. It is
// the only way that code reaches the host: the trap halts the VM on every
// path, so `tart run` exits zero whether the job finished or the runner
// died, and its status cannot distinguish the two.
//
// Absent for a guest killed without running its trap, and for any host
// where the status share is not attached at all (it rides on the cache
// volume feature). Absence therefore means "unknown", never "clean" —
// see runnerTermination.
const runnerExitFile = "runner-rc"

// runnerLogFile is dispatch-poll.sh's own output, mirrored into the
// writable status share by the guest so it outlives the VM. The copy
// inside the guest (/var/log/tuist-runner/poll.log) dies with the VM at
// teardown, and Tart cannot capture a macOS guest's console, so without
// this the host has an exit code and nothing that explains it.
//
// That gap is not academic: the trap reports 0 both for a finished job
// and for a runner that halted without ever taking one, so the exit code
// alone cannot tell those apart. This file is what does.
//
// Absent for the same two reasons as runnerExitFile — a guest killed
// before its trap ran, and hosts with no status share attached at all.
const runnerLogFile = "runner.log"

// runnerLogTailLines / runnerLogTailBytes bound what publishRunnerLog
// re-emits. dispatch-poll.sh is quiet by design — the job's own output
// goes to GitHub server-side, so this log is warm-standby ticks plus the
// cache teardown trail — but the file is guest-writable, so it is bounded
// rather than trusted.
const (
	runnerLogTailLines = 200
	runnerLogTailBytes = 64 << 10
)

// openGuestFile opens a file the guest wrote into the status share and requires
// it to be a plain file. Both the path and its contents are attacker-chosen: the
// share is writable by the guest, and the guest runs untrusted customer CI.
// O_NOFOLLOW stops a guest-planted symlink from making the host resolve and read
// some other file on its behalf. O_NONBLOCK stops a FIFO from parking the caller
// inside the open until something writes to the other end, which nothing ever
// does: one job could otherwise wedge a reconcile for as long as it liked. The
// regular-file check cannot stand in for O_NONBLOCK there, because it never runs
// if the open never returns.
//
// Returns the handle and its stat together, so a reader that wants metadata
// rather than bytes fstats what it already opened instead of racing a second
// path lookup against the guest.
func openGuestFile(statusDir, name string) (*os.File, os.FileInfo, bool) {
	if statusDir == "" {
		return nil, nil, false
	}
	f, err := os.OpenFile(
		filepath.Join(statusDir, name),
		os.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK,
		0,
	)
	if err != nil {
		return nil, nil, false
	}
	fi, err := f.Stat()
	if err != nil || !fi.Mode().IsRegular() {
		f.Close()
		return nil, nil, false
	}
	return f, fi, true
}

// guestMarkerMaxBytes bounds the scalar markers: an exit code, a percentage, a
// millisecond count, a promote outcome. Set orders of magnitude above anything
// the guest legitimately writes, so it binds only on a file the host has no
// reason to be holding in memory in the first place.
const guestMarkerMaxBytes = 4 << 10

// guestHeadMaxBytes bounds volume-head.json, whose presigned download URL is the
// one field that is not a handful of bytes.
const guestHeadMaxBytes = 64 << 10

// readGuestFile returns the bytes of a guest-written status file, or false when
// the guest left something other than a plain file. Oversize reads as absent
// rather than truncated: every caller parses a whole value, and half of one is
// not a value.
func readGuestFile(statusDir, name string, maxBytes int64) ([]byte, bool) {
	f, _, ok := openGuestFile(statusDir, name)
	if !ok {
		return nil, false
	}
	defer f.Close()

	b, err := io.ReadAll(io.LimitReader(f, maxBytes+1))
	if err != nil || int64(len(b)) > maxBytes {
		return nil, false
	}
	return b, true
}

// readRunnerExit reads the guest-reported exit code from the status share.
// The bool is false when the guest reported nothing usable.
//
// A wait status is a byte, and the shell reports 128+signal for a
// signalled child, so anything outside 0-255 did not come from `$?` and
// is a torn or truncated read of a file the guest was still writing.
// Rejecting it matters more than it looks: the value decides clean
// versus abnormal downstream, so a garbage read that happened to land on
// 0 would report a dead runner as a successful job, which is the bug
// this file exists to close. Out of range therefore reads as unreported,
// the same as no file at all.
func readRunnerExit(statusDir string) (int32, bool) {
	b, ok := readGuestFile(statusDir, runnerExitFile, guestMarkerMaxBytes)
	if !ok {
		return 0, false
	}
	// ParseInt over Atoi so an oversized value fails here rather than
	// silently wrapping on the conversion to int32.
	code, err := strconv.ParseInt(strings.TrimSpace(string(b)), 10, 32)
	if err != nil || code < 0 || code > 255 {
		return 0, false
	}
	return int32(code), true
}

// readRunnerLog returns a bounded tail of the guest's mirrored log, or
// "" when there is nothing usable. Callers re-emit it to tart-kubelet's
// own stdout before teardown deletes the share.
//
// Tail rather than head: the interesting part of a runner that gave up
// is what it said last. Bounded twice because the file is guest-written
// — by bytes first so a single pathological line cannot blow up the log
// record, then by lines.
//
// Read through openGuestFile, which is what keeps a guest-planted
// symlink or FIFO at this path from being followed. The stake is highest
// here of all the status-share readers: this one's output goes to Loki,
// so a followed symlink publishes up to runnerLogTailBytes of a
// host-readable file the guest chose.
func readRunnerLog(statusDir string) string {
	f, fi, ok := openGuestFile(statusDir, runnerLogFile)
	if !ok {
		return ""
	}
	defer f.Close()

	offset := int64(0)
	if fi.Size() > runnerLogTailBytes {
		offset = fi.Size() - runnerLogTailBytes
	}
	b := make([]byte, fi.Size()-offset)
	if _, err := f.ReadAt(b, offset); err != nil {
		return ""
	}

	lines := strings.Split(strings.TrimRight(string(b), "\n"), "\n")
	// A byte-bounded read almost certainly starts mid-line; drop that
	// fragment so the tail begins on a real record.
	if offset > 0 && len(lines) > 1 {
		lines = lines[1:]
	}
	if len(lines) > runnerLogTailLines {
		lines = lines[len(lines)-runnerLogTailLines:]
	}
	return strings.Join(lines, "\n")
}

// readRunnerExitTime returns when the guest wrote its exit report, which
// is the moment it halted. Used to date a stop on the recovered path,
// where no `tart run` handle survived to have observed the exit itself.
func readRunnerExitTime(statusDir string) (time.Time, bool) {
	f, fi, ok := openGuestFile(statusDir, runnerExitFile)
	if !ok {
		return time.Time{}, false
	}
	defer f.Close()
	return fi.ModTime(), true
}

// runnerHeartbeatFile is the guest's liveness beat: dispatch-poll.sh
// rewrites it once per poll while it is warm, and once more when it takes
// a job. The contents are the state it is in; the mtime is the beat.
//
// It exists because a macOS Pod's Ready condition says only that the VM
// process is up and has an IP. tart-kubelet runs no container probes, so
// a guest whose poller died still reads 1/1 Running indefinitely and the
// runners-controller goes on counting it as warm capacity that can never
// take a job. Linux needs none of this: its poller is an init container,
// so the container runtime already reports whether it is running.
//
// Absent on hosts with no status share, and on runner images from before
// the guest wrote it. Both must read as "no signal" rather than "dead" —
// see publishRunnerHeartbeat.
const runnerHeartbeatFile = "runner-heartbeat"

// Heartbeat states dispatch-poll.sh writes. Anything else is a guest
// writing something we do not model, which reads as no signal at all
// rather than as a state to act on.
const (
	heartbeatStatePolling = "polling"
	heartbeatStateClaimed = "claimed"
)

// readRunnerHeartbeat returns the guest's last beat: the state it reported
// and the mtime of the report.
//
// The mtime is the host's, not the guest's — the write lands on the host
// filesystem through virtio-fs, so the host kernel stamps it, which is
// what makes it comparable to the host clock here. readRunnerExitTime
// dates a runner's halt off the same property.
//
// An unrecognized state reads as no beat. The file is guest-written and
// the states drive whether the controller counts this Pod as capacity, so
// the set is closed rather than passed through.
func readRunnerHeartbeat(statusDir string) (string, time.Time, bool) {
	f, fi, ok := openGuestFile(statusDir, runnerHeartbeatFile)
	if !ok {
		return "", time.Time{}, false
	}
	defer f.Close()

	b, err := io.ReadAll(io.LimitReader(f, guestMarkerMaxBytes+1))
	if err != nil || int64(len(b)) > guestMarkerMaxBytes {
		return "", time.Time{}, false
	}
	switch state := strings.TrimSpace(string(b)); state {
	case heartbeatStatePolling, heartbeatStateClaimed:
		return state, fi.ModTime(), true
	default:
		return "", time.Time{}, false
	}
}

// cacheReadyFile is the marker the host writes into the writable status share
// once it has materialized the dispatched account's cache into the VM's branch
// (or determined there is no master to materialize — a cold first job).
// dispatch-poll.sh waits (bounded) for it before starting the runner so the
// guest never reads or writes the cache while the host is still clonefiling it.
const cacheReadyFile = "cache-ready"

// cacheBudgetFile carries the binary cache's share of the fixed split, which a
// runner image older than sharedCacheBudgetFile exports as TUIST_CACHE_MAX_BYTES
// for the CLI's LRU self-prune. Staged by the host because the guest sees the
// whole shared quota volume's free space over the virtio-fs share, which would be
// a far-too-large budget.
const cacheBudgetFile = "cache-max-bytes"

// sharedCacheBudgetFile carries what the binary cache and the compilation cache
// may hold together (cacheImageBudget). The guest divides it between them by
// what each holds, at attach and again at teardown, so this is the one figure the
// host decides. cacheBudgetFile and the casEnabledFile figure stay staged beside
// it, because tart-kubelet and the runner image roll out separately and an older
// image reads only those.
const sharedCacheBudgetFile = "cache-budget-bytes"

// allocateVolumeBranch prepares an empty per-VM cache branch directory for a
// booting VM (shared into the guest as a virtio-fs mount), or returns an
// un-attached zero value when the feature is off or the root is not mounted. The
// branch is filled, and admitted, later by maybeMaterializeVolume, once dispatch
// has bound the VM to an account.
func (r *Reconciler) allocateVolumeBranch(vmName string) (VolumeAttachment, error) {
	if r.Volumes == nil || !r.Volumes.Enabled() {
		return VolumeAttachment{}, nil
	}
	return r.Volumes.AllocateBranch(ReservedTuistCacheVolume, vmName)
}

// maybeMaterializeVolume clonefiles the dispatched job's cache master, for its
// account and volume, into this VM's branch and signals the guest, exactly once
// per VM. The Tuist server stamps the pod's runner-account and cache-volume
// labels when it claims a job, so this runs on the reconcile that observes them —
// the account and volume are known before any cache bytes reach the VM, which is
// what makes the shared-host model safe. A cold first job (no master yet) still
// writes cache-ready so the guest stops waiting; its writes become the volume's
// first master at Finalize.
func (r *Reconciler) maybeMaterializeVolume(pod *corev1.Pod) {
	if r.Volumes == nil {
		return
	}
	entry := r.Store.Get(pod.Namespace, pod.Name)
	if entry == nil || !entry.Volume.Attached || entry.Volume.Materialized {
		return
	}
	account := pod.Labels[runnerAccountLabel]
	if account == "" {
		return // not dispatched yet — nothing to materialize
	}

	// Fork-exclusion: an untrusted job never touches the shared cache. It gets an
	// EMPTY image rather than a master, and SourceAccount stays empty so
	// Finalize's SourceAccount==account guard discards the branch — the job can
	// neither read a warm master nor promote into it. It still needs an image of
	// its own: cache-ready tells the guest to attach, and signalling without one
	// would drop every fork job onto the local cold cache. A malformed volume
	// label is isolated the same way.
	volume, validVolume := RunnerCacheVolumeFromPod(pod)
	if !validVolume {
		log.Log.WithName("volume").Info("cache volume label is not a volume name; running the job on an empty image",
			"vm", entry.VMName, "account", account, "volume", pod.Labels[runnerCacheVolumeLabel])
	}
	if pod.Labels[runnerCacheUntrustedLabel] == "true" || !validVolume {
		if err := r.Volumes.MaterializeEmpty(entry.Volume); err != nil && !errors.Is(err, errAdmissionDeclined) {
			log.Log.WithName("volume").Error(err, "create empty cache image for untrusted job", "vm", entry.VMName)
		}
		entry.Volume.Materialized = true
		// Mark it on disk too, not just in memory: without the marker a kubelet
		// restart re-enters here and recreates the image while the guest still has
		// it mounted.
		r.Volumes.MarkMaterialized(entry.Volume)
		r.writeCASEnabled(entry.VolumeStatusDir)
		writeCacheReady(entry.VolumeStatusDir)
		return
	}

	// Materialize this host's LOCAL master into the branch immediately — a CoW
	// clonefile that touches the network zero times (~tens of ms) — and signal
	// the guest, so the job starts warm without ever blocking on a download.
	// A declined branch has no image, so the guest's attach fails and it runs on
	// its local cold cache. That is logged and counted where admission declines.
	entry.Volume.VolumeName = volume
	source, baseGeneration, err := r.Volumes.Materialize(entry.Volume, account)
	declined := errors.Is(err, errAdmissionDeclined)
	if err != nil && !declined {
		log.Log.WithName("volume").Error(err, "materialize cache volume", "vm", entry.VMName, "account", account, "volume", volume)
	}
	entry.Volume.SourceAccount = account
	entry.Volume.Materialized = true
	// Stage the base generation the branch was cloned from into the status share.
	// The guest sends it back at promote, and the server accepts the HEAD
	// fast-forward only if HEAD is still at this generation — so a job that built
	// on a stale master cannot clobber a newer HEAD.
	writeBaseGeneration(entry.VolumeStatusDir, baseGeneration)
	// Drop the host-written materialization marker so a kubelet restart can tell
	// this (materialized) branch from an idle VM's boot-created empty cache dir.
	r.Volumes.MarkMaterialized(entry.Volume)
	// Point the guest at the folded CAS store (before cache-ready, no race).
	r.writeCASEnabled(entry.VolumeStatusDir)
	// Signal the guest the cache is ready (warm or cold) so its bounded wait
	// releases and the job runs.
	writeCacheReady(entry.VolumeStatusDir)
	// One line per job, with the account the materialize counter cannot carry,
	// so warm rates can be compared per account: the fleet-wide rate moves with
	// the mix of accounts as much as with anything the host does.
	result := string(source)
	if declined {
		result = "declined"
	}
	log.Log.WithName("volume").Info("materialized cache volume",
		"vm", entry.VMName, "account", account, "volume", volume, "result", result, "base_generation", baseGeneration)
	// A declined job was refused space in this volume, and converging downloads
	// into the same volume with nothing reserved.
	if declined {
		return
	}
	RecordVolumeMaterialized(source)

	// Queue the volume's HEAD for the host's converge worker, off the job-start
	// critical path. The running job already holds its own CoW branch, so
	// refreshing the master never touches the job in flight — it makes the NEXT
	// job on this host start from the volume's current warm set.
	go r.queueConvergence(entry.VMName, entry.VolumeStatusDir, entry.Volume.VolumeName, account)
}

// writeCacheReady drops the cache-ready marker into the writable status share.
// dispatch-poll.sh blocks (bounded) on this file before starting the runner so
// the guest never touches the cache mid-materialization.
func writeCacheReady(statusDir string) {
	if statusDir == "" {
		return
	}
	_ = os.WriteFile(filepath.Join(statusDir, cacheReadyFile), []byte("1"), 0o644)
}

const (
	// cacheVolumeReserveFloorGiB / cacheVolumeReservePercent size the space kept
	// free in the cache image when both caches are at their limits: reserve =
	// max(floor, percent of cap). It is the room a job has to grow into before
	// anything prunes, since the compilation cache is pruned only at attach and
	// teardown, and it also covers APFS metadata and CoW headroom. The floor keeps
	// a real slice on a small cap. The binary cache and the folded CAS share the
	// rest: 24 GiB at cap 30, with 6 GiB of room.
	cacheVolumeReserveFloorGiB = 2
	cacheVolumeReservePercent  = 20
)

// cacheImageBudget is what the binary cache and the folded CAS may hold together
// in a capGiB cache image: the cap less the reserve.
func cacheImageBudget(capGiB int) uint64 {
	if capGiB <= 0 {
		return 0
	}
	const gib = uint64(1024 * 1024 * 1024)
	capBytes := uint64(capGiB) * gib
	reserve := uint64(cacheVolumeReserveFloorGiB) * gib
	if pct := capBytes * cacheVolumeReservePercent / 100; pct > reserve {
		reserve = pct
	}
	if reserve > capBytes/2 {
		reserve = capBytes / 2 // a tiny cap never reserves more than half
	}
	return capBytes - reserve
}

// cacheImageSplit divides cacheImageBudget at a fixed point, for runner images
// that predate the guest's division by use. It returns the binary cache's byte
// budget (TUIST_CACHE_MAX_BYTES) and the CAS's allowance (0 when the CAS is off),
// which add up to the budget, so the two independent pruners cannot over-commit
// the one image to ENOSPC. A CASGiB set larger than the budget is clamped so the
// binary cache always keeps a slice. At cap 30 / cas 14 that is 10 GiB for the
// binary cache and 14 GiB for the compilation cache.
//
// The CAS figure is both what the store may occupy and the limit the compiler
// and the prune are given: llcas, and `prune_store`, rotate a store once its
// primary passes HALF the limit, so the limit already covers the primary and the
// upstream generation it demoted.
func cacheImageSplit(capGiB, casGiB int) (binaryBytes, casBytes uint64) {
	usable := cacheImageBudget(capGiB)
	if usable == 0 || casGiB <= 0 {
		return usable, 0
	}
	const gib = uint64(1024 * 1024 * 1024)
	casBytes = uint64(casGiB) * gib
	if maxCAS := usable * 90 / 100; casBytes > maxCAS {
		casBytes = maxCAS // oversized CASGiB: keep the binary cache a ≥10% slice
	}
	binaryBytes = usable - casBytes
	return binaryBytes, casBytes
}

// writeCacheBudget stages the budget both caches share, and the binary cache's
// share of the fixed split for runner images that read only that, into the status
// share before the VM boots.
func writeCacheBudget(statusDir string, capGiB, casGiB int) {
	if statusDir == "" || capGiB <= 0 {
		return
	}
	budget, _ := cacheImageSplit(capGiB, casGiB)
	_ = os.WriteFile(filepath.Join(statusDir, cacheBudgetFile), []byte(strconv.FormatUint(budget, 10)), 0o644)
	_ = os.WriteFile(filepath.Join(statusDir, sharedCacheBudgetFile), []byte(strconv.FormatUint(cacheImageBudget(capGiB), 10)), 0o644)
}

// casEnabledFile signals the guest to point the compiler at the folded CAS store
// inside the mounted cache image. Written (before cache-ready, so the guest never
// races it) only when the feature is on; absent ⇒ the guest leaves the
// compilation cache VM-local.
const casEnabledFile = "cas-enabled"

func (r *Reconciler) writeCASEnabled(statusDir string) {
	if statusDir == "" || r.Volumes == nil || !r.Volumes.casEnabled() {
		return
	}
	// The marker's presence turns the folded CAS on. Its figure is the CAS's share
	// of the fixed split (the other half of writeCacheBudget's, from the same
	// cacheImageSplit so the two can't drift), which only a runner image older
	// than sharedCacheBudgetFile applies. A newer one divides the shared budget
	// by use instead. Either way the guest emits the figure as
	// COMPILATION_CACHE_LIMIT_SIZE — an absolute bound, not a percent, because
	// Swift Build's LIMIT_PERCENT is against the cache-db size plus free space,
	// which shrinks as the binary cache fills — and prunes to the same value, so
	// the bound the build is told to keep is the one that is enforced.
	_, casBytes := cacheImageSplit(r.Volumes.CapGiB, r.Volumes.CASGiB)
	_ = os.WriteFile(filepath.Join(statusDir, casEnabledFile), []byte(strconv.FormatUint(casBytes, 10)), 0o644)
}

// uploadMillisFile carries the wall-clock ms the guest teardown spent uploading
// the cache image as the account HEAD. That upload blocks the VM halt, so it is
// how long a promoting job held the host slot.
const uploadMillisFile = "volume-upload-ms"

// readUploadMillis returns the guest-reported upload duration in ms, or -1 when
// absent (no promote, or the job did not upload).
func readUploadMillis(statusDir string) int64 {
	b, ok := readGuestFile(statusDir, uploadMillisFile, guestMarkerMaxBytes)
	if !ok {
		return -1
	}
	ms, err := strconv.ParseInt(strings.TrimSpace(string(b)), 10, 64)
	if err != nil {
		return -1
	}
	return ms
}

// fillPercentFile carries the cache image mount's post-job fill % (binary cache +
// CAS + overhead), sampled by the guest while still mounted. It is the signal for
// whether the reserve is holding or the volume runs near ENOSPC — the missing
// observation that makes the reserve tunable from data rather than from failures.
const fillPercentFile = "cache-fill-percent"

// readFillPercent returns the guest-reported image fill %, or -1 when absent.
func readFillPercent(statusDir string) int {
	b, ok := readGuestFile(statusDir, fillPercentFile, guestMarkerMaxBytes)
	if !ok {
		return -1
	}
	pct, err := strconv.Atoi(strings.TrimSpace(string(b)))
	if err != nil || pct < 0 || pct > 100 {
		return -1
	}
	return pct
}

// cacheLimitsFile carries what the guest's division of the shared budget
// measured and decided: one "<when>\t<cache>\t<held bytes>\t<limit bytes>" line
// per cache, appended at attach and again at teardown. Those sizes are the only
// per-cache measurement the fleet has, and the limits beside them are what the
// division's rule and its floors are retuned from. The runner log carries the
// same numbers, but the host re-emits only a bounded tail of it, so a verbose
// job's attach lines fall off before they reach the log store.
const cacheLimitsFile = "cache-limits"

// cacheLimitsMaxSamples bounds what one job can make the host record. A division
// stages four lines; the file is guest-written and the guest runs untrusted
// customer CI.
const cacheLimitsMaxSamples = 8

// cacheLimitSample is one cache's size and limit at one end of a job.
type cacheLimitSample struct {
	when, cache           string
	heldBytes, limitBytes float64
}

// readCacheLimits returns what the guest staged, dropping every line that is not
// a measurement. A job that ran on a host staging the fixed split stages nothing,
// which reads as none.
func readCacheLimits(statusDir string) []cacheLimitSample {
	b, ok := readGuestFile(statusDir, cacheLimitsFile, guestMarkerMaxBytes)
	if !ok {
		return nil
	}
	var samples []cacheLimitSample
	for _, line := range strings.Split(string(b), "\n") {
		fields := strings.Split(strings.TrimSpace(line), "\t")
		if len(fields) != 4 {
			continue
		}
		when, cache := fields[0], fields[1]
		if when != "attach" && when != "teardown" {
			continue
		}
		if cache != "binary" && cache != "compilation" {
			continue
		}
		held, err := strconv.ParseUint(fields[2], 10, 64)
		if err != nil {
			continue
		}
		limit, err := strconv.ParseUint(fields[3], 10, 64)
		if err != nil {
			continue
		}
		samples = append(samples, cacheLimitSample{
			when:       when,
			cache:      cache,
			heldBytes:  float64(held),
			limitBytes: float64(limit),
		})
		if len(samples) == cacheLimitsMaxSamples {
			break
		}
	}
	return samples
}

// baseGenerationFile carries the HEAD generation the branch was clonefiled from,
// staged by the host at materialize. The guest sends it as the fast-forward base
// at promote so the server accepts the bump only if HEAD is still at it.
const baseGenerationFile = "cache-base-generation"

// writeBaseGeneration stages the branch's base generation for the guest to relay
// at promote. Always written (even 0 for a cold branch) so the guest sends a
// definite base rather than guessing.
func writeBaseGeneration(statusDir string, generation int) {
	if statusDir == "" {
		return
	}
	_ = os.WriteFile(filepath.Join(statusDir, baseGenerationFile), []byte(strconv.Itoa(generation)), 0o644)
}

// nodeNameFile carries this host's Kubernetes Node name into the writable status
// share. The guest relays it with its promote report, which is how a HEAD row
// records the host that published it — the only attribution the fleet has for a
// generation once it stands. It is the Node name rather than the Pod name
// deliberately: the Pod is gone minutes later, whereas the Node name is what the
// `tuist.dev/cache-master-<account>` advertisements and the volume affinities are
// keyed on, so a HEAD can be traced back to the host still holding its master.
//
// Staged at VM create alongside the branch budget, not at materialize: it is a
// property of the host, constant for the VM's whole life, and known before
// dispatch binds the VM to an account.
const nodeNameFile = "node-name"

// writeNodeName stages the host's Node name for the guest to relay at promote.
// Best-effort, like every other host to guest signal here: an unstaged name
// leaves the attribution field empty, which is exactly the status quo.
func writeNodeName(statusDir, nodeName string) {
	if statusDir == "" || nodeName == "" {
		return
	}
	_ = os.WriteFile(filepath.Join(statusDir, nodeNameFile), []byte(nodeName), 0o644)
}

// promoteResultFile carries the outcome of this job's HEAD fast-forward, written
// by the guest after the bump. It distinguishes the three cases the host must not
// conflate: "accepted <generation>" (200 — install the branch as the local master
// at that generation), "conflict" (409 — a stale base another host advanced past,
// genuine cross-host contention), and "error" (an upload/network/control-plane
// failure). Absent means the guest never reached the bump (also treated as an
// error for an otherwise promote-eligible job). Only "accepted" installs; the
// rest discard and re-converge.
const promoteResultFile = "cache-promote-result"

// promoteResult is the parsed guest outcome. Result is "accepted", "conflict",
// "error", or "" (absent). Generation is the accepted HEAD generation, non-zero
// only when Result == "accepted".
type promoteResult struct {
	Result     string
	Generation int
}

// readPromoteResult parses the guest-relayed promote outcome.
func readPromoteResult(statusDir string) promoteResult {
	b, ok := readGuestFile(statusDir, promoteResultFile, guestMarkerMaxBytes)
	if !ok {
		return promoteResult{}
	}
	fields := strings.Fields(string(b))
	if len(fields) == 0 {
		return promoteResult{}
	}
	switch fields[0] {
	case "accepted":
		gen := 0
		if len(fields) > 1 {
			if g, err := strconv.Atoi(fields[1]); err == nil && g > 0 {
				gen = g
			}
		}
		return promoteResult{Result: "accepted", Generation: gen}
	case "conflict":
		return promoteResult{Result: "conflict"}
	default:
		return promoteResult{Result: "error"}
	}
}

// volumeHeadFile carries the account's cache-volume HEAD (generation, inventory
// digest, presigned download URL for the latest master archive) that the guest
// echoes from its dispatch response into the status share, so the host can
// converge a stale master toward it before materializing.
const volumeHeadFile = "volume-head.json"

type volumeHead struct {
	Generation int    `json:"generation"`
	Digest     string `json:"digest"`
	// ContentDigest is the SHA-256 of the master object's bytes, published by
	// the promoting guest alongside the inventory digest. Empty for a HEAD
	// promoted by a runner image that predates the content hash, in which case
	// the convergence skips the content check (the status quo).
	ContentDigest string `json:"content_digest"`
	DownloadURL   string `json:"download_url"`
}

func readVolumeHead(statusDir string) *volumeHead {
	b, ok := readGuestFile(statusDir, volumeHeadFile, guestHeadMaxBytes)
	if !ok {
		return nil
	}
	var h volumeHead
	if err := json.Unmarshal(b, &h); err != nil {
		return nil
	}
	return &h
}

// queueConvergence hands the volume's HEAD, as the job's guest relays it, to the
// host's converge worker, which fast-forwards the master off every job's
// critical path. Runs in the background of materialize: it waits for the guest
// to stage the HEAD, then returns. Takes plain values, not the shared *Entry, so
// it can't race the reconciler mutating that entry.
func (r *Reconciler) queueConvergence(vmName, statusDir, volumeName, account string) {
	if r.Volumes == nil || !r.Volumes.Enabled() || r.Converge == nil {
		return
	}
	// Wait (bounded) for the guest to stage the HEAD. The guest writes
	// volume-head.json only after it receives the dispatch response, which the
	// server returns after stamping the label that triggered this, so the file
	// lands a beat later than this goroutine starts.
	logger := log.Log.WithName("volume")
	head := awaitVolumeHead(statusDir, r.ConvergeHeadWaitInterval, r.ConvergeHeadWaitAttempts)
	// Each of these three used to share one silent `return`, which made the most
	// likely reason a convergence does not happen indistinguishable from the
	// other two — and from convergence never having been attempted. They have
	// nothing in common: the first is the guest or the wait, the second is an
	// account that has published nothing yet, the third is the server
	// deliberately withholding the HEAD from an untrusted job.
	switch {
	case head == nil:
		logger.Info("converge: guest never staged the volume HEAD; skipping",
			"vm", vmName, "account", account, "volume", volumeName)
		return
	case head.Generation <= 0:
		logger.Info("converge: account has no published HEAD yet; skipping",
			"vm", vmName, "account", account, "volume", volumeName)
		return
	case head.DownloadURL == "":
		logger.Info("converge: HEAD carries no download URL (untrusted job?); skipping",
			"vm", vmName, "account", account, "volume", volumeName, "generation", head.Generation)
		return
	}
	key := masterKey{account: account, volume: volumeName}
	// A job dispatched with a HEAD this host already proved does not reproduce
	// its digests relays that proof with its promote. The converge worker
	// usually runs after the job that first relayed the HEAD has gone, so a
	// later job with the same HEAD is what lets the server retire it.
	r.Converge.RelayDisproof(key, *head, statusDir)
	// The healthy no-op, logged so it can be told apart from a convergence that
	// failed or never ran. The worker checks again before it downloads, since a
	// promote can land in between.
	if local, err := r.Volumes.MasterGeneration(account, volumeName); err == nil && local >= head.Generation {
		logger.Info("converge: host already at or past the HEAD; nothing to adopt",
			"vm", vmName, "account", account, "volume", volumeName,
			"local_generation", local, "head_generation", head.Generation)
		return
	}
	r.Converge.Enqueue(convergeRequest{
		key:       key,
		head:      *head,
		source:    convergeSourceJob,
		statusDir: statusDir,
	})
}

// unverifiableHeadFile carries, into the writable status share, the HEAD digest
// this host downloaded and found the object does not reproduce. The guest relays
// it with its promote report, which is what lets the server retire a HEAD nothing
// can adopt.
//
// The status share is the established host→guest direction (cache-ready, the
// branch budget, the base generation all travel this way) and the host has no
// server credentials of its own, so this is how host-observed evidence reaches
// the control plane. Best-effort: an account that stays wedged one more job is
// the status quo, whereas failing the convergence here would cost the job.
const unverifiableHeadFile = "volume-head-unverifiable"

func stageUnverifiableHead(statusDir, digest string) {
	if statusDir == "" || digest == "" {
		return
	}
	_ = os.WriteFile(filepath.Join(statusDir, unverifiableHeadFile), []byte(digest), 0o644)
}

// convergeHeadWaitInterval / convergeHeadWaitAttempts bound how long the
// background convergence waits for the guest to stage the HEAD before giving
// up (best-effort; the next job on this host converges instead).
const (
	convergeHeadWaitInterval = 1 * time.Second
	convergeHeadWaitAttempts = 15
)

// awaitVolumeHead polls the status share for the guest-staged HEAD, returning
// as soon as it appears or nil once the bound elapses. Interval and attempts are
// parameters so tests do not wait real seconds, mirroring the manager's
// mount-check wait.
func awaitVolumeHead(statusDir string, interval time.Duration, attempts int) *volumeHead {
	if interval <= 0 {
		interval = convergeHeadWaitInterval
	}
	if attempts <= 0 {
		attempts = convergeHeadWaitAttempts
	}
	for i := 0; i < attempts; i++ {
		if h := readVolumeHead(statusDir); h != nil {
			return h
		}
		time.Sleep(interval)
	}
	return readVolumeHead(statusDir)
}

// fileSHA256 returns the lowercase hex SHA-256 of the file's bytes — the same
// digest the promoting guest computed over its settled image and the object
// store verified at ingest, so all three measure the identical byte stream.
func fileSHA256(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	noPageCache(f)
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// finalizeVolume promotes or discards the entry's cache-volume branch and
// marks it consumed so the call is idempotent across the multiple teardown
// paths (terminal transition, Pod deletion, best-effort cleanup). cleanExit
// reflects whether `tart run` exited cleanly (the VM halted, not the job's
// conclusion); the guest's dirty marker carries the actual job result — it is
// "1" only when the runner exited 0 AND the cache changed — so promotion needs
// both a clean VM halt and a marker that says the job succeeded and was dirty.
func (r *Reconciler) finalizeVolume(entry *Entry, actualAccount string, cleanExit bool) {
	if r.Volumes == nil || entry == nil || !entry.Volume.Attached {
		return
	}
	present, dirty := readDirtyMarker(entry.VolumeStatusDir)
	succeeded := cleanExit && present
	// The guest-relayed outcome of the HEAD fast-forward. Only "accepted" carries a
	// generation to install the branch at; "conflict"/"error"/absent discard the
	// branch rather than moving the local master off the accepted lineage.
	promote := readPromoteResult(entry.VolumeStatusDir)
	entry.Volume.PromotedGeneration = promote.Generation

	// For a promote-eligible job (it did cache-changing work for its own account),
	// record the server's decision. "rejected" is reserved for an actual 409
	// (stale-base contention); an upload/network/control-plane failure — or an
	// absent result for an otherwise-eligible job — is "error", so a storage
	// outage does not masquerade as cache races. Read-only, failed, and
	// account-mismatched jobs never promote and are excluded from the ratio.
	if succeeded && dirty && actualAccount != "" && entry.Volume.SourceAccount == actualAccount {
		switch promote.Result {
		case "accepted":
			RecordVolumePromote("accepted")
		case "conflict":
			RecordVolumePromote("rejected")
		default:
			RecordVolumePromote("error")
		}
	}

	// The CAS store is folded into the cache image, so it promotes as part of the
	// one image below — no separate CAS finalize. A compile-only job still
	// persists its CAS because its growth flips the inventory digest (via the CAS
	// size line) → dirty → the whole image promotes.
	outcome, err := r.Volumes.Finalize(entry.Volume, actualAccount, succeeded, dirty)
	if err != nil {
		log.Log.WithName("volume").Error(err, "finalize cache volume", "vm", entry.VMName, "account", actualAccount)
	}
	RecordVolumeOutcome(string(outcome))
	// Record how long the guest's HEAD upload blocked teardown (and thus slot
	// reclaim), if it uploaded — the signal for keeping the volume sized so the
	// folded-in CAS doesn't make uploads slow.
	if ms := readUploadMillis(entry.VolumeStatusDir); ms >= 0 {
		RecordVolumeUpload(ms)
	}
	// Record how full the image got this job — the ENOSPC-pressure signal for
	// tuning the reserve/split from observation instead of from build failures.
	if pct := readFillPercent(entry.VolumeStatusDir); pct >= 0 {
		RecordVolumeFill(pct)
	}
	// Record what the guest's division measured and decided. Nothing else reports
	// what either cache in the image actually holds.
	RecordVolumeCacheLimits(readCacheLimits(entry.VolumeStatusDir))

	// Consumed: the branch has been renamed away (promote) or removed
	// (discard). Clear the flag so a later teardown path does not re-run
	// Finalize against a path that no longer exists.
	entry.Volume.Attached = false
}

// readDirtyMarker reads the guest's dirty marker from the status share.
// Returns (present, dirty): present is false when the guest never wrote it
// (crashed / incomplete job), which the caller treats as "discard".
func readDirtyMarker(statusDir string) (present, dirty bool) {
	b, ok := readGuestFile(statusDir, dirtyMarkerFile, guestMarkerMaxBytes)
	if !ok {
		return false, false
	}
	return true, strings.TrimSpace(string(b)) == "1"
}
