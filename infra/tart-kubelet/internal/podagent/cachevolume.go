package podagent

import (
	"fmt"
	"os"
	"path/filepath"

	corev1 "k8s.io/api/core/v1"
)

const (
	RunnerCacheVolumeAnnotation = "tart-kubelet.tuist.dev/runner-cache-volume"
	RunnerAccountLabel          = "tuist.dev/runner-account"
	RunnerCacheShareName        = "tuist-cache"
)

// CacheVolumeManager owns the per-VM `tuist-cache` share directory: the empty
// directory Tart mounts into the runner VM and that the reconciler writes the
// host Kura endpoint marker into. The account's cache data itself is served by
// the persistent per-account host Kura (see HostKuraManager) over the vmnet
// bridge — it is never copied into the share — so the manager only stages and
// tears the share down.
type CacheVolumeManager struct {
	RootDir string
}

func (m *CacheVolumeManager) EnabledForPod(pod *corev1.Pod) bool {
	return m != nil &&
		m.RootDir != "" &&
		pod.Annotations[RunnerCacheVolumeAnnotation] == "true"
}

// StageVM creates an empty per-VM share directory (resetting any stale one from
// a prior VM of the same name) that Tart mounts as the `tuist-cache` shared dir.
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

// CleanupVM removes a VM's share directory on teardown.
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
