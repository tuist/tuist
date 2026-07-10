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
// A VolumeManager owns the whole image lifecycle of per-account cache
// volumes, exactly as the reconciler owns golden VM images: create + format
// a master on first use, CoW-clone it per job into a branch, attach the
// branch to the runner VM as a block device, and on job end promote the
// branch to be the new master (job succeeded AND it changed the cache) or
// discard it. Masters are disposable by construction — deleting one costs at
// most one status-quo cold job for that account on that host.
//
// The account a warm-pool VM will serve is not known at boot (dispatch binds
// it only after the VM polls), so AttachForBoot predicts the account by
// picking the host's most-recently-used master (local LRU). That prediction
// and the server's dispatch-history affinity are two views of the same "who
// ran here recently" signal, so they converge without an inventory channel.
// Finalize verifies the branch's source account against the job's actual
// account (learned from the Pod label after dispatch) and never promotes a
// mispredicted branch onto a different account's master, so a misprediction
// costs only the cold path and can never contaminate another tenant.
//
// The host disk is fenced in layers: the runner-cache root is its own
// quota-bounded APFS volume (a filesystem ceiling provisioned at host
// bootstrap), admission gates growth up front, and watermark eviction keeps
// free space above a low mark. Every space pressure degrades a job to the
// cold path; running the host out of disk — the one non-degradable failure —
// is prevented by construction, never merely reacted to.

// ReservedTuistCacheVolume is the reserved volume name for the managed Tuist
// module cache. Masters are keyed (account_id, volume_name) on disk so that
// generic, user-declared volumes (spec #69) are new names rather than a
// re-keying migration.
const ReservedTuistCacheVolume = "tuist-cache"

// imageBackend abstracts the macOS-specific disk-image mechanics so the
// manager's lifecycle logic (admission, LRU, promote/discard, paths) is
// testable off a Mac. The real implementation lives in volume_darwin.go
// (hdiutil / clonefile / statfs); tests inject a fake.
type imageBackend interface {
	// createMaster creates a sparse, APFS-formatted raw disk image at path
	// with the given provisioned capacity and internal volume label. The
	// APFS volume inside is fixed-size at creation, so the image can never
	// exceed capGiB; because the file is sparse, capGiB can be generous and
	// the host quota above is the real aggregate bound.
	createMaster(path string, capGiB int, label string) error
	// clone CoW-clones src into dst (APFS clonefile: instant, no byte copy).
	clone(src, dst string) error
	// remove deletes an image file. Best-effort; absent is not an error.
	remove(path string) error
	// freeBytes reports the free space on the filesystem holding root
	// (statfs). This is the ground truth for admission and watermarks:
	// per-file allocated sizes cannot be summed because CoW clones share
	// blocks (a master plus its branch would double-count).
	freeBytes(root string) (uint64, error)
}

// VolumeOutcome is the terminal disposition of a branch, for observability.
type VolumeOutcome string

const (
	// VolumeOutcomePromoted: branch became the account's new master.
	VolumeOutcomePromoted VolumeOutcome = "promoted"
	// VolumeOutcomeDiscarded: branch dropped (clean/read-only job, or a
	// crashed job with no marker).
	VolumeOutcomeDiscarded VolumeOutcome = "discarded"
	// VolumeOutcomeMispredicted: the branch was cloned from account A but the
	// job actually ran account B; discarded to avoid cross-account
	// contamination.
	VolumeOutcomeMispredicted VolumeOutcome = "mispredicted"
	// VolumeOutcomeNone: no volume was attached for this VM (feature off, or
	// admission declined). The job ran on the status-quo cold path.
	VolumeOutcomeNone VolumeOutcome = "none"
)

// VolumeAttachment records what AttachForBoot prepared for a VM so Finalize
// can promote or discard it. The zero value (Attached false) means the VM
// booted without a volume — the cold path — and Finalize is a no-op.
type VolumeAttachment struct {
	// Attached is false when the feature is off or admission declined.
	Attached bool
	// VolumeName is the reserved/generic volume name (tuist-cache in v1).
	VolumeName string
	// BranchPath is the per-VM branch image attached to the VM.
	BranchPath string
	// SourceAccount is the account whose master was cloned into the branch,
	// or "" when the branch was empty-seeded (no local master to predict
	// from). Finalize promotes an empty-seeded branch to whatever account
	// the job actually ran, which is how a host warms an account for the
	// first time.
	SourceAccount string
}

