//go:build darwin

package podagent

import (
	"bytes"
	"crypto/rand"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
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

// The digest a promoting guest publishes must be measured on the DETACHED image,
// because it is a claim about the bytes it uploads: it becomes both the HEAD's
// tree_digest and the immutable object key. Measured through the job's own live
// read-write mount instead, anything that writes between the measurement and the
// detach — a build service outliving the runner, the compilation cache's own
// asynchronous store flush or prune — publishes a HEAD naming bytes that no host
// can reproduce. Convergence then downloads the object, computes a different
// digest and declines, and since a cold promote's base generation 0 is rejected
// while a HEAD exists, the account is stuck cold fleet-wide until that HEAD is
// retired. This pins the reason dispatch-poll.sh re-attaches read-only at teardown
// rather than reading the mount it already has.
func TestLiveMountDigestDivergesFromTheUploadedImage(t *testing.T) {
	be := darwinVolumeBackend{}
	image := filepath.Join(t.TempDir(), "cache.sparseimage")
	if err := be.createImage(image, 1); err != nil {
		t.Fatalf("create image: %v", err)
	}

	mnt := t.TempDir()
	if _, err := runCmd(2*attachTimeout, "hdiutil", "attach", image,
		"-owners", "off", "-nobrowse", "-noverify", "-quiet", "-mountpoint", mnt); err != nil {
		t.Fatalf("attach image read-write: %v", err)
	}
	store := filepath.Join(mnt, casStoreDir, "v1")
	if err := os.MkdirAll(store, 0o755); err != nil {
		t.Fatalf("seed CAS store: %v", err)
	}
	records := filepath.Join(store, "records")
	if err := os.WriteFile(records, make([]byte, 4096), 0o644); err != nil {
		t.Fatalf("seed CAS records: %v", err)
	}

	// What the guest used to publish: the inventory of the still-mounted image.
	published, err := inventoryDigest(mnt)
	if err != nil {
		t.Fatalf("digest through the live mount: %v", err)
	}

	// A straggler appends to the size-capped store after the runner exited. Every
	// ~cas/ line carries a file size, so one late append is enough.
	appended, err := os.OpenFile(records, os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		t.Fatalf("open CAS records for append: %v", err)
	}
	if _, err := appended.Write(make([]byte, 512)); err != nil {
		t.Fatalf("append to CAS records: %v", err)
	}
	if err := appended.Close(); err != nil {
		t.Fatalf("close CAS records: %v", err)
	}
	if _, err := runCmd(attachTimeout, "hdiutil", "detach", mnt, "-force", "-quiet"); err != nil {
		t.Fatalf("detach: %v", err)
	}

	// What a converging host measures on the object it downloads, which is also
	// what the settled read-only re-attach at teardown now publishes.
	verified, err := be.imageInventoryDigest(image)
	if err != nil {
		t.Fatalf("digest of the settled image: %v", err)
	}

	if verified == published {
		t.Fatal("expected the live-mount digest to disagree with the uploaded image; " +
			"if this now holds, the window this guards against is gone and the reason should be re-checked")
	}
}

// guestCacheInventoryScript mirrors dispatch-poll.sh's cache_inventory pipeline
// byte-for-byte. It takes the image MOUNT root as $1. Keep in sync with the
// script; TestInventoryDigestMatchesGuestPipeline runs BOTH and asserts they
// agree, so a divergence fails here rather than silently aborting convergence in
// production.
const guestCacheInventoryScript = `
set -u
root="$1/tuist"
cas="$1/CompilationCache.noindex"
{
  for d in Binaries EditProjects GenerationMetadata Manifests Plugins ProjectDescriptionHelpers Projects Runs SelectiveTests; do
    /bin/ls -1 "${root}/${d}" 2>/dev/null | sed "s|^|${d}/|"
  done
  ( cd "${cas}" 2>/dev/null && find . -type f -not -path '*/.*' -exec stat -f "%N$(printf '\t')%z" {} + 2>/dev/null ) \
    | sed 's|^\./|~cas/|'
} | LC_ALL=C sort | shasum | awk '{print $1}'
`

// The host's Go inventoryDigest and the guest's real shell pipeline must produce
// the SAME digest for the same tree — the convergence-critical invariant. This
// runs the ACTUAL find/stat/sed/ls/sort/shasum tools (not a Go re-derivation),
// so it catches a bash/Go format divergence that TestInventoryDigestMatchesGuestScript
// (Go-only) cannot.
func TestInventoryDigestMatchesGuestPipeline(t *testing.T) {
	root := t.TempDir()

	// Binary subtrees: two entries + a dotfile the guest's `ls -1` and the host
	// both drop.
	binaries := filepath.Join(root, cacheHomeSubdir, "Binaries")
	for _, name := range []string{"hashA", "hashB"} {
		if err := os.MkdirAll(filepath.Join(binaries, name), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(binaries, ".DS_Store"), []byte("noise"), 0o644); err != nil {
		t.Fatal(err)
	}

	// One entry in every other covered subtree, so a subdir added to one side's
	// list and not the other diverges here rather than in production. Runs holds a
	// result bundle, GenerationMetadata a flat file, to cover both entry shapes.
	for _, sub := range []string{"EditProjects", "Manifests", "Plugins", "ProjectDescriptionHelpers", "Projects", "SelectiveTests"} {
		if err := os.MkdirAll(filepath.Join(root, cacheHomeSubdir, sub, "entry"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.MkdirAll(filepath.Join(root, cacheHomeSubdir, "Runs", "run-id", "result-bundle"), 0o755); err != nil {
		t.Fatal(err)
	}
	generationMetadata := filepath.Join(root, cacheHomeSubdir, "GenerationMetadata")
	if err := os.MkdirAll(generationMetadata, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(generationMetadata, "hash.json"), []byte("{}"), 0o644); err != nil {
		t.Fatal(err)
	}

	// CAS store: nested files, a name with a space, plus dot-path noise (a dotfile
	// and a whole hidden dir) that BOTH sides must exclude.
	cas := filepath.Join(root, casStoreDir)
	if err := os.MkdirAll(filepath.Join(cas, "v1"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(cas, ".hidden"), 0o755); err != nil {
		t.Fatal(err)
	}
	writes := map[string]int{
		filepath.Join(cas, "data"):            40,
		filepath.Join(cas, "v1", "records"):   100,
		filepath.Join(cas, "with space"):      7,
		filepath.Join(cas, ".writable"):       1,
		filepath.Join(cas, ".hidden", "junk"): 3,
	}
	for path, size := range writes {
		if err := os.WriteFile(path, make([]byte, size), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	host, err := inventoryDigest(root)
	if err != nil {
		t.Fatalf("inventoryDigest: %v", err)
	}

	out, err := exec.Command("bash", "-c", guestCacheInventoryScript, "cache_inventory", root).Output()
	if err != nil {
		t.Fatalf("guest pipeline: %v", err)
	}
	guest := strings.TrimSpace(string(out))

	if host != guest {
		t.Fatalf("host/guest digest divergence:\n  host  = %q\n  guest = %q", host, guest)
	}
}

// imageCapacityBytes is a detached image's current size, from the middle column
// of `hdiutil resize -limits` (minimum, current and maximum, in 512-byte sectors).
func imageCapacityBytes(t *testing.T, image string) uint64 {
	t.Helper()
	out, err := runCmd(attachTimeout, "hdiutil", "resize", "-limits", image)
	if err != nil {
		t.Fatalf("hdiutil resize -limits: %v", err)
	}
	fields := strings.Fields(out)
	if len(fields) != 3 {
		t.Fatalf("hdiutil resize -limits printed %q; want minimum, current and maximum", out)
	}
	sectors, err := strconv.ParseUint(fields[1], 10, 64)
	if err != nil {
		t.Fatalf("current size %q: %v", fields[1], err)
	}
	return sectors * 512
}

// allocatedBytes is what the image file takes on the host, which is what a
// master costs the runner-cache volume.
func allocatedBytes(t *testing.T, path string) uint64 {
	t.Helper()
	fi, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	return uint64(fi.Sys().(*syscall.Stat_t).Blocks) * 512
}

// `hdiutil resize -size` shrinks an image that is already larger than the size
// it is given, moving data to do it, so growing a branch has to check before it
// resizes. A master converged from a host with a larger ceiling must reach a job
// unchanged.
func TestDarwinGrowImageNeverShrinks(t *testing.T) {
	be := darwinVolumeBackend{}
	image := filepath.Join(t.TempDir(), "branch.sparseimage")
	if err := be.createImage(image, 1); err != nil {
		t.Fatalf("create image: %v", err)
	}
	const mib = uint64(1 << 20)

	if err := be.growImage(image, 2); err != nil {
		t.Fatalf("growImage(2): %v", err)
	}
	if got := imageCapacityBytes(t, image); got < 2*gib-mib {
		t.Fatalf("capacity after growing to 2 GiB = %d; want at least 2 GiB", got)
	}

	if err := be.growImage(image, 1); err != nil {
		t.Fatalf("growImage(1): %v", err)
	}
	if got := imageCapacityBytes(t, image); got < 2*gib-mib {
		t.Fatalf("capacity after growing to 1 GiB = %d; a grow must never shrink a larger image", got)
	}
}

// At teardown the guest shrinks the image it is about to promote to its content
// and compacts it, so a master costs the host what it holds rather than the most
// it ever held, and the host's grow gives the next job its room back.
func TestGuestShrinkCacheImageKeepsItsContent(t *testing.T) {
	be := darwinVolumeBackend{}
	image := filepath.Join(t.TempDir(), "cache.sparseimage")
	if err := be.createImage(image, 1); err != nil {
		t.Fatalf("create image: %v", err)
	}
	kept := seedPrunedCache(t, image)
	capacityBefore := imageCapacityBytes(t, image)
	allocatedBefore := allocatedBytes(t, image)

	cmd := exec.Command("/bin/bash", "-c", "set -u\n"+guestShellFunction(t, "shrink_cache_image")+"\nshrink_cache_image")
	cmd.Env = append(os.Environ(), "CACHE_IMAGE="+image)
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("shrink_cache_image: %v\n%s", err, out)
	}

	if capacityAfter := imageCapacityBytes(t, image); capacityAfter >= capacityBefore/2 {
		t.Fatalf("capacity %d -> %d; want the image shrunk to its content\n%s", capacityBefore, capacityAfter, out)
	}
	if allocatedAfter := allocatedBytes(t, image); allocatedAfter >= allocatedBefore {
		t.Fatalf("allocated %d -> %d; want the pruned bytes returned to the host\n%s", allocatedBefore, allocatedAfter, out)
	}
	assertCacheContent(t, image, kept)
	assertGrownImageTakesWrites(t, be, image)
}

// The next job clones the shrunk master, and the host's grow is what gives it
// room to write again.
func assertGrownImageTakesWrites(t *testing.T, be darwinVolumeBackend, image string) {
	t.Helper()
	if err := be.growImage(image, 1); err != nil {
		t.Fatalf("growImage: %v", err)
	}
	mnt := t.TempDir()
	if _, err := runCmd(2*attachTimeout, "hdiutil", "attach", image,
		"-owners", "off", "-nobrowse", "-noverify", "-quiet", "-mountpoint", mnt); err != nil {
		t.Fatalf("attach grown image: %v", err)
	}
	defer runCmd(attachTimeout, "hdiutil", "detach", mnt, "-force", "-quiet")
	if err := os.WriteFile(filepath.Join(mnt, cacheHomeSubdir, "Binaries", "next-job"), make([]byte, 200<<20), 0o644); err != nil {
		t.Fatalf("writing 200 MiB into the grown image: %v", err)
	}
}

// seedPrunedCache fills a binary cache inside the image and prunes half of it,
// the way a job's LRU prune leaves freed space behind inside the image. It
// returns the surviving files and their contents.
func seedPrunedCache(t *testing.T, image string) map[string][]byte {
	t.Helper()
	mnt := t.TempDir()
	if _, err := runCmd(2*attachTimeout, "hdiutil", "attach", image,
		"-owners", "off", "-nobrowse", "-noverify", "-quiet", "-mountpoint", mnt); err != nil {
		t.Fatalf("attach image for seeding: %v", err)
	}
	binaries := filepath.Join(mnt, cacheHomeSubdir, "Binaries")
	if err := os.MkdirAll(binaries, 0o755); err != nil {
		t.Fatal(err)
	}
	kept := map[string][]byte{}
	for i := 0; i < 20; i++ {
		content := make([]byte, 4<<20)
		if _, err := rand.Read(content); err != nil {
			t.Fatal(err)
		}
		name := fmt.Sprintf("artifact-%02d", i)
		if err := os.WriteFile(filepath.Join(binaries, name), content, 0o644); err != nil {
			t.Fatal(err)
		}
		if i%2 == 0 {
			kept[name] = content
		}
	}
	for i := 1; i < 20; i += 2 {
		if err := os.Remove(filepath.Join(binaries, fmt.Sprintf("artifact-%02d", i))); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := runCmd(attachTimeout, "hdiutil", "detach", mnt, "-quiet"); err != nil {
		t.Fatalf("detach seeded image: %v", err)
	}
	return kept
}

func assertCacheContent(t *testing.T, image string, want map[string][]byte) {
	t.Helper()
	mnt := t.TempDir()
	if _, err := runCmd(2*attachTimeout, "hdiutil", "attach", image,
		"-readonly", "-owners", "off", "-nobrowse", "-noverify", "-quiet", "-mountpoint", mnt); err != nil {
		t.Fatalf("attach resized image: %v", err)
	}
	defer runCmd(attachTimeout, "hdiutil", "detach", mnt, "-force", "-quiet")
	binaries := filepath.Join(mnt, cacheHomeSubdir, "Binaries")
	entries, err := os.ReadDir(binaries)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != len(want) {
		t.Fatalf("image holds %d artifacts; want %d", len(entries), len(want))
	}
	for name, content := range want {
		got, err := os.ReadFile(filepath.Join(binaries, name))
		if err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(got, content) {
			t.Fatalf("%s changed across the resize", name)
		}
	}
}
