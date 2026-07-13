package podagent

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"

	"sigs.k8s.io/controller-runtime/pkg/log"
)

// Per-account cache volumes for the macOS runner fleet (spec #76).
//
// A VolumeManager owns the lifecycle of per-account cache masters kept as
// APFS directory trees under a single quota-bounded runner-cache root. The
// model is "materialize after dispatch":
//
//   - A warm-pool VM boots GENERIC — an empty, writable directory is attached
//     as a virtio-fs share at the cache root. No account data, no prediction.
//   - The server stamps the pod's `tuist.dev/runner-account` label when it
//     claims a job. The reconciler then calls Materialize, which APFS-
//     clonefiles that account's master tree into the VM's branch (instant,
//     CoW) and the guest is signalled to proceed warm.
//   - On job end Finalize promotes the branch back to the account's master
//     (job succeeded AND the cache changed) or discards it.
//
// Because the account is known before any bytes are materialized, one
// account's cache can never reach a VM that runs another account's job — the
// cross-account exposure and single-account-per-host problems of a predict-
// at-boot model are structurally absent. Masters are disposable: deleting one
// costs at most a single cold job for that account on that host.
//
// The host disk is fenced in layers: the runner-cache root is its own quota-
// bounded APFS volume (provisioned at host bootstrap), admission reserves the
// worst-case growth of every live branch up front, and watermark eviction
// keeps free space above a low mark. Every space pressure degrades a job to
// the cold path; running the host out of disk is prevented by construction.
//
// This control flow is identical to the eventual macOS 26 hot-plug model
// (VZXHCIController runtime attach): only the device swaps — a virtio-fs share
// today, a hot-attached block device once tart exposes the API.

// ReservedTuistCacheVolume is the reserved volume name for the managed Tuist
// module cache. Masters are keyed (account_id, volume_name) on disk so that
// generic, user-declared volumes (spec #69) are new names rather than a
// re-keying migration.
const ReservedTuistCacheVolume = "tuist-cache"

// cacheHomeSubdir is the single top-level directory the Tuist CLI writes
// under its cache home (TUIST_XDG_CACHE_HOME/tuist/...). Materialize and
// promote move exactly this subtree, so the guest only ever sees it appear or
// disappear atomically.
const cacheHomeSubdir = "tuist"

// volumeBackend abstracts the two macOS-specific operations the manager needs
// so its lifecycle logic (admission, LRU, promote/discard, paths) is testable
// off a Mac. The real implementation lives in volume_darwin.go (clonefile via
// `cp -c -R`, statfs via `df`); tests inject a fake.
type volumeBackend interface {
	// cloneTree CoW-clones the directory tree at src to dst (APFS clonefile:
	// instant, no byte copy). dst must not exist; its parent must.
	cloneTree(src, dst string) error
	// freeBytes reports the free space on the filesystem holding root
	// (statfs). Ground truth for admission and watermarks: per-file sizes
	// cannot be summed because CoW clones share blocks.
	freeBytes(root string) (uint64, error)
}

// VolumeOutcome is the terminal disposition of a branch, for observability.
type VolumeOutcome string

const (
	// VolumeOutcomePromoted: branch became the account's new master.
	VolumeOutcomePromoted VolumeOutcome = "promoted"
	// VolumeOutcomeDiscarded: branch dropped (clean/read-only job, or a
	// crashed job with no marker, or a never-dispatched warm VM).
	VolumeOutcomeDiscarded VolumeOutcome = "discarded"
	// VolumeOutcomeNone: no volume was attached for this VM (feature off, or
	// admission declined). The job ran on the status-quo cold path.
	VolumeOutcomeNone VolumeOutcome = "none"
)