// VolumeManager manages per-account cache-volume images under a single
// quota-bounded runner-cache root. Safe for concurrent use.
type VolumeManager struct {
	// Root is the runner-cache root — a dedicated quota-bounded APFS volume
	// provisioned at host bootstrap. Empty disables the whole feature: every
	// method no-ops and every VM boots on the cold path, so a host that was
	// never provisioned with the volume behaves exactly as today.
	Root string

	// CapGiB is the provisioned capacity of each master image. 20 GiB
	// comfortably holds a large cache directory; the file is sparse so this
	// is a ceiling, not an allocation.
	CapGiB int

	// LowWatermarkFraction is the free-space fraction the background evictor
	// keeps the quota volume above by dropping whole masters LRU.
	LowWatermarkFraction float64

	backend imageBackend

	// mu serializes disk-mutating operations. Clones are fast (CoW) so a
	// single lock is sufficient at the 2-VMs-per-host concurrency of this
	// fleet and keeps admission/eviction accounting race-free.
	mu sync.Mutex

	// ReconcileInterval is how often the background watermark evictor +
	// observability sampler runs. Defaults to 5m.
	ReconcileInterval time.Duration

	// now is injectable for tests; defaults to time.Now.
	now func() time.Time
}

// NewVolumeManager builds a manager. root == "" returns a disabled manager
// whose methods all no-op (the feature is off on that host). A nil backend
// defaults to the platform image backend (macOS hdiutil/clonefile); tests
// inject a fake.
func NewVolumeManager(root string, capGiB int, backend imageBackend) *VolumeManager {
	if capGiB <= 0 {
		capGiB = 20
	}
	if backend == nil {
		backend = newImageBackend()
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

// masterPath is <root>/<account>/<volume>/master.img.
func (m *VolumeManager) masterPath(account, volume string) string {
	return filepath.Join(m.Root, account, volume, "master.img")
}

// branchPath is <root>/<account>/<volume>/branches/<vm>.img.
func (m *VolumeManager) branchPath(account, volume, vm string) string {
	return filepath.Join(m.Root, account, volume, "branches", vm+".img")
}

// stagingBranchPath is <root>/_staging/<vm>.img, used for an empty-seeded
// branch whose account is not known until the job runs.
func (m *VolumeManager) stagingBranchPath(vm string) string {
	return filepath.Join(m.Root, "_staging", vm+".img")
}

// AttachForBoot prepares a per-VM branch for a booting warm-pool VM. It
// predicts the account by cloning the host's most-recently-used master for
// the given volume; if the host holds none, it creates a fresh empty master
// image so the job's pulls still warm a volume that can be promoted to
// whatever account dispatch assigns. When the feature is off or admission
// declines (no room even after eviction), it returns an un-attached zero
// value and the VM boots on the cold path — warmth is the only thing ever
// sacrificed.
func (m *VolumeManager) AttachForBoot(volume, vm string) (VolumeAttachment, error) {
	if !m.Enabled() {
		return VolumeAttachment{}, nil
	}
	if volume == "" {
		volume = ReservedTuistCacheVolume
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	// Admission: reserve the conservative per-volume cap for this job's
	// worst-case growth. If it doesn't fit, evict LRU masters to make room;
	// if it still doesn't fit, decline (cold path).
	if err := m.ensureFreeLocked(m.capBytes()); err != nil {
		if errors.Is(err, errNoRoom) {
			return VolumeAttachment{}, nil
		}
		return VolumeAttachment{}, err
	}

	predicted, err := m.hottestMasterLocked(volume)
	if err != nil {
		return VolumeAttachment{}, err
	}

	if predicted != "" {
		branch := m.branchPath(predicted, volume, vm)
		if err := os.MkdirAll(filepath.Dir(branch), 0o755); err != nil {
			return VolumeAttachment{}, fmt.Errorf("mkdir branch dir: %w", err)
		}
		if err := m.backend.clone(m.masterPath(predicted, volume), branch); err != nil {
			return VolumeAttachment{}, fmt.Errorf("clone master: %w", err)
		}
		// Touch the master so "most recently used" tracks attachment, not
		// just promotion — an account that keeps getting picked stays hot
		// and won't be evicted out from under its own warm pool.
		_ = os.Chtimes(m.masterPath(predicted, volume), m.now(), m.now())
		return VolumeAttachment{
			Attached:      true,
			VolumeName:    volume,
			BranchPath:    branch,
			SourceAccount: predicted,
		}, nil
	}

	// No local master to predict from: empty-seed a fresh image. Its writes
	// are captured for whatever account the job turns out to run.
	branch := m.stagingBranchPath(vm)
	if err := os.MkdirAll(filepath.Dir(branch), 0o755); err != nil {
		return VolumeAttachment{}, fmt.Errorf("mkdir staging dir: %w", err)
	}
	if err := m.backend.createMaster(branch, m.CapGiB, volume); err != nil {
		return VolumeAttachment{}, fmt.Errorf("create empty branch: %w", err)
	}
	return VolumeAttachment{
		Attached:      true,
		VolumeName:    volume,
		BranchPath:    branch,
		SourceAccount: "",
	}, nil
}

// Finalize promotes or discards a branch after the job ends. Promotion is
// last-writer-wins (atomic rename) and happens only when the job succeeded,
// the guest reported the cache actually changed (dirty), and the branch's
// source account matches the job's actual account (or the branch was
// empty-seeded). A read-only, failed, crashed (no marker), or mispredicted
// job discards the branch. The dirty gate is load-bearing: under
// last-writer-wins, promoting an unchanged read-only branch after a
// concurrent writer's branch would silently clobber the writer's captured
// warmth.
func (m *VolumeManager) Finalize(att VolumeAttachment, actualAccount string, jobSucceeded, dirty bool) (VolumeOutcome, error) {
	if !m.Enabled() || !att.Attached {
		return VolumeOutcomeNone, nil
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	discard := func() (VolumeOutcome, error) {
		_ = m.backend.remove(att.BranchPath)
		return VolumeOutcomeDiscarded, nil
	}

	if !jobSucceeded || !dirty || actualAccount == "" {
		return discard()
	}

	// Misprediction guard: never promote account A's clone (plus B's writes)
	// onto B's master. A's artifacts would fail B's signature validation and
	// dilute B's warm set; discard instead — the job already ran, at the
	// cost of the cold path only.
	if att.SourceAccount != "" && att.SourceAccount != actualAccount {
		_ = m.backend.remove(att.BranchPath)
		return VolumeOutcomeMispredicted, nil
	}

	master := m.masterPath(actualAccount, att.VolumeName)
	if err := os.MkdirAll(filepath.Dir(master), 0o755); err != nil {
		_ = m.backend.remove(att.BranchPath)
		return "", fmt.Errorf("mkdir master dir: %w", err)
	}
	// Atomic rename: last-writer-wins. A concurrent second VM of the same
	// account promoting after us simply replaces the master with its own
	// branch; the loser's delta is bounded to one job and acceptable for a
	// cache.
	if err := os.Rename(att.BranchPath, master); err != nil {
		_ = m.backend.remove(att.BranchPath)
		return "", fmt.Errorf("promote branch: %w", err)
	}
	_ = os.Chtimes(master, m.now(), m.now())
	return VolumeOutcomePromoted, nil
}

// Start implements controller-runtime's manager.Runnable: on a ticker it
// keeps free space above the low watermark by evicting whole masters LRU and
// publishes the resident-count / free-bytes gauges. No-op when the feature is
// off. Returns nil on context cancellation.
func (m *VolumeManager) Start(ctx context.Context) error {
	if !m.Enabled() {
		return nil
	}
	interval := m.ReconcileInterval
	if interval <= 0 {
		interval = 5 * time.Minute
	}
	logger := log.FromContext(ctx).WithName("cache-volumes")
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
// low watermark. Called on the reconcile tick. Eviction is pure account-LRU
// in v1; size-aware weighting is adopted only if telemetry shows large
// masters crowding out many small accounts.
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
	// The watermark is a fraction of the quota volume's capacity. We only
	// have free (statfs); approximate capacity by free + used is not
	// available without the total, so the darwin backend reports free and we
	// treat the low watermark as an absolute floor derived from the cap: keep
	// at least one worst-case job's headroom plus the fractional margin.
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
		if err := m.backend.remove(mm.path); err != nil {
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
// Derived from the provisioned cap and the configured fraction so it scales
// with volume size without needing the quota volume's total from statfs.
func (m *VolumeManager) lowWatermarkBytes() uint64 {
	frac := m.LowWatermarkFraction
	if frac <= 0 {
		frac = 0.20
	}
	// Keep headroom of the fractional margin on top of one worst-case job.
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
		if err := m.backend.remove(mm.path); err != nil {
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

// hottestMasterLocked returns the account whose master for the volume was used
// most recently (newest mtime), or "" if the host holds none.
func (m *VolumeManager) hottestMasterLocked(volume string) (string, error) {
	masters, err := m.mastersForVolumeLocked(volume)
	if err != nil {
		return "", err
	}
	if len(masters) == 0 {
		return "", nil
	}
	sort.Slice(masters, func(i, j int) bool { return masters[i].modTime.After(masters[j].modTime) })
	return masters[0].account, nil
}

// mastersForVolumeLocked lists all masters for a specific volume name.
func (m *VolumeManager) mastersForVolumeLocked(volume string) ([]masterEntry, error) {
	all, err := m.allMastersLocked()
	if err != nil {
		return nil, err
	}
	out := all[:0]
	for _, e := range all {
		if filepath.Base(filepath.Dir(e.path)) == volume {
			out = append(out, e)
		}
	}
	return out, nil
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

// allMastersLocked scans <root>/<account>/<volume>/master.img. Accounts are
// directory names; the _staging dir (empty-seed branches) is skipped.
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
		if !acct.IsDir() || acct.Name() == "_staging" {
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
			p := m.masterPath(acct.Name(), vol.Name())
			info, err := os.Stat(p)
			if err != nil {
				continue
			}
			out = append(out, masterEntry{account: acct.Name(), path: p, modTime: info.ModTime()})
		}
	}
	return out, nil
}
