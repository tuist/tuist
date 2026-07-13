package podagent

import (
	"crypto/sha1"
	"encoding/hex"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// fakeBackend models APFS clonefile + statfs against real files under a temp
// root so the manager's os-based master scanning works unchanged. Free space is
// total minus one provisioned cap per resident master directory; branches are
// CoW-sparse and don't count, mirroring the real backend.
type fakeBackend struct {
	totalBytes uint64
	perMaster  uint64
	root       string
}

func (f *fakeBackend) cloneTree(src, dst string) error {
	if _, err := os.Stat(dst); err == nil {
		return os.ErrExist
	}
	return copyTree(src, dst)
}

func copyTree(src, dst string) error {
	info, err := os.Stat(src)
	if err != nil {
		return err
	}
	if info.IsDir() {
		if err := os.MkdirAll(dst, 0o777); err != nil {
			return err
		}
		entries, err := os.ReadDir(src)
		if err != nil {
			return err
		}
		for _, e := range entries {
			if err := copyTree(filepath.Join(src, e.Name()), filepath.Join(dst, e.Name())); err != nil {
				return err
			}
		}
		return nil
	}
	b, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	return os.WriteFile(dst, b, 0o644)
}

func (f *fakeBackend) freeBytes(root string) (uint64, error) {
	var masters uint64
	_ = filepath.Walk(root, func(p string, info os.FileInfo, err error) error {
		if err != nil || !info.IsDir() || filepath.Base(p) != "master" {
			return nil
		}
		// <root>/<account>/<volume>/master — a real master, not the branches dir.
		if filepath.Base(filepath.Dir(filepath.Dir(filepath.Dir(p)))) == filepath.Base(root) {
			masters++
		}
		return nil
	})
	used := masters * f.perMaster
	if used > f.totalBytes {
		return 0, nil
	}
	return f.totalBytes - used, nil
}

const gib = uint64(1024 * 1024 * 1024)

func newTestManager(t *testing.T, totalGiB int) (*VolumeManager, *fakeBackend) {
	t.Helper()
	root := t.TempDir()
	be := &fakeBackend{totalBytes: uint64(totalGiB) * gib, perMaster: gib, root: root}
	return NewVolumeManager(root, 1, be), be // 1 GiB provisioned cap
}

func mustAllocate(t *testing.T, m *VolumeManager, vm string) VolumeAttachment {
	t.Helper()
	att, err := m.AllocateBranch(ReservedTuistCacheVolume, vm)
	if err != nil {
		t.Fatalf("AllocateBranch: %v", err)
	}
	return att
}

// writeBranchCache simulates a job writing cache artifacts into the branch's
// tuist subtree (what the guest does during a job before promote).
func writeBranchCache(t *testing.T, att VolumeAttachment, marker string) {
	t.Helper()
	dir := filepath.Join(att.BranchPath, cacheHomeSubdir, "Binaries")
	if err := os.MkdirAll(dir, 0o777); err != nil {
		t.Fatalf("write branch cache: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "artifact"), []byte(marker), 0o644); err != nil {
		t.Fatalf("write branch cache: %v", err)
	}
}

func masterExists(m *VolumeManager, account string) bool {
	_, err := os.Stat(m.masterDir(account, ReservedTuistCacheVolume))
	return err == nil
}

func branchTuistExists(att VolumeAttachment) bool {
	_, err := os.Stat(filepath.Join(att.BranchPath, cacheHomeSubdir))
	return err == nil
}

func TestVolumeDisabled(t *testing.T) {
	m := NewVolumeManager("", 1, &fakeBackend{})
	att, err := m.AllocateBranch(ReservedTuistCacheVolume, "vm1")
	if err != nil || att.Attached {
		t.Fatalf("disabled manager should not attach: att=%+v err=%v", att, err)
	}
	if warm, err := m.Materialize(att, "42"); err != nil || warm {
		t.Fatalf("disabled Materialize = %v, %v; want false, nil", warm, err)
	}
	out, err := m.Finalize(att, "42", true, true)
	if err != nil || out != VolumeOutcomeNone {
		t.Fatalf("disabled Finalize = %s, %v; want none", out, err)
	}
}

func TestColdFirstJobSeedsMaster(t *testing.T) {
	m, _ := newTestManager(t, 100)
	att := mustAllocate(t, m, "vm1")
	if !att.Attached {
		t.Fatalf("branch should attach: %+v", att)
	}
	// No master for account 42 yet: cold materialize.
	warm, err := m.Materialize(att, "42")
	if err != nil || warm {
		t.Fatalf("cold Materialize = %v, %v; want false, nil", warm, err)
	}
	if branchTuistExists(att) {
		t.Fatal("cold branch should have no materialized cache")
	}
	// The job pulls + writes the cache, then promotes.
	writeBranchCache(t, att, "from-42")
	out, err := m.Finalize(att, "42", true, true)
	if err != nil || out != VolumeOutcomePromoted {
		t.Fatalf("Finalize = %s, %v; want promoted", out, err)
	}
	if !masterExists(m, "42") {
		t.Fatal("account 42 master should exist after promote")
	}
	if _, err := os.Stat(att.BranchPath); !os.IsNotExist(err) {
		t.Fatal("branch should be gone after promote")
	}
}

func TestWarmMaterializeAndPromote(t *testing.T) {
	m, _ := newTestManager(t, 100)
	// Seed account 42's master with a known artifact.
	seedMaster(t, m, "42")

	att := mustAllocate(t, m, "vm2")
	warm, err := m.Materialize(att, "42")
	if err != nil || !warm {
		t.Fatalf("warm Materialize = %v, %v; want true, nil", warm, err)
	}
	// The account's cached artifact is now visible in the branch.
	got, err := os.ReadFile(filepath.Join(att.BranchPath, cacheHomeSubdir, "Binaries", "marker"))
	if err != nil || string(got) != "42" {
		t.Fatalf("materialized branch marker = %q, %v; want \"42\"", got, err)
	}
	if out, err := m.Finalize(att, "42", true, true); err != nil || out != VolumeOutcomePromoted {
		t.Fatalf("warm Finalize = %s, %v; want promoted", out, err)
	}
	if !masterExists(m, "42") {
		t.Fatal("account 42 master should still exist")
	}
}

// A VM dispatched to account 99 only ever materializes account 99's master —
// account 42's cache is structurally unreachable, so there is no cross-account
// exposure and no misprediction to guard.
func TestMaterializeIsAccountScoped(t *testing.T) {
	m, _ := newTestManager(t, 100)
	seedMaster(t, m, "42")

	att := mustAllocate(t, m, "vm3")
	warm, err := m.Materialize(att, "99") // dispatched to 99, which has no master here
	if err != nil || warm {
		t.Fatalf("Materialize(99) = %v, %v; want cold (false), nil", warm, err)
	}
	if branchTuistExists(att) {
		t.Fatal("account 99's VM must not see account 42's cache")
	}
	writeBranchCache(t, att, "from-99")
	if out, err := m.Finalize(att, "99", true, true); err != nil || out != VolumeOutcomePromoted {
		t.Fatalf("Finalize(99) = %s, %v; want promoted", out, err)
	}
	if !masterExists(m, "99") {
		t.Fatal("account 99's master should be created")
	}
	if !masterExists(m, "42") {
		t.Fatal("account 42's master must survive untouched")
	}
}

func TestReadOnlyAndFailedDiscard(t *testing.T) {
	m, _ := newTestManager(t, 100)

	// Clean/read-only job: success but not dirty.
	att := mustAllocate(t, m, "vm-ro")
	_, _ = m.Materialize(att, "42")
	if out, _ := m.Finalize(att, "42", true, false); out != VolumeOutcomeDiscarded {
		t.Fatalf("read-only job should discard, got %s", out)
	}
	if masterExists(m, "42") {
		t.Fatal("read-only job must not create a master")
	}

	// Failed job: dirty but not successful.
	att = mustAllocate(t, m, "vm-fail")
	_, _ = m.Materialize(att, "42")
	writeBranchCache(t, att, "half")
	if out, _ := m.Finalize(att, "42", false, true); out != VolumeOutcomeDiscarded {
		t.Fatalf("failed job should discard, got %s", out)
	}
	if masterExists(m, "42") {
		t.Fatal("failed job must not create a master")
	}
}

func TestNeverDispatchedDiscards(t *testing.T) {
	m, _ := newTestManager(t, 100)
	att := mustAllocate(t, m, "idle-vm")
	// VM was never dispatched: no account, no materialize. Finalize with an
	// empty account discards and releases the reservation.
	if out, _ := m.Finalize(att, "", false, false); out != VolumeOutcomeDiscarded {
		t.Fatalf("never-dispatched VM should discard, got %s", out)
	}
}

func TestAdmissionDeclinesToColdPath(t *testing.T) {
	// Total capacity below one provisioned cap: no room even after eviction.
	root := t.TempDir()
	be := &fakeBackend{totalBytes: gib / 2, perMaster: gib, root: root}
	m := NewVolumeManager(root, 1, be)

	att, err := m.AllocateBranch(ReservedTuistCacheVolume, "vm1")
	if err != nil {
		t.Fatalf("AllocateBranch err: %v", err)
	}
	if att.Attached {
		t.Fatal("admission should decline (cold path) when the root cannot fit a cap")
	}
}

func TestAdmissionEvictsThenAdmits(t *testing.T) {
	// 3 GiB total, 1 GiB cap. Seed 3 masters (free -> 0), then a new attach
	// must evict an LRU master to make room and still admit.
	m, _ := newTestManager(t, 3)
	for i, acct := range []string{"a", "b", "c"} {
		seedMaster(t, m, acct)
		setMtime(t, m.masterDir(acct, ReservedTuistCacheVolume), time.Now().Add(time.Duration(i)*time.Minute))
	}

	att := mustAllocate(t, m, "vmX")
	if !att.Attached {
		t.Fatal("attach should admit after evicting an LRU master")
	}
	if masterExists(m, "a") {
		t.Fatal("oldest master 'a' should have been evicted for admission")
	}
}

// Reservation (review finding 3): CoW branches start ~0 bytes, so instantaneous
// free space would let N concurrent branches all pass a per-branch check and
// later exhaust the quota. AllocateBranch reserves cap per live branch, so a
// second concurrent branch is declined when only ~1 cap fits.
func TestReservationPreventsOvercommit(t *testing.T) {
	root := t.TempDir()
	be := &fakeBackend{totalBytes: gib + gib/2, perMaster: gib, root: root} // 1.5 GiB
	m := NewVolumeManager(root, 1, be)                                      // 1 GiB cap

	a1, _ := m.AllocateBranch(ReservedTuistCacheVolume, "vm1")
	if !a1.Attached {
		t.Fatal("first branch should attach (needs 1 cap, 1.5 free)")
	}
	a2, _ := m.AllocateBranch(ReservedTuistCacheVolume, "vm2")
	if a2.Attached {
		t.Fatal("second concurrent branch should decline: 2 caps reserved > 1.5 free")
	}
}

// Finalize releases the reservation so the freed headroom is reusable without
// evicting a just-promoted master.
func TestFinalizeReleasesReservation(t *testing.T) {
	root := t.TempDir()
	be := &fakeBackend{totalBytes: 2 * gib, perMaster: gib, root: root} // 2 GiB
	m := NewVolumeManager(root, 1, be)                                  // 1 GiB cap

	a1 := mustAllocate(t, m, "vm1")
	writeBranchCache(t, a1, "x")
	if out, _ := m.Finalize(a1, "42", true, true); out != VolumeOutcomePromoted {
		t.Fatalf("promote = %s", out)
	}
	// Free is now 1 GiB (2 - one master). With the reservation released
	// (liveBranches back to 0) a new branch needs only 1 cap and fits without
	// evicting account 42's fresh master.
	a2 := mustAllocate(t, m, "vm2")
	if !a2.Attached {
		t.Fatal("second branch should attach after the first's reservation is released")
	}
	if !masterExists(m, "42") {
		t.Fatal("account 42's master must not be evicted to admit vm2")
	}
}

func TestEvictToWatermark(t *testing.T) {
	// 3 GiB total, 1 GiB cap; low watermark = 1 + 0.2 = 1.2 GiB.
	m, _ := newTestManager(t, 3)
	for i, acct := range []string{"a", "b", "c"} {
		seedMaster(t, m, acct)
		setMtime(t, m.masterDir(acct, ReservedTuistCacheVolume), time.Now().Add(time.Duration(i)*time.Minute))
	}
	// free = 3 - 3 = 0 < 1.2 -> evict oldest until free >= 1.2 (need <= 1 master).
	evicted, err := m.EvictToWatermark()
	if err != nil {
		t.Fatalf("EvictToWatermark: %v", err)
	}
	if evicted != 2 {
		t.Fatalf("evicted = %d; want 2", evicted)
	}
	if masterExists(m, "a") || masterExists(m, "b") {
		t.Fatal("two oldest masters should be evicted")
	}
	if !masterExists(m, "c") {
		t.Fatal("newest master 'c' should survive")
	}
}

// SweepBranches (review finding 4): branches are per-job scratch, so any that
// survive a kubelet restart are orphans that must be removed on startup, and
// the reservation counter reset.
func TestSweepBranches(t *testing.T) {
	m, _ := newTestManager(t, 100)
	a1 := mustAllocate(t, m, "vm1")
	a2 := mustAllocate(t, m, "vm2")
	writeBranchCache(t, a1, "x")
	writeBranchCache(t, a2, "y")

	if err := m.SweepBranches(); err != nil {
		t.Fatalf("SweepBranches: %v", err)
	}
	if _, err := os.Stat(a1.BranchPath); !os.IsNotExist(err) {
		t.Fatal("branch vm1 should be swept")
	}
	if _, err := os.Stat(a2.BranchPath); !os.IsNotExist(err) {
		t.Fatal("branch vm2 should be swept")
	}
	if m.liveBranches != 0 {
		t.Fatalf("liveBranches after sweep = %d; want 0", m.liveBranches)
	}
	// A master must survive the sweep (only branches are removed).
	seedMaster(t, m, "42")
	if err := m.SweepBranches(); err != nil {
		t.Fatalf("SweepBranches: %v", err)
	}
	if !masterExists(m, "42") {
		t.Fatal("sweep must not remove masters")
	}
}

// MasterDigest must match dispatch-poll.sh's cache_inventory (sorted, subtree-
// prefixed entry names joined by newlines, SHA-1'd) so a host can compare its
// local master against the HEAD digest the guest reports.
func TestMasterDigestMatchesInventory(t *testing.T) {
	m, _ := newTestManager(t, 100)

	// No master: digest of the empty inventory is SHA-1 of the empty string.
	d0, err := m.MasterDigest("42", ReservedTuistCacheVolume)
	if err != nil {
		t.Fatalf("MasterDigest: %v", err)
	}
	if d0 != "da39a3ee5e6b4b0d3255bfef95601890afd80709" {
		t.Fatalf("empty digest = %q; want sha1(\"\")", d0)
	}

	// Two Binaries entries → SHA-1 over the sorted, prefixed, newline-joined
	// lines, independent of creation order.
	binaries := filepath.Join(m.masterDir("42", ReservedTuistCacheVolume), cacheHomeSubdir, "Binaries")
	if err := os.MkdirAll(filepath.Join(binaries, "hashB"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(binaries, "hashA"), 0o755); err != nil {
		t.Fatal(err)
	}

	got, err := m.MasterDigest("42", ReservedTuistCacheVolume)
	if err != nil {
		t.Fatalf("MasterDigest: %v", err)
	}
	h := sha1.New()
	for _, l := range []string{"Binaries/hashA", "Binaries/hashB"} {
		h.Write([]byte(l))
		h.Write([]byte("\n"))
	}
	if want := hex.EncodeToString(h.Sum(nil)); got != want {
		t.Fatalf("digest = %q; want %q", got, want)
	}
}

func TestReplaceMasterFastForwards(t *testing.T) {
	m, _ := newTestManager(t, 100)
	seedMaster(t, m, "42") // master/tuist/Binaries/marker

	// A converged staging tree with different content, on the runner-cache volume.
	staging := m.ConvergeStagingDir("vmX")
	dir := filepath.Join(staging, cacheHomeSubdir, "Binaries", "newhash")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "artifact"), []byte("fresh"), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := m.ReplaceMaster("42", ReservedTuistCacheVolume, staging); err != nil {
		t.Fatalf("ReplaceMaster: %v", err)
	}

	master := filepath.Join(m.masterDir("42", ReservedTuistCacheVolume), cacheHomeSubdir)
	if _, err := os.Stat(filepath.Join(master, "Binaries", "newhash", "artifact")); err != nil {
		t.Fatal("master should hold the converged artifact after fast-forward")
	}
	if _, err := os.Stat(filepath.Join(master, "Binaries", "marker")); !os.IsNotExist(err) {
		t.Fatal("stale master content should be replaced by the fast-forward")
	}
}

func TestReadDirtyMarker(t *testing.T) {
	// Absent status dir -> not present (crashed/incomplete job).
	if present, dirty := readDirtyMarker(""); present || dirty {
		t.Fatalf("empty status dir should be absent")
	}
	dir := t.TempDir()
	if present, _ := readDirtyMarker(dir); present {
		t.Fatalf("missing marker file should be absent")
	}
	if err := os.WriteFile(filepath.Join(dir, dirtyMarkerFile), []byte("1\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if present, dirty := readDirtyMarker(dir); !present || !dirty {
		t.Fatalf("marker '1' => present+dirty; got present=%v dirty=%v", present, dirty)
	}
	if err := os.WriteFile(filepath.Join(dir, dirtyMarkerFile), []byte("0"), 0o644); err != nil {
		t.Fatal(err)
	}
	if present, dirty := readDirtyMarker(dir); !present || dirty {
		t.Fatalf("marker '0' => present, not dirty; got present=%v dirty=%v", present, dirty)
	}
}

func setMtime(t *testing.T, path string, at time.Time) {
	t.Helper()
	if err := os.Chtimes(path, at, at); err != nil {
		t.Fatalf("chtimes %s: %v", path, err)
	}
}

// seedMaster writes a resident master tree for an account directly (with a
// known artifact under tuist/Binaries), bypassing the allocate/promote flow so
// tests can set up hosts holding several distinct accounts' masters.
func seedMaster(t *testing.T, m *VolumeManager, account string) {
	t.Helper()
	dir := filepath.Join(m.masterDir(account, ReservedTuistCacheVolume), cacheHomeSubdir, "Binaries")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatalf("mkdir master dir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "marker"), []byte(account), 0o644); err != nil {
		t.Fatalf("seed master: %v", err)
	}
}
