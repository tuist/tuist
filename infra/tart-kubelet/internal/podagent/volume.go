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
	"strings"
	"sync"
	"time"

	"sigs.k8s.io/controller-runtime/pkg/log"
)

// Per-account cache volumes for the macOS runner fleet.
//
// A VolumeManager owns the lifecycle of per-account cache masters kept as
// sparse APFS disk images under a single quota-bounded runner-cache root. The
// model is "materialize after dispatch":
//
//   - A warm-pool VM boots GENERIC — an empty, writable directory is attached
//     as a virtio-fs share at the cache root. No account data, no prediction.
//   - The server stamps the pod's `tuist.dev/runner-account` label when it
//     claims a job. The reconciler then calls Materialize, which APFS-
//     clonefiles that account's master IMAGE into the VM's branch (instant,
//     CoW) and the guest is signalled to attach it and proceed warm.
//   - On job end Finalize promotes the branch image back to the account's
//     master (job succeeded AND the cache changed) or discards it.
//
// The cache is a disk image rather than a directory tree because the share
// between host and guest is virtio-fs, which cannot carry a macOS cache
// faithfully: copying a versioned framework bundle onto it fails to set
// extended attributes on the bundle's symlinks (surfacing as ELOOP), and the
// CLI's artifact signatures live in xattrs. With an image, exactly one regular
// file crosses virtio-fs and the filesystem inside it is real APFS, so
// symlinks, xattrs, ownership and inode semantics are native. The guest
// attaches with `-owners off`, which also makes the host/guest uid split
// irrelevant — the only permission the host has to settle is the mode of the
// image file itself.
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
// (VZXHCIController runtime attach): only the device swaps — an image on a
// virtio-fs share today, a hot-attached block device once tart exposes the API.

// ReservedTuistCacheVolume is the reserved volume name for the managed Tuist
// module cache. Masters are keyed (account_id, volume_name) on disk so that
// generic, user-declared volumes (spec #69) are new names rather than a
// re-keying migration.
const ReservedTuistCacheVolume = "tuist-cache"

// cacheHomeSubdir is the single top-level directory the Tuist CLI writes under
// its cache home (TUIST_XDG_CACHE_HOME/tuist/...), which the guest points at
// the mounted image. The host only sees it when it reads an image's inventory
// through a read-only attach.
const cacheHomeSubdir = "tuist"

// masterImageName / masterDigestName are the account's promoted cache image and
// the sidecar recording the inventory digest of what is inside it. The host
// cannot see into an image without attaching it, so the digest travels beside
// the file rather than being computed on demand.
const (
	masterImageName  = "master.sparseimage"
	masterDigestName = "master.digest"
)

// branchImageName is the cache image inside a VM's branch share — the only
// thing that crosses virtio-fs. The guest attaches it by this name.
const branchImageName = "cache.sparseimage"

// casImageName is the per-account Xcode compilation-cache (CAS) store, carried
// as a SECOND sparse APFS disk image sitting beside the binary cache image in
// the same volume dir (master) and branch share.
//
// It is a separate image, not a subtree of the binary cache image, for two
// reasons. First, promotion gate: the binary cache promotes only when the guest
// reports it changed (dirty), while the CAS promotes on runner success alone —
// a compile-only job that leaves the binary cache clean still grew its
// compilation cache — so the two cannot share one promote decision. Second,
// blast radius: llcas is the component that corrupts under load, and a torn CAS
// snapshot must not be able to tear the binary cache. Two sibling image files
// are independent by construction: promoting one via rename never touches the
// other.
//
// Like the binary cache, an image (not a bare subtree on the share) because
// Xcode's on-disk CAS (llcas / UnifiedOnDiskCache) memory-maps its store, and
// mmap over virtio-fs faults with SIGBUS; attaching a block-device APFS image
// off the share gives llcas real read/write. The host clonefiles it
// master<->branch exactly like the binary image, and it is sparse so a master
// costs only its real CAS bytes.
const casImageName = "xcode-cas.sparseimage"

// materializedMarker is a host-written sentinel dropped in the branch once the
// host has materialized (or decided cold-path) for a VM. It is the ONLY signal
// that the branch was host-materialized, and it stays host-authoritative: the
// guest writes only inside the image, never this dotfile. That keeps restart
// recovery from marking an idle branch materialized and skipping its real
// materialization.
const materializedMarker = ".host-materialized"

