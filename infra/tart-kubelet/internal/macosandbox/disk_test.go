package macosandbox

import (
	"bytes"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"testing"

	"github.com/google/uuid"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

func TestDiskAdmissionIncludesEvictedDisksAndCheckpointReplacement(t *testing.T) {
	const gib = uint64(1024 * 1024 * 1024)
	vms := []tart.VM{{Name: "sbx-a", Disk: 100, Memory: 24576}, {Name: "sbx-b", Disk: 100, Memory: 24576}}
	if err := diskRoom(vms, 0, 1024*gib, 100*gib, 24576, 0); err != nil {
		t.Fatal(err)
	}
	if diskRoom(vms, 0, 512*gib, 100*gib, 24576, 0) == nil {
		t.Fatal("writable roots exceeded half-disk ceiling")
	}
	if diskRoom(vms, 0, 1024*gib, 67*gib, 24576, 0) == nil {
		t.Fatal("checkpoint replacement spent CI disk reserve")
	}
	// A VM not cloned yet counts against the same half-disk budget.
	if diskRoom(vms, 0, 1024*gib, 100*gib, 24576, 400*gib) == nil {
		t.Fatal("a clone past the half-disk ceiling admitted")
	}
	// So do the disk snapshots the host holds.
	if diskRoom(vms, 400*gib, 1024*gib, 100*gib, 24576, 0) == nil {
		t.Fatal("snapshots past the half-disk ceiling admitted")
	}
	vms[0].Disk = 0
	if diskRoom(vms, 0, 1024*gib, 100*gib, 24576, 0) == nil {
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

// A save copies a stopped VM's disk files, for a stacked VM its manifest and
// private overlay, and leaves its checkpoint and control files behind, so a
// VM cloned from it cold boots. The snapshot reserves the overlay's allocated
// bytes, and a save repeated after a lost answer returns the same snapshot.
func TestSaveDisksCopiesDisksWithoutCheckpoint(t *testing.T) {
	clone, size := cloneFile, filesystemSize
	t.Cleanup(func() { cloneFile, filesystemSize = clone, size })
	cloneFile = func(src, dst string) error {
		data, err := os.ReadFile(src)
		if err != nil {
			return err
		}
		return os.WriteFile(dst, data, 0o600)
	}
	const gib = uint64(1024 * 1024 * 1024)
	filesystemSize = func(string) (uint64, uint64, error) { return 1024 * gib, 500 * gib, nil }
	dir := t.TempDir()
	binary := filepath.Join(dir, "tart")
	if err := os.WriteFile(binary, []byte("#!/bin/sh\n[ \"$1\" = list ] && echo '[]'\nexit 0\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	runtime := &TartRuntime{Client: &tart.Client{Binary: binary, HomeDir: filepath.Join(dir, "home")}}
	r := &Record{CreateArgs: protocol.CreateArgs{SandboxID: uuid.NewString(), Template: "macos", TemplateTag: "image@sha256:a", WorkspaceGB: 10}, WorkspaceVolumeGB: 10}
	source := runtime.directory(r)
	if err := os.MkdirAll(source, 0o700); err != nil {
		t.Fatal(err)
	}
	overlay := strings.Repeat("x", 64*1024)
	for name, content := range map[string]string{"config.json": "{}", "nvram.bin": "n", "manifest.json": "m", "overlay.asif": overlay, "state.vzvmsave": "s", "checkpoint-instance": "i", "sandbox-request.json": "{}"} {
		if err := os.WriteFile(filepath.Join(source, name), []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	id := uuid.NewString()
	info, err := runtime.SaveDisks(t.Context(), r, id)
	if err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(runtime.snapshotDirectory(id))
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, e := range entries {
		names = append(names, e.Name())
	}
	if got := strings.Join(names, ","); got != "config.json,disk-snapshot.json,manifest.json,nvram.bin,overlay.asif" {
		t.Fatalf("snapshot holds %s", got)
	}
	if info.Bytes < int64(len(overlay)) || info.TemplateTag != "image@sha256:a" || info.WorkspaceGB != 10 {
		t.Fatalf("snapshot info %+v", info)
	}
	if err := os.WriteFile(filepath.Join(source, "overlay.asif"), []byte("changed"), 0o600); err != nil {
		t.Fatal(err)
	}
	again, err := runtime.SaveDisks(t.Context(), r, id)
	if err != nil || again.Bytes != info.Bytes {
		t.Fatalf("repeated save: %+v %v", again, err)
	}
	listed, err := runtime.DiskSnapshots()
	if err != nil || len(listed) != 1 || listed[0].ID != id {
		t.Fatalf("listed %+v %v", listed, err)
	}
	if err := runtime.DeleteDisks(t.Context(), id); err != nil {
		t.Fatal(err)
	}
	if listed, _ := runtime.DiskSnapshots(); len(listed) != 0 {
		t.Fatalf("deleted snapshot still listed: %+v", listed)
	}
	// A standalone image's disk is the whole image: no snapshot is saved.
	if err := os.WriteFile(filepath.Join(source, "disk.img"), []byte("whole image"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := runtime.SaveDisks(t.Context(), r, uuid.NewString()); !errors.Is(err, ErrNotArchivable) {
		t.Fatalf("saved a standalone image: %v", err)
	}
	if listed, _ := runtime.DiskSnapshots(); len(listed) != 0 {
		t.Fatalf("a refused save left %+v", listed)
	}
}

// A copy is a restore that stays stopped: the host clones the image the
// snapshot was saved from, even once its template moved on, and puts the
// archived files over the clone's. A host serving another repository's image
// refuses it and keeps nothing.
func TestArchivedDiskSnapshotCopiesOntoTheImageItWasSavedFrom(t *testing.T) {
	size := filesystemSize
	t.Cleanup(func() { filesystemSize = size })
	const gib = uint64(1024 * 1024 * 1024)
	filesystemSize = func(string) (uint64, uint64, error) { return 1024 * gib, 500 * gib, nil }
	const repo = "ghcr.io/tuist/runner"
	saved := repo + "@sha256:" + strings.Repeat("a", 64)
	moved := repo + "@sha256:" + strings.Repeat("b", 64)
	dir := t.TempDir()
	// A fake Tart: the saved image is cached, and a clone records its source
	// and leaves a fresh stacked VM.
	binary := filepath.Join(dir, "tart")
	script := fmt.Sprintf(`#!/bin/sh
case "$1" in
list) printf '[{"Name":"%s","Source":"OCI"}]' ;;
get) echo '{}' ;;
clone) mkdir -p "$TART_HOME/vms/$3" && cd "$TART_HOME/vms/$3" && echo fresh > config.json && echo fresh > nvram.bin && echo '{}' > manifest.json && : > overlay.asif && echo "$2" > source ;;
esac
`, saved)
	if err := os.WriteFile(binary, []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	host := func(name, image string) *TartRuntime {
		r := &TartRuntime{Client: &tart.Client{Binary: binary, HomeDir: filepath.Join(dir, name)}, Templates: NewTemplates(map[string]string{"macos": image})}
		r.rootfs.Store(int64(64 * gib))
		return r
	}
	overlay := strings.Repeat("o", 3<<20)
	source, id := host("source", saved), uuid.NewString()
	snapshot := source.snapshotDirectory(id)
	if err := os.MkdirAll(snapshot, 0o700); err != nil {
		t.Fatal(err)
	}
	for name, content := range map[string]string{"config.json": "saved", "nvram.bin": "n", "manifest.json": "{}", "overlay.asif": overlay,
		snapshotMetadata: fmt.Sprintf(`{"id":%q,"template":"macos","template_tag":%q,"workspace_gb":10}`, id, saved)} {
		if err := os.WriteFile(filepath.Join(snapshot, name), []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
	}

	var mu sync.Mutex
	parts := map[int][]byte{}
	store := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		defer mu.Unlock()
		if r.Method == http.MethodPut {
			n, _ := strconv.Atoi(strings.TrimPrefix(r.URL.Path, "/part/"))
			var body bytes.Buffer
			_, _ = body.ReadFrom(r.Body)
			parts[n] = body.Bytes()
			w.Header().Set("ETag", fmt.Sprintf(`"%d"`, n))
			return
		}
		numbers := []int{}
		for n := range parts {
			numbers = append(numbers, n)
		}
		sort.Ints(numbers)
		var object []byte
		for _, n := range numbers {
			object = append(object, parts[n]...)
		}
		w.Header().Set("Content-Length", strconv.Itoa(len(object)))
		_, _ = w.Write(object)
	}))
	defer store.Close()

	res, err := source.ArchiveDisks(t.Context(), protocol.ArchiveDisksArgs{SnapshotID: id, PartSize: 5 << 20, PartURLs: []string{store.URL + "/part/1", store.URL + "/part/2"}})
	if err != nil {
		t.Fatal(err)
	}
	args := protocol.CopyDisksArgs{SnapshotID: id, Template: "macos", TemplateTag: saved, WorkspaceGB: 10, Bytes: int64(len(overlay)),
		FromArchive: &protocol.ArchiveSource{URL: store.URL + "/object", Bytes: res.Bytes, SHA256: res.SHA256}}

	other := host("other-repository", "ghcr.io/evil/runner@sha256:"+strings.Repeat("c", 64))
	if _, err := other.CopyDisks(t.Context(), args); !errors.Is(err, ErrArchiveMismatch) {
		t.Fatalf("copied onto a host serving another repository: %v", err)
	}
	if _, err := os.Stat(other.snapshotDirectory(id)); !os.IsNotExist(err) {
		t.Fatalf("a refused copy left its VM: %v", err)
	}

	newer := host("newer-image", moved)
	info, err := newer.CopyDisks(t.Context(), args)
	if err != nil {
		t.Fatal(err)
	}
	if info.TemplateTag != saved || info.WorkspaceGB != 10 || info.Bytes < int64(len(overlay)) {
		t.Fatalf("copied snapshot %+v", info)
	}
	copied := newer.snapshotDirectory(id)
	if cloned, _ := os.ReadFile(filepath.Join(copied, "source")); strings.TrimSpace(string(cloned)) != saved {
		t.Fatalf("copy cloned %q, not the image the snapshot was saved from", cloned)
	}
	for name, want := range map[string]string{"overlay.asif": overlay, "config.json": "saved"} {
		if got, err := os.ReadFile(filepath.Join(copied, name)); err != nil || string(got) != want {
			t.Fatalf("copied %s differs: %v", name, err)
		}
	}
	if listed, _ := newer.DiskSnapshots(); len(listed) != 1 || listed[0].ID != id {
		t.Fatalf("copy not listed: %+v", listed)
	}
}
