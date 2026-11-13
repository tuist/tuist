package checkout

import (
	"os"

	"golang.org/x/sys/unix"
)

// syncFilesystem writes back the filesystem holding dir.
func syncFilesystem(dir string) error {
	file, err := os.Open(dir)
	if err != nil {
		return err
	}
	defer file.Close()
	return unix.Syncfs(int(file.Fd()))
}