// volumeBackend abstracts the macOS-specific operations the manager needs so
// its lifecycle logic (admission, LRU, promote/discard, paths) is testable off
// a Mac. The real implementation lives in volume_darwin.go (clonefile via
// `cp -c`, statfs via `df`, images via `hdiutil`); tests inject a fake.
type volumeBackend interface {
	// clonePath CoW-clones the file at src to dst (APFS clonefile: instant, no
	// byte copy). dst must not exist; its parent must.
	clonePath(src, dst string) error
	// freeBytes reports the free space on the filesystem holding root
	// (statfs). Ground truth for admission and watermarks: per-file sizes
	// cannot be summed because CoW clones share blocks.
	freeBytes(root string) (uint64, error)
	// createImage creates an empty sparse APFS disk image of at most sizeGiB
	// at path. Sparse: the file costs megabytes until written. Used for both
	// the binary cache image and an account's first CAS master on a host.
	createImage(path string, sizeGiB int) error
	// imageInventoryDigest attaches the image read-only and returns the
	// inventory digest of the cache home inside it.
	imageInventoryDigest(path string) (string, error)
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
	// BranchPath is the per-VM branch directory shared into the VM. It holds
	// exactly one file: the branch cache image.
	BranchPath string
	// SourceAccount is the account whose master was materialized into the
	// branch, learned from the pod label at dispatch. Empty until Materialize
	// runs (or if the VM is never dispatched).
	SourceAccount string
	// Materialized is true once the account's master has been clonefiled into
	// the branch (or determined absent — a cold first job). Guards against
	// re-materializing on repeated reconciles.
	Materialized bool
	// ReportedDigest is the inventory digest the guest computed inside the
	// mounted image at job end, recorded beside the master on promotion. The
	// host cannot compute it itself without attaching the image, so the guest
	// — which had it mounted anyway — reports it.
	ReportedDigest string
}

// VolumeManager manages per-account cache-volume master images under a single
// quota-bounded runner-cache root. Safe for concurrent use.
type VolumeManager struct {
	// Root is the runner-cache root — a dedicated quota-bounded APFS volume
	// provisioned at host bootstrap. Empty disables the whole feature: every
	// method no-ops and every VM boots on the cold path.
	Root string

	// CapGiB is the provisioned size of a cache image and the worst-case
	// growth admission reserves per live branch. The image is sparse, so this
	// is a ceiling rather than an allocation; the APFS volume's own quota is
	// the real aggregate ceiling.
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
	// and reaps the rest, so a restart never pulls a mounted cache image out
	// from under a live job.
	retained map[string]bool

	// ReconcileInterval is how often the background watermark evictor +
	// observability sampler runs. Defaults to 5m.
	ReconcileInterval time.Duration

	// now is injectable for tests; defaults to time.Now.
	now func() time.Time
}

// NewVolumeManager builds a manager. root == "" returns a disabled manager
// whose methods all no-op. A nil backend defaults to the platform backend
// (macOS clonefile/df/hdiutil); tests inject a fake.
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

// volumeDir is <root>/<account>/<volume> — the master image, its digest
// sidecar, and the sibling CAS master image live here, and eviction drops the
// whole directory.
func (m *VolumeManager) volumeDir(account, volume string) string {
	return filepath.Join(m.Root, account, volume)
}

// masterImage is <root>/<account>/<volume>/master.sparseimage.
func (m *VolumeManager) masterImage(account, volume string) string {
	return filepath.Join(m.volumeDir(account, volume), masterImageName)
}

// masterDigestPath is the sidecar recording the inventory digest of the
// master image's contents.
func (m *VolumeManager) masterDigestPath(account, volume string) string {
	return filepath.Join(m.volumeDir(account, volume), masterDigestName)
}

