//go:build darwin

package podagent

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

// attachTimeout bounds the hdiutil attach/detach calls the darwin tests make.
const attachTimeout = time.Minute

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

// imageInventoryDigest attaches a real sparse image read-only and digests the
// cache home inside it — the integrity check convergence runs on a downloaded
// HEAD before adopting it. It must be stable across attaches and change with the
// cache contents. Runs only where hdiutil exists.
func TestDarwinImageInventoryDigest(t *testing.T) {
	be := darwinVolumeBackend{}
	image := filepath.Join(t.TempDir(), "master.sparseimage")
	if err := be.createImage(image, 1); err != nil {
		t.Fatalf("create image: %v", err)
	}

	// Empty cache home: a stable digest, repeatable across attaches.
	d0, err := be.imageInventoryDigest(image)
	if err != nil {
		t.Fatalf("imageInventoryDigest (empty): %v", err)
	}
	if again, err := be.imageInventoryDigest(image); err != nil || again != d0 {
		t.Fatalf("imageInventoryDigest not stable: %q vs %q, %v", d0, again, err)
	}

	// Seed a Binaries object; the digest must change to reflect the new inventory.
	mnt := t.TempDir()
	if _, err := runCmd(2*attachTimeout, "hdiutil", "attach", image,
		"-owners", "off", "-nobrowse", "-noverify", "-quiet", "-mountpoint", mnt); err != nil {
		t.Fatalf("attach image for seeding: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(mnt, cacheHomeSubdir, "Binaries", "hashA"), 0o755); err != nil {
		t.Fatalf("seed object: %v", err)
	}
	if _, err := runCmd(attachTimeout, "hdiutil", "detach", mnt, "-force", "-quiet"); err != nil {
		t.Fatalf("detach: %v", err)
	}

	d1, err := be.imageInventoryDigest(image)
	if err != nil {
		t.Fatalf("imageInventoryDigest (seeded): %v", err)
	}
	if d1 == d0 {
		t.Fatal("digest did not change after adding a Binaries object")
	}
}
