package macosandbox

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

func TestDiskAdmissionIncludesEvictedDisksAndCheckpointReplacement(t *testing.T) {
	const gib = uint64(1024 * 1024 * 1024)
	vms := []tart.VM{{Name: "sbx-a", Disk: 100, Memory: 24576}, {Name: "sbx-b", Disk: 100, Memory: 24576}}
	if err := diskRoom(vms, 1024*gib, 100*gib, 24576); err != nil {
		t.Fatal(err)
	}
	if diskRoom(vms, 512*gib, 100*gib, 24576) == nil {
		t.Fatal("writable roots exceeded half-disk ceiling")
	}
	if diskRoom(vms, 1024*gib, 67*gib, 24576) == nil {
		t.Fatal("checkpoint replacement spent CI disk reserve")
	}
	vms[0].Disk = 0
	if diskRoom(vms, 1024*gib, 100*gib, 24576) == nil {
		t.Fatal("unknown logical disk admitted")
	}
}

// A stacked image the CI store cached through a rack mirror is seeded under
// the upstream name with exactly the disk files its manifest names, and a CI
// store missing one of them leaves no record behind.
func TestSeedImageClonesTheCIStoresCachedStackedImage(t *testing.T) {
	clone := cloneFile
	t.Cleanup(func() { cloneFile = clone })
	cloneFile = func(src, dst string) error {
		info, err := os.Stat(src)
		if err != nil {
			return err
		}
		if info.IsDir() {
			return os.CopyFS(dst, os.DirFS(src))
		}
		data, err := os.ReadFile(src)
		if err != nil {
			return err
		}
		return os.WriteFile(dst, data, 0600)
	}

	write := func(path, data string) {
		t.Helper()
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(data), 0600); err != nil {
			t.Fatal(err)
		}
	}
	base, overlay, unrelated := strings.Repeat("b", 64), strings.Repeat("c", 64), strings.Repeat("d", 64)
	digest := "sha256:" + strings.Repeat("a", 64)
	image := "ghcr.io/tuist/tuist-runner@" + digest
	manifest := `{"layers":[{"mediaType":"application/vnd.cirruslabs.tart.config.v1"},` +
		`{"annotations":{"` + tartContentDigestAnnotation + `":"sha256:` + base + `"}},{},` +
		`{"annotations":{"` + tartContentDigestAnnotation + `":"sha256:` + overlay + `"}}]}`

	ci := t.TempDir()
	record := filepath.Join(ci, "cache", "OCIs", "10.0.0.5%3A5000", "tuist", "tuist-runner", digest)
	write(filepath.Join(record, "config.json"), "config")
	write(filepath.Join(record, "nvram.bin"), "nvram")
	write(filepath.Join(record, "manifest.json"), manifest)
	content := filepath.Join(ci, "cache", "content")
	write(filepath.Join(content, ".gc.lock"), "")
	write(filepath.Join(content, "sha256", base), "base disk")
	write(filepath.Join(content, "sha256", unrelated), "another image")

	store := t.TempDir()
	if err := seedImage(ci, store, image); err == nil {
		t.Fatal("seeded an image whose overlay the CI store lacks")
	}
	seeded := filepath.Join(store, "cache", "OCIs", "ghcr.io", "tuist", "tuist-runner", digest)
	if _, err := os.Stat(seeded); !os.IsNotExist(err) {
		t.Fatalf("record published without its disk files: %v", err)
	}

	write(filepath.Join(content, "sha256", overlay), "overlay")
	if err := seedImage(ci, store, image); err != nil {
		t.Fatal(err)
	}
	for path, want := range map[string]string{
		filepath.Join(seeded, "config.json"):                        "config",
		filepath.Join(seeded, "nvram.bin"):                          "nvram",
		filepath.Join(seeded, "manifest.json"):                      manifest,
		filepath.Join(store, "cache", "content", "sha256", base):    "base disk",
		filepath.Join(store, "cache", "content", "sha256", overlay): "overlay",
	} {
		if got, err := os.ReadFile(path); err != nil || string(got) != want {
			t.Errorf("%s = %q, %v; want %q", path, got, err, want)
		}
	}
	if _, err := os.Stat(filepath.Join(store, "cache", "content", "sha256", unrelated)); !os.IsNotExist(err) {
		t.Errorf("seeded content the image does not name: %v", err)
	}
	if err := seedImage(ci, store, "ghcr.io/tuist/tuist-runner:26.6"); err == nil {
		t.Error("seeded an image not pinned by digest")
	}
}
