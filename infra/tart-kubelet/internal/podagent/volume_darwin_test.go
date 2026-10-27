//go:build darwin

package podagent

import (
	"os"
	"path/filepath"
	"testing"
)

// The real darwin mount check must not be fooled by an absent or stray
// mountpoint directory: both are "not a mount", where df would happily report
// the boot volume's free space.
func TestDarwinIsMountedNegatives(t *testing.T) {
	be := darwinVolumeBackend{}

	// A path that does not exist is not mounted, and that is not an error.
	if mounted, err := be.isMounted(filepath.Join(t.TempDir(), "missing")); err != nil || mounted {
		t.Fatalf("isMounted(missing) = (%v, %v), want (false, nil)", mounted, err)
	}

	// A plain subdirectory on the boot filesystem shares its parent's device id,
	// so it is not a mount point.
	sub := filepath.Join(t.TempDir(), "sub")
	if err := os.Mkdir(sub, 0o755); err != nil {
		t.Fatal(err)
	}
	if mounted, err := be.isMounted(sub); err != nil || mounted {
		t.Fatalf("isMounted(plain subdir) = (%v, %v), want (false, nil)", mounted, err)
	}
}

// When the real runner-cache volume happens to be mounted on this host, the
// check recognizes it as a mount. Skips when the volume is absent so the test
// stays green on any Mac.
func TestDarwinIsMountedRecognizesRealVolume(t *testing.T) {
	const mount = "/Volumes/tuist-runner-cache"
	if _, err := os.Stat(mount); err != nil {
		t.Skipf("runner-cache volume not present on this host: %v", err)
	}
	mounted, err := darwinVolumeBackend{}.isMounted(mount)
	if err != nil || !mounted {
		t.Fatalf("isMounted(%s) = (%v, %v), want (true, nil)", mount, mounted, err)
	}
}
