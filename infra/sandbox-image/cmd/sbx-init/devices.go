package main

import (
	"fmt"
	"os"
	"path/filepath"
)

// devtmpfs supplies device nodes, but init must create the descriptor aliases.
// In particular, Bash process substitution opens paths such as /dev/fd/63.
func ensureDeviceLinks(directory string) error {
	for name, target := range map[string]string{
		"fd":     "/proc/self/fd",
		"stdin":  "/proc/self/fd/0",
		"stdout": "/proc/self/fd/1",
		"stderr": "/proc/self/fd/2",
	} {
		path := filepath.Join(directory, name)
		if err := os.Symlink(target, path); err != nil {
			if existing, readErr := os.Readlink(path); readErr == nil && existing == target {
				continue
			}
			return fmt.Errorf("create %s: %w", path, err)
		}
	}
	return nil
}
