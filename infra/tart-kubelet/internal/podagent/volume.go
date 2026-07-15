package podagent

import (
	"context"
	"crypto/sha1"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"

	"sigs.k8s.io/controller-runtime/pkg/log"
)

// Per-account cache volumes for the macOS runner fleet.
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
// Because the account is materialized only after dispatch commits (the server
// stamps the trigger label only once a claim fully succeeds), one account's
// cache does not reach a VM that runs another account's job — the cross-account
// exposure and single-account-per-host problems of a predict-at-boot model are
// avoided. Finalize additionally refuses to promote a branch whose materialized
// SourceAccount differs from the account the job ran, as defense in depth
// against a stale label. Masters are disposable: deleting one costs at most a
// single cold job for that account on that host.
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

// casImageName is the per-account Xcode compilation-cache (CAS) store, carried
// as a sparse APFS disk IMAGE that sits next to the `tuist` tree in the same
// master/branch — NOT as a directory subtree like the rest of the cache.
//
// Why an image and not a subtree: Xcode's on-disk CAS (llcas / UnifiedOnDiskCache)
// uses memory-mapped file locking, and mmap over the virtio-fs share the branch
// is mounted through faults with SIGBUS — a CAS pointed straight at the share
// crashes the build. A disk image dodges this: the guest `hdiutil attach`es the
// image file off the share and gets a real block-device APFS volume, whose block
// layer does plain read/write to the backing file (no mmap of the shared file),
// so llcas works. The image is still an ordinary file on the host, so the host
// clonefiles it master<->branch exactly like the tree (CoW, ~free), and it is
// sparse so a master costs only its real CAS bytes, not its logical cap.
//
// This is why the CAS rides an image while the binary cache (Binaries,
// Manifests, ...) stays a plain virtio-fs subtree: only the CAS mmaps its store.
const casImageName = "xcode-cas.sparseimage"

// materializedMarker is a host-written sentinel dropped in the branch once the
// host has materialized (or decided cold-path) for a VM. It is the ONLY signal
// that the branch was host-materialized: the guest creates the `tuist` cache
// subtree itself at boot (empty), so the subtree's existence can't distinguish
// an idle, never-dispatched VM from a materialized one. The guest writes only
// under `tuist/`, never this dotfile, so it stays host-authoritative — which
// keeps restart recovery from marking an idle branch materialized and skipping
// its real materialization.
const materializedMarker = ".host-materialized"

