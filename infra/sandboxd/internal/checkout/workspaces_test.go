package checkout

import (
	"archive/tar"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

const (
	masterCommit = "89abcdef0123456789abcdef0123456789abcdef"
	lfsOID       = "aa11223344556677889900aabbccddeeff00112233445566778899aabbccddee"
)

type treeEntry struct {
	name, data, link string
	dir              bool
}

func treeArchive(t *testing.T, entries []treeEntry) []byte {
	t.Helper()
	var buffer bytes.Buffer
	archive := tar.NewWriter(&buffer)
	for _, entry := range entries {
		header := &tar.Header{Name: entry.name, Mode: 0o644, Typeflag: tar.TypeReg, Size: int64(len(entry.data))}
		switch {
		case entry.dir:
			header = &tar.Header{Name: entry.name + "/", Mode: 0o755, Typeflag: tar.TypeDir}
		case entry.link != "":
			header = &tar.Header{Name: entry.name, Mode: 0o777, Typeflag: tar.TypeSymlink, Linkname: entry.link}
		}
		if err := archive.WriteHeader(header); err != nil {
			t.Fatal(err)
		}
		if header.Typeflag == tar.TypeReg {
			archive.Write([]byte(entry.data))
		}
	}
	if err := archive.Close(); err != nil {
		t.Fatal(err)
	}
	return buffer.Bytes()
}

// A master on a branch whose ref git packed, with an LFS object and a link.
func masterTree(t *testing.T) []byte {
	return treeArchive(t, []treeEntry{
		{name: ".git", dir: true},
		{name: ".git/HEAD", data: "ref: refs/heads/main\n"},
		{name: ".git/packed-refs", data: "# pack-refs with: peeled fully-peeled sorted\n" + masterCommit + " refs/heads/main\n"},
		{name: ".git/lfs/objects/aa/11/" + lfsOID, data: "lfs"},
		{name: "Sources/main.swift", data: "print(1)\n"},
		{name: "README", link: "Sources/main.swift"},
	})
}

// testOwner is a user the test can hand files to.
func testOwner() (int, int) {
	if os.Getuid() == 0 {
		return 1001, 1001
	}
	return os.Getuid(), os.Getgid()
}

func testKey() WorkspaceKey {
	uid, gid := testOwner()
	return WorkspaceKey{Scope: strings.Repeat("ab", 32), Generation: 2, Path: "claude-code/acme/app", Bytes: 1 << 20, UID: uid, GID: gid}
}

// fakeMkfs writes the tree it was given into the image as "path mode uid:gid"
// lines, so a test reads what the image would hold.
func fakeMkfs(_ context.Context, image, root string) error {
	var lines []string
	err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
		if err != nil || path == root {
			return err
		}
		info, err := os.Lstat(path)
		if err != nil {
			return err
		}
		stat := info.Sys().(*syscall.Stat_t)
		rel, _ := filepath.Rel(root, path)
		lines = append(lines, fmt.Sprintf("%s %v %d:%d", rel, info.Mode().Type(), stat.Uid, stat.Gid))
		return nil
	})
	if err != nil {
		return err
	}
	sort.Strings(lines)
	file, err := os.OpenFile(image, os.O_WRONLY, 0)
	if err != nil {
		return err
	}
	defer file.Close()
	_, err = file.WriteAt([]byte(strings.Join(lines, "\n")), 0)
	return err
}

func newWorkspaces(t *testing.T) *Workspaces {
	t.Helper()
	w := &Workspaces{
		Dir: t.TempDir(), MaxBytes: 1 << 30, TTL: time.Hour, Mkfs: fakeMkfs,
		FreeBytes: func(string) (int64, error) { return 1 << 50, nil },
	}
	if err := w.Clean(); err != nil {
		t.Fatal(err)
	}
	return w
}

