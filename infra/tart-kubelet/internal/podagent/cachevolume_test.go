package podagent

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCacheVolumeManagerStageVMResetsShare(t *testing.T) {
	root := t.TempDir()
	manager := &CacheVolumeManager{RootDir: root}

	shareDir, err := manager.StageVM("vm-one")
	if err != nil {
		t.Fatalf("StageVM() error = %v", err)
	}
	if err := os.WriteFile(filepath.Join(shareDir, "stale"), []byte("old"), 0o644); err != nil {
		t.Fatalf("write stale file: %v", err)
	}

	shareDir, err = manager.StageVM("vm-one")
	if err != nil {
		t.Fatalf("StageVM() second error = %v", err)
	}
	if _, err := os.Stat(filepath.Join(shareDir, "stale")); !os.IsNotExist(err) {
		t.Fatalf("stale file should be removed, stat err = %v", err)
	}
}

func TestCacheVolumeManagerCleanupVMRemovesShare(t *testing.T) {
	root := t.TempDir()
	manager := &CacheVolumeManager{RootDir: root}

	shareDir, err := manager.StageVM("vm-one")
	if err != nil {
		t.Fatalf("StageVM() error = %v", err)
	}
	if err := manager.CleanupVM("vm-one"); err != nil {
		t.Fatalf("CleanupVM() error = %v", err)
	}
	if _, err := os.Stat(shareDir); !os.IsNotExist(err) {
		t.Fatalf("share should be removed, stat err = %v", err)
	}
}