// volumeBackend abstracts the macOS-specific operations the manager needs so
// its lifecycle logic (admission, LRU, promote/discard, paths) is testable off
// a Mac. The real implementation lives in volume_darwin.go (clonefile via
// `cp -c`, statfs via `df`, image via `hdiutil`); tests inject a fake.
type volumeBackend interface {
	// cloneTree CoW-clones the directory tree at src to dst (APFS clonefile:
	// instant, no byte copy). dst must not exist; its parent must.
	cloneTree(src, dst string) error
	// freeBytes reports the free space on the filesystem holding root
	// (statfs). Ground truth for admission and watermarks: per-file sizes
	// cannot be summed because CoW clones share blocks.
	freeBytes(root string) (uint64, error)
	// cloneFile CoW-clones a single file src to dst (the CAS disk image).
	// Same clonefile(2) as cloneTree, without directory recursion. dst must
	// not exist; its parent must.
	cloneFile(src, dst string) error
	// createSparseImage creates an empty sparse APFS disk image of the given
	// logical size (GiB) at path. Used for an account's first CAS master on a
	// host, before any job has populated one.
	createSparseImage(path string, sizeGiB int) error
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

	// CASGiB is the logical cap of each account's CAS disk image and the extra
	// headroom admission reserves per live branch for it. Zero disables the CAS
	// image entirely — the binary cache still rides the virtio-fs tree, but the
	// Xcode compilation cache is not persisted (it stays VM-local, dying with
	// the VM). The image is sparse, so this is a ceiling, not an allocation.
	CASGiB int

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

	// retained is the set of branch dirs (keyed by VM name) that belong to
	// VMs still running after a kubelet restart. ReattachBranch adds to it
	// during state recovery; the startup SweepBranches keeps exactly these
	// and reaps the rest, so a restart never pulls a virtio-fs-mounted cache
	// out from under a live job.
	retained map[string]bool

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

// casEnabled reports whether the CAS disk image is managed (feature on AND a
// non-zero image cap configured).
func (m *VolumeManager) casEnabled() bool { return m.Enabled() && m.CASGiB > 0 }

// casReserveBytes is the per-live-branch headroom admission keeps for the CAS
// image on top of capBytes. Zero when the CAS image is disabled.
func (m *VolumeManager) casReserveBytes() uint64 {
	if !m.casEnabled() {
		return 0
	}
	return uint64(m.CASGiB) * 1024 * 1024 * 1024
}

// masterDir is <root>/<account>/<volume>/master.
func (m *VolumeManager) masterDir(account, volume string) string {
	return filepath.Join(m.Root, account, volume, "master")
}

// masterCASImage is the account's CAS disk image at <master>/xcode-cas.sparseimage.
func (m *VolumeManager) masterCASImage(account, volume string) string {
	return filepath.Join(m.masterDir(account, volume), casImageName)
}

// branchCASImage is a VM branch's CAS disk image at <branch>/xcode-cas.sparseimage.
// It lives inside the branch dir, which is already the virtio-fs share, so the
// guest attaches it with no extra mount.
func (m *VolumeManager) branchCASImage(att VolumeAttachment) string {
	return filepath.Join(att.BranchPath, casImageName)
}

// branchDir is <root>/branches/<vm>. Branches are per-VM and account-agnostic
// until Materialize — they live under a single top-level dir, not per account.
func (m *VolumeManager) branchDir(vm string) string {
	return filepath.Join(m.Root, "branches", vm)
}

func (m *VolumeManager) branchesRoot() string { return filepath.Join(m.Root, "branches") }

// ConvergeStagingDir is scratch on the runner-cache volume where a downloaded
// HEAD archive is extracted before ReplaceMaster swaps it in — on the same
// volume as the masters so the swap stays a same-volume CoW op.
func (m *VolumeManager) ConvergeStagingDir(vm string) string {
	return filepath.Join(m.Root, "_converge", vm)
}

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
	want := (m.capBytes() + m.casReserveBytes()) * uint64(m.liveBranches+1)
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

	// Materialize the CAS disk image FIRST and independent of the binary tree: a
	// job whose binary cache is cold on this host may still want a warm (or at
	// least a fresh, promotable) compilation cache, so this must run even when
	// the tree branch below takes the cold early return. Best-effort — a CAS
	// failure never costs the job its binary-cache warmth, which is the larger
	// win. The guest attaches whatever image lands here; if none does, its
	// compilation cache is simply VM-local (cold) this job.
	m.materializeCASImageLocked(att, account)

	masterTree := filepath.Join(m.masterDir(account, att.VolumeName), cacheHomeSubdir)
	if _, statErr := os.Stat(masterTree); statErr != nil {
		// No master tree for this account here yet: cold binary path. The guest
		// warms from the remote cache and Finalize promotes the result into a
		// new master tree.
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

// materializeCASImageLocked places the account's CAS disk image into the branch
// so the guest can attach it: a CoW clone of the account's master image when one
// exists, or a fresh empty sparse image for a cold first job (whose writes
// Finalize promotes into that account's first master). Best-effort and
// non-fatal — the caller holds m.mu. No-op when the CAS image is disabled.
//
// A cold first job with no master must still get an EMPTY image (not nothing):
// the guest needs a block device to attach so its build's CAS lands on the
// image and can be promoted. Without it the first job's CAS would fall to the
// VM-local disk and never persist.
func (m *VolumeManager) materializeCASImageLocked(att VolumeAttachment, account string) {
	if !m.casEnabled() {
		return
	}
	logger := log.Log.WithName("volume-cas")
	masterImg := m.masterCASImage(account, att.VolumeName)
	branchImg := m.branchCASImage(att)
	tmp := branchImg + ".materialize.tmp"
	_ = os.Remove(tmp)

	if _, statErr := os.Stat(masterImg); statErr == nil {
		if err := m.backend.cloneFile(masterImg, tmp); err != nil {
			_ = os.Remove(tmp)
			logger.Error(err, "clone CAS master image into branch", "account", account)
			return
		}
		// Bump master recency so LRU keeps a CAS-active account hot even when its
		// binary tree is cold on this host (that path doesn't touch the mtime).
		_ = os.Chtimes(m.masterDir(account, att.VolumeName), m.now(), m.now())
	} else {
		// No master image yet: create a fresh empty sparse image in the branch.
		// hdiutil takes the path without the .sparseimage suffix and appends it,
		// so create at a base path and then move the produced file to tmp.
		base := branchImg + ".create"
		_ = os.Remove(base + ".sparseimage")
		if err := m.backend.createSparseImage(base, m.CASGiB); err != nil {
			logger.Error(err, "create fresh CAS image", "account", account)
			return
		}
		if err := os.Rename(base+".sparseimage", tmp); err != nil {
			_ = os.Remove(base + ".sparseimage")
			logger.Error(err, "stage fresh CAS image", "account", account)
			return
		}
	}
	if err := os.Rename(tmp, branchImg); err != nil {
		_ = os.Remove(tmp)
		logger.Error(err, "swap CAS image into branch", "account", account)
	}
}

// MasterDigest returns the inventory digest of an account's on-disk master —
// the same fingerprint the guest reports as the volume HEAD (sorted entry names
// under the cache subtrees, SHA-1'd). Empty when the account has no master here.
// Compared against the HEAD to decide whether this host is behind and should
// converge before materializing.
func (m *VolumeManager) MasterDigest(account, volume string) (string, error) {
	if volume == "" {
		volume = ReservedTuistCacheVolume
	}
	return inventoryDigest(filepath.Join(m.masterDir(account, volume), cacheHomeSubdir))
}

// TreeDigest returns the inventory digest of a staged cache tree (dir/tuist),
// computed identically to MasterDigest and the guest's cache_inventory. Used to
// verify a downloaded HEAD archive matches the digest it claims before it
// replaces the local master.
func (m *VolumeManager) TreeDigest(dir string) (string, error) {
	return inventoryDigest(filepath.Join(dir, cacheHomeSubdir))
}

// cacheInventorySubdirs mirror dispatch-poll.sh's cache_inventory so host and
// guest compute the same digest over the cache subtrees whose entry-name churn
// means the cache actually changed.
var cacheInventorySubdirs = []string{"Binaries", "Manifests", "ProjectDescriptionHelpers", "Plugins"}

func inventoryDigest(cacheRoot string) (string, error) {
	var lines []string
	for _, sub := range cacheInventorySubdirs {
		entries, err := os.ReadDir(filepath.Join(cacheRoot, sub))
		if err != nil {
			continue // a missing subtree contributes no entries, like `ls` on a missing dir
		}
		for _, e := range entries {
			lines = append(lines, sub+"/"+e.Name())
		}
	}
	sort.Strings(lines)
	h := sha1.New()
	for _, l := range lines {
		_, _ = h.Write([]byte(l))
		_, _ = h.Write([]byte("\n"))
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// ReplaceMaster fast-forwards an account's master to the tree at src (an
// extracted archive of a fresher master pulled from the volume HEAD), then the
// caller materializes from it. src must live on the runner-cache volume so the
// clone stays a same-volume CoW op, and must contain the cache home subtree.
func (m *VolumeManager) ReplaceMaster(account, volume, src string) error {
	if !m.Enabled() {
		return nil
	}
	if volume == "" {
		volume = ReservedTuistCacheVolume
	}
	srcTree := filepath.Join(src, cacheHomeSubdir)
	if _, err := os.Stat(srcTree); err != nil {
		return fmt.Errorf("converged tree missing cache home: %w", err)
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	master := m.masterDir(account, volume)
	if err := os.MkdirAll(master, 0o755); err != nil {
		return fmt.Errorf("ensure master dir: %w", err)
	}
	// Swap only the `tuist` subtree, leaving the CAS disk image sibling in
	// place. This is what carries the host's local compilation cache forward
	// across a HEAD convergence: the HEAD archive is the binary tree only (the
	// CAS is per-host, never uploaded), so replacing the whole master dir would
	// drop the local CAS. Subtree-scoping preserves it by construction.
	masterTree := filepath.Join(master, cacheHomeSubdir)
	stagedTree := masterTree + ".converge"
	_ = os.RemoveAll(stagedTree)
	if err := m.backend.cloneTree(srcTree, stagedTree); err != nil {
		_ = os.RemoveAll(stagedTree)
		return fmt.Errorf("clone converged tree: %w", err)
	}
	oldTree := masterTree + ".old"
	_ = os.RemoveAll(oldTree)
	if _, err := os.Stat(masterTree); err == nil {
		if err := os.Rename(masterTree, oldTree); err != nil {
			_ = os.RemoveAll(stagedTree)
			return fmt.Errorf("stash old master tree: %w", err)
		}
	}
	if err := os.Rename(stagedTree, masterTree); err != nil {
		_ = os.Rename(oldTree, masterTree)
		return fmt.Errorf("swap converged master tree: %w", err)
	}
	_ = os.RemoveAll(oldTree)
	_ = os.Chtimes(master, m.now(), m.now())
	return nil
}

// Finalize promotes or discards a branch after the job ends and releases its
// reservation. Promotion is last-writer-wins and happens only when the job
// succeeded, the guest reported the cache actually changed (dirty), the account
// is known, AND that account matches the one the branch was materialized from.
// A read-only, failed, crashed (no marker), or never-dispatched branch
// discards.
//
// The SourceAccount == account guard is the defense-in-depth half of the
// cross-account fix: the server only stamps the materialize-trigger label after
// a dispatch commits, so in the normal path SourceAccount always equals the
// account the job ran. If a stale label from a failed dispatch ever let a
// branch materialized for account A reach a job the label now says is account
// B, promoting into B's master would leak A's artifacts — so a mismatch
// discards instead of promoting.
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
	if !jobSucceeded || !dirty || account == "" || att.SourceAccount != account {
		return discard()
	}
	if _, err := os.Stat(branchTree); err != nil {
		return discard()
	}

	master := m.masterDir(account, att.VolumeName)
	if err := os.MkdirAll(master, 0o755); err != nil {
		_ = os.RemoveAll(att.BranchPath)
		return "", fmt.Errorf("ensure master dir: %w", err)
	}
	// Swap only the `tuist` subtree, not the whole master dir, so sibling
	// artifacts in master/ (the CAS disk image, promoted just above) survive the
	// binary-tree promote.
	masterTree := filepath.Join(master, cacheHomeSubdir)
	stagedTree := masterTree + ".new"
	_ = os.RemoveAll(stagedTree)
	if err := m.backend.cloneTree(branchTree, stagedTree); err != nil {
		_ = os.RemoveAll(stagedTree)
		_ = os.RemoveAll(att.BranchPath)
		return "", fmt.Errorf("clone branch into staged master tree: %w", err)
	}
	// Swap stagedTree → master/tuist (last-writer-wins). A concurrent second VM
	// of the same account promoting after us simply replaces the tree with its
	// own; the loser's delta is bounded to one job and acceptable for a cache.
	oldTree := masterTree + ".old"
	_ = os.RemoveAll(oldTree)
	if _, err := os.Stat(masterTree); err == nil {
		if err := os.Rename(masterTree, oldTree); err != nil {
			_ = os.RemoveAll(stagedTree)
			_ = os.RemoveAll(att.BranchPath)
			return "", fmt.Errorf("stash old master tree: %w", err)
		}
	}
	if err := os.Rename(stagedTree, masterTree); err != nil {
		// Best-effort restore of the old tree so warmth isn't lost.
		_ = os.Rename(oldTree, masterTree)
		_ = os.RemoveAll(att.BranchPath)
		return "", fmt.Errorf("promote staged master tree: %w", err)
	}
	_ = os.RemoveAll(oldTree)
	_ = os.RemoveAll(att.BranchPath)
	_ = os.Chtimes(master, m.now(), m.now())
	return VolumeOutcomePromoted, nil
}

// FinalizeCAS promotes the branch's CAS disk image into the account's master
// when the runner exited 0 and the branch was materialized for this account.
// It is SEPARATE from Finalize (the binary tree) because the CAS promotes on its
// own gate — runner success alone, NOT the tree's dirty bit — so a compile-only
// job that leaves the binary cache clean still persists its compilation cache.
// Must be called BEFORE Finalize, which removes the branch on discard.
//
// runnerSucceeded MUST reflect the runner's own exit status (rc == 0), carried
// separately from the dirty marker. The host's clean-VM-halt signal is true on
// any exit (the VM always halts), and the dirty marker is written as "0" even on
// a failed run — so both stay true for a failed or cancelled job. Gating the CAS
// promote on either would advance the account's master from a failed run; only a
// dedicated runner-success signal is safe.
func (m *VolumeManager) FinalizeCAS(att VolumeAttachment, account string, runnerSucceeded bool) {
	if !m.casEnabled() || !att.Attached {
		return
	}
	if !runnerSucceeded || account == "" || att.SourceAccount != account {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.promoteCASImageLocked(att, account)
}

// promoteCASImageLocked clones the branch's CAS disk image over the account's
// master image (atomic tmp + rename), so the next job on this host materializes
// the grown compilation cache. Best-effort and non-fatal; the caller holds m.mu
// and has already checked runner success + account match. No-op when the CAS
// image is disabled or the branch produced none (the guest never attached one —
// its CAS ran VM-local this job).
func (m *VolumeManager) promoteCASImageLocked(att VolumeAttachment, account string) {
	if !m.casEnabled() {
		return
	}
	branchImg := m.branchCASImage(att)
	// Lstat, not Stat: the branch is a guest-writable virtio-fs share, so a
	// hostile job can unlink its own CAS image and drop a SYMLINK in its place
	// pointing at another account's master image (a guessable numeric path on the
	// same runner-cache volume). `cp -c` follows a command-line symlink, so
	// cloning it would pull that account's CAS into this job's master — a
	// cross-account leak. Refuse anything that isn't a plain regular file.
	fi, err := os.Lstat(branchImg)
	if err != nil {
		return
	}
	if !fi.Mode().IsRegular() {
		log.Log.WithName("volume-cas").Info("refusing to promote non-regular CAS image (possible symlink attack)", "account", account, "mode", fi.Mode().String())
		return
	}
	logger := log.Log.WithName("volume-cas")
	master := m.masterDir(account, att.VolumeName)
	if err := os.MkdirAll(master, 0o755); err != nil {
		logger.Error(err, "ensure master dir for CAS promote", "account", account)
		return
	}
	masterImg := m.masterCASImage(account, att.VolumeName)
	tmp := masterImg + ".promote.tmp"
	_ = os.Remove(tmp)
	if err := m.backend.cloneFile(branchImg, tmp); err != nil {
		_ = os.Remove(tmp)
		logger.Error(err, "clone branch CAS image", "account", account)
		return
	}
	if err := os.Rename(tmp, masterImg); err != nil {
		_ = os.Remove(tmp)
		logger.Error(err, "swap CAS master image", "account", account)
	}
}

// ReattachBranch reconstructs the attachment for a VM whose branch survived a
// kubelet restart (its Tart VM is still running, virtio-fs-mounting the branch)
// and marks the branch to be preserved by the startup SweepBranches. Returns
// (zero, false) when the feature is off or the branch is gone. The caller sets
// SourceAccount from the Pod's runner-account label so the recovered job's
// warm set still promotes into the right master on completion.
func (m *VolumeManager) ReattachBranch(volume, vm string) (VolumeAttachment, bool) {
	if !m.Enabled() {
		return VolumeAttachment{}, false
	}
	if volume == "" {
		volume = ReservedTuistCacheVolume
	}
	branch := m.branchDir(vm)
	if _, err := os.Stat(branch); err != nil {
		return VolumeAttachment{}, false
	}

	m.mu.Lock()
	if m.retained == nil {
		m.retained = map[string]bool{}
	}
	m.retained[vm] = true
	m.mu.Unlock()

	materialized := false
	if _, err := os.Stat(filepath.Join(branch, materializedMarker)); err == nil {
		materialized = true
	}
	return VolumeAttachment{
		Attached:     true,
		VolumeName:   volume,
		BranchPath:   branch,
		Materialized: materialized,
	}, true
}

// MarkMaterialized drops the host-written materialization sentinel in a branch,
// so a kubelet restart can tell a materialized branch from an idle VM's
// boot-created (empty) cache subtree. Best-effort: a write failure only means a
// recovered VM re-materializes, which is safe.
func (m *VolumeManager) MarkMaterialized(att VolumeAttachment) {
	if !m.Enabled() || !att.Attached || att.BranchPath == "" {
		return
	}
	_ = os.WriteFile(filepath.Join(att.BranchPath, materializedMarker), []byte("1"), 0o644)
}

// SweepBranches reaps per-VM branch directories on startup, keeping only those
// ReattachBranch marked as belonging to a VM that survived the restart. Swept
// branches are dead per-job scratch whose VM is gone (their Finalize can never
// run) and would otherwise leak disk; retained branches are still virtio-fs-
// mounted by a live job, so removing them would corrupt that job's cache.
// liveBranches is reset to the retained count so admission accounting matches
// what actually survived. No-op when the feature is off.
func (m *VolumeManager) SweepBranches() error {
	if !m.Enabled() {
		return nil
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	// Convergence scratch is per-job too, so it can't survive a restart either
	// (a live VM's convergence completed before its job started).
	_ = os.RemoveAll(filepath.Join(m.Root, "_converge"))
	entries, err := os.ReadDir(m.branchesRoot())
	if err != nil {
		if os.IsNotExist(err) {
			m.liveBranches = 0
			return nil
		}
		return err
	}
	kept := 0
	for _, e := range entries {
		if m.retained[e.Name()] {
			kept++
			continue
		}
		_ = os.RemoveAll(filepath.Join(m.branchesRoot(), e.Name()))
	}
	m.liveBranches = kept
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
