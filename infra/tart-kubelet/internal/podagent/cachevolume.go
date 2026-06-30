package podagent

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"

	corev1 "k8s.io/api/core/v1"
)

const (
	RunnerCacheVolumeAnnotation = "tart-kubelet.tuist.dev/runner-cache-volume"
	RunnerAccountLabel          = "tuist.dev/runner-account"
	RunnerCacheShareName        = "tuist-cache"
	RunnerCacheReadyFile        = ".tuist-cache-ready"
	runnerCachePreparingFile    = ".tuist-cache-preparing"
	runnerLocalKuraPIDFile      = ".tuist-local-kura.pid"
)

type CacheTreeCloner func(ctx context.Context, source, destination string) error

type CacheVolumeManager struct {
	RootDir   string
	CloneTree CacheTreeCloner
	mu        sync.Mutex
}

func (m *CacheVolumeManager) EnabledForPod(pod *corev1.Pod) bool {
	return m != nil &&
		m.RootDir != "" &&
		pod.Annotations[RunnerCacheVolumeAnnotation] == "true"
}

func (m *CacheVolumeManager) StageVM(vmName string) (string, error) {
	shareDir, err := m.vmShareDir(vmName)
	if err != nil {
		return "", err
	}
	if err := os.RemoveAll(shareDir); err != nil {
		return "", fmt.Errorf("reset runner cache volume: %w", err)
	}
	if err := os.MkdirAll(shareDir, 0o755); err != nil {
		return "", fmt.Errorf("create runner cache volume: %w", err)
	}
	return shareDir, nil
}

func (m *CacheVolumeManager) Bind(ctx context.Context, pod *corev1.Pod, entry *Entry) error {
	if !m.EnabledForPod(pod) {
		return nil
	}
	accountID := strings.TrimSpace(pod.Labels[RunnerAccountLabel])
	if accountID == "" {
		return nil
	}
	if _, err := safePathElement(accountID, "runner account label"); err != nil {
		return err
	}
	if entry.CachePreparedAccountID == accountID {
		return nil
	}
	if entry.CachePreparedAccountID != "" {
		return fmt.Errorf("runner cache volume already prepared for account %s", entry.CachePreparedAccountID)
	}

	shareDir := entry.CacheShareDir
	if shareDir == "" {
		var err error
		shareDir, err = m.vmShareDir(entry.VMName)
		if err != nil {
			return err
		}
		entry.CacheShareDir = shareDir
	}
	if err := os.MkdirAll(shareDir, 0o755); err != nil {
		return fmt.Errorf("create runner cache volume: %w", err)
	}

	readyPath := filepath.Join(shareDir, RunnerCacheReadyFile)
	if preparedAccountID, err := readPreparedAccountID(readyPath); err == nil {
		if preparedAccountID == accountID {
			entry.CachePreparedAccountID = accountID
			return nil
		}
		return fmt.Errorf("runner cache volume already marked ready for account %s", preparedAccountID)
	} else if !os.IsNotExist(err) {
		return fmt.Errorf("read runner cache ready marker: %w", err)
	}

	if err := clearDirectory(shareDir); err != nil {
		return fmt.Errorf("clear runner cache volume: %w", err)
	}
	preparingPath := filepath.Join(shareDir, runnerCachePreparingFile)
	if err := os.WriteFile(preparingPath, []byte(accountID+"\n"), 0o644); err != nil {
		return fmt.Errorf("write runner cache preparing marker: %w", err)
	}

	sourceDir, err := m.accountCacheDir(accountID)
	if err != nil {
		return err
	}
	if info, err := os.Stat(sourceDir); err == nil {
		if !info.IsDir() {
			return fmt.Errorf("runner cache source %s is not a directory", sourceDir)
		}
		if err := m.cloneTree(ctx, sourceDir, shareDir); err != nil {
			return fmt.Errorf("clone runner cache volume: %w", err)
		}
	} else if !os.IsNotExist(err) {
		return fmt.Errorf("stat runner cache source: %w", err)
	}

	if err := os.Remove(preparingPath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("remove runner cache preparing marker: %w", err)
	}
	if err := os.WriteFile(readyPath, []byte(accountID+"\n"), 0o644); err != nil {
		return fmt.Errorf("write runner cache ready marker: %w", err)
	}
	entry.CachePreparedAccountID = accountID
	return nil
}