// VolumeAttachment records what AllocateBranch prepared for a VM so
// Materialize and Finalize can act on it. The zero value (Attached false)
// means the VM booted without a volume — the cold path — and both are no-ops.
type VolumeAttachment struct {
	// Attached is false when the feature is off or admission declined.
	Attached bool
	// VolumeName is the reserved/generic volume name (tuist-cache in v1).
	VolumeName string
	// BranchPath is the per-VM branch directory shared into the VM.
	BranchPath string
	// SourceAccount is the account whose master was materialized into the
	// branch, learned from the pod label at dispatch. Empty until Materialize
	// runs (or if the VM is never dispatched).
	SourceAccount string
	// Materialized is true once the account's master has been clonefiled into
	// the branch (or determined absent — a cold first job). Guards against
	// re-materializing on repeated reconciles.
	Materialized bool
}

// VolumeManager manages per-account cache-volume master trees under a single
// quota-bounded runner-cache root. Safe for concurrent use.
type VolumeManager struct {
	// Root is the runner-cache root — a dedicated quota-bounded APFS volume
	// provisioned at host bootstrap. Empty disables the whole feature: every
	// method no-ops and every VM boots on the cold path.
	Root string

	// CapGiB is the worst-case size admission reserves per live branch. The
	// APFS volume's own quota is the real aggregate ceiling; this is the
	// per-job headroom the admission check keeps free.
	CapGiB int

	// LowWatermarkFraction is the free-space fraction the background evictor
	// keeps the quota volume above by dropping whole masters LRU.
	LowWatermarkFraction float64

	backend volumeBackend

	// mu serializes disk-mutating operations and the live-branch reservation
	// count. Clones are fast (CoW) so a single lock is sufficient at the
	// 2-VMs-per-host concurrency of this fleet.
	mu sync.Mutex

	// liveBranches counts branches that have been allocated but not yet
	// finalized. Admission reserves CapGiB per live branch so concurrent
	// sparse clones cannot collectively overrun the quota volume.
	liveBranches int

	// ReconcileInterval is how often the background watermark evictor +
	// observability sampler runs. Defaults to 5m.
	ReconcileInterval time.Duration

	// now is injectable for tests; defaults to time.Now.
	now func() time.Time
}

// NewVolumeManager builds a manager. root == "" returns a disabled manager
// whose methods all no-op. A nil backend defaults to the platform backend
// (macOS clonefile/df); tests inject a fake.
func NewVolumeManager(root string, capGiB int, backend volumeBackend) *VolumeManager {
	if capGiB <= 0 {
		capGiB = 20
	}
	if backend == nil {
		backend = newVolumeBackend()
	}
	return &VolumeManager{
		Root:                 root,
		CapGiB:               capGiB,
		LowWatermarkFraction: 0.20,
		backend:              backend,
		now:                  time.Now,
	}
}

// Enabled reports whether the feature is active on this host.
func (m *VolumeManager) Enabled() bool { return m != nil && m.Root != "" }

func (m *VolumeManager) capBytes() uint64 { return uint64(m.CapGiB) * 1024 * 1024 * 1024 }

// masterDir is <root>/<account>/<volume>/master.
func (m *VolumeManager) masterDir(account, volume string) string {
	return filepath.Join(m.Root, account, volume, "master")
}

// branchDir is <root>/branches/<vm>. Branches are per-VM and account-agnostic
// until Materialize — they live under a single top-level dir, not per account.
func (m *VolumeManager) branchDir(vm string) string {
	return filepath.Join(m.Root, "branches", vm)
}

func (m *VolumeManager) branchesRoot() string { return filepath.Join(m.Root, "branches") }

