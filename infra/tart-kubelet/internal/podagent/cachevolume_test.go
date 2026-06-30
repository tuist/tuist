package podagent

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func TestCacheVolumeManagerStageVMResetsShare(t *testing.T) {
	root := t.TempDir()
	manager := &CacheVolumeManager{RootDir: root}

	shareDir, err := manager.StageVM("vm-one")
	if err != nil {
		t.Fatalf("StageVM() error = %v", err)
	}
	if err := os.WriteFile(filepath.Join(shareDir, RunnerCacheReadyFile), []byte("42\n"), 0o644); err != nil {
		t.Fatalf("write stale ready marker: %v", err)
	}
	if err := os.WriteFile(filepath.Join(shareDir, "stale"), []byte("old"), 0o644); err != nil {
		t.Fatalf("write stale file: %v", err)
	}

	shareDir, err = manager.StageVM("vm-one")
	if err != nil {
		t.Fatalf("StageVM() second error = %v", err)
	}
	if _, err := os.Stat(filepath.Join(shareDir, RunnerCacheReadyFile)); !os.IsNotExist(err) {
		t.Fatalf("ready marker should be removed, stat err = %v", err)
	}
	if _, err := os.Stat(filepath.Join(shareDir, "stale")); !os.IsNotExist(err) {
		t.Fatalf("stale file should be removed, stat err = %v", err)
	}
}

func TestCacheVolumeManagerBindWaitsForAccountLabel(t *testing.T) {
	root := t.TempDir()
	manager := &CacheVolumeManager{RootDir: root}
	shareDir, err := manager.StageVM("vm-one")
	if err != nil {
		t.Fatalf("StageVM() error = %v", err)
	}
	entry := &Entry{VMName: "vm-one", CacheShareDir: shareDir}
	pod := runnerCachePod(nil)

	if err := manager.Bind(context.Background(), pod, entry); err != nil {
		t.Fatalf("Bind() error = %v", err)
	}
	if _, err := os.Stat(filepath.Join(shareDir, RunnerCacheReadyFile)); !os.IsNotExist(err) {
		t.Fatalf("ready marker should not exist before account label, stat err = %v", err)
	}
	if entry.CachePreparedAccountID != "" {
		t.Fatalf("CachePreparedAccountID = %q, want empty", entry.CachePreparedAccountID)
	}
}

func TestCacheVolumeManagerBindClonesAccountCache(t *testing.T) {
	root := t.TempDir()
	sourceDir := filepath.Join(root, "accounts", "42", "current")
	if err := os.MkdirAll(filepath.Join(sourceDir, "ModuleCache"), 0o755); err != nil {
		t.Fatalf("mkdir source: %v", err)
	}
	if err := os.WriteFile(filepath.Join(sourceDir, "ModuleCache", "artifact"), []byte("warm"), 0o644); err != nil {
		t.Fatalf("write source artifact: %v", err)
	}

	cloneCalls := 0
	manager := &CacheVolumeManager{
		RootDir: root,
		CloneTree: func(ctx context.Context, source, destination string) error {
			cloneCalls++
			if source != sourceDir {
				t.Fatalf("clone source = %q, want %q", source, sourceDir)
			}
			return copyDirectoryForTest(source, destination)
		},
	}
	shareDir, err := manager.StageVM("vm-one")
	if err != nil {
		t.Fatalf("StageVM() error = %v", err)
	}
	entry := &Entry{VMName: "vm-one", CacheShareDir: shareDir}

	if err := manager.Bind(context.Background(), runnerCachePod(map[string]string{RunnerAccountLabel: "42"}), entry); err != nil {
		t.Fatalf("Bind() error = %v", err)
	}
	if got := readFileForTest(t, filepath.Join(shareDir, "ModuleCache", "artifact")); got != "warm" {
		t.Fatalf("cloned artifact = %q, want warm", got)
	}
	if got := readFileForTest(t, filepath.Join(shareDir, RunnerCacheReadyFile)); got != "42\n" {
		t.Fatalf("ready marker = %q, want account id", got)
	}
	if entry.CachePreparedAccountID != "42" {
		t.Fatalf("CachePreparedAccountID = %q, want 42", entry.CachePreparedAccountID)
	}

	if err := manager.Bind(context.Background(), runnerCachePod(map[string]string{RunnerAccountLabel: "42"}), entry); err != nil {
		t.Fatalf("Bind() second error = %v", err)
	}
	if cloneCalls != 1 {
		t.Fatalf("clone calls = %d, want 1", cloneCalls)
	}
}

