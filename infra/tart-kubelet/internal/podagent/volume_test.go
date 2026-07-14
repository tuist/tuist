package podagent

import (
	"crypto/sha1"
	"encoding/hex"
	"os"
	"path/filepath"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
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
	// The reconciler records the dispatched account on the attachment (what
	// maybeMaterializeVolume does); Finalize checks it before promoting.
	att.SourceAccount = "42"
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
	att.SourceAccount = "42"
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
// account 42's cache is unreachable because materialize is keyed to the
// dispatched account, so there is no cross-account exposure.
func TestMaterializeIsAccountScoped(t *testing.T) {
	m, _ := newTestManager(t, 100)
	seedMaster(t, m, "42")

	att := mustAllocate(t, m, "vm3")
	warm, err := m.Materialize(att, "99") // dispatched to 99, which has no master here
	if err != nil || warm {
		t.Fatalf("Materialize(99) = %v, %v; want cold (false), nil", warm, err)
	}
	att.SourceAccount = "99"
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

// Defense in depth for the cross-account fix: if a branch materialized for one
// account is ever finalized against a different account (a stale label from a
// failed dispatch that then won a claim for another account), Finalize must
// discard rather than promote the first account's artifacts into the second's
// master.
func TestFinalizeRejectsAccountMismatch(t *testing.T) {
	m, _ := newTestManager(t, 100)
	seedMaster(t, m, "A")

	att := mustAllocate(t, m, "vm-mismatch")
	if _, err := m.Materialize(att, "A"); err != nil {
		t.Fatalf("Materialize(A): %v", err)
	}
	att.SourceAccount = "A" // materialized from A...
	writeBranchCache(t, att, "from-A")

	// ...but finalized as if the VM ran account B.
	out, err := m.Finalize(att, "B", true, true)
	if err != nil || out != VolumeOutcomeDiscarded {
		t.Fatalf("Finalize(B) with SourceAccount A = %s, %v; want discarded", out, err)
	}
	if masterExists(m, "B") {
		t.Fatal("account A's cache must not be promoted into account B's master")
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
	a1.SourceAccount = "42"
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

// SweepBranches: branches whose VM is gone after a kubelet restart are orphans
// that must be removed on startup, with the reservation counter reset to the
// number that survived (zero here — nothing was reattached).
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

// A branch belonging to a VM that survived the restart (ReattachBranch) must be
// kept by the sweep — removing a virtio-fs-mounted branch would corrupt the
// running job — while a sibling orphan branch is still reaped, and liveBranches
// reflects only the retained one.
func TestSweepBranchesRetainsReattached(t *testing.T) {
	m, _ := newTestManager(t, 100)
	live := mustAllocate(t, m, "vm-live")
	orphan := mustAllocate(t, m, "vm-orphan")
	writeBranchCache(t, live, "warm")
	writeBranchCache(t, orphan, "stale")
	m.MarkMaterialized(live) // host materialized this branch before the restart

	// Simulate recovery of the still-running VM after a kubelet restart.
	att, ok := m.ReattachBranch(ReservedTuistCacheVolume, "vm-live")
	if !ok || !att.Attached || !att.Materialized {
		t.Fatalf("ReattachBranch = %+v, %v; want attached+materialized", att, ok)
	}

	if err := m.SweepBranches(); err != nil {
		t.Fatalf("SweepBranches: %v", err)
	}
	if _, err := os.Stat(live.BranchPath); err != nil {
		t.Fatal("live VM's branch must be retained across the sweep")
	}
	if _, err := os.Stat(orphan.BranchPath); !os.IsNotExist(err) {
		t.Fatal("orphan branch should be swept")
	}
	if m.liveBranches != 1 {
		t.Fatalf("liveBranches after sweep = %d; want 1 (only the retained branch)", m.liveBranches)
	}
}

// Recovery must preserve the untrusted decision: a fork job's branch (which the
// dispatch path left with an empty SourceAccount) must NOT get a SourceAccount
// reconstructed from the account label on restart — otherwise the attacker-
// controlled branch promotes into the account's master.
func TestReattachVolumeForPodPreservesUntrusted(t *testing.T) {
	m, _ := newTestManager(t, 100)
	att := mustAllocate(t, m, "vm-untrusted")
	writeBranchCache(t, att, "attacker")

	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Labels: map[string]string{
		runnerAccountLabel:        "42",
		runnerCacheUntrustedLabel: "true",
	}}}

	got, ok := ReattachVolumeForPod(m, pod, "vm-untrusted")
	if !ok || !got.Attached {
		t.Fatalf("ReattachVolumeForPod = %+v, %v; want attached", got, ok)
	}
	if got.SourceAccount != "" {
		t.Fatalf("untrusted recovered branch must keep an empty SourceAccount; got %q", got.SourceAccount)
	}

	// Completing the recovered job dirty must DISCARD, not promote.
	out, err := m.Finalize(got, "42", true, true)
	if err != nil || out != VolumeOutcomeDiscarded {
		t.Fatalf("Finalize = %s, %v; want discarded", out, err)
	}
	if masterExists(m, "42") {
		t.Fatal("an untrusted (fork) branch must never become the account's master via recovery")
	}
}

// The trusted side still works: a recovered trusted branch gets its
// SourceAccount and promotes.
func TestReattachVolumeForPodTrustedPromotes(t *testing.T) {
	m, _ := newTestManager(t, 100)
	att := mustAllocate(t, m, "vm-trusted")
	m.MarkMaterialized(att)
	writeBranchCache(t, att, "warm")

	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Labels: map[string]string{runnerAccountLabel: "42"}}}

	got, ok := ReattachVolumeForPod(m, pod, "vm-trusted")
	if !ok || got.SourceAccount != "42" {
		t.Fatalf("trusted reattach SourceAccount = %q (ok=%v); want 42", got.SourceAccount, ok)
	}
	if out, _ := m.Finalize(got, "42", true, true); out != VolumeOutcomePromoted {
		t.Fatalf("trusted recovered branch should promote, got %s", out)
	}
}

