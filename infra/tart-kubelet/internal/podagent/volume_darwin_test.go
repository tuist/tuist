//go:build darwin

package podagent

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// attachTimeout bounds the hdiutil attach/detach calls the darwin tests make.
const attachTimeout = time.Minute

// mergeInto against real sparse images must UNION cache objects (preserving
// xattrs and symlinks via ditto), not replace: an object only the destination
// holds survives, an object only the source holds is copied in, and a shared one
// is left alone. Exercises the real hdiutil attach + ditto path, so it only runs
// where hdiutil exists.
func TestDarwinMergeIntoUnionsObjects(t *testing.T) {
	be := darwinVolumeBackend{}
	dir := t.TempDir()

	dst := filepath.Join(dir, "dst.sparseimage")
	src := filepath.Join(dir, "src.sparseimage")
	if err := be.createImage(dst, 1); err != nil {
		t.Fatalf("create dst image: %v", err)
	}
	if err := be.createImage(src, 1); err != nil {
		t.Fatalf("create src image: %v", err)
	}

	// dst holds a shared binary + a dst-only binary; src holds the shared binary +
	// a src-only binary that also carries an xattr'd symlink (the artifact shape
	// the whole disk-image design exists to preserve across virtio-fs).
	seedImageObjects(t, be, dst, map[string]bool{
		"Binaries/shared":  false,
		"Binaries/dstOnly": false,
	})
	seedImageObjects(t, be, src, map[string]bool{
		"Binaries/shared":  false,
		"Binaries/srcOnly": true,
	})

	digest, err := be.mergeInto(dst, src)
	if err != nil {
		t.Fatalf("mergeInto: %v", err)
	}

	// The merged dst holds the union of the two object sets.
	mnt := t.TempDir()
	if _, err := runCmd(2*attachTimeout, "hdiutil", "attach", dst,
		"-readonly", "-owners", "off", "-nobrowse", "-noverify", "-quiet", "-mountpoint", mnt); err != nil {
		t.Fatalf("attach merged dst: %v", err)
	}
	defer runCmd(attachTimeout, "hdiutil", "detach", mnt, "-force", "-quiet")

	binaries := filepath.Join(mnt, cacheHomeSubdir, "Binaries")
	for _, want := range []string{"shared", "dstOnly", "srcOnly"} {
		if _, err := os.Lstat(filepath.Join(binaries, want)); err != nil {
			t.Fatalf("merged master missing object Binaries/%s: %v", want, err)
		}
	}
	// The src-only object's xattr'd symlink came across intact — the property a
	// plain copy over virtio-fs would have lost.
	link := filepath.Join(binaries, "srcOnly", "link")
	if fi, err := os.Lstat(link); err != nil || fi.Mode()&os.ModeSymlink == 0 {
		t.Fatalf("merged src-only object lost its symlink: fi=%v err=%v", fi, err)
	}
	if out, err := runCmd(attachTimeout, "xattr", "-p", "-s", "user.tuist", link); err != nil || strings.TrimSpace(out) != "signed" {
		t.Fatalf("merged symlink lost its xattr: out=%q err=%v", out, err)
	}

	// The digest mergeInto returned equals a fresh read of the merged inventory,
	// computed from the mount already held (re-attaching the same image would
	// fail — hdiutil refuses a second attach).
	if want, err := inventoryDigest(filepath.Join(mnt, cacheHomeSubdir)); err != nil || want != digest {
		t.Fatalf("mergeInto digest = %q; fresh inventory of merged image = %q, %v", digest, want, err)
	}
}

// seedImageObjects attaches image read-write and creates each Binaries object as
// a directory; when withXattrSymlink is set the object also gets a symlink
// carrying a user xattr, so the test can assert ditto preserved it.
func seedImageObjects(t *testing.T, be darwinVolumeBackend, image string, objects map[string]bool) {
	t.Helper()
	mnt := t.TempDir()
	if _, err := runCmd(2*attachTimeout, "hdiutil", "attach", image,
		"-owners", "off", "-nobrowse", "-noverify", "-quiet", "-mountpoint", mnt); err != nil {
		t.Fatalf("attach image for seeding: %v", err)
	}
	defer runCmd(attachTimeout, "hdiutil", "detach", mnt, "-force", "-quiet")

	for obj, withXattrSymlink := range objects {
		objDir := filepath.Join(mnt, cacheHomeSubdir, obj)
		if err := os.MkdirAll(objDir, 0o755); err != nil {
			t.Fatalf("mkdir object %s: %v", obj, err)
		}
		if err := os.WriteFile(filepath.Join(objDir, "content"), []byte(obj), 0o644); err != nil {
			t.Fatalf("write object content %s: %v", obj, err)
		}
		if withXattrSymlink {
			link := filepath.Join(objDir, "link")
			if err := os.Symlink("content", link); err != nil {
				t.Fatalf("symlink in %s: %v", obj, err)
			}
			if _, err := runCmd(attachTimeout, "xattr", "-w", "-s", "user.tuist", "signed", link); err != nil {
				t.Fatalf("set xattr on symlink in %s: %v", obj, err)
			}
		}
	}
}

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
