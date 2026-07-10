//go:build !darwin

package podagent

import "fmt"

// newImageBackend on non-darwin returns a backend whose disk operations
// error. tart-kubelet only runs on macOS hosts; this exists so the package
// still builds and its platform-neutral logic (the VolumeManager) stays
// unit-testable on Linux CI with an injected fake backend.
func newImageBackend() imageBackend { return unsupportedImageBackend{} }

type unsupportedImageBackend struct{}

var errUnsupported = fmt.Errorf("cache volumes require macOS")

func (unsupportedImageBackend) createMaster(string, int, string) error { return errUnsupported }
func (unsupportedImageBackend) clone(string, string) error             { return errUnsupported }
func (unsupportedImageBackend) remove(string) error                    { return errUnsupported }
func (unsupportedImageBackend) freeBytes(string) (uint64, error)       { return 0, errUnsupported }
