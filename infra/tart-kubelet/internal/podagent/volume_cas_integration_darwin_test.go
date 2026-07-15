//go:build darwin

package podagent

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Integration test that drives the REAL VolumeManager against the REAL darwin
// backend (hdiutil createSparseImage, cp -c clonefile) on a Mac host — the gap
// the fake-backend unit tests can't cover. Gated on CAS_STAGING_VALIDATE=1 so it
// never runs in normal `go test` / CI (it creates real disk images and needs a
// Mac). Build the binary with `go test -c` and run it on a staging host.
func TestCASImageIntegrationRealBackend(t *testing.T) {
	if os.Getenv("CAS_STAGING_VALIDATE") != "1" {
		t.Skip("set CAS_STAGING_VALIDATE=1 to run the real-backend CAS integration test on a Mac host")
	}
	root := t.TempDir()
	m := NewVolumeManager(root, 1, nil) // nil backend => real darwinVolumeBackend
	m.CASGiB = 1                        // 1 GiB logical sparse image (fast to create)
	if _, ok := m.backend.(darwinVolumeBackend); !ok {
		t.Fatalf("expected real darwin backend, got %T", m.backend)
	}

	acct := "acct-integration"

	// --- Lifecycle A: cold first job creates a fresh sparse image, then promote.
	att1 := mustAllocate(t, m, "vm1")
	if !att1.Attached {
		t.Fatal("admission declined on a real host with free disk")
	}
	att1.SourceAccount = acct

	t0 := time.Now()
	warm, err := m.Materialize(att1, acct)
	if err != nil {
		t.Fatalf("Materialize (cold): %v", err)
	}
	t.Logf("cold Materialize (hdiutil create fresh image) took %s", time.Since(t0))
	if warm {
		t.Fatal("cold first job should report tree warm=false")
	}
	branchImg := filepath.Join(att1.BranchPath, casImageName)
	assertRealSparseImage(t, branchImg, "fresh branch image")

	// Attach the fresh image, prove it's a usable read/write block device (the
	// SIGBUS-free property is proven separately on staging via llvm-cas), write a
	// marker file, detach.
	mnt := attachImage(t, branchImg)
	if err := os.WriteFile(filepath.Join(mnt, "job1-marker"), []byte("v1"), 0o644); err != nil {
		t.Fatalf("write into attached image: %v", err)
	}
	detachImage(t, mnt)

	// Binary tree content so the promote path runs.
	writeBranchCache(t, att1, "tree-v1")
	m.FinalizeCAS(att1, acct, true) // runner succeeded => promote the CAS image
	outcome, err := m.Finalize(att1, acct, true, true)
	if err != nil || outcome != VolumeOutcomePromoted {
		t.Fatalf("Finalize (promote): outcome=%s err=%v", outcome, err)
	}
	masterImg := m.masterCASImage(acct, ReservedTuistCacheVolume)
	assertRealSparseImage(t, masterImg, "promoted master image")
	if !masterExists(m, acct) {
		t.Fatal("binary tree not promoted")
	}

	// --- Lifecycle B: warm second job clones the master image (real cp -c CoW).
	att2 := mustAllocate(t, m, "vm2")
	att2.SourceAccount = acct
	t1 := time.Now()
	warm, err = m.Materialize(att2, acct)
	if err != nil {
		t.Fatalf("Materialize (warm): %v", err)
	}
	cloneDur := time.Since(t1)
	t.Logf("warm Materialize (cp -c clone master image) took %s", cloneDur)
	if !warm {
		t.Fatal("second job should report tree warm=true")
	}
	branch2Img := filepath.Join(att2.BranchPath, casImageName)
	assertRealSparseImage(t, branch2Img, "cloned branch image")
	// The clone must carry the job-1 marker written into the master's image.
	mnt2 := attachImage(t, branch2Img)
	if _, err := os.Stat(filepath.Join(mnt2, "job1-marker")); err != nil {
		t.Fatalf("cloned image missing job-1 marker => clone did not carry CAS content: %v", err)
	}
	t.Log("cloned branch image carries the master's CAS content (warm)")
	detachImage(t, mnt2)

	// --- Subtree-swap: a binary-tree promote must PRESERVE the sibling image.
	writeBranchCache(t, att2, "tree-v2")
	m.FinalizeCAS(att2, acct, true)
	if o, err := m.Finalize(att2, acct, true, true); err != nil || o != VolumeOutcomePromoted {
		t.Fatalf("Finalize2: outcome=%s err=%v", o, err)
	}
	assertRealSparseImage(t, masterImg, "master image after binary promote")

	// --- Converge (ReplaceMaster) must PRESERVE the sibling image too.
	src := filepath.Join(t.TempDir(), "converged")
	if err := os.MkdirAll(filepath.Join(src, cacheHomeSubdir, "Binaries"), 0o777); err != nil {
		t.Fatalf("build converged tree: %v", err)
	}
	if err := os.WriteFile(filepath.Join(src, cacheHomeSubdir, "Binaries", "new"), []byte("x"), 0o644); err != nil {
		t.Fatalf("write converged: %v", err)
	}
	if err := m.ReplaceMaster(acct, ReservedTuistCacheVolume, src); err != nil {
		t.Fatalf("ReplaceMaster: %v", err)
	}
	assertRealSparseImage(t, masterImg, "master image after HEAD convergence")

	t.Log("PASS: real-backend CAS image lifecycle (create/clone/promote/converge) validated on host")
}

// assertRealSparseImage checks the path is a real hdiutil sparse image, not the
// fake's stand-in file — proving the darwin backend actually ran.
func assertRealSparseImage(t *testing.T, path, label string) {
	t.Helper()
	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("%s missing: %v", label, err)
	}
	out, err := exec.Command("hdiutil", "imageinfo", path).CombinedOutput()
	if err != nil {
		t.Fatalf("%s is not a valid disk image (hdiutil imageinfo failed): %v\n%s", label, err, out)
	}
	if !strings.Contains(string(out), "Format:") {
		t.Fatalf("%s hdiutil imageinfo unexpected output: %s", label, out)
	}
	t.Logf("%s OK (%d bytes on disk, valid hdiutil image)", label, info.Size())
}

func attachImage(t *testing.T, img string) string {
	t.Helper()
	mnt := filepath.Join(t.TempDir(), "mnt")
	_ = os.MkdirAll(mnt, 0o755)
	out, err := exec.Command("hdiutil", "attach", img, "-mountpoint", mnt, "-nobrowse", "-owners", "on").CombinedOutput()
	if err != nil {
		t.Fatalf("attach %s: %v\n%s", img, err, out)
	}
	return mnt
}

func detachImage(t *testing.T, mnt string) {
	t.Helper()
	for i := 0; i < 5; i++ {
		if out, err := exec.Command("hdiutil", "detach", mnt).CombinedOutput(); err == nil {
			return
		} else if i == 4 {
			t.Logf("detach %s failed after retries: %s", mnt, out)
			_ = exec.Command("hdiutil", "detach", mnt, "-force").Run()
		}
		time.Sleep(time.Second)
	}
}
