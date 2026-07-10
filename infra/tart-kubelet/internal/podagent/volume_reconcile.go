package podagent

import (
	"os"
	"path/filepath"
	"strings"

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

// attachVolume prepares a cache-volume branch for a booting VM, or returns an
// un-attached zero value when the feature is off on this host.
func (r *Reconciler) attachVolume(vmName string) (VolumeAttachment, error) {
	if r.Volumes == nil || !r.Volumes.Enabled() {
		return VolumeAttachment{}, nil
	}
	return r.Volumes.AttachForBoot(ReservedTuistCacheVolume, vmName)
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

// volumeManifestJSON is the volumes.json the guest reads (from the ro env
// share) to learn which attached block device carries the cache and where to
// point the cache root. Plural and label-keyed from day one so generic
// volumes (spec #69) are additive; v1 emits exactly one entry.
func volumeManifestJSON(volumeName string) string {
	if volumeName == "" {
		volumeName = ReservedTuistCacheVolume
	}
	return `[{"label":"` + volumeName + `","cache_root":true}]`
}
