package fakevm

import (
	"errors"
	"os"
)

// CopyFile replaces dst with an independent copy of a tiny fake rootfs.
// Fake-VM lifecycle tests need no reflink-capable filesystem. Production
// leaves CloneFile unset and uses vm.Reflink without a copy fallback.
func CopyFile(src, dst string) error {
	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	if err := os.Remove(dst); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return os.WriteFile(dst, data, 0o644)
}