func awaitImage(t *testing.T, w *Workspaces, k WorkspaceKey) string {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		w.mu.Lock()
		building := w.building[k.name()]
		w.mu.Unlock()
		if image, ok := w.Lookup(k); ok && !building {
			return image
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("no prepared workspace")
	return ""
}

func TestASeedsTreeBecomesAPreparedWorkspaceOwnedByTheRunner(t *testing.T) {
	w := newWorkspaces(t)
	k := testKey()
	agent := &fakeAgent{tree: masterTree(t)}
	path := serveRecording(t, agent, Limits{}, func() Recording { return w.Recorder(k) })

	response, rest := ask(t, path, `{"op":"seed"}`, nil)
	if !response.OK || !bytes.Equal(rest, agent.tree) {
		t.Fatalf("the guest's seed changed: %+v, %d bytes", response, len(rest))
	}
	image := awaitImage(t, w, k)
	data, err := os.ReadFile(image)
	if err != nil {
		t.Fatal(err)
	}
	listing := string(bytes.TrimRight(data, "\x00"))
	owner := fmt.Sprintf("%d:%d", k.UID, k.GID)
	for _, want := range []string{
		"claude-code d--------- " + owner,
		"claude-code/acme d--------- " + owner,
		"claude-code/acme/app d--------- " + owner,
		"claude-code/acme/app/Sources/main.swift ---------- " + owner,
		"claude-code/acme/app/README L--------- " + owner,
		"claude-code/acme/app/" + protocol.CheckoutPreparedFile + " ---------- " + owner,
	} {
		if !strings.Contains(listing, want+"\n") && !strings.HasSuffix(listing, want) {
			t.Errorf("image lacks %q:\n%s", want, listing)
		}
	}
	if entries, _ := os.ReadDir(w.Dir); len(entries) != 2 {
		t.Errorf("the build left files behind: %v", entries)
	}
}

func TestThePreparedStateNamesTheMastersCommitAndLFSObjects(t *testing.T) {
	w := newWorkspaces(t)
	k := testKey()
	var marker []byte
	w.Mkfs = func(_ context.Context, _, root string) error {
		var err error
		marker, err = os.ReadFile(filepath.Join(root, k.Path, protocol.CheckoutPreparedFile))
		return err
	}
	recording := w.Recorder(k)
	recording.Write(masterTree(t))
	recording.Finish(true)
	awaitImage(t, w, k)

	var state preparedState
	if err := json.Unmarshal(marker, &state); err != nil {
		t.Fatal(err)
	}
	if state.Base != masterCommit || len(state.LFS) != 1 || state.LFS[0] != lfsOID {
		t.Fatalf("state = %+v", state)
	}
}

func TestAnInterruptedOrUnfinishedTreePreparesNothing(t *testing.T) {
	for name, finish := range map[string]func(Recording, []byte){
		"seed failed":       func(r Recording, tree []byte) { r.Write(tree); r.Finish(false) },
		"no end of archive": func(r Recording, tree []byte) { r.Write(tree[:len(tree)-1024]); r.Finish(true) },
	} {
		t.Run(name, func(t *testing.T) {
			w := newWorkspaces(t)
			k := testKey()
			finish(w.Recorder(k), masterTree(t))
			deadline := time.Now().Add(2 * time.Second)
			for time.Now().Before(deadline) {
				w.mu.Lock()
				building := w.building[k.name()]
				w.mu.Unlock()
				if !building {
					break
				}
				time.Sleep(10 * time.Millisecond)
			}
			if _, ok := w.Lookup(k); ok {
				t.Fatal("prepared a workspace from an incomplete tree")
			}
			if entries, _ := os.ReadDir(w.Dir); len(entries) != 0 {
				t.Errorf("left files behind: %v", entries)
			}
		})
	}
}

func TestAPreparedWorkspaceIsUsedOnlyWithinItsTTLAndForItsExactKey(t *testing.T) {
	w := newWorkspaces(t)
	now := time.Now()
	w.Now = func() time.Time { return now }
	k := testKey()
	recording := w.Recorder(k)
	recording.Write(masterTree(t))
	recording.Finish(true)
	awaitImage(t, w, k)

	if w.Recorder(k) != nil {
		t.Error("recorded again while the image is fresh")
	}
	for _, other := range []func(*WorkspaceKey){
		func(k *WorkspaceKey) { k.Generation++ },
		func(k *WorkspaceKey) { k.Bytes *= 2 },
		func(k *WorkspaceKey) { k.Path = "claude-code/acme/other" },
		func(k *WorkspaceKey) { k.UID++ },
	} {
		changed := k
		other(&changed)
		if _, ok := w.Lookup(changed); ok {
			t.Errorf("used the image for %+v", changed)
		}
	}

	now = now.Add(time.Hour)
	if _, ok := w.Lookup(k); ok {
		t.Fatal("used an image past its TTL")
	}
	if entries, _ := os.ReadDir(w.Dir); len(entries) != 0 {
		t.Errorf("an expired image stayed: %v", entries)
	}
	if recording := w.Recorder(k); recording == nil {
		t.Error("an expired image is not rebuilt")
	} else {
		recording.Finish(false)
	}
}

func TestBuildsEvictTheOldestImagesBeyondTheBound(t *testing.T) {
	w := newWorkspaces(t)
	now := time.Now()
	w.Now = func() time.Time { return now }
	w.Mkfs = func(_ context.Context, image, _ string) error {
		return os.WriteFile(image, bytes.Repeat([]byte{1}, 256<<10), 0o600)
	}
	keys := []WorkspaceKey{testKey(), testKey(), testKey()}
	keys[1].Scope = strings.Repeat("cd", 32)
	keys[2].Scope = strings.Repeat("ef", 32)
	w.MaxBytes = 600 << 10
	for _, k := range keys {
		now = now.Add(time.Minute)
		recording := w.Recorder(k)
		recording.Write(masterTree(t))
		recording.Finish(true)
		awaitImage(t, w, k)
	}
	if _, ok := w.Lookup(keys[0]); ok {
		t.Error("the oldest image stayed past the bound")
	}
	for _, k := range keys[1:] {
		if _, ok := w.Lookup(k); !ok {
			t.Errorf("evicted a newer image %s", k.Scope[:4])
		}
	}
}

func TestNoRecordingWithoutRoomOrForAnInvalidKey(t *testing.T) {
	w := newWorkspaces(t)
	w.FreeBytes = func(string) (int64, error) { return 4*w.MaxBytes + minFreeBytes - 1, nil }
	if w.Recorder(testKey()) != nil {
		t.Error("recorded without room for the build")
	}
	w.FreeBytes = nil
	invalid := testKey()
	invalid.Path = "../escape"
	if w.Recorder(invalid) != nil {
		t.Error("recorded for a path outside the workspace")
	}
}

func TestExpireRemovesImagesNobodyLookedUpPastTheirTTL(t *testing.T) {
	w := newWorkspaces(t)
	now := time.Now()
	w.Now = func() time.Time { return now }
	k := testKey()
	recording := w.Recorder(k)
	recording.Write(masterTree(t))
	recording.Finish(true)
	awaitImage(t, w, k)

	now = now.Add(time.Hour - time.Second)
	w.Expire()
	if entries, _ := os.ReadDir(w.Dir); len(entries) != 2 {
		t.Fatalf("expired a fresh image: %v", entries)
	}
	now = now.Add(time.Second)
	w.Expire()
	if entries, _ := os.ReadDir(w.Dir); len(entries) != 0 {
		t.Fatalf("an image past its TTL stayed: %v", entries)
	}
}
