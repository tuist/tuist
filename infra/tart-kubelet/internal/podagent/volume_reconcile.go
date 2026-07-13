package podagent

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// runnerAccountLabel is the Pod label the Tuist server stamps at dispatch with
// the account id the job belongs to (see server serve_claim). It is the
// authoritative "which account did this VM actually run" signal used to
// promote a cache-volume branch to the right master.
const runnerAccountLabel = "tuist.dev/runner-account"

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
	warm, err := r.Volumes.Materialize(entry.Volume, account)
	if err != nil {
		log.Log.WithName("volume").Error(err, "materialize cache volume", "vm", entry.VMName, "account", account)
	}
	entry.Volume.SourceAccount = account
	entry.Volume.Materialized = true
	// Signal the guest the cache is ready (warm or cold) so its bounded wait
	// releases and the job runs.
	writeCacheReady(entry.VolumeStatusDir)
	RecordVolumeMaterialized(warm)
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

// finalizeVolume promotes or discards the entry's cache-volume branch and
// marks it consumed so the call is idempotent across the multiple teardown
// paths (terminal transition, Pod deletion, best-effort cleanup). cleanExit
// reflects whether `tart run` exited cleanly; combined with the guest's dirty
// marker it decides promotion.
func (r *Reconciler) finalizeVolume(entry *Entry, actualAccount string, cleanExit bool) {
	if r.Volumes == nil || entry == nil || !entry.Volume.Attached {
		return
	}
	present, dirty := readDirtyMarker(entry.VolumeStatusDir)
	succeeded := cleanExit && present

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