// masterCASImage is the account's CAS disk image at
// <root>/<account>/<volume>/xcode-cas.sparseimage — a sibling of the binary
// master image in the same volume dir.
func (m *VolumeManager) masterCASImage(account, volume string) string {
	return filepath.Join(m.volumeDir(account, volume), casImageName)
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

// BranchImage is the cache image inside a VM's branch share — the path the
// guest attaches.
func (m *VolumeManager) BranchImage(att VolumeAttachment) string {
	return filepath.Join(att.BranchPath, branchImageName)
}

// ConvergeStagingDir is scratch on the runner-cache volume where a downloaded
// HEAD image is written before ReplaceMaster swaps it in — on the same volume
// as the masters so the swap stays a same-volume CoW op.
func (m *VolumeManager) ConvergeStagingDir(vm string) string {
	return filepath.Join(m.Root, convergeDirName, vm)
}

// convergeDirName is the top-level scratch dir for convergence downloads. It
// sits beside the account dirs under Root, so master scanning skips it by name.
const convergeDirName = "_converge"

// AllocateBranch prepares an empty per-VM branch directory for a booting warm-
// pool VM and reserves its worst-case growth against the quota volume. It
// clones nothing and predicts nothing — the branch gets its image later from
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
	// 0o777 so the guest's unprivileged runner user can attach the image
	// read-write over the virtio-fs share (the host relaxes the status share
	// the same way).
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

// Materialize clonefiles the given account's master image into the VM's branch,
// making the branch a warm, private CoW copy of the account's cache. It is
// called once, after the server has stamped the pod's account label. Returns
// warm=true when a master existed and was cloned; warm=false when the account
// has no master on this host yet (a cold first job whose writes Finalize will
// promote into that account's first master).
//
// Every path leaves an image at the branch: the guest is already pointed at the
// share and cannot attach what isn't there, and a missing image kills the job
// on its first cache write. So a clone failure or an absent master falls back to
// creating an EMPTY image and running cold — cold costs warmth, no image costs
// the job.
func (m *VolumeManager) Materialize(att VolumeAttachment, account string) (warm bool, err error) {
	if !m.Enabled() || !att.Attached || account == "" {
		return false, nil
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	// Materialize the CAS image FIRST and independent of the binary cache: a job
	// whose binary cache is cold on this host may still want a warm (or at least
	// a fresh, promotable) compilation cache, so this must run even when the
	// binary branch below takes the cold early return. Best-effort — a CAS
	// failure never costs the job its binary-cache warmth, which is the larger
	// win. The guest attaches whatever CAS image lands here; if none does, its
	// compilation cache is simply VM-local (cold) this job.
	m.materializeCASImageLocked(att, account)

	dest := m.BranchImage(att)
	master := m.masterImage(account, att.VolumeName)
	if _, statErr := os.Stat(master); statErr != nil {
		// No master for this account here yet: cold path. The guest warms from
		// the remote cache and Finalize promotes the result into a new master.
		return false, m.createBranchImageLocked(dest)
	}

	// Clone beside the destination and rename, so a clone that fails partway
	// never leaves a torn image the guest could attach.
	tmp := dest + ".materialize.tmp"
	_ = os.Remove(tmp)
	if err := m.backend.clonePath(master, tmp); err != nil {
		_ = os.Remove(tmp)
		return false, joinFallback(fmt.Errorf("clone master image into branch: %w", err), m.createBranchImageLocked(dest))
	}
	_ = os.Remove(dest)
	if err := os.Rename(tmp, dest); err != nil {
		_ = os.Remove(tmp)
		return false, joinFallback(fmt.Errorf("swap materialized image into place: %w", err), m.createBranchImageLocked(dest))
	}
	if err := chmodImageGuestWritable(dest); err != nil {
		return false, fmt.Errorf("make materialized image guest-writable: %w", err)
	}
	// Mark the master used so LRU tracks materialization, not just promotion —
	// an account whose jobs keep landing here stays hot.
	_ = os.Chtimes(master, m.now(), m.now())
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

	if _, statErr := os.Stat(masterImg); statErr == nil {
		// Warm: CoW-clone the CAS master into the branch beside the destination
		// and rename, so a clone that fails partway never leaves a torn image the
		// guest could attach.
		tmp := branchImg + ".materialize.tmp"
		_ = os.Remove(tmp)
		if err := m.backend.clonePath(masterImg, tmp); err != nil {
			_ = os.Remove(tmp)
			logger.Error(err, "clone CAS master image into branch", "account", account)
			return
		}
		_ = os.Remove(branchImg)
		if err := os.Rename(tmp, branchImg); err != nil {
			_ = os.Remove(tmp)
			logger.Error(err, "swap CAS image into branch", "account", account)
			return
		}
		// Bump master recency so LRU keeps a CAS-active account hot even when its
		// binary cache is cold on this host (that path doesn't touch the mtime).
		_ = os.Chtimes(m.volumeDir(account, att.VolumeName), m.now(), m.now())
	} else {
		// No master yet: create a fresh empty sparse image directly at the branch
		// path (createImage writes at the given .sparseimage path, like the binary
		// cold path's createBranchImageLocked).
		_ = os.Remove(branchImg)
		if err := m.backend.createImage(branchImg, m.CASGiB); err != nil {
			logger.Error(err, "create fresh CAS image", "account", account)
			return
		}
	}
	// The guest attaches this READ-WRITE with its unprivileged runner user. A
	// cloned image carries the master's mode and a fresh one the kubelet's;
	// 0666 (uid-independent, and everything inside is the guest's own under
	// `-owners off`) lets the attach succeed. Without it the CAS silently
	// degrades to VM-local.
	_ = chmodImageGuestWritable(branchImg)
}

// MaterializeEmpty gives a branch an empty image without consulting any
// account's master. Used for untrusted (fork) jobs, which must neither read the
// account's warm master nor promote into it, but still need something to attach
// — cache-ready always means "an image is waiting for you".
func (m *VolumeManager) MaterializeEmpty(att VolumeAttachment) error {
	if !m.Enabled() || !att.Attached {
		return nil
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.createBranchImageLocked(m.BranchImage(att))
}

// createBranchImageLocked puts an empty, guest-writable cache image at dest,
// replacing whatever is there.
func (m *VolumeManager) createBranchImageLocked(dest string) error {
	_ = os.Remove(dest)
	if err := m.backend.createImage(dest, m.CapGiB); err != nil {
		return fmt.Errorf("create empty cache image: %w", err)
	}
	return chmodImageGuestWritable(dest)
}

// chmodImageGuestWritable makes the image file writable by the guest's
// unprivileged user, which is all the permission handling this design needs:
// host and guest uids don't line up across virtio-fs, so mode is the only lever
// and 0666 is uid-independent. Everything INSIDE the image is the guest's own
// because it attaches with `-owners off`.
func chmodImageGuestWritable(image string) error { return os.Chmod(image, 0o666) }

// joinFallback reports the original failure, plus the fallback's own failure
// when even that didn't work.
func joinFallback(err, fallbackErr error) error {
	if fallbackErr == nil {
		return err
	}
	return errors.Join(err, fallbackErr)
}

// MasterDigest returns the inventory digest of an account's on-disk master —
// the same fingerprint the guest reports as the volume HEAD. It READS the
// sidecar rather than computing it: the host cannot see inside an image without
// attaching it, so the digest is recorded when the master is written. Empty when
// the account has no master here (or its digest was never recorded), which makes
// the caller converge rather than assume it is current.
func (m *VolumeManager) MasterDigest(account, volume string) (string, error) {
	if volume == "" {
		volume = ReservedTuistCacheVolume
	}
	b, err := os.ReadFile(m.masterDigestPath(account, volume))
	if err != nil {
		if os.IsNotExist(err) {
			return "", nil
		}
		return "", err
	}
	return strings.TrimSpace(string(b)), nil
}

// ImageDigest returns the inventory digest of the cache inside an image — the
// one place the host looks in. It attaches READ-ONLY, so it is safe to run
// beside a concurrent reader and cannot mutate what it measures. Used to verify
// a downloaded HEAD image matches its advertised digest before adoption.
func (m *VolumeManager) ImageDigest(image string) (string, error) {
	return m.backend.imageInventoryDigest(image)
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
			// Skip dotfiles to match the guest's `ls -1` (no -a): os.ReadDir
			// returns hidden entries (.DS_Store, in-flight .tmp*) that `ls -1`
			// omits, so including them here would make the host digest disagree
			// with the guest-reported one and abort every convergence.
			if strings.HasPrefix(e.Name(), ".") {
				continue
			}
			lines = append(lines, sub+"/"+e.Name())
		}
	}
	// Byte order, matching the guest's `LC_ALL=C sort`. Go's sort.Strings is
	// already byte-wise; the guest is the side that has to pin the locale.
	sort.Strings(lines)
	h := sha1.New()
	for _, l := range lines {
		_, _ = h.Write([]byte(l))
		_, _ = h.Write([]byte("\n"))
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// ReplaceMaster fast-forwards an account's master to the image at src (a
// fresher master downloaded from the volume HEAD), recording digest as the
// inventory it holds. src must live on the runner-cache volume so the clone
// stays a same-volume CoW op.
func (m *VolumeManager) ReplaceMaster(account, volume, src, digest string) error {
	if !m.Enabled() {
		return nil
	}
	if volume == "" {
		volume = ReservedTuistCacheVolume
	}
	if _, err := os.Stat(src); err != nil {
		return fmt.Errorf("converged image missing: %w", err)
	}

	m.mu.Lock()
	defer m.mu.Unlock()
	return m.installMasterLocked(account, volume, src, digest)
}

// installMasterLocked clones srcImage into the account's master slot and swaps
// it in, recording digest beside it. Last-writer-wins.
func (m *VolumeManager) installMasterLocked(account, volume, srcImage, digest string) error {
	if err := os.MkdirAll(m.volumeDir(account, volume), 0o755); err != nil {
		return fmt.Errorf("mkdir volume dir: %w", err)
	}
	master := m.masterImage(account, volume)
	staged := master + ".new"
	_ = os.Remove(staged)
	if err := m.backend.clonePath(srcImage, staged); err != nil {
		_ = os.Remove(staged)
		return fmt.Errorf("clone image into staged master: %w", err)
	}
	// Rename first, digest second. A crash between the two leaves a fresh image
	// under a stale/absent digest, which only makes the next convergence
	// re-download; the reverse order would leave a digest claiming a freshness
	// the image doesn't have, and the host would never converge again.
	if err := os.Rename(staged, master); err != nil {
		_ = os.Remove(staged)
		return fmt.Errorf("swap master image: %w", err)
	}
	sidecar := m.masterDigestPath(account, volume)
	if err := os.WriteFile(sidecar, []byte(digest), 0o644); err != nil {
		_ = os.Remove(sidecar)
	}
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
//
// The branch image is promoted as-is: the guest detaches before the host reads
// it, so the file is a settled filesystem rather than a torn snapshot.
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

	if !jobSucceeded || !dirty || account == "" || att.SourceAccount != account {
		return discard()
	}
	image := m.BranchImage(att)
	if _, err := os.Stat(image); err != nil {
		return discard()
	}

	if err := m.installMasterLocked(account, att.VolumeName, image, att.ReportedDigest); err != nil {
		_ = os.RemoveAll(att.BranchPath)
		return "", err
	}
	_ = os.RemoveAll(att.BranchPath)
	return VolumeOutcomePromoted, nil
}

// FinalizeCAS promotes the branch's CAS disk image into the account's master
// when the runner exited 0 and the branch was materialized for this account.
// It is SEPARATE from Finalize (the binary cache) because the CAS promotes on
// its own gate — runner success alone, NOT the dirty bit — so a compile-only
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
	// Lstat, not Stat: the branch share is guest-writable, so a hostile job can
	// unlink its own CAS image and drop a SYMLINK in its place pointing at
	// another account's master image (a guessable numeric path on the same
	// runner-cache volume). clonePath's `cp -c` follows a command-line symlink,
	// so cloning it would pull that account's CAS into this job's master — a
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
	if err := os.MkdirAll(m.volumeDir(account, att.VolumeName), 0o755); err != nil {
		logger.Error(err, "ensure volume dir for CAS promote", "account", account)
		return
	}
	masterImg := m.masterCASImage(account, att.VolumeName)
	tmp := masterImg + ".promote.tmp"
	_ = os.Remove(tmp)
	if err := m.backend.clonePath(branchImg, tmp); err != nil {
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
// kubelet restart (its Tart VM is still running, with the branch image mounted)
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
// so a kubelet restart can tell a materialized branch from an idle VM's.
// Best-effort: a write failure only means a recovered VM re-materializes, which
// is safe.
func (m *VolumeManager) MarkMaterialized(att VolumeAttachment) {
	if !m.Enabled() || !att.Attached || att.BranchPath == "" {
		return
	}
	_ = os.WriteFile(filepath.Join(att.BranchPath, materializedMarker), []byte("1"), 0o644)
}

// SweepBranches reaps per-VM branch directories on startup, keeping only those
// ReattachBranch marked as belonging to a VM that survived the restart. Swept
// branches are dead per-job scratch whose VM is gone (their Finalize can never
// run) and would otherwise leak disk; retained branches still have their image
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
	_ = os.RemoveAll(filepath.Join(m.Root, convergeDirName))
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

// allMastersLocked scans <root>/<account>/<volume>/master.sparseimage. Accounts
// are directory names; the branches dir (per-VM scratch) and the convergence
// scratch dir are skipped. Eviction drops the whole <account>/<volume> dir, so
// the entry path is that dir, while LRU order comes from the image's mtime.
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
		if !acct.IsDir() || acct.Name() == "branches" || acct.Name() == convergeDirName {
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
			info, err := os.Stat(m.masterImage(acct.Name(), vol.Name()))
			if err != nil {
				continue
			}
			out = append(out, masterEntry{
				account: acct.Name(),
				path:    m.volumeDir(acct.Name(), vol.Name()),
				modTime: info.ModTime(),
			})
		}
	}
	return out, nil
}
