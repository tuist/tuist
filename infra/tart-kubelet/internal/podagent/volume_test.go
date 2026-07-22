package podagent

import (
	"context"
	"crypto/sha1"
	"encoding/hex"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"
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
// can read (the real read-through-attach behaviour is covered by the on-host
// darwin probe). Off a Mac the fake stands in for that filesystem by treating an
// image file's bytes as a newline-joined SET of cache-object tokens: a single
// opaque marker like "image-of-42" is a one-object set, and mergeInto unions two
// sets exactly as the real ditto-the-delta merge unions two attached images. The
// "digest" is imageDigests[content] when registered, else sha1(content) — so a
// merged image's digest reflects the union, which is what the object-level
// reconciliation tests assert. Free space is total minus one provisioned cap per
// resident master image; branches are CoW-sparse and don't count, mirroring the
// real backend.
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
	// imageDigests maps an image's opaque content to the digest a real attach
	// would report, standing in for the filesystem inside it.
	imageDigests map[string]string
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

func (f *fakeBackend) imageInventoryDigest(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return f.digestForContent(string(b)), nil
}

// digestForContent returns the digest a real attach would report for an image
// whose modelled content is the given token set: a registered override when the
// test pinned one, else sha1 of the content so a union changes the digest.
func (f *fakeBackend) digestForContent(content string) string {
	if d, ok := f.imageDigests[content]; ok {
		return d
	}
	h := sha1.Sum([]byte(content))
	return hex.EncodeToString(h[:])
}

// mergeInto models the real ditto-the-delta union: dstImage's content becomes the
// sorted, de-duplicated union of dst's and src's object tokens, and the merged
// digest is returned. A token present on both sides collapses to one (content-
// addressed → identical), and no token is ever removed.
func (f *fakeBackend) mergeInto(dstImage, srcImage string) (string, error) {
	db, err := os.ReadFile(dstImage)
	if err != nil {
		return "", err
	}
	sb, err := os.ReadFile(srcImage)
	if err != nil {
		return "", err
	}
	merged := unionImageTokens(string(db), string(sb))
	if err := os.WriteFile(dstImage, []byte(merged), 0o644); err != nil {
		return "", err
	}
	return f.digestForContent(merged), nil
}

// unionImageTokens merges two newline-joined object-token sets into one sorted,
// de-duplicated set — the fake's stand-in for unioning the objects of two
// attached cache images.
func unionImageTokens(a, b string) string {
	set := map[string]struct{}{}
	for _, content := range []string{a, b} {
		for _, tok := range strings.Split(content, "\n") {
			if tok != "" {
				set[tok] = struct{}{}
			}
		}
	}
	tokens := make([]string, 0, len(set))
	for tok := range set {
		tokens = append(tokens, tok)
	}
	sort.Strings(tokens)
	return strings.Join(tokens, "\n")
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
	if branchHasWarmCache(m, att) {
		t.Fatal("cold branch should hold no cached content")
	}
	// A cold branch still gets an EMPTY image: the guest can only attach what
	// is there, and no image at all kills the job rather than costing it warmth.
	if !branchImageExists(m, att) {
		t.Fatal("cold materialize must still leave an empty image for the guest to attach")
	}
	// The job pulls + writes the cache, then promotes.
	writeBranchCache(t, m, att, "from-42")
	att.ReportedDigest = "digest-from-42"
	out, err := m.Finalize(att, "42", true, true)
	if err != nil || out != VolumeOutcomePromoted {
		t.Fatalf("Finalize = %s, %v; want promoted", out, err)
	}
	if !masterExists(m, "42") {
		t.Fatal("account 42 master should exist after promote")
	}
	// The promoted master records the digest the guest reported from inside the
	// image, since the host can't compute it without attaching.
	if got, err := m.MasterDigest("42", ReservedTuistCacheVolume); err != nil || got != "digest-from-42" {
		t.Fatalf("MasterDigest after promote = %q, %v; want the guest-reported digest", got, err)
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
	// The account's cached image is now the branch's image.
	if got := branchImageContent(t, m, att); got != masterImageContent("42") {
		t.Fatalf("materialized branch image = %q; want a clone of account 42's master", got)
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
	if branchHasWarmCache(m, att) {
		t.Fatalf("account 99's VM must not see account 42's cache; branch image = %q", branchImageContent(t, m, att))
	}
	writeBranchCache(t, m, att, "from-99")
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
	warm, err := m.Materialize(att, "42")
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
	if _, err := m.Materialize(cold, "no-master-here"); err != nil {
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

	if _, err := m.Materialize(att, "42"); err == nil {
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

	_, err := m.Materialize(att, "42")
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
func TestMasterDigestReadsSidecar(t *testing.T) {
	m, _ := newTestManager(t, 100)

	// No master: empty, NOT the digest of an empty inventory. The host can't see
	// into an image, so "I don't know" must not be reported as "I am empty" —
	// that would look like a legitimate state and could match a HEAD.
	d0, err := m.MasterDigest("42", ReservedTuistCacheVolume)
	if err != nil {
		t.Fatalf("MasterDigest: %v", err)
	}
	if d0 != "" {
		t.Fatalf("digest with no master = %q; want empty", d0)
	}

	seedMasterWithDigest(t, m, "42", "deadbeef")
	got, err := m.MasterDigest("42", ReservedTuistCacheVolume)
	if err != nil {
		t.Fatalf("MasterDigest: %v", err)
	}
	if got != "deadbeef" {
		t.Fatalf("digest = %q; want the recorded sidecar value", got)
	}

	// A master whose sidecar never landed reads as unknown, so convergence
	// refreshes it rather than trusting an inventory nobody recorded.
	if err := os.Remove(m.masterDigestPath("42", ReservedTuistCacheVolume)); err != nil {
		t.Fatal(err)
	}
	if got, err := m.MasterDigest("42", ReservedTuistCacheVolume); err != nil || got != "" {
		t.Fatalf("digest with no sidecar = %q, %v; want empty", got, err)
	}
}

// The converged-head marker records which HEAD a host has already absorbed.
// After a union merge the master is a superset of that HEAD, so MasterDigest no
// longer equals it — the marker is the only thing that lets convergence skip a
// re-download, and it must read empty until the host actually converges.
func TestConvergedHeadMarkerRoundTrips(t *testing.T) {
	m, _ := newTestManager(t, 100)

	// No marker yet: a host that never converged must not claim to be at any HEAD,
	// or it would skip the convergence that would warm it.
	if got, err := m.MasterConvergedHead("42", ReservedTuistCacheVolume); err != nil || got != "" {
		t.Fatalf("MasterConvergedHead with no marker = %q, %v; want empty", got, err)
	}

	if err := m.RecordConvergedHead("42", ReservedTuistCacheVolume, "head-xyz"); err != nil {
		t.Fatalf("RecordConvergedHead: %v", err)
	}
	if got, err := m.MasterConvergedHead("42", ReservedTuistCacheVolume); err != nil || got != "head-xyz" {
		t.Fatalf("MasterConvergedHead = %q, %v; want the recorded HEAD", got, err)
	}

	// A newer HEAD overwrites the marker so the next comparison re-converges.
	if err := m.RecordConvergedHead("42", ReservedTuistCacheVolume, "head-abc"); err != nil {
		t.Fatalf("RecordConvergedHead (update): %v", err)
	}
	if got, _ := m.MasterConvergedHead("42", ReservedTuistCacheVolume); got != "head-abc" {
		t.Fatalf("MasterConvergedHead after update = %q; want the newer HEAD", got)
	}
}

// The host's inventory digest must match dispatch-poll.sh's cache_inventory
// (sorted, subtree-prefixed entry names joined by newlines, SHA-1'd): the guest
// computes it inside the mounted image and the host computes it through a
// read-only attach, and the two are compared against each other.
func TestInventoryDigestMatchesGuestScript(t *testing.T) {
	root := t.TempDir()

	// Empty inventory: SHA-1 of the empty string, matching `... | sort | shasum`
	// over no entries.
	d0, err := inventoryDigest(filepath.Join(root, cacheHomeSubdir))
	if err != nil {
		t.Fatalf("inventoryDigest: %v", err)
	}
	if d0 != "da39a3ee5e6b4b0d3255bfef95601890afd80709" {
		t.Fatalf("empty digest = %q; want sha1(\"\")", d0)
	}

	// Two Binaries entries → SHA-1 over the sorted, prefixed, newline-joined
	// lines, independent of creation order.
	binaries := filepath.Join(root, cacheHomeSubdir, "Binaries")
	if err := os.MkdirAll(filepath.Join(binaries, "hashB"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(binaries, "hashA"), 0o755); err != nil {
		t.Fatal(err)
	}

	got, err := inventoryDigest(filepath.Join(root, cacheHomeSubdir))
	if err != nil {
		t.Fatalf("inventoryDigest: %v", err)
	}
	h := sha1.New()
	for _, l := range []string{"Binaries/hashA", "Binaries/hashB"} {
		h.Write([]byte(l))
		h.Write([]byte("\n"))
	}
	if want := hex.EncodeToString(h.Sum(nil)); got != want {
		t.Fatalf("digest = %q; want %q", got, want)
	}

	// A dotfile (.DS_Store, an in-flight .tmp) must be ignored: the guest's
	// `ls -1` never lists it, so counting it here would make the host digest
	// disagree with the guest-reported one and abort convergence forever.
	if err := os.WriteFile(filepath.Join(binaries, ".DS_Store"), []byte("noise"), 0o644); err != nil {
		t.Fatal(err)
	}
	withDotfile, err := inventoryDigest(filepath.Join(root, cacheHomeSubdir))
	if err != nil {
		t.Fatalf("inventoryDigest: %v", err)
	}
	if withDotfile != got {
		t.Fatalf("dotfile changed the digest: %q != %q (must be skipped to match the guest)", withDotfile, got)
	}
}

func TestObjectsToMergeIsAdditiveDelta(t *testing.T) {
	src := t.TempDir()
	dst := t.TempDir()

	// src holds two binaries + a manifest; dst already has one of the binaries.
	// The union delta is everything in src that dst lacks — never what dst
	// already has (content-addressed → identical) and never dst-only objects
	// (union removes nothing).
	for _, p := range []string{"Binaries/hashA", "Binaries/hashB", "Manifests/m1"} {
		if err := os.MkdirAll(filepath.Join(src, p), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	for _, p := range []string{"Binaries/hashA", "Plugins/keepMe", ".DS_Store"} {
		if err := os.MkdirAll(filepath.Join(dst, filepath.Dir(p)), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.MkdirAll(filepath.Join(dst, p), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	// A dotfile in src must never be treated as an object.
	if err := os.WriteFile(filepath.Join(src, "Binaries", ".DS_Store"), []byte("noise"), 0o644); err != nil {
		t.Fatal(err)
	}

	got := objectsToMerge(src, dst)
	want := []string{"Binaries/hashB", "Manifests/m1"}
	if len(got) != len(want) {
		t.Fatalf("objectsToMerge = %v; want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("objectsToMerge = %v; want %v", got, want)
		}
	}

	// No delta when dst already has everything src does — a converge that would
	// be a no-op must copy nothing (and skip the expensive attach+ditto).
	if d := objectsToMerge(src, src); len(d) != 0 {
		t.Fatalf("objectsToMerge(src, src) = %v; want empty (nothing to add)", d)
	}
}

// MergeMaster UNIONS a converged HEAD image into the local master rather than
// replacing it: an object the local master holds but the HEAD lacks must survive.
// This is the cross-host half of the whole-image-replace fix — a replace here is
// exactly what stranded objects and emptied masters fleet-wide.
func TestMergeMasterUnionsConvergedHead(t *testing.T) {
	m, _ := newTestManager(t, 100)
	seedMasterImage(t, m, "42", "objLocalA\nobjShared", "stale-digest")

	// A converged HEAD image staged on the runner-cache volume, holding a shared
	// object plus one the local master does not have.
	staging := m.ConvergeStagingDir("vmX")
	if err := os.MkdirAll(staging, 0o755); err != nil {
		t.Fatal(err)
	}
	image := filepath.Join(staging, convergeImageName)
	if err := os.WriteFile(image, []byte("objShared\nobjHeadB"), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := m.MergeMaster("42", ReservedTuistCacheVolume, image, "head-digest"); err != nil {
		t.Fatalf("MergeMaster: %v", err)
	}

	// The master now holds the union: the HEAD's new object AND the local-only one
	// a replace would have dropped.
	got, err := os.ReadFile(m.masterImage("42", ReservedTuistCacheVolume))
	if err != nil {
		t.Fatalf("read master: %v", err)
	}
	if want := "objHeadB\nobjLocalA\nobjShared"; string(got) != want {
		t.Fatalf("merged master = %q; want the union %q", got, want)
	}
	// The recorded digest reflects the merged union, not the incoming HEAD digest.
	if d, _ := m.MasterDigest("42", ReservedTuistCacheVolume); d == "head-digest" || d == "stale-digest" {
		t.Fatalf("MasterDigest = %q; want a digest recomputed from the union", d)
	}
}

// MergeMaster on a host with no master yet installs the image verbatim and
// records the digest it was handed (the cold-converge path).
func TestMergeMasterColdInstallsVerbatim(t *testing.T) {
	m, _ := newTestManager(t, 100)

	staging := m.ConvergeStagingDir("vmX")
	if err := os.MkdirAll(staging, 0o755); err != nil {
		t.Fatal(err)
	}
	image := filepath.Join(staging, convergeImageName)
	if err := os.WriteFile(image, []byte("objA\nobjB"), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := m.MergeMaster("42", ReservedTuistCacheVolume, image, "head-digest"); err != nil {
		t.Fatalf("MergeMaster: %v", err)
	}
	got, err := os.ReadFile(m.masterImage("42", ReservedTuistCacheVolume))
	if err != nil || string(got) != "objA\nobjB" {
		t.Fatalf("cold master = %q, %v; want the HEAD image verbatim", got, err)
	}
	if d, _ := m.MasterDigest("42", ReservedTuistCacheVolume); d != "head-digest" {
		t.Fatalf("cold MasterDigest = %q; want the HEAD digest recorded as-is", d)
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

// A promote UNIONS the branch's objects into the master instead of replacing it.
// This reproduces the bug the object-level reconciliation fixes: a job whose
// end-of-job cache dropped an object the master held (e.g. a `test` job that
// carried manifests but none of the master's binaries) used to clobber the
// richer master via a whole-image replace, emptying it. The union keeps both the
// job's new object and the master's pre-existing one.
func TestPromoteUnionsIntoMaster(t *testing.T) {
	m, _ := newTestManager(t, 100)
	seedMasterImage(t, m, "42", "objShared\nobjMaster", "master-digest")

	att := mustAllocate(t, m, "vm-union")
	if _, err := m.Materialize(att, "42"); err != nil {
		t.Fatalf("Materialize: %v", err)
	}
	att.SourceAccount = "42"

	// The job ends with a cache that shares one object with the master, adds a new
	// one, and — critically — no longer carries objMaster.
	writeBranchCache(t, m, att, "objShared\nobjJob")
	att.ReportedDigest = "branch-digest"

	if out, err := m.Finalize(att, "42", true, true); err != nil || out != VolumeOutcomePromoted {
		t.Fatalf("Finalize = %s, %v; want promoted", out, err)
	}

	got, err := os.ReadFile(m.masterImage("42", ReservedTuistCacheVolume))
	if err != nil {
		t.Fatalf("read master: %v", err)
	}
	if want := "objJob\nobjMaster\nobjShared"; string(got) != want {
		t.Fatalf("promoted master = %q; want the union %q (objMaster must survive)", got, want)
	}
	if d, _ := m.MasterDigest("42", ReservedTuistCacheVolume); d == "branch-digest" {
		t.Fatal("MasterDigest still the branch digest; a warm promote must recompute it from the union")
	}
}

// A promote onto a host with no prior master installs the branch verbatim and
// trusts the guest-reported digest (the cold-first-job path), unchanged by the
// union rework.
func TestPromoteColdRecordsReportedDigest(t *testing.T) {
	m, _ := newTestManager(t, 100)
	att := mustAllocate(t, m, "vm-cold")
	if _, err := m.Materialize(att, "42"); err != nil {
		t.Fatalf("Materialize: %v", err)
	}
	att.SourceAccount = "42"
	writeBranchCache(t, m, att, "objA\nobjB")
	att.ReportedDigest = "reported-digest"

	if out, err := m.Finalize(att, "42", true, true); err != nil || out != VolumeOutcomePromoted {
		t.Fatalf("Finalize = %s, %v; want promoted", out, err)
	}
	got, err := os.ReadFile(m.masterImage("42", ReservedTuistCacheVolume))
	if err != nil || string(got) != "objA\nobjB" {
		t.Fatalf("cold master = %q, %v; want the branch image verbatim", got, err)
	}
	if d, _ := m.MasterDigest("42", ReservedTuistCacheVolume); d != "reported-digest" {
		t.Fatalf("cold MasterDigest = %q; want the guest-reported digest", d)
	}
}

func TestReadReportedDigest(t *testing.T) {
	if got := readReportedDigest(""); got != "" {
		t.Fatalf("empty status dir = %q; want empty", got)
	}
	dir := t.TempDir()
	if got := readReportedDigest(dir); got != "" {
		t.Fatalf("missing digest file = %q; want empty", got)
	}
	if err := os.WriteFile(filepath.Join(dir, digestMarkerFile), []byte("abc123\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := readReportedDigest(dir); got != "abc123" {
		t.Fatalf("digest = %q; want abc123 (trimmed)", got)
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

// seedMaster writes a resident master image for an account directly, plus its
// digest sidecar, bypassing the allocate/promote flow so tests can set up hosts
// holding several distinct accounts' masters.
func seedMaster(t *testing.T, m *VolumeManager, account string) {
	t.Helper()
	seedMasterWithDigest(t, m, account, "digest-of-"+account)
}

func seedMasterWithDigest(t *testing.T, m *VolumeManager, account, digest string) {
	t.Helper()
	seedMasterImage(t, m, account, masterImageContent(account), digest)
}

// seedMasterImage writes a resident master with explicit modelled content (a
// newline-joined object-token set) plus its digest sidecar, so union tests can
// set up a master holding specific objects.
func seedMasterImage(t *testing.T, m *VolumeManager, account, content, digest string) {
	t.Helper()
	if err := os.MkdirAll(m.volumeDir(account, ReservedTuistCacheVolume), 0o755); err != nil {
		t.Fatalf("mkdir volume dir: %v", err)
	}
	image := m.masterImage(account, ReservedTuistCacheVolume)
	if err := os.WriteFile(image, []byte(content), 0o644); err != nil {
		t.Fatalf("seed master image: %v", err)
	}
	if err := os.WriteFile(m.masterDigestPath(account, ReservedTuistCacheVolume), []byte(digest), 0o644); err != nil {
		t.Fatalf("seed master digest: %v", err)
	}
}
