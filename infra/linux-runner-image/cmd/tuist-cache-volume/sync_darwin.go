//go:build darwin

package main

import (
	"os"

	"golang.org/x/sys/unix"
)

// fullSync asks the host to commit the file to its storage. Over the VM's
// virtio-fs share a plain fsync can return before the host has the writes.
func fullSync(f *os.File) error {
	if _, err := unix.FcntlInt(f.Fd(), unix.F_FULLFSYNC, 0); err == nil {
		return nil
	}
	return f.Sync()
}