func TestCacheVolumeManagerBindMarksMissingAccountCacheReady(t *testing.T) {
	root := t.TempDir()
	cloneCalls := 0
	manager := &CacheVolumeManager{
		RootDir: root,
		CloneTree: func(ctx context.Context, source, destination string) error {
			cloneCalls++
			return nil
		},
	}
	shareDir, err := manager.StageVM("vm-one")
	if err != nil {
		t.Fatalf("StageVM() error = %v", err)
	}
	entry := &Entry{VMName: "vm-one", CacheShareDir: shareDir}

	if err := manager.Bind(context.Background(), runnerCachePod(map[string]string{RunnerAccountLabel: "42"}), entry); err != nil {
		t.Fatalf("Bind() error = %v", err)
	}
	if got := readFileForTest(t, filepath.Join(shareDir, RunnerCacheReadyFile)); got != "42\n" {
		t.Fatalf("ready marker = %q, want account id", got)
	}
	if cloneCalls != 0 {
		t.Fatalf("clone calls = %d, want 0", cloneCalls)
	}
}

func TestCacheVolumeManagerFinalizeMergesVMCacheIntoAccountCache(t *testing.T) {
	root := t.TempDir()
	accountDir := filepath.Join(root, "accounts", "42", "current")
	if err := os.MkdirAll(filepath.Join(accountDir, "ModuleCache"), 0o755); err != nil {
		t.Fatalf("mkdir account cache: %v", err)
	}
	if err := os.WriteFile(filepath.Join(accountDir, "ModuleCache", "existing"), []byte("warm"), 0o644); err != nil {
		t.Fatalf("write existing artifact: %v", err)
	}

	shareDir := filepath.Join(root, "vms", "vm-one")
	if err := os.MkdirAll(filepath.Join(shareDir, "ModuleCache"), 0o755); err != nil {
		t.Fatalf("mkdir VM cache: %v", err)
	}
	if err := os.WriteFile(filepath.Join(shareDir, "ModuleCache", "new"), []byte("hot"), 0o644); err != nil {
		t.Fatalf("write new artifact: %v", err)
	}
	if err := os.WriteFile(filepath.Join(shareDir, RunnerCacheReadyFile), []byte("42\n"), 0o644); err != nil {
		t.Fatalf("write ready marker: %v", err)
	}
	if err := os.WriteFile(filepath.Join(shareDir, runnerCachePreparingFile), []byte("42\n"), 0o644); err != nil {
		t.Fatalf("write preparing marker: %v", err)
	}
	if err := os.WriteFile(filepath.Join(shareDir, runnerLocalKuraPIDFile), []byte("123\n"), 0o644); err != nil {
		t.Fatalf("write local Kura PID marker: %v", err)
	}

	manager := &CacheVolumeManager{
		RootDir: root,
		CloneTree: func(ctx context.Context, source, destination string) error {
			if source != shareDir {
				t.Fatalf("merge source = %q, want %q", source, shareDir)
			}
			if destination != accountDir {
				t.Fatalf("merge destination = %q, want %q", destination, accountDir)
			}
			return copyDirectoryForTest(source, destination)
		},
	}
	entry := &Entry{
		VMName:                 "vm-one",
		CacheShareDir:          shareDir,
		CachePreparedAccountID: "42",
	}

	if err := manager.Finalize(context.Background(), entry); err != nil {
		t.Fatalf("Finalize() error = %v", err)
	}
	if got := readFileForTest(t, filepath.Join(accountDir, "ModuleCache", "existing")); got != "warm" {
		t.Fatalf("existing artifact = %q, want warm", got)
	}
	if got := readFileForTest(t, filepath.Join(accountDir, "ModuleCache", "new")); got != "hot" {
		t.Fatalf("new artifact = %q, want hot", got)
	}
	if _, err := os.Stat(filepath.Join(accountDir, RunnerCacheReadyFile)); !os.IsNotExist(err) {
		t.Fatalf("ready marker should not be promoted, stat err = %v", err)
	}
	if _, err := os.Stat(filepath.Join(accountDir, runnerCachePreparingFile)); !os.IsNotExist(err) {
		t.Fatalf("preparing marker should not be promoted, stat err = %v", err)
	}
	if _, err := os.Stat(filepath.Join(accountDir, runnerLocalKuraPIDFile)); !os.IsNotExist(err) {
		t.Fatalf("local Kura PID marker should not be promoted, stat err = %v", err)
	}
}

func runnerCachePod(labels map[string]string) *corev1.Pod {
	if labels == nil {
		labels = map[string]string{}
	}
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Annotations: map[string]string{RunnerCacheVolumeAnnotation: "true"},
			Labels:      labels,
		},
	}
}

func copyDirectoryForTest(source, destination string) error {
	return filepath.WalkDir(source, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		relativePath, err := filepath.Rel(source, path)
		if err != nil {
			return err
		}
		if relativePath == "." {
			return nil
		}
		destinationPath := filepath.Join(destination, relativePath)
		if entry.IsDir() {
			return os.MkdirAll(destinationPath, 0o755)
		}
		contents, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		return os.WriteFile(destinationPath, contents, 0o644)
	})
}

func readFileForTest(t *testing.T, path string) string {
	t.Helper()
	contents, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(contents)
}
