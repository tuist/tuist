package podagent

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// fakeBackend models the disk-image mechanics against real files under a temp
// root so the manager's os-based master scanning works unchanged. Free space
// is modelled as total minus one provisioned cap per resident .img file,
// mirroring the conservative admission accounting.
type fakeBackend struct {
	totalBytes uint64
	perImage   uint64
	failCreate bool
	root       string
}

func (f *fakeBackend) createMaster(path string, _ int, _ string) error {
	if f.failCreate {
		return os.ErrPermission
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte("img"), 0o644)
}

func (f *fakeBackend) clone(src, dst string) error {
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	b, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	return os.WriteFile(dst, b, 0o644)
}

func (f *fakeBackend) remove(path string) error { return os.RemoveAll(path) }

func (f *fakeBackend) freeBytes(root string) (uint64, error) {
	var count uint64
	_ = filepath.Walk(root, func(p string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if !info.IsDir() && strings.HasSuffix(p, ".img") {
			count++
		}
		return nil
	})
	used := count * f.perImage
	if used > f.totalBytes {
		return 0, nil
	}
	return f.totalBytes - used, nil
}

const gib = uint64(1024 * 1024 * 1024)

func newTestManager(t *testing.T, totalGiB int) (*VolumeManager, *fakeBackend) {
	t.Helper()
	root := t.TempDir()
	be := &fakeBackend{totalBytes: uint64(totalGiB) * gib, perImage: gib, root: root}
	m := NewVolumeManager(root, 1, be) // 1 GiB provisioned cap
	return m, be
}

func mustAttach(t *testing.T, m *VolumeManager, vm string) VolumeAttachment {
	t.Helper()
	att, err := m.AttachForBoot(ReservedTuistCacheVolume, vm)
	if err != nil {
		t.Fatalf("AttachForBoot: %v", err)
	}
	return att
}

func masterExists(m *VolumeManager, account string) bool {
	_, err := os.Stat(m.masterPath(account, ReservedTuistCacheVolume))
	return err == nil
}

func TestVolumeDisabled(t *testing.T) {
	m := NewVolumeManager("", 1, &fakeBackend{})
	att, err := m.AttachForBoot(ReservedTuistCacheVolume, "vm1")
	if err != nil || att.Attached {
		t.Fatalf("disabled manager should not attach: att=%+v err=%v", att, err)
	}
	out, err := m.Finalize(att, "42", true, true)
	if err != nil || out != VolumeOutcomeNone {
		t.Fatalf("disabled Finalize = %s, %v; want none", out, err)
	}
}

func TestFirstContactEmptySeedPromotes(t *testing.T) {
	m, _ := newTestManager(t, 100)
	att := mustAttach(t, m, "vm1")
	if !att.Attached || att.SourceAccount != "" {
		t.Fatalf("first contact should empty-seed: %+v", att)
	}
	if !strings.Contains(att.BranchPath, "_staging") {
		t.Fatalf("empty-seed branch should live in _staging: %s", att.BranchPath)
	}
	out, err := m.Finalize(att, "42", true, true)
	if err != nil || out != VolumeOutcomePromoted {
		t.Fatalf("Finalize = %s, %v; want promoted", out, err)
	}
	if !masterExists(m, "42") {
		t.Fatal("account 42 master should exist after promote")
	}
	if _, err := os.Stat(att.BranchPath); !os.IsNotExist(err) {
		t.Fatal("branch should be gone after promote (renamed)")
	}
}

func TestWarmHitPredictsAndPromotes(t *testing.T) {
	m, _ := newTestManager(t, 100)
	// Seed account 42's master.
	out, _ := m.Finalize(mustAttach(t, m, "seed"), "42", true, true)
	if out != VolumeOutcomePromoted {
		t.Fatalf("seed promote = %s", out)
	}

	att := mustAttach(t, m, "vm2")
	if att.SourceAccount != "42" {
		t.Fatalf("should predict account 42: %+v", att)
	}
	if !strings.Contains(att.BranchPath, filepath.Join("42", ReservedTuistCacheVolume, "branches")) {
		t.Fatalf("branch path unexpected: %s", att.BranchPath)
	}
	if out, err := m.Finalize(att, "42", true, true); err != nil || out != VolumeOutcomePromoted {
		t.Fatalf("warm Finalize = %s, %v; want promoted", out, err)
	}
	if !masterExists(m, "42") {
		t.Fatal("account 42 master should still exist")
	}
}

func TestMispredictionDiscardsNoContamination(t *testing.T) {
	m, _ := newTestManager(t, 100)
	m.Finalize(mustAttach(t, m, "seed"), "42", true, true) // seed account 42

	att := mustAttach(t, m, "vm3")
	if att.SourceAccount != "42" {
		t.Fatalf("expected prediction 42, got %q", att.SourceAccount)
	}
	// Dispatch actually assigned account 99.
	out, err := m.Finalize(att, "99", true, true)
	if err != nil || out != VolumeOutcomeMispredicted {
		t.Fatalf("Finalize = %s, %v; want mispredicted", out, err)
	}
	if masterExists(m, "99") {
		t.Fatal("mispredicted branch must NOT become account 99's master")
	}
	if !masterExists(m, "42") {
		t.Fatal("account 42's master must survive a misprediction")
	}
}