// ReattachBranch declines when the feature is off or the branch is gone.
func TestReattachBranchAbsent(t *testing.T) {
	m, _ := newTestManager(t, 100)
	if att, ok := m.ReattachBranch(ReservedTuistCacheVolume, "never-existed"); ok || att.Attached {
		t.Fatalf("ReattachBranch of a missing branch = %+v, %v; want zero, false", att, ok)
	}
}

// An idle VM creates its (empty) tuist cache subtree at boot but the host never
// materialized it, so ReattachBranch must NOT report it as materialized — else
// a restart would leave it permanently skipping materialization and running
// cold. The host-written marker, not the subtree, is the signal.
func TestReattachBranchIdleNotMaterialized(t *testing.T) {
	m, _ := newTestManager(t, 100)
	att := mustAllocate(t, m, "vm-idle")
	// Guest created branch/tuist at boot, but no host materialization happened.
	if err := os.MkdirAll(filepath.Join(att.BranchPath, cacheHomeSubdir), 0o777); err != nil {
		t.Fatal(err)
	}

	got, ok := m.ReattachBranch(ReservedTuistCacheVolume, "vm-idle")
	if !ok || !got.Attached {
		t.Fatalf("ReattachBranch = %+v, %v; want attached", got, ok)
	}
	if got.Materialized {
		t.Fatal("an idle branch with only the boot-created tuist subtree must not be materialized")
	}

	// Once the host marks it, reattach reports materialized.
	m.MarkMaterialized(got)
	if again, _ := m.ReattachBranch(ReservedTuistCacheVolume, "vm-idle"); !again.Materialized {
		t.Fatal("after MarkMaterialized, reattach must report materialized")
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

// TreeDigest (used by convergence to verify a downloaded archive matches the
// HEAD digest before install) computes over the staged dir's tuist subtree,
// identically to MasterDigest — so a matching tree verifies and a divergent one
// is rejected.
func TestTreeDigestMatchesMaster(t *testing.T) {
	m, _ := newTestManager(t, 100)
	seedMaster(t, m, "42") // master/tuist/Binaries/marker

	// A staged tree with identical inventory (entry name "marker") must digest
	// equal to the account's master.
	staging := m.ConvergeStagingDir("vmX")
	dir := filepath.Join(staging, cacheHomeSubdir, "Binaries")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "marker"), []byte("whatever"), 0o644); err != nil {
		t.Fatal(err)
	}

	master, err := m.MasterDigest("42", ReservedTuistCacheVolume)
	if err != nil {
		t.Fatalf("MasterDigest: %v", err)
	}
	staged, err := m.TreeDigest(staging)
	if err != nil {
		t.Fatalf("TreeDigest: %v", err)
	}
	if staged != master {
		t.Fatalf("TreeDigest = %q; want it to equal MasterDigest %q for identical inventory", staged, master)
	}

	// A divergent inventory must NOT match — this is the reject-on-mismatch guard.
	if err := os.MkdirAll(filepath.Join(dir, "extra"), 0o755); err != nil {
		t.Fatal(err)
	}
	if diverged, _ := m.TreeDigest(staging); diverged == master {
		t.Fatal("a tree with an extra entry must not digest-match the master")
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
