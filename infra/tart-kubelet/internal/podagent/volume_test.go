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
	"strconv"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/testutil"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// fakeBackend models APFS clonefile + statfs + hdiutil against real files under
// a temp root so the manager's os-based master scanning works unchanged.
//
// A cache image's CONTENTS are a real APFS filesystem that only a macOS attach
// can read (covered by the on-host darwin probe). Off a Mac the fake treats an
// image file's bytes as opaque content, cloned verbatim; its "digest" is
// sha1(content), standing in for the inventory a real attach would report. Free
// space is total minus one provisioned cap per resident master image; branches
// are CoW-sparse and don't count, mirroring the real backend.
type fakeBackend struct {
	totalBytes uint64
	perMaster  uint64
	root       string
	// cloneErr, when set, fails every clone — used to prove a failed
	// materialize still leaves the guest an image to attach.
	cloneErr error
	// createErr, when set, fails image creation.
	createErr error
	// notMounted, when set, makes isMounted report the runner-cache root as an
	// unmounted volume — the "feature enabled, volume missing" case. Default
	// (false) reports the root mounted, so ordinary tests need not opt in.
	notMounted bool
	// mountErr, when set, is returned from isMounted to model a stat failure.
	mountErr error
}

func (f *fakeBackend) clonePath(src, dst string) error {
	if f.cloneErr != nil {
		return f.cloneErr
	}
	if _, err := os.Stat(dst); err == nil {
		return os.ErrExist
	}
	b, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	return os.WriteFile(dst, b, 0o644)
}

// createImage writes an opaque placeholder standing in for an empty sparse
// image, so callers can stat/clone/upload it exactly as they would the real one.
func (f *fakeBackend) createImage(path string, sizeGiB int) error {
	if f.createErr != nil {
		return f.createErr
	}
	if sizeGiB <= 0 {
		return errors.New("cache image size must be positive")
	}
	return os.WriteFile(path, []byte("empty-image"), 0o644)
}

// imageInventoryDigest stands in for a read-through attach: the digest is
// sha1(content) of the opaque image bytes.
func (f *fakeBackend) imageInventoryDigest(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	h := sha1.Sum(b)
	return hex.EncodeToString(h[:]), nil
}

func (f *fakeBackend) isMounted(string) (bool, error) {
	if f.mountErr != nil {
		return false, f.mountErr
	}
	return !f.notMounted, nil
}