// AllocateBranch prepares an empty per-VM branch directory for a booting warm-
// pool VM and reserves its worst-case growth against the quota volume. It
// clones nothing and predicts nothing — the branch is filled later by
// Materialize, once dispatch has bound the VM to an account. When the feature
// is off or admission declines (no room even after eviction), it returns an
// un-attached zero value and the VM boots on the cold path.
func (m *VolumeManager) AllocateBranch(volume, vm string) (VolumeAttachment, error) {
	if !m.Enabled() {
		return VolumeAttachment{}, nil
	}
	if volume == "" {
		volume = ReservedTuistCacheVolume
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	// Admission: reserve CapGiB for this branch AND for every other live
	// branch's worst-case remaining growth. statfs `free` already reflects
	// what live branches have written; reserving CapGiB per live branch keeps
	// enough headroom that all of them reaching full cap cannot ENOSPC the
	// volume. If it doesn't fit, evict LRU masters; if it still doesn't,
	// decline (cold path).
	want := m.capBytes() * uint64(m.liveBranches+1)
	if err := m.ensureFreeLocked(want); err != nil {
		if errors.Is(err, errNoRoom) {
			return VolumeAttachment{}, nil
		}
		return VolumeAttachment{}, err
	}

	branch := m.branchDir(vm)
	if err := os.RemoveAll(branch); err != nil {
		return VolumeAttachment{}, fmt.Errorf("clear stale branch dir: %w", err)
	}
	// 0o777 so the guest's unprivileged runner user can write the cache into
	// the virtio-fs share (the host chowns/relaxes shares the same way for the
	// status dir).
	if err := os.MkdirAll(branch, 0o777); err != nil {
		return VolumeAttachment{}, fmt.Errorf("mkdir branch dir: %w", err)
	}
	if err := os.Chmod(branch, 0o777); err != nil {
		return VolumeAttachment{}, fmt.Errorf("chmod branch dir: %w", err)
	}

	m.liveBranches++
	return VolumeAttachment{
		Attached:   true,
		VolumeName: volume,
		BranchPath: branch,
	}, nil
}

// Materialize clonefiles the given account's master tree into the VM's branch,
// making the branch a warm, private CoW copy of the account's cache. It is
// called once, after the server has stamped the pod's account label. Returns
// warm=true when a master existed and was cloned; warm=false when the account
// has no master on this host yet (a cold first job whose writes Finalize will
// promote into that account's first master). The clone lands in a temp dir and
// is swapped into place with a single atomic rename, so the guest never
// observes a partial tree.
func (m *VolumeManager) Materialize(att VolumeAttachment, account string) (warm bool, err error) {
	if !m.Enabled() || !att.Attached || account == "" {
		return false, nil
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	masterTree := filepath.Join(m.masterDir(account, att.VolumeName), cacheHomeSubdir)
	if _, statErr := os.Stat(masterTree); statErr != nil {
		// No master for this account here yet: cold path. The guest warms from
		// the remote cache and Finalize promotes the result into a new master.
		return false, nil
	}

	tmp := filepath.Join(att.BranchPath, "."+cacheHomeSubdir+".materialize.tmp")
	dest := filepath.Join(att.BranchPath, cacheHomeSubdir)
	_ = os.RemoveAll(tmp)
	if err := m.backend.cloneTree(masterTree, tmp); err != nil {
		_ = os.RemoveAll(tmp)
		return false, fmt.Errorf("clone master into branch: %w", err)
	}
	// Swap into place atomically. A fresh branch has no existing subtree, but
	// remove defensively so the rename can't collide.
	_ = os.RemoveAll(dest)
	if err := os.Rename(tmp, dest); err != nil {
		_ = os.RemoveAll(tmp)
		return false, fmt.Errorf("swap materialized cache into place: %w", err)
	}
	// Mark the master used so LRU tracks materialization, not just promotion —
	// an account whose jobs keep landing here stays hot.
	_ = os.Chtimes(m.masterDir(account, att.VolumeName), m.now(), m.now())
	return true, nil
}

// Finalize promotes or discards a branch after the job ends and releases its
// reservation. Promotion is last-writer-wins and happens only when the job
// succeeded, the guest reported the cache actually changed (dirty), and the
// account is known. A read-only, failed, crashed (no marker), or never-
// dispatched branch discards. Because the branch was materialized from the
// job's own account, there is no cross-account case to guard.
func (m *VolumeManager) Finalize(att VolumeAttachment, account string, jobSucceeded, dirty bool) (VolumeOutcome, error) {
	if !m.Enabled() || !att.Attached {
		return VolumeOutcomeNone, nil
	}

	m.mu.Lock()
	defer m.mu.Unlock()
	if m.liveBranches > 0 {
		m.liveBranches--
	}

	discard := func() (VolumeOutcome, error) {
		_ = os.RemoveAll(att.BranchPath)
		return VolumeOutcomeDiscarded, nil
	}

	branchTree := filepath.Join(att.BranchPath, cacheHomeSubdir)
	if !jobSucceeded || !dirty || account == "" {
		return discard()
	}
	if _, err := os.Stat(branchTree); err != nil {
		return discard()
	}

	master := m.masterDir(account, att.VolumeName)
	staged := master + ".new"
	_ = os.RemoveAll(staged)
	if err := os.MkdirAll(staged, 0o755); err != nil {
		_ = os.RemoveAll(att.BranchPath)
		return "", fmt.Errorf("mkdir staged master: %w", err)
	}
	if err := m.backend.cloneTree(branchTree, filepath.Join(staged, cacheHomeSubdir)); err != nil {
		_ = os.RemoveAll(staged)
		_ = os.RemoveAll(att.BranchPath)
		return "", fmt.Errorf("clone branch into staged master: %w", err)
	}
	// Swap staged → master (last-writer-wins). A concurrent second VM of the
	// same account promoting after us simply replaces the master with its own;
	// the loser's delta is bounded to one job and acceptable for a cache.
	old := master + ".old"
	_ = os.RemoveAll(old)
	if _, err := os.Stat(master); err == nil {
		if err := os.Rename(master, old); err != nil {
			_ = os.RemoveAll(staged)
			_ = os.RemoveAll(att.BranchPath)
			return "", fmt.Errorf("stash old master: %w", err)
		}
	}
	if err := os.Rename(staged, master); err != nil {
		// Best-effort restore of the old master so warmth isn't lost.
		_ = os.Rename(old, master)
		_ = os.RemoveAll(att.BranchPath)
		return "", fmt.Errorf("promote staged master: %w", err)
	}
	_ = os.RemoveAll(old)
	_ = os.RemoveAll(att.BranchPath)
	_ = os.Chtimes(master, m.now(), m.now())
	return VolumeOutcomePromoted, nil
}

// SweepBranches removes every per-VM branch directory. Called once on startup:
// branches are ephemeral per-job scratch, so any that survive a kubelet
// restart belong to VMs that are gone and would otherwise leak disk (their
// Finalize can never run). No-op when the feature is off.
func (m *VolumeManager) SweepBranches() error {
	if !m.Enabled() {
		return nil
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.liveBranches = 0
	entries, err := os.ReadDir(m.branchesRoot())
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	for _, e := range entries {
		_ = os.RemoveAll(filepath.Join(m.branchesRoot(), e.Name()))
	}
	return nil
}

// Start implements controller-runtime's manager.Runnable: sweeps stale
// branches once, then on a ticker keeps free space above the low watermark by
// evicting whole masters LRU and publishes the resident-count / free-bytes
// gauges. No-op when the feature is off. Returns nil on context cancellation.
func (m *VolumeManager) Start(ctx context.Context) error {
	if !m.Enabled() {
		return nil
	}
	logger := log.FromContext(ctx).WithName("cache-volumes")
	if err := m.SweepBranches(); err != nil {
		logger.Error(err, "sweep stale branches on startup")
	}
	interval := m.ReconcileInterval
	if interval <= 0 {
		interval = 5 * time.Minute
	}
	tick := func() {
		if evicted, err := m.EvictToWatermark(); err != nil {
			logger.Error(err, "watermark eviction")
		} else if evicted > 0 {
			logger.Info("evicted cache masters under watermark", "count", evicted)
		}
		if count, free, err := m.Stats(); err == nil {
			RecordVolumeResident(count, free)
		}
	}
	tick()
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-t.C:
			tick()
		}
	}
}

// Stats reports the resident master count and free bytes on the quota volume.
func (m *VolumeManager) Stats() (residentCount int, freeBytes uint64, err error) {
	if !m.Enabled() {
		return 0, 0, nil
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	masters, err := m.allMastersLocked()
	if err != nil {
		return 0, 0, err
	}
	free, err := m.backend.freeBytes(m.Root)
	if err != nil {
		return len(masters), 0, err
	}
	return len(masters), free, nil
}

// EvictToWatermark drops whole masters LRU until free space is back above the
// low watermark. Called on the reconcile tick.
func (m *VolumeManager) EvictToWatermark() (evicted int, err error) {
	if !m.Enabled() {
		return 0, nil
	}
	m.mu.Lock()
	defer m.mu.Unlock()

	free, err := m.backend.freeBytes(m.Root)
	if err != nil {
		return 0, err
	}
	target := m.lowWatermarkBytes()
	if free >= target {
		return 0, nil
	}
	masters, err := m.mastersByLRULocked()
	if err != nil {
		return 0, err
	}
	for _, mm := range masters {
		if free >= target {
			break
		}
		if err := os.RemoveAll(mm.path); err != nil {
			continue
		}
		evicted++
		f, ferr := m.backend.freeBytes(m.Root)
		if ferr != nil {
			return evicted, ferr
		}
		free = f
	}
	return evicted, nil
}

// lowWatermarkBytes is the absolute free-space floor the evictor maintains.
func (m *VolumeManager) lowWatermarkBytes() uint64 {
	frac := m.LowWatermarkFraction
	if frac <= 0 {
		frac = 0.20
	}
	return m.capBytes() + uint64(float64(m.capBytes())*frac)
}

var errNoRoom = errors.New("runner-cache root has no room for a cache volume")

// ensureFreeLocked makes sure at least want bytes are free, evicting LRU
// masters as needed. Returns errNoRoom when even a fully-evicted root cannot
// fit the request (caller declines to the cold path).
func (m *VolumeManager) ensureFreeLocked(want uint64) error {
	free, err := m.backend.freeBytes(m.Root)
	if err != nil {
		return err
	}
	if free >= want {
		return nil
	}
	masters, err := m.mastersByLRULocked()
	if err != nil {
		return err
	}
	for _, mm := range masters {
		if free >= want {
			return nil
		}
		if err := os.RemoveAll(mm.path); err != nil {
			continue
		}
		f, ferr := m.backend.freeBytes(m.Root)
		if ferr != nil {
			return ferr
		}
		free = f
	}
	if free < want {
		return errNoRoom
	}
	return nil
}

type masterEntry struct {
	account string
	path    string
	modTime time.Time
}

// mastersByLRULocked lists every master (all volumes) oldest-mtime first —
// the eviction order.
func (m *VolumeManager) mastersByLRULocked() ([]masterEntry, error) {
	all, err := m.allMastersLocked()
	if err != nil {
		return nil, err
	}
	sort.Slice(all, func(i, j int) bool { return all[i].modTime.Before(all[j].modTime) })
	return all, nil
}

// allMastersLocked scans <root>/<account>/<volume>/master. Accounts are
// directory names; the branches dir (per-VM scratch) is skipped.
func (m *VolumeManager) allMastersLocked() ([]masterEntry, error) {
	accounts, err := os.ReadDir(m.Root)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	var out []masterEntry
	for _, acct := range accounts {
		if !acct.IsDir() || acct.Name() == "branches" {
			continue
		}
		volumes, err := os.ReadDir(filepath.Join(m.Root, acct.Name()))
		if err != nil {
			continue
		}
		for _, vol := range volumes {
			if !vol.IsDir() {
				continue
			}
			p := m.masterDir(acct.Name(), vol.Name())
			info, err := os.Stat(p)
			if err != nil {
				continue
			}
			out = append(out, masterEntry{account: acct.Name(), path: p, modTime: info.ModTime()})
		}
	}
	return out, nil
}
