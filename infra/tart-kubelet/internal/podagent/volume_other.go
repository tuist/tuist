//go:build !darwin

package podagent

import "fmt"

// newVolumeBackend on non-darwin returns a backend whose operations error.
// tart-kubelet only runs on macOS hosts; this exists so the package still
// builds and its platform-neutral logic (the VolumeManager) stays unit-
// testable on Linux CI with an injected fake backend.
func newVolumeBackend() volumeBackend { return unsupportedVolumeBackend{} }

type unsupportedVolumeBackend struct{}

var errUnsupported = fmt.Errorf("cache volumes require macOS")

func (unsupportedVolumeBackend) clonePath(string, string) error   { return errUnsupported }
func (unsupportedVolumeBackend) freeBytes(string) (uint64, error) { return 0, errUnsupported }
func (unsupportedVolumeBackend) isMounted(string) (bool, error)   { return false, errUnsupported }
func (unsupportedVolumeBackend) createImage(string, int) error    { return errUnsupported }

func (unsupportedVolumeBackend) imageInventoryDigest(string) (string, error) {
	return "", errUnsupported
}
