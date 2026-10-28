package vm

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

// HardLink replaces dst with a hard link to src.
func HardLink(src, dst string) error {
	if err := os.Remove(dst); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if err := os.Link(src, dst); err != nil {
		return fmt.Errorf("linking %s to %s: %w", src, dst, err)
	}
	return nil
}

// Reflink replaces dst with a copy-on-write clone of src.
func Reflink(src, dst string) error {
	if err := os.Remove(dst); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if err := reflink(src, dst); err != nil {
		return fmt.Errorf("reflinking %s to %s: %w", src, dst, err)
	}
	return nil
}

// Sparse creates dst as a sparse file of size bytes (no mkfs; the guest
// formats it).
func Sparse(dst string, size int64) error {
	if err := os.Remove(dst); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	f, err := os.OpenFile(dst, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	if err := f.Truncate(size); err != nil {
		return fmt.Errorf("sizing %s to %d bytes: %w", dst, size, err)
	}
	return nil
}

// Chown hands a file to the jail uid. It is a no-op when the daemon is not
// root (local development on macOS), where Firecracker never runs anyway.
func Chown(path string, uid, gid int) error {
	if os.Geteuid() != 0 || uid < 0 {
		return nil
	}
	if err := os.Lchown(path, uid, gid); err != nil {
		return fmt.Errorf("chown %s: %w", path, err)
	}
	return nil
}

// Rename moves src over dst within the same filesystem.
func Rename(src, dst string) error {
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	return os.Rename(src, dst)
}

func FileSize(path string) int64 {
	info, err := os.Stat(path)
	if err != nil {
		return 0
	}
	return info.Size()
}

func Exists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
