//go:build darwin

package podagent

import (
	"crypto/rand"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
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
  for d in Binaries Manifests ProjectDescriptionHelpers Plugins; do
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

// shellFunc returns a top-level `name() {` … `}` definition from a shell script.
func shellFunc(src, name string) (string, bool) {
	lines := strings.Split(src, "\n")
	for i, line := range lines {
		if line != name+"() {" {
			continue
		}
		for j := i + 1; j < len(lines); j++ {
			if lines[j] == "}" {
				return strings.Join(lines[i:j+1], "\n"), true
			}
		}
	}
	return "", false
}

// guestSampleCacheUsage runs dispatch-poll.sh's sample_cache_usage against a
// fixture mount. The function is EXTRACTED from the shipping script rather than
// mirrored here, so the guest's real `du` walk is what gets asserted.
func guestSampleCacheUsage(t *testing.T, mount, statusDir string) {
	t.Helper()
	const script = "../../../runner-image/dispatch-poll.sh"
	src, err := os.ReadFile(script)
	if err != nil {
		t.Fatalf("read %s: %v", script, err)
	}
	body, ok := shellFunc(string(src), "sample_cache_usage")
	if !ok {
		t.Fatalf("sample_cache_usage not found in %s", script)
	}
	prog := "set -u\n" +
		"CACHE_MOUNT=\"$1\"\n" +
		"STATUS_SHARE=\"$2\"\n" +
		"CAS_STORE_DIR=\"" + casStoreDir + "\"\n" +
		body + "\nsample_cache_usage\n"
	out, err := exec.Command("bash", "-c", prog, "sample_cache_usage", mount, statusDir).CombinedOutput()
	if err != nil {
		t.Fatalf("run sample_cache_usage: %v\n%s", err, out)
	}
}

// seedIncompressible writes n KiB that APFS cannot compress away, so `du`
// reports the size the test intends rather than zero.
func seedIncompressible(t *testing.T, path string, kib int) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, kib*1024)
	if _, err := rand.Read(buf); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, buf, 0o644); err != nil {
		t.Fatal(err)
	}
}

// readSubtreeReport parses the guest's `<name>\t<KiB>` report off the status share.
func readSubtreeReport(t *testing.T, statusDir string) map[string]int {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(statusDir, "cache-subtree-kib"))
	if err != nil {
		t.Fatalf("read report: %v", err)
	}
	got := map[string]int{}
	for _, line := range strings.Split(strings.TrimSpace(string(b)), "\n") {
		if line == "" {
			continue
		}
		name, kib, ok := strings.Cut(line, "\t")
		if !ok {
			t.Fatalf("malformed report line %q", line)
		}
		n, err := strconv.Atoi(kib)
		if err != nil {
			t.Fatalf("non-numeric KiB in %q", line)
		}
		got[name] = n
	}
	return got
}

// The whole-mount fill % says the image is full; this report says what filled it.
// One line per cache category plus the folded CAS store, and nothing else: the
// cache root's own total and loose files under it are not subtrees and would
// double-count against the categories if reported.
func TestGuestSampleCacheUsageReportsPerSubtreeKiB(t *testing.T) {
	mount := t.TempDir()
	statusDir := t.TempDir()

	root := filepath.Join(mount, cacheHomeSubdir)
	seedIncompressible(t, filepath.Join(root, "Binaries", "hashA", "slice.a"), 3000)
	seedIncompressible(t, filepath.Join(root, "Runs", "run-1", "graph.json"), 500)
	seedIncompressible(t, filepath.Join(mount, casStoreDir, "v1", "data"), 8000)
	if err := os.MkdirAll(filepath.Join(root, "Manifests"), 0o755); err != nil {
		t.Fatal(err)
	}
	seedIncompressible(t, filepath.Join(root, "loose"), 64)

	guestSampleCacheUsage(t, mount, statusDir)
	got := readSubtreeReport(t, statusDir)

	for name, want := range map[string]int{"Binaries": 3000, "Runs": 500, "cas": 8000} {
		if got[name] < want || got[name] > want+64 {
			t.Errorf("%s = %d KiB, want ~%d", name, got[name], want)
		}
	}
	if _, ok := got["Manifests"]; !ok {
		t.Error("an existing but empty category must still be reported")
	}
	for _, name := range []string{cacheHomeSubdir, "loose"} {
		if _, ok := got[name]; ok {
			t.Errorf("%q reported as a subtree; it overlaps or is not a directory", name)
		}
	}
}

// The guest writes the report and the host parses it, and neither half is worth
// anything if they disagree about the format. This runs the real `du` pipeline
// out of dispatch-poll.sh and feeds its output straight into the host reader, so
// a format drift fails here instead of silently emptying the metric in
// production.
func TestGuestSampleCacheUsageParsesOnTheHost(t *testing.T) {
	mount := t.TempDir()
	statusDir := t.TempDir()

	root := filepath.Join(mount, cacheHomeSubdir)
	seedIncompressible(t, filepath.Join(root, "Binaries", "hashA", "slice.a"), 3000)
	seedIncompressible(t, filepath.Join(root, "Runs", "run-1", "graph.json"), 500)
	seedIncompressible(t, filepath.Join(mount, casStoreDir, "v1", "data"), 8000)

	guestSampleCacheUsage(t, mount, statusDir)

	usage := readSubtreeUsage(statusDir)
	if usage == nil {
		t.Fatal("host read no usage from a report the guest just wrote")
	}
	for label, want := range map[string]uint64{"binaries": 3000, "runs": 500, "cas": 8000} {
		got := usage[label] >> 10
		if got < want || got > want+64 {
			t.Errorf("%s = %d KiB, want ~%d", label, got, want)
		}
	}
	if _, ok := usage[subtreeOther]; ok {
		t.Errorf("host folded a known category into %q: %v", subtreeOther, usage)
	}
}

// A cold cache has no tree to walk and no CAS store. The guest must leave a
// report the host reads as "nothing measured" rather than one claiming zeros.
func TestGuestSampleCacheUsageOnEmptyMount(t *testing.T) {
	statusDir := t.TempDir()
	guestSampleCacheUsage(t, t.TempDir(), statusDir)

	if got := readSubtreeReport(t, statusDir); len(got) != 0 {
		t.Fatalf("report over an empty mount = %v, want no lines", got)
	}
}