func (f *fakeBackend) freeBytes(root string) (uint64, error) {
	var masters uint64
	_ = filepath.Walk(root, func(p string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() || filepath.Base(p) != masterImageName {
			return nil
		}
		// <root>/<account>/<volume>/master.sparseimage — a real master.
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

// emptyImageContent is what the fake backend's createImage writes, so tests can
// tell an empty (cold) image from one cloned off a master.
const emptyImageContent = "empty-image"

// masterImageContent is the opaque content standing in for an account's master
// image — the fake's equivalent of "the APFS filesystem holding 42's cache".
func masterImageContent(account string) string { return "image-of-" + account }

// writeBranchCache simulates a job filling the branch's cache image (what the
// guest does inside the mounted image before promote). The host cannot see in,
// so from its side this is just the image file's content changing.
func writeBranchCache(t *testing.T, m *VolumeManager, att VolumeAttachment, marker string) {
	t.Helper()
	if err := os.WriteFile(m.BranchImage(att), []byte(marker), 0o644); err != nil {
		t.Fatalf("write branch cache: %v", err)
	}
}

func masterExists(m *VolumeManager, account string) bool {
	_, err := os.Stat(m.masterImage(account, ReservedTuistCacheVolume))
	return err == nil
}

func branchImageExists(m *VolumeManager, att VolumeAttachment) bool {
	_, err := os.Stat(m.BranchImage(att))
	return err == nil
}

func branchImageContent(t *testing.T, m *VolumeManager, att VolumeAttachment) string {
	t.Helper()
	b, err := os.ReadFile(m.BranchImage(att))
	if err != nil {
		t.Fatalf("read branch image: %v", err)
	}
	return string(b)
}

// branchHasWarmCache reports whether the branch carries a master's contents
// rather than the empty image the cold path creates.
func branchHasWarmCache(m *VolumeManager, att VolumeAttachment) bool {
	b, err := os.ReadFile(m.BranchImage(att))
	return err == nil && string(b) != emptyImageContent
}

func TestVolumeDisabled(t *testing.T) {
	m := NewVolumeManager("", 1, &fakeBackend{})
	att, err := m.AllocateBranch(ReservedTuistCacheVolume, "vm1")
	if err != nil || att.Attached {
		t.Fatalf("disabled manager should not attach: att=%+v err=%v", att, err)
	}
	if warm, _, err := m.Materialize(att, "42"); err != nil || warm {
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
	warm, base, err := m.Materialize(att, "42")
	if err != nil || warm || base != 0 {
		t.Fatalf("cold Materialize = %v, %v, %v; want false, 0, nil", warm, base, err)
	}
	// The reconciler records the dispatched account on the attachment (what
	// maybeMaterializeVolume does); Finalize checks it before promoting.
	att.SourceAccount = "42"
	if branchHasWarmCache(m, att) {
		t.Fatal("cold branch should hold no cached content")
	}
	// A cold branch still gets an EMPTY image: the guest can only attach what
	// is there, and no image at all kills the job rather than costing it warmth.
	if !branchImageExists(m, att) {
		t.Fatal("cold materialize must still leave an empty image for the guest to attach")
	}
	// The job pulls + writes the cache, then promotes. The server accepted this
	// first HEAD fast-forward as generation 1 (relayed by the guest).
	writeBranchCache(t, m, att, "from-42")
	att.PromotedGeneration = 1
	out, err := m.Finalize(att, "42", true, true)
	if err != nil || out != VolumeOutcomePromoted {
		t.Fatalf("Finalize = %s, %v; want promoted", out, err)
	}
	if !masterExists(m, "42") {
		t.Fatal("account 42 master should exist after promote")
	}
	// The promoted master is tagged with the accepted generation.
	if got, err := m.MasterGeneration("42", ReservedTuistCacheVolume); err != nil || got != 1 {
		t.Fatalf("MasterGeneration after promote = %d, %v; want the accepted generation 1", got, err)
	}
	if _, err := os.Stat(att.BranchPath); !os.IsNotExist(err) {
		t.Fatal("branch should be gone after promote")
	}
}

func TestWarmMaterializeAndPromote(t *testing.T) {
	m, _ := newTestManager(t, 100)
	// Seed account 42's master at generation 3.
	seedMasterGen(t, m, "42", masterImageContent("42"), 3)

	att := mustAllocate(t, m, "vm2")
	warm, base, err := m.Materialize(att, "42")
	if err != nil || !warm || base != 3 {
		t.Fatalf("warm Materialize = %v, %v, %v; want true, 3, nil", warm, base, err)
	}
	att.SourceAccount = "42"
	// The account's cached image is now the branch's image.
	if got := branchImageContent(t, m, att); got != masterImageContent("42") {
		t.Fatalf("materialized branch image = %q; want a clone of account 42's master", got)
	}
	// The server accepted the fast-forward from base 3 to generation 4.
	att.PromotedGeneration = 4
	if out, err := m.Finalize(att, "42", true, true); err != nil || out != VolumeOutcomePromoted {
		t.Fatalf("warm Finalize = %s, %v; want promoted", out, err)
	}
	if !masterExists(m, "42") {
		t.Fatal("account 42 master should still exist")
	}
	if got, _ := m.MasterGeneration("42", ReservedTuistCacheVolume); got != 4 {
		t.Fatalf("MasterGeneration after promote = %d; want 4", got)
	}
}

// A VM dispatched to account 99 only ever materializes account 99's master —
// account 42's cache is unreachable because materialize is keyed to the
// dispatched account, so there is no cross-account exposure.
func TestMaterializeIsAccountScoped(t *testing.T) {
	m, _ := newTestManager(t, 100)
	seedMaster(t, m, "42")

	att := mustAllocate(t, m, "vm3")
	warm, _, err := m.Materialize(att, "99") // dispatched to 99, which has no master here
	if err != nil || warm {
		t.Fatalf("Materialize(99) = %v, %v; want cold (false), nil", warm, err)
	}
	att.SourceAccount = "99"
	if branchHasWarmCache(m, att) {
		t.Fatalf("account 99's VM must not see account 42's cache; branch image = %q", branchImageContent(t, m, att))
	}
	writeBranchCache(t, m, att, "from-99")
	att.PromotedGeneration = 1
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
	if _, _, err := m.Materialize(att, "A"); err != nil {
		t.Fatalf("Materialize(A): %v", err)
	}
	att.SourceAccount = "A" // materialized from A...
	att.PromotedGeneration = 1
	writeBranchCache(t, m, att, "from-A")

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
	_, _, _ = m.Materialize(att, "42")
	if out, _ := m.Finalize(att, "42", true, false); out != VolumeOutcomeDiscarded {
		t.Fatalf("read-only job should discard, got %s", out)
	}
	if masterExists(m, "42") {
		t.Fatal("read-only job must not create a master")
	}

	// Failed job: dirty but not successful.
	att = mustAllocate(t, m, "vm-fail")
	_, _, _ = m.Materialize(att, "42")
	writeBranchCache(t, m, att, "half")
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

// A decline for lack of room used to be entirely silent. It must now bump the
// admission-declined counter so a host wedged under disk pressure is visible in
// Prometheus rather than looking identical to an idle one.
func TestAdmissionDeclineIncrementsMetric(t *testing.T) {
	before := testutil.ToFloat64(cacheVolumeAdmissionDeclinedTotal)

	root := t.TempDir()
	be := &fakeBackend{totalBytes: gib / 2, perMaster: gib, root: root}
	m := NewVolumeManager(root, 1, be)

	att, err := m.AllocateBranch(ReservedTuistCacheVolume, "vm1")
	if err != nil {
		t.Fatalf("AllocateBranch err: %v", err)
	}
	if att.Attached {
		t.Fatal("admission should decline to the cold path")
	}
	if got := testutil.ToFloat64(cacheVolumeAdmissionDeclinedTotal); got != before+1 {
		t.Fatalf("admission-declined counter = %v, want %v", got, before+1)
	}
}

// AllocateBranch must decline to the cold path when the root is not a mounted
// volume, rather than writing the branch (and later a clonefiled cache image)
// onto the boot filesystem. Guards the P1 boot-disk-write hazard.
func TestAllocateBranchDeclinesWhenRootUnmounted(t *testing.T) {
	m, be := newTestManager(t, 100)
	be.notMounted = true

	att, err := m.AllocateBranch(ReservedTuistCacheVolume, "vm1")
	if err != nil {
		t.Fatalf("AllocateBranch err: %v", err)
	}
	if att.Attached {
		t.Fatal("allocation must decline to the cold path when the root is not mounted")
	}
	if _, statErr := os.Stat(m.branchDir("vm1")); statErr == nil {
		t.Fatal("no branch dir should be created on an unmounted root")
	}
	if got := testutil.ToFloat64(cacheVolumeRootMounted); got != 0 {
		t.Fatalf("root-mounted gauge = %v, want 0", got)
	}
}

// A backend error from isMounted is treated as not-mounted: decline, don't
// error out or allocate.
func TestAllocateBranchDeclinesWhenMountCheckErrors(t *testing.T) {
	m, be := newTestManager(t, 100)
	be.mountErr = errors.New("stat: boom")

	att, err := m.AllocateBranch(ReservedTuistCacheVolume, "vm1")
	if err != nil {
		t.Fatalf("AllocateBranch err: %v", err)
	}
	if att.Attached {
		t.Fatal("allocation must decline when the mount check errors")
	}
}

// AwaitMountedRoot returns immediately on a healthy host (root already mounted)
// and publishes the enabled + root-mounted gauges as 1.
func TestAwaitMountedRootReturnsWhenMounted(t *testing.T) {
	m, _ := newTestManager(t, 100)   // fake reports mounted by default
	m.mountCheckInterval = time.Hour // a retry would hang the test; a mounted root must not retry
	m.mountCheckAttempts = 3

	done := make(chan struct{})
	go func() {
		m.AwaitMountedRoot(context.Background())
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("AwaitMountedRoot should return at once when the root is mounted")
	}
	if got := testutil.ToFloat64(cacheVolumeRootMounted); got != 1 {
		t.Fatalf("root-mounted gauge = %v, want 1", got)
	}
	if got := testutil.ToFloat64(cacheVolumeEnabled); got != 1 {
		t.Fatalf("enabled gauge = %v, want 1", got)
	}
}

// A disabled manager's AwaitMountedRoot is a no-op and never marks the feature
// enabled.
func TestAwaitMountedRootDisabledIsNoop(t *testing.T) {
	m := NewVolumeManager("", 1, &fakeBackend{})
	m.AwaitMountedRoot(context.Background()) // must not block or panic
}

// AwaitMountedRoot retries a bounded number of times when the root never
// mounts, then gives up (rather than blocking forever) with the gauge at 0.
func TestAwaitMountedRootGivesUpWhenUnmounted(t *testing.T) {
	m, be := newTestManager(t, 100)
	be.notMounted = true
	m.mountCheckInterval = time.Millisecond
	m.mountCheckAttempts = 3

	start := time.Now()
	m.AwaitMountedRoot(context.Background())
	if elapsed := time.Since(start); elapsed > time.Second {
		t.Fatalf("AwaitMountedRoot took %s; should give up after %d bounded attempts", elapsed, m.mountCheckAttempts)
	}
	if got := testutil.ToFloat64(cacheVolumeRootMounted); got != 0 {
		t.Fatalf("root-mounted gauge = %v, want 0", got)
	}
}

// A cancelled context short-circuits the retry wait so kubelet shutdown is not
// blocked on a missing volume.
func TestAwaitMountedRootStopsOnContextCancel(t *testing.T) {
	m, be := newTestManager(t, 100)
	be.notMounted = true
	m.mountCheckInterval = time.Hour
	m.mountCheckAttempts = 100

	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	done := make(chan struct{})
	go func() {
		m.AwaitMountedRoot(ctx)
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("AwaitMountedRoot should return promptly once the context is cancelled")
	}
}

func TestAdmissionEvictsThenAdmits(t *testing.T) {
	// 3 GiB total, 1 GiB cap. Seed 3 masters (free -> 0), then a new attach
	// must evict an LRU master to make room and still admit.
	m, _ := newTestManager(t, 3)
	for i, acct := range []string{"a", "b", "c"} {
		seedMaster(t, m, acct)
		setMtime(t, m.masterImage(acct, ReservedTuistCacheVolume), time.Now().Add(time.Duration(i)*time.Minute))
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
	a1.PromotedGeneration = 1
	writeBranchCache(t, m, a1, "x")
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
		setMtime(t, m.masterImage(acct, ReservedTuistCacheVolume), time.Now().Add(time.Duration(i)*time.Minute))
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
	writeBranchCache(t, m, a1, "x")
	writeBranchCache(t, m, a2, "y")

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
	writeBranchCache(t, m, live, "warm")
	writeBranchCache(t, m, orphan, "stale")
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

// The image FILE's mode is the whole of the host's permission handling: the
// guest attaches it read-write over virtio-fs as a different uid, so the clone
// (which carries the master's host-owned mode) must be relaxed or the attach
// fails. Everything inside the image is the guest's own — it attaches with
// `-owners off` — so there is nothing else to relax.
func TestMaterializedImageIsGuestWritable(t *testing.T) {
	m, _ := newTestManager(t, 100)
	seedMaster(t, m, "42")
	// A master as the host stages it: host-owned and not group/other-writable.
	if err := os.Chmod(m.masterImage("42", ReservedTuistCacheVolume), 0o600); err != nil {
		t.Fatal(err)
	}

	att := mustAllocate(t, m, "vm-warm")
	warm, _, err := m.Materialize(att, "42")
	if err != nil || !warm {
		t.Fatalf("Materialize = warm %v, err %v; want warm", warm, err)
	}

	fi, err := os.Stat(m.BranchImage(att))
	if err != nil {
		t.Fatalf("materialized image missing: %v", err)
	}
	if fi.Mode().Perm() != 0o666 {
		t.Errorf("materialized image mode = %#o, want 0666 so the guest can attach it read-write", fi.Mode().Perm())
	}

	// The cold path creates rather than clones, and must land on the same mode.
	cold := mustAllocate(t, m, "vm-cold")
	if _, _, err := m.Materialize(cold, "no-master-here"); err != nil {
		t.Fatalf("cold Materialize: %v", err)
	}
	cfi, err := os.Stat(m.BranchImage(cold))
	if err != nil {
		t.Fatalf("cold image missing: %v", err)
	}
	if cfi.Mode().Perm() != 0o666 {
		t.Errorf("cold image mode = %#o, want 0666", cfi.Mode().Perm())
	}
}

// A failed clone must never strand the branch WITHOUT an image: the guest is
// already pointed at the share and cannot attach what isn't there, so a missing
// image kills the job rather than costing it warmth. Falling back to an empty
// image runs the job cold.
func TestMaterializeFailureStillLeavesAnImage(t *testing.T) {
	m, be := newTestManager(t, 100)
	att := mustAllocate(t, m, "vm-fail")
	seedMaster(t, m, "42")
	be.cloneErr = errors.New("clonefile boom")

	if _, _, err := m.Materialize(att, "42"); err == nil {
		t.Fatal("expected Materialize to fail")
	}
	if !branchImageExists(m, att) {
		t.Fatal("failed materialize left the branch with no image (the job would die, not run cold)")
	}
	if branchHasWarmCache(m, att) {
		t.Fatal("failed materialize must leave an EMPTY image, not a half-cloned master")
	}
}

// When even the empty-image fallback fails there is nothing more the host can
// do, and the error must surface rather than be swallowed — the guest will fall
// back to its own local cold cache.
func TestMaterializeReportsFallbackFailure(t *testing.T) {
	m, be := newTestManager(t, 100)
	att := mustAllocate(t, m, "vm-doomed")
	seedMaster(t, m, "42")
	be.cloneErr = errors.New("clonefile boom")
	be.createErr = errors.New("hdiutil boom")

	_, _, err := m.Materialize(att, "42")
	if err == nil {
		t.Fatal("expected Materialize to fail")
	}
	if !errors.Is(err, be.cloneErr) || !errors.Is(err, be.createErr) {
		t.Fatalf("error should report both the clone and the fallback failure; got %v", err)
	}
}

// An untrusted (fork) job gets an image of its own — cache-ready tells the guest
// to attach, so signalling without one would drop every fork job onto the local
// cold cache — but it must be EMPTY, never a clone of the account's master.
func TestMaterializeEmptyIsolatesForkJobs(t *testing.T) {
	m, _ := newTestManager(t, 100)
	seedMaster(t, m, "42")

	att := mustAllocate(t, m, "vm-fork")
	if err := m.MaterializeEmpty(att); err != nil {
		t.Fatalf("MaterializeEmpty: %v", err)
	}
	if !branchImageExists(m, att) {
		t.Fatal("an untrusted job still needs an image to attach")
	}
	if branchHasWarmCache(m, att) {
		t.Fatalf("an untrusted job must not receive the account's cache; branch image = %q", branchImageContent(t, m, att))
	}

	// It promotes nothing: the dispatch path leaves SourceAccount empty, so even
	// a successful, dirty fork job discards.
	writeBranchCache(t, m, att, "attacker")
	if out, _ := m.Finalize(att, "42", true, true); out != VolumeOutcomeDiscarded {
		t.Fatalf("untrusted branch Finalize = %s; want discarded", out)
	}
	if got, _ := os.ReadFile(m.masterImage("42", ReservedTuistCacheVolume)); string(got) != masterImageContent("42") {
		t.Fatal("account 42's master must survive a fork job untouched")
	}
}

// Recovery must preserve the untrusted decision: a fork job's branch (which the
// dispatch path left with an empty SourceAccount) must NOT get a SourceAccount
// reconstructed from the account label on restart — otherwise the attacker-
// controlled branch promotes into the account's master.
func TestReattachVolumeForPodPreservesUntrusted(t *testing.T) {
	m, _ := newTestManager(t, 100)
	att := mustAllocate(t, m, "vm-untrusted")
	writeBranchCache(t, m, att, "attacker")

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
	writeBranchCache(t, m, att, "warm")

	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Labels: map[string]string{runnerAccountLabel: "42"}}}

	got, ok := ReattachVolumeForPod(m, pod, "vm-trusted")
	if !ok || got.SourceAccount != "42" {
		t.Fatalf("trusted reattach SourceAccount = %q (ok=%v); want 42", got.SourceAccount, ok)
	}
	// finalizeVolume fills this from the guest-relayed status share; set it here to
	// stand in for a server-accepted fast-forward.
	got.PromotedGeneration = 1
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

// MasterGeneration reads the generation sidecar, but ONLY while the master image
// exists — a generation beside a missing master must read 0 so a promote/converge
// treats the host as behind and rebuilds rather than skipping on a stale marker.
func TestMasterGenerationReadsSidecar(t *testing.T) {
	m, _ := newTestManager(t, 100)

	// No master: 0, not a guessed generation. The host can't see into an image, so
	// "I have nothing" must not read as "I am at some generation" and match a HEAD.
	if g0, err := m.MasterGeneration("42", ReservedTuistCacheVolume); err != nil || g0 != 0 {
		t.Fatalf("generation with no master = %d, %v; want 0", g0, err)
	}

	seedMasterGen(t, m, "42", masterImageContent("42"), 7)
	if got, err := m.MasterGeneration("42", ReservedTuistCacheVolume); err != nil || got != 7 {
		t.Fatalf("generation = %d, %v; want the recorded sidecar value 7", got, err)
	}

	// A master whose sidecar never landed reads as 0, so convergence refreshes it
	// rather than trusting a version nobody recorded.
	if err := os.Remove(m.masterGenerationPath("42", ReservedTuistCacheVolume)); err != nil {
		t.Fatal(err)
	}
	if got, err := m.MasterGeneration("42", ReservedTuistCacheVolume); err != nil || got != 0 {
		t.Fatalf("generation with no sidecar = %d, %v; want 0", got, err)
	}

	// A generation beside a MISSING master reads 0: re-seed both, drop only the
	// image, and the marker must not be honored.
	seedMasterGen(t, m, "42", masterImageContent("42"), 7)
	if err := os.Remove(m.masterImage("42", ReservedTuistCacheVolume)); err != nil {
		t.Fatal(err)
	}
	if got, _ := m.MasterGeneration("42", ReservedTuistCacheVolume); got != 0 {
		t.Fatalf("generation with master removed = %d; want 0 (not honored without a master)", got)
	}
}

// InstallMaster is the whole of reconciliation under fast-forward last-writer-
// wins: it replaces the local master with a newer generation's image and REFUSES
// to move the master backwards. It is both the converge path (adopt a newer HEAD)
// and the promote path (install the branch at the server-accepted generation).
func TestInstallMasterFastForwardsAndRefusesRegression(t *testing.T) {
	m, _ := newTestManager(t, 100)
	seedMasterGen(t, m, "42", "gen-5-image", 5)

	// A newer generation replaces the master wholesale.
	installed, err := m.InstallMaster("42", ReservedTuistCacheVolume, stageConvergeImage(t, m, "vmX", "gen-8-image"), 8)
	if err != nil || !installed {
		t.Fatalf("InstallMaster newer = installed %v, err %v; want installed", installed, err)
	}
	if got, _ := os.ReadFile(m.masterImage("42", ReservedTuistCacheVolume)); string(got) != "gen-8-image" {
		t.Fatalf("master image = %q; want the newer generation's image", got)
	}
	if got, _ := m.MasterGeneration("42", ReservedTuistCacheVolume); got != 8 {
		t.Fatalf("master generation = %d; want 8", got)
	}

	// An equal or older generation is a no-op: a slow promote or a redundant
	// converge must never overwrite a newer master.
	for _, stale := range []int{8, 6} {
		installed, err := m.InstallMaster("42", ReservedTuistCacheVolume, stageConvergeImage(t, m, "vmStale", "gen-stale-image"), stale)
		if err != nil {
			t.Fatalf("InstallMaster stale gen %d: %v", stale, err)
		}
		if installed {
			t.Fatalf("InstallMaster at generation %d installed over generation 8; must refuse to regress", stale)
		}
	}
	if got, _ := os.ReadFile(m.masterImage("42", ReservedTuistCacheVolume)); string(got) != "gen-8-image" {
		t.Fatalf("master image after stale installs = %q; want the generation-8 image untouched", got)
	}
}

// stageConvergeImage writes a downloaded-HEAD image with the given modelled
// content into the convergence staging dir and returns its path.
func stageConvergeImage(t *testing.T, m *VolumeManager, vm, content string) string {
	t.Helper()
	staging := m.ConvergeStagingDir(vm)
	if err := os.MkdirAll(staging, 0o755); err != nil {
		t.Fatal(err)
	}
	img := filepath.Join(staging, convergeImageName)
	if err := os.WriteFile(img, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return img
}

// The host's inventory digest must match dispatch-poll.sh's cache_inventory
// (sorted, subtree-prefixed entry names joined by newlines, SHA-1'd): the guest
// computes it inside the mounted image and the host computes it through a
// read-only attach, and the two are compared against each other.
func TestInventoryDigestMatchesGuestScript(t *testing.T) {
	root := t.TempDir() // the image MOUNT root (parent of tuist/ and the CAS store)

	// wantDigest builds the digest exactly as the guest's cache_inventory does:
	// the binary entry-name lines plus one `~cas/<relpath>\t<size>` line per CAS
	// file, LC_ALL=C sorted (`~` sorts last), newline-joined, sha1'd.
	wantDigest := func(entries, casLines []string) string {
		lines := append(append([]string{}, entries...), casLines...)
		sort.Strings(lines)
		h := sha1.New()
		for _, l := range lines {
			h.Write([]byte(l))
			h.Write([]byte("\n"))
		}
		return hex.EncodeToString(h.Sum(nil))
	}

	// Empty binary inventory + absent CAS store: no lines at all → sha1 of the
	// empty stream (a binary-only master's digest is unchanged by the CAS fold).
	d0, err := inventoryDigest(root)
	if err != nil {
		t.Fatalf("inventoryDigest: %v", err)
	}
	if want := wantDigest(nil, nil); d0 != want {
		t.Fatalf("empty digest = %q; want %q", d0, want)
	}

	// Two Binaries entries, still no CAS — order-independent.
	binaries := filepath.Join(root, cacheHomeSubdir, "Binaries")
	if err := os.MkdirAll(filepath.Join(binaries, "hashB"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(binaries, "hashA"), 0o755); err != nil {
		t.Fatal(err)
	}
	got, err := inventoryDigest(root)
	if err != nil {
		t.Fatalf("inventoryDigest: %v", err)
	}
	if want := wantDigest([]string{"Binaries/hashA", "Binaries/hashB"}, nil); got != want {
		t.Fatalf("digest = %q; want %q", got, want)
	}

	// A dotfile in the binary subtree is ignored (matches the guest's `ls -1`).
	if err := os.WriteFile(filepath.Join(binaries, ".DS_Store"), []byte("noise"), 0o644); err != nil {
		t.Fatal(err)
	}
	if withDotfile, _ := inventoryDigest(root); withDotfile != got {
		t.Fatalf("dotfile changed the digest: %q != %q (must be skipped to match the guest)", withDotfile, got)
	}

	// The folded CAS store's per-file (relpath, size) inventory enters the digest:
	// a compile-only job (binary subtree unchanged) that only grew the CAS still
	// changes the digest → promotes. Lines match the guest's find/stat pipeline —
	// regular files only, dot-paths excluded, relpath + real TAB + logical bytes
	// (the real bash pipeline is cross-checked in TestInventoryDigestMatchesGuestPipeline).
	casDir := filepath.Join(root, casStoreDir)
	if err := os.MkdirAll(filepath.Join(casDir, "v1"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(casDir, "v1", "records"), make([]byte, 100), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(casDir, "data"), make([]byte, 40), 0o644); err != nil {
		t.Fatal(err)
	}
	// A dot-path in the CAS store (the .writable probe, .DS_Store, in-flight .tmp)
	// is excluded on both sides, so it must not move the digest.
	if err := os.WriteFile(filepath.Join(casDir, ".writable"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	withCAS, err := inventoryDigest(root)
	if err != nil {
		t.Fatalf("inventoryDigest: %v", err)
	}
	if withCAS == got {
		t.Fatal("CAS growth must change the digest so a compile-only job promotes")
	}
	casLines := []string{
		fmt.Sprintf("%s/data\t%d", casLinePrefix, 40),
		fmt.Sprintf("%s/v1/records\t%d", casLinePrefix, 100),
	}
	if want := wantDigest([]string{"Binaries/hashA", "Binaries/hashB"}, casLines); withCAS != want {
		t.Fatalf("digest with CAS = %q; want %q", withCAS, want)
	}

	// Collision resistance: two stores with the SAME total size but different file
	// layouts must produce DIFFERENT digests, or the (immutable) object key would
	// clobber. Swap the 100/40 split for 40/100 — same 140 total, different names.
	if err := os.WriteFile(filepath.Join(casDir, "v1", "records"), make([]byte, 40), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(casDir, "data"), make([]byte, 100), 0o644); err != nil {
		t.Fatal(err)
	}
	if swapped, _ := inventoryDigest(root); swapped == withCAS {
		t.Fatal("equal-total but different-layout stores collided; the object key would clobber")
	}
}

// The convergence staging dir lives under Root, beside the account dirs. A
// downloaded HEAD image there must never be mistaken for a resident master —
// it would be counted against capacity and could be evicted as one.
func TestConvergeStagingIsNotAMaster(t *testing.T) {
	m, _ := newTestManager(t, 100)
	staging := m.ConvergeStagingDir("vmX")
	if err := os.MkdirAll(staging, 0o755); err != nil {
		t.Fatal(err)
	}
	// Worst case: staging holds a file named exactly like a master image.
	if err := os.WriteFile(filepath.Join(staging, masterImageName), []byte("downloaded"), 0o644); err != nil {
		t.Fatal(err)
	}

	masters, err := m.allMastersLocked()
	if err != nil {
		t.Fatalf("allMastersLocked: %v", err)
	}
	if len(masters) != 0 {
		t.Fatalf("convergence scratch must not be scanned as a master; got %+v", masters)
	}
}

// A promote is discarded when the server did NOT accept the HEAD fast-forward
// (PromotedGeneration 0): the job built on a base another host has since advanced
// past, so installing its branch would move this host's master off the accepted
// lineage. The local master must stay exactly as it was.
func TestFinalizeDiscardsWhenFastForwardRejected(t *testing.T) {
	m, _ := newTestManager(t, 100)
	seedMasterGen(t, m, "42", "existing-master", 5)

	att := mustAllocate(t, m, "vm-rejected")
	if _, _, err := m.Materialize(att, "42"); err != nil {
		t.Fatalf("Materialize: %v", err)
	}
	att.SourceAccount = "42"
	writeBranchCache(t, m, att, "stale-branch")
	att.PromotedGeneration = 0 // server rejected: HEAD advanced past this job's base

	if out, err := m.Finalize(att, "42", true, true); err != nil || out != VolumeOutcomeDiscarded {
		t.Fatalf("Finalize with rejected fast-forward = %s, %v; want discarded", out, err)
	}
	if got, _ := os.ReadFile(m.masterImage("42", ReservedTuistCacheVolume)); string(got) != "existing-master" {
		t.Fatalf("master after rejected promote = %q; want the pre-existing master untouched", got)
	}
	if got, _ := m.MasterGeneration("42", ReservedTuistCacheVolume); got != 5 {
		t.Fatalf("master generation after rejected promote = %d; want 5 (unchanged)", got)
	}
	if _, err := os.Stat(att.BranchPath); !os.IsNotExist(err) {
		t.Fatal("branch should be discarded (removed) after a rejected promote")
	}
}

func TestReadPromoteResult(t *testing.T) {
	if got := readPromoteResult(""); got.Result != "" || got.Generation != 0 {
		t.Fatalf("empty status dir = %+v; want zero", got)
	}
	dir := t.TempDir()
	if got := readPromoteResult(dir); got.Result != "" {
		t.Fatalf("missing file = %+v; want zero (guest did not report)", got)
	}

	write := func(s string) {
		if err := os.WriteFile(filepath.Join(dir, promoteResultFile), []byte(s), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	write("accepted 9\n")
	if got := readPromoteResult(dir); got.Result != "accepted" || got.Generation != 9 {
		t.Fatalf("accepted = %+v; want {accepted 9}", got)
	}
	// Accepted without a usable generation carries no install target.
	write("accepted")
	if got := readPromoteResult(dir); got.Result != "accepted" || got.Generation != 0 {
		t.Fatalf("accepted-no-gen = %+v; want {accepted 0}", got)
	}
	// A 409 is a distinct rejection, NOT an error.
	write("conflict")
	if got := readPromoteResult(dir); got.Result != "conflict" || got.Generation != 0 {
		t.Fatalf("conflict = %+v; want {conflict 0}", got)
	}
	// An upload/network failure is an error, never a rejection.
	write("error")
	if got := readPromoteResult(dir); got.Result != "error" {
		t.Fatalf("error = %+v; want error", got)
	}
	// Anything unrecognized is treated as an error, never a false rejection.
	write("weird garbage")
	if got := readPromoteResult(dir); got.Result != "error" {
		t.Fatalf("garbage = %+v; want error", got)
	}
}

func TestCacheImageSplit(t *testing.T) {
	const gib = uint64(1024 * 1024 * 1024)

	// CAS off: the binary cache gets ~80% of a mid cap; no CAS budget.
	if b, cas := cacheImageSplit(20, 0); b != 20*gib*80/100 || cas != 0 {
		t.Fatalf("cap20 cas0 = %d,%d; want %d,0", b, cas, 20*gib*80/100)
	}

	// CAS on, mid cap (8 of 20): reserve = max(2 GiB, 5%=1 GiB) = 2 GiB (the FLOOR
	// binds); binary 10 GiB, CAS the requested 8 GiB exactly, summing to cap.
	if b, cas := cacheImageSplit(20, 8); b != 10*gib || cas != 8*gib || b+cas+2*gib != 20*gib {
		t.Fatalf("cap20 cas8 = %d,%d; want 10GiB,8GiB summing to cap", b, cas)
	}

	// Large cap: the PERCENT reserve binds, not the floor (5% of 100 = 5 GiB > 2).
	// CAS 20 of 100 → binary = 100 - 5(reserve) - 20 = 75 GiB, CAS the requested 20.
	if b, cas := cacheImageSplit(100, 20); b != 75*gib || cas != 20*gib {
		t.Fatalf("cap100 cas20 = %d,%d; want 75GiB,20GiB", b, cas)
	}

	// Small cap: the floor binds — reserve stays 2 GiB on a 10 GiB cap (20%), where
	// a flat 5% would have left far too little.
	if b, _ := cacheImageSplit(10, 4); 10*gib-(b+4*gib) != 2*gib {
		t.Fatalf("cap10 cas4 reserve = %d GiB; want 2 (floor)", (10*gib-(b+4*gib))/gib)
	}

	// Oversized CASGiB: clamped so the binary cache keeps a slice and the
	// invariant binary + CAS + reserve <= cap still holds (the ENOSPC guard).
	b, cas := cacheImageSplit(20, 25)
	if b == 0 {
		t.Fatal("oversized cas-gib starved the binary cache to 0")
	}
	if b+cas+2*gib > 20*gib {
		t.Fatalf("oversized: binary(%d)+cas(%d)+reserve exceeds cap", b, cas)
	}

	// writeCacheBudget stages exactly the binary half.
	dir := t.TempDir()
	writeCacheBudget(dir, 20, 8)
	raw, err := os.ReadFile(filepath.Join(dir, cacheBudgetFile))
	if err != nil {
		t.Fatal(err)
	}
	if got, _ := strconv.ParseUint(string(raw), 10, 64); got != 10*gib {
		t.Fatalf("staged budget = %d; want 10 GiB", got)
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

// seedMaster writes a resident master image for an account directly at
// generation 1, bypassing the allocate/promote flow so tests can set up hosts
// holding several distinct accounts' masters.
func seedMaster(t *testing.T, m *VolumeManager, account string) {
	t.Helper()
	seedMasterGen(t, m, account, masterImageContent(account), 1)
}

// seedMasterGen writes a resident master with explicit opaque content and its
// generation sidecar, so tests can set up a master at a known fast-forward
// version.
func seedMasterGen(t *testing.T, m *VolumeManager, account, content string, generation int) {
	t.Helper()
	if err := os.MkdirAll(m.volumeDir(account, ReservedTuistCacheVolume), 0o755); err != nil {
		t.Fatalf("mkdir volume dir: %v", err)
	}
	image := m.masterImage(account, ReservedTuistCacheVolume)
	if err := os.WriteFile(image, []byte(content), 0o644); err != nil {
		t.Fatalf("seed master image: %v", err)
	}
	if err := os.WriteFile(m.masterGenerationPath(account, ReservedTuistCacheVolume), []byte(strconv.Itoa(generation)), 0o644); err != nil {
		t.Fatalf("seed master generation: %v", err)
	}
}
