//go:build !linux

package checkout

import "syscall"

// syncFilesystem writes back every filesystem: macOS has no syncfs, and only
// tests build the daemon there.
func syncFilesystem(string) error {
	syscall.Sync()
	return nil
}