func TestReadOnlyAndFailedDiscard(t *testing.T) {
	m, _ := newTestManager(t, 100)

	// Clean/read-only job: success but not dirty.
	att := mustAttach(t, m, "vm-ro")
	if out, _ := m.Finalize(att, "42", true, false); out != VolumeOutcomeDiscarded {
		t.Fatalf("read-only job should discard, got %s", out)
	}
	if masterExists(m, "42") {
		t.Fatal("read-only job must not create a master")
	}

	// Failed job: dirty but not successful.
	att = mustAttach(t, m, "vm-fail")
	if out, _ := m.Finalize(att, "42", false, true); out != VolumeOutcomeDiscarded {
		t.Fatalf("failed job should discard, got %s", out)
	}
	if masterExists(m, "42") {
		t.Fatal("failed job must not create a master")
	}
}

func TestAdmissionDeclinesToColdPath(t *testing.T) {
	// Total capacity below one provisioned cap: no room even after eviction.
	root := t.TempDir()
	be := &fakeBackend{totalBytes: gib / 2, perImage: gib, root: root}
	m := NewVolumeManager(root, 1, be)

	att, err := m.AttachForBoot(ReservedTuistCacheVolume, "vm1")
	if err != nil {
		t.Fatalf("AttachForBoot err: %v", err)
	}
	if att.Attached {
		t.Fatal("admission should decline (cold path) when the root cannot fit a cap")
	}
}

func TestAdmissionEvictsThenAdmits(t *testing.T) {
	// 3 GiB total, 1 GiB cap. Seed 3 masters (free -> 0), then a new attach
	// must evict an LRU master to make room and still admit.
	m, _ := newTestManagerBig(t, 3)
	for i, acct := range []string{"a", "b", "c"} {
		seedMaster(t, m, acct)
		// Stagger mtimes so LRU order is a (oldest) .. c (newest).
		setMtime(t, m.masterPath(acct, ReservedTuistCacheVolume), time.Now().Add(time.Duration(i)*time.Minute))
	}

	att := mustAttach(t, m, "vmX")
	if !att.Attached {
		t.Fatal("attach should admit after evicting an LRU master")
	}
	if masterExists(m, "a") {
		t.Fatal("oldest master 'a' should have been evicted for admission")
	}
}

func TestEvictToWatermark(t *testing.T) {
	// 3 GiB total, 1 GiB cap; low watermark = 1 + 0.2 = 1.2 GiB.
	m, _ := newTestManagerBig(t, 3)
	for i, acct := range []string{"a", "b", "c"} {
		seedMaster(t, m, acct)
		setMtime(t, m.masterPath(acct, ReservedTuistCacheVolume), time.Now().Add(time.Duration(i)*time.Minute))
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

func TestHottestMasterPrediction(t *testing.T) {
	m, _ := newTestManager(t, 100)
	seedMaster(t, m, "old")
	seedMaster(t, m, "new")
	setMtime(t, m.masterPath("old", ReservedTuistCacheVolume), time.Now().Add(-time.Hour))
	setMtime(t, m.masterPath("new", ReservedTuistCacheVolume), time.Now())

	att := mustAttach(t, m, "vm")
	if att.SourceAccount != "new" {
		t.Fatalf("hottest master should be 'new', predicted %q", att.SourceAccount)
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
	// dirty=1
	if err := os.WriteFile(filepath.Join(dir, dirtyMarkerFile), []byte("1\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if present, dirty := readDirtyMarker(dir); !present || !dirty {
		t.Fatalf("marker '1' => present+dirty; got present=%v dirty=%v", present, dirty)
	}
	// dirty=0 (clean read-only job)
	if err := os.WriteFile(filepath.Join(dir, dirtyMarkerFile), []byte("0"), 0o644); err != nil {
		t.Fatal(err)
	}
	if present, dirty := readDirtyMarker(dir); !present || dirty {
		t.Fatalf("marker '0' => present, not dirty; got present=%v dirty=%v", present, dirty)
	}
}

func TestVolumeManifestJSON(t *testing.T) {
	got := volumeManifestJSON(ReservedTuistCacheVolume)
	want := `[{"label":"tuist-cache","cache_root":true}]`
	if got != want {
		t.Fatalf("manifest = %s; want %s", got, want)
	}
	if volumeManifestJSON("") != want {
		t.Fatalf("empty volume name should default to tuist-cache")
	}
}

func newTestManagerBig(t *testing.T, totalGiB int) (*VolumeManager, *fakeBackend) {
	t.Helper()
	root := t.TempDir()
	be := &fakeBackend{totalBytes: uint64(totalGiB) * gib, perImage: gib, root: root}
	return NewVolumeManager(root, 1, be), be
}

func setMtime(t *testing.T, path string, at time.Time) {
	t.Helper()
	if err := os.Chtimes(path, at, at); err != nil {
		t.Fatalf("chtimes %s: %v", path, err)
	}
}

// seedMaster writes a resident master image for an account directly, bypassing
// the attach/promote flow. Needed to set up hosts holding several distinct
// accounts' masters — the normal attach path predicts the first master and its
// contamination guard would (correctly) refuse to promote a second account.
func seedMaster(t *testing.T, m *VolumeManager, account string) {
	t.Helper()
	p := m.masterPath(account, ReservedTuistCacheVolume)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatalf("mkdir master dir: %v", err)
	}
	if err := os.WriteFile(p, []byte("img"), 0o644); err != nil {
		t.Fatalf("seed master: %v", err)
	}
}