func (m *CacheVolumeManager) Finalize(ctx context.Context, entry *Entry) error {
	if m == nil || entry == nil || entry.CacheShareDir == "" || entry.CachePreparedAccountID == "" {
		return nil
	}

	accountID := strings.TrimSpace(entry.CachePreparedAccountID)
	if _, err := safePathElement(accountID, "runner account label"); err != nil {
		return err
	}

	info, err := os.Stat(entry.CacheShareDir)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("stat runner cache volume: %w", err)
	}
	if !info.IsDir() {
		return fmt.Errorf("runner cache volume %s is not a directory", entry.CacheShareDir)
	}

	accountDir, err := m.accountCacheDir(accountID)
	if err != nil {
		return err
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	if err := os.MkdirAll(accountDir, 0o755); err != nil {
		return fmt.Errorf("create account runner cache: %w", err)
	}
	for _, marker := range []string{RunnerCacheReadyFile, runnerCachePreparingFile, runnerLocalKuraPIDFile} {
		if err := os.Remove(filepath.Join(entry.CacheShareDir, marker)); err != nil && !os.IsNotExist(err) {
			return fmt.Errorf("remove runner cache marker: %w", err)
		}
	}
	if err := m.cloneTree(ctx, entry.CacheShareDir, accountDir); err != nil {
		return fmt.Errorf("merge runner cache volume: %w", err)
	}
	return nil
}

func (m *CacheVolumeManager) CleanupVM(vmName string) error {
	shareDir, err := m.vmShareDir(vmName)
	if err != nil {
		return err
	}
	if err := os.RemoveAll(shareDir); err != nil {
		return fmt.Errorf("cleanup runner cache volume: %w", err)
	}
	return nil
}

func (m *CacheVolumeManager) vmShareDir(vmName string) (string, error) {
	safeVMName, err := safePathElement(vmName, "VM name")
	if err != nil {
		return "", err
	}
	return filepath.Join(m.RootDir, "vms", safeVMName), nil
}

func (m *CacheVolumeManager) accountCacheDir(accountID string) (string, error) {
	safeAccountID, err := safePathElement(accountID, "runner account label")
	if err != nil {
		return "", err
	}
	return filepath.Join(m.RootDir, "accounts", safeAccountID, "current"), nil
}

func (m *CacheVolumeManager) cloneTree(ctx context.Context, source, destination string) error {
	if m.CloneTree != nil {
		return m.CloneTree(ctx, source, destination)
	}
	return cloneTreeWithAPFSCopy(ctx, source, destination)
}

func cloneTreeWithAPFSCopy(ctx context.Context, source, destination string) error {
	sourceContents := source + string(os.PathSeparator) + "."
	cmd := exec.CommandContext(ctx, "/bin/cp", "-cR", sourceContents, destination)
	output, err := cmd.CombinedOutput()
	if err != nil {
		details := strings.TrimSpace(string(output))
		if details == "" {
			return err
		}
		return fmt.Errorf("%w: %s", err, details)
	}
	return nil
}

func clearDirectory(dir string) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if err := os.RemoveAll(filepath.Join(dir, entry.Name())); err != nil {
			return err
		}
	}
	return nil
}

func readPreparedAccountID(path string) (string, error) {
	contents, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	accountID := strings.TrimSpace(string(contents))
	if accountID == "" {
		return "", fmt.Errorf("runner cache ready marker is empty")
	}
	return accountID, nil
}

func safePathElement(value, label string) (string, error) {
	if value == "" || value == "." || value == ".." {
		return "", fmt.Errorf("%s %q is not a safe path element", label, value)
	}
	for _, char := range value {
		if char >= 'a' && char <= 'z' ||
			char >= 'A' && char <= 'Z' ||
			char >= '0' && char <= '9' ||
			char == '.' ||
			char == '_' ||
			char == '-' {
			continue
		}
		return "", fmt.Errorf("%s %q is not a safe path element", label, value)
	}
	return value, nil
}
