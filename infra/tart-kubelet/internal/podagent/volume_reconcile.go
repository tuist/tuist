package podagent

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// runnerAccountLabel is the Pod label the Tuist server stamps at dispatch with
// the account id the job belongs to (see server serve_claim). It is the
// authoritative "which account did this VM actually run" signal used to
// promote a cache-volume branch to the right master.
const runnerAccountLabel = "tuist.dev/runner-account"

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

// RunnerCacheUntrusted reports whether the server marked this Pod's job as
// untrusted (a fork it could not confirm as same-repo). Exported so state
// recovery in package main can preserve the untrusted decision.
func RunnerCacheUntrusted(pod *corev1.Pod) bool {
	return pod != nil && pod.Labels[runnerCacheUntrustedLabel] == "true"
}

// ReattachVolumeForPod reconstructs the cache-volume attachment for a VM that
// survived a kubelet restart. It preserves the untrusted decision: SourceAccount
// is set from the account label ONLY for a trusted pod. An untrusted branch is
// reattached (so its live virtio-fs mount isn't swept and it's cleaned at job
// end) but keeps SourceAccount empty, so Finalize's SourceAccount==account guard
// discards it — recovery can never revive attacker-controlled content into the
// account's master. Both recoverState and the createPod adoption path use this.
func ReattachVolumeForPod(volumes *VolumeManager, pod *corev1.Pod, vm string) (VolumeAttachment, bool) {
	att, ok := volumes.ReattachBranch(ReservedTuistCacheVolume, vm)
	if !ok {
		return VolumeAttachment{}, false
	}
	if !RunnerCacheUntrusted(pod) {
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

// cacheReadyFile is the marker the host writes into the writable status share
// once it has materialized the dispatched account's cache into the VM's branch
// (or determined there is no master to materialize — a cold first job).
// dispatch-poll.sh waits (bounded) for it before starting the runner so the
// guest never reads or writes the cache while the host is still clonefiling it.
const cacheReadyFile = "cache-ready"

// cacheBudgetFile carries the per-branch byte budget the guest exports as
// TUIST_CACHE_MAX_BYTES for the CLI's LRU self-prune. Staged by the host
// because the guest sees the whole shared quota volume's free space over the
// virtio-fs share, which would be a far-too-large budget.
const cacheBudgetFile = "cache-max-bytes"

// allocateVolumeBranch prepares an empty per-VM cache branch directory for a
// booting VM (shared into the guest as a virtio-fs mount), or returns an
// un-attached zero value when the feature is off or admission declines. The
// branch is filled later by maybeMaterializeVolume, once dispatch has bound
// the VM to an account.
func (r *Reconciler) allocateVolumeBranch(vmName string) (VolumeAttachment, error) {
	if r.Volumes == nil || !r.Volumes.Enabled() {
		return VolumeAttachment{}, nil
	}
	return r.Volumes.AllocateBranch(ReservedTuistCacheVolume, vmName)
}

// maybeMaterializeVolume clonefiles the dispatched account's cache master into
// this VM's branch and signals the guest, exactly once per VM. The Tuist
// server stamps the pod's runner-account label when it claims a job, so this
// runs on the reconcile that observes that label — the account is known before
// any cache bytes reach the VM, which is what makes the shared-host model safe.
// A cold first job (no master yet) still writes cache-ready so the guest stops
// waiting; its writes become the account's first master at Finalize.
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
	// EMPTY image rather than the account's master, and SourceAccount stays empty
	// so Finalize's SourceAccount==account guard discards the branch — the job can
	// neither read the account's warm master nor promote into it. It still needs
	// an image of its own: cache-ready tells the guest to attach, and signalling
	// without one would drop every fork job onto the local cold cache.
	if pod.Labels[runnerCacheUntrustedLabel] == "true" {
		if err := r.Volumes.MaterializeEmpty(entry.Volume); err != nil {
			log.Log.WithName("volume").Error(err, "create empty cache image for untrusted job", "vm", entry.VMName)
		}
		entry.Volume.Materialized = true
		// Mark it on disk too, not just in memory: without the marker a kubelet
		// restart re-enters here and recreates the image while the guest still has
		// it mounted.
		r.Volumes.MarkMaterialized(entry.Volume)
		writeCacheReady(entry.VolumeStatusDir)
		return
	}

	// Materialize this host's LOCAL master into the branch immediately — a CoW
	// clonefile that touches the network zero times (~tens of ms) — and signal
	// the guest, so the job starts warm without ever blocking on a download.
	warm, baseGeneration, err := r.Volumes.Materialize(entry.Volume, account)
	if err != nil {
		log.Log.WithName("volume").Error(err, "materialize cache volume", "vm", entry.VMName, "account", account)
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
	// Signal the guest the cache is ready (warm or cold) so its bounded wait
	// releases and the job runs.
	writeCacheReady(entry.VolumeStatusDir)
	RecordVolumeMaterialized(warm)

	// Converge the on-disk master toward the account's HEAD in the background,
	// off the job-start critical path. The running job already holds its own
	// CoW branch, so refreshing the master (an atomic swap of a separate dir)
	// never touches the job in flight — it just makes the NEXT job on this host
	// start from the account's current warm set instead of paying remote misses
	// for the delta. Best-effort and self-limiting: one goroutine per VM
	// (materialize runs at most once per VM), bounded by a download deadline.
	go r.convergeMaster(entry.VMName, entry.VolumeStatusDir, entry.Volume.VolumeName, account)
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

// writeCacheBudget stages the per-branch byte budget (≈80% of a master's
// provisioned cap) into the status share before the VM boots, for the guest's
// TUIST_CACHE_MAX_BYTES.
func writeCacheBudget(statusDir string, capGiB int) {
	if statusDir == "" || capGiB <= 0 {
		return
	}
	budget := uint64(capGiB) * 1024 * 1024 * 1024 * 8 / 10
	_ = os.WriteFile(filepath.Join(statusDir, cacheBudgetFile), []byte(strconv.FormatUint(budget, 10)), 0o644)
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

// promotedGenerationFile carries the HEAD generation the server ACCEPTED for this
// job's fast-forward, written by the guest after a successful bump. The host
// reads it at Finalize: present-and-positive means install the branch as the
// local master at that generation; absent means the guest did not promote or the
// server rejected the bump, so the branch is discarded.
const promotedGenerationFile = "cache-promoted-generation"

// readPromotedGeneration reads the server-accepted generation the guest relayed,
// or 0 when the guest never promoted or the bump was rejected.
func readPromotedGeneration(statusDir string) int {
	if statusDir == "" {
		return 0
	}
	b, err := os.ReadFile(filepath.Join(statusDir, promotedGenerationFile))
	if err != nil {
		return 0
	}
	gen, err := strconv.Atoi(strings.TrimSpace(string(b)))
	if err != nil || gen < 0 {
		return 0
	}
	return gen
}

// volumeHeadFile carries the account's cache-volume HEAD (generation, inventory
// digest, presigned download URL for the latest master archive) that the guest
// echoes from its dispatch response into the status share, so the host can
// converge a stale master toward it before materializing.
const volumeHeadFile = "volume-head.json"

type volumeHead struct {
	Generation  int    `json:"generation"`
	Digest      string `json:"digest"`
	DownloadURL string `json:"download_url"`
}

func readVolumeHead(statusDir string) *volumeHead {
	if statusDir == "" {
		return nil
	}
	b, err := os.ReadFile(filepath.Join(statusDir, volumeHeadFile))
	if err != nil {
		return nil
	}
	var h volumeHead
	if err := json.Unmarshal(b, &h); err != nil {
		return nil
	}
	return &h
}

// convergeMaster fast-forwards this host's master for the account to the
// account's HEAD when the host is behind, by downloading the latest master
// archive and atomically swapping it in. Runs in the background off the
// job-start critical path (see maybeMaterializeVolume): it refreshes the master
// dir, which the in-flight job's CoW branch does not reference, so the NEXT job
// clonefiles the fresher set. Takes plain values, not the shared *Entry, so it
// can't race the reconciler mutating that entry. Best-effort and bounded: no
// HEAD, already-current, or any download/extract failure leaves the local
// master untouched (the status quo — jobs just pay a few remote misses).
func (r *Reconciler) convergeMaster(vmName, statusDir, volumeName, account string) {
	if r.Volumes == nil || !r.Volumes.Enabled() {
		return
	}
	// Wait (bounded) for the guest to stage the HEAD. The guest writes
	// volume-head.json only after it receives the dispatch response, which the
	// server returns after stamping the label that triggered this convergence,
	// so the file lands a beat later than this goroutine starts. Reading it once
	// would usually miss it and permanently skip convergence; since this runs in
	// the background, it can afford to wait for the file to appear.
	head := awaitVolumeHead(statusDir)
	if head == nil || head.Generation <= 0 || head.DownloadURL == "" {
		return
	}
	// Skip if this host's master is already at or past the HEAD generation. The
	// generation is monotonic (the server only ever fast-forwards it), so a local
	// generation >= the HEAD's means this host already holds that HEAD (or its own
	// newer promote) and has nothing to adopt.
	if local, err := r.Volumes.MasterGeneration(account, volumeName); err == nil && local >= head.Generation {
		return
	}

	logger := log.Log.WithName("volume")
	staging := r.Volumes.ConvergeStagingDir(vmName)
	_ = os.RemoveAll(staging)
	if err := os.MkdirAll(staging, 0o755); err != nil {
		logger.Error(err, "converge: mkdir staging", "vm", vmName)
		return
	}
	defer os.RemoveAll(staging)

	image := filepath.Join(staging, convergeImageName)
	if err := downloadMasterImage(head.DownloadURL, image); err != nil {
		logger.Error(err, "converge: download master image", "vm", vmName, "account", account)
		return
	}
	// Verify the downloaded image's inventory matches the HEAD digest before
	// adopting it, so the host never records a generation for an image that isn't
	// the one the HEAD advertised. On mismatch, stay on the local master (status
	// quo). With content-addressed HEAD keys a mismatch is rare, but a stale
	// presigned URL or a partial download can still surface one.
	if head.Digest != "" {
		if got, err := r.Volumes.ImageDigest(image); err != nil || got != head.Digest {
			logger.Info("converge: image digest does not match HEAD; keeping local master",
				"vm", vmName, "account", account, "want", head.Digest, "got", got)
			return
		}
	}
	// Adopt the HEAD wholesale: a plain generation-gated whole-image replace. HEAD
	// is a monotonic fast-forward lineage (the server rejects any bump that does
	// not build on the current tip), so replacing a behind master with it strands
	// nothing — the local master is meant to match HEAD exactly.
	installed, err := r.Volumes.InstallMaster(account, volumeName, image, head.Generation)
	if err != nil {
		logger.Error(err, "converge: install master", "vm", vmName, "account", account)
		return
	}
	if installed {
		RecordVolumeConverged()
		logger.Info("converged master to HEAD", "vm", vmName, "account", account, "generation", head.Generation)
	}
}

// convergeHeadWaitInterval / convergeHeadWaitAttempts bound how long the
// background convergence waits for the guest to stage the HEAD before giving
// up (best-effort; the next job on this host converges instead).
const (
	convergeHeadWaitInterval = 1 * time.Second
	convergeHeadWaitAttempts = 15
)

// awaitVolumeHead polls the status share for the guest-staged HEAD, returning
// as soon as it appears or nil once the bound elapses.
func awaitVolumeHead(statusDir string) *volumeHead {
	for i := 0; i < convergeHeadWaitAttempts; i++ {
		if h := readVolumeHead(statusDir); h != nil {
			return h
		}
		time.Sleep(convergeHeadWaitInterval)
	}
	return readVolumeHead(statusDir)
}

// convergeImageName is the downloaded HEAD image inside the convergence staging
// dir. It deliberately does NOT use the master image's name: staging lives under
// Root, and a file named like a master could be picked up by the master scan.
const convergeImageName = "head.sparseimage"

// convergeDownloadTimeout bounds the HEAD image fetch. The object is the cache
// image itself — gigabytes, not a manifest — so the ceiling is generous. It runs
// in the background off the job-start path, so a slow fetch delays only the NEXT
// job's warmth; the bound just keeps a stalled transfer from leaking a goroutine
// and staging disk forever.
const convergeDownloadTimeout = 30 * time.Minute

// downloadMasterImage fetches the account's master image from a presigned URL to
// dst. The object IS the image — a settled APFS filesystem carrying the
// symlinks, xattrs and modes the cache needs — so there is nothing to unpack.
func downloadMasterImage(url, dst string) error {
	ctx, cancel := context.WithTimeout(context.Background(), convergeDownloadTimeout)
	defer cancel()

	// No -L: a presigned object-storage URL is fetched directly (200, no
	// redirect), so refuse to follow redirects — that removes redirect-based
	// SSRF where a hostile/misconfigured endpoint bounces this host to an
	// internal address. The server also validates the URL host is public before
	// handing it over (see volume_head_payload).
	if out, err := exec.CommandContext(ctx, "curl", "-fsS", "-o", dst, url).CombinedOutput(); err != nil {
		_ = os.Remove(dst)
		return fmt.Errorf("curl master image: %w (%s)", err, strings.TrimSpace(string(out)))
	}
	return nil
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
	// The generation the server ACCEPTED for this job's HEAD fast-forward, relayed
	// by the guest. Zero means no promote or a rejected bump — Finalize then
	// discards the branch rather than moving the local master off the lineage.
	entry.Volume.PromotedGeneration = readPromotedGeneration(entry.VolumeStatusDir)

	// For a promote-eligible job (it did cache-changing work for its own account),
	// record whether the server accepted the fast-forward — the reject-rate signal.
	// Read-only, failed, and account-mismatched jobs never promote, so they are
	// excluded to keep the ratio meaningful.
	if succeeded && dirty && actualAccount != "" && entry.Volume.SourceAccount == actualAccount {
		RecordVolumePromote(entry.Volume.PromotedGeneration > 0)
	}

	outcome, err := r.Volumes.Finalize(entry.Volume, actualAccount, succeeded, dirty)
	if err != nil {
		log.Log.WithName("volume").Error(err, "finalize cache volume", "vm", entry.VMName, "account", actualAccount)
	}
	RecordVolumeOutcome(string(outcome))

	// Consumed: the branch has been renamed away (promote) or removed
	// (discard). Clear the flag so a later teardown path does not re-run
	// Finalize against a path that no longer exists.
	entry.Volume.Attached = false
}

// readDirtyMarker reads the guest's dirty marker from the status share.
// Returns (present, dirty): present is false when the guest never wrote it
// (crashed / incomplete job), which the caller treats as "discard".
func readDirtyMarker(statusDir string) (present, dirty bool) {
	if statusDir == "" {
		return false, false
	}
	b, err := os.ReadFile(filepath.Join(statusDir, dirtyMarkerFile))
	if err != nil {
		return false, false
	}
	return true, strings.TrimSpace(string(b)) == "1"
}
