package blobcache

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"strings"
	"sync"
	"testing"
	"time"

	repb "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	"google.golang.org/protobuf/proto"
)

func (f *fakeCAS) putDir(t *testing.T, d *repb.Directory) *repb.Digest {
	t.Helper()
	b, err := proto.Marshal(d)
	if err != nil {
		t.Fatal(err)
	}
	hash, size := f.put(string(b))
	return &repb.Digest{Hash: hash, SizeBytes: size}
}

func (f *fakeCAS) file(name, data string, executable bool) *repb.FileNode {
	hash, size := f.put(data)
	return &repb.FileNode{Name: name, Digest: &repb.Digest{Hash: hash, SizeBytes: size}, IsExecutable: executable}
}

// guestTree asks the host for a directory's image, as the executor does.
func guestTree(t *testing.T, socket string, r Request) Response {
	t.Helper()
	conn, err := net.Dial("unix", socket)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	line, _ := json.Marshal(r)
	conn.Write(append(line, '\n'))
	answer, err := bufio.NewReader(conn).ReadSlice('\n')
	if err != nil {
		t.Fatal(err)
	}
	var response Response
	if err := json.Unmarshal(answer, &response); err != nil {
		t.Fatal(err)
	}
	return response
}

func debugfs(t *testing.T, image, request string) string {
	t.Helper()
	out, err := exec.Command("debugfs", "-R", request, image).Output()
	if err != nil {
		t.Fatalf("debugfs %s: %v", request, err)
	}
	return string(out)
}

func TestRecurringInputTreesAreImagedPerScope(t *testing.T) {
	for _, tool := range []string{"mkfs.ext4", "debugfs"} {
		if _, err := exec.LookPath(tool); err != nil {
			t.Skip(tool + " is not installed")
		}
	}
	c, cas, endpoint := setup(t, 64<<20)
	c.treeMin = 1
	// Larger than streamedBlobBytes, so it comes through the blob cache.
	big := strings.Repeat("0123456789abcdef", 100_000)
	lib := cas.putDir(t, &repb.Directory{Files: []*repb.FileNode{
		cas.file("libstd.so", big, false),
		cas.file("libstd-copy.so", big, false),
	}})
	bin := cas.putDir(t, &repb.Directory{Files: []*repb.FileNode{cas.file("rustc", "#!/bin/sh\n", true)}})
	root := cas.putDir(t, &repb.Directory{
		Files:       []*repb.FileNode{cas.file("README", "hello", false)},
		Directories: []*repb.DirectoryNode{{Name: "bin", Digest: bin}, {Name: "lib", Digest: lib}},
		Symlinks:    []*repb.SymlinkNode{{Name: "current", Target: "lib/libstd.so"}},
	})
	tree := Tree{Hash: root.Hash, Size: root.SizeBytes, Bytes: int64(2*len(big) + 15)}
	a := Scope{Endpoint: endpoint, Instance: "a", Token: "token-a"}

	var mu sync.Mutex
	var attached []string
	attach := func(_ context.Context, image string) (int, error) {
		mu.Lock()
		defer mu.Unlock()
		if len(attached) == 2 {
			return 0, ErrNoDrive
		}
		attached = append(attached, image)
		return len(attached) - 1, nil
	}
	socket, _ := serveWith(t, c, a, attach)

	// One action materializing the directory is no evidence it recurs.
	if r := guestTree(t, socket, Request{Op: "trees", Trees: []Tree{tree}}); !r.OK {
		t.Fatalf("trees: %+v", r)
	}
	time.Sleep(100 * time.Millisecond)
	if r := guestTree(t, socket, Request{Op: "tree", Hash: tree.Hash, Size: tree.Size}); r.OK {
		t.Fatalf("image after one sighting: %+v", r)
	}
	guestTree(t, socket, Request{Op: "trees", Trees: []Tree{tree}})
	var image string
	for deadline := time.Now().Add(10 * time.Second); ; time.Sleep(20 * time.Millisecond) {
		var ok bool
		if image, ok = c.TreeImage(a, tree); ok {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("no image after two sightings")
		}
	}

	r := guestTree(t, socket, Request{Op: "tree", Hash: tree.Hash, Size: tree.Size})
	if !r.OK || r.Drive == nil || *r.Drive != 0 || r.Bytes <= int64(len(big)) {
		t.Fatalf("tree: %+v", r)
	}
	if r := guestTree(t, socket, Request{Op: "tree", Hash: tree.Hash, Size: tree.Size}); !r.OK || *r.Drive != 1 {
		t.Fatalf("second attach: %+v", r)
	}
	if r := guestTree(t, socket, Request{Op: "tree", Hash: tree.Hash, Size: tree.Size}); r.OK || r.Error != ErrNoDrive.Error() {
		t.Fatalf("attach without a free drive: %+v", r)
	}

	if got := debugfs(t, image, "cat /lib/libstd-copy.so"); got != big {
		t.Fatalf("image holds %d bytes for the copied library, want %d", len(got), len(big))
	}
	if got := debugfs(t, image, "cat /README"); got != "hello" {
		t.Fatalf("README: %q", got)
	}
	// Entries belong to the guest's build user; only root can give them away.
	owner := fmt.Sprintf("User:  %d", os.Geteuid())
	if os.Geteuid() == 0 {
		owner = fmt.Sprintf("User:  %d", GuestBuildUID)
	}
	if got := debugfs(t, image, "stat /bin/rustc"); !strings.Contains(got, "Mode:  0755") || !strings.Contains(got, owner) {
		t.Fatalf("executable entry:\n%s", got)
	}
	if got := debugfs(t, image, "stat /README"); !strings.Contains(got, "Mode:  0644") {
		t.Fatalf("plain file entry:\n%s", got)
	}
	if got := debugfs(t, image, "stat /current"); !strings.Contains(got, `Fast link dest: "lib/libstd.so"`) {
		t.Fatalf("symlink entry:\n%s", got)
	}
	if out, err := exec.Command("e2fsck", "-fn", image).CombinedOutput(); err != nil {
		t.Fatalf("e2fsck: %v\n%s", err, out)
	}

	// Another project asking for the same digest gets no image.
	if _, ok := c.TreeImage(Scope{Endpoint: endpoint, Instance: "b", Token: "token-b"}, tree); ok {
		t.Fatal("an image answered for another scope")
	}
}

func TestTreesThatEscapeOrAreSmallGetNoImage(t *testing.T) {
	c, cas, endpoint := setup(t, 64<<20)
	s := Scope{Endpoint: endpoint, Instance: "a", Token: "token-a"}
	ctx := context.Background()
	escaping := cas.putDir(t, &repb.Directory{Symlinks: []*repb.SymlinkNode{{Name: "up", Target: "../outside"}}})
	if _, err := c.makeTree(ctx, s, Tree{Hash: escaping.Hash, Size: escaping.SizeBytes}); err == nil || !strings.Contains(err.Error(), "leaves") {
		t.Fatalf("escaping symlink: %v", err)
	}
	small := cas.putDir(t, &repb.Directory{Files: []*repb.FileNode{cas.file("a", "tiny", false)}})
	if _, err := c.makeTree(ctx, s, Tree{Hash: small.Hash, Size: small.SizeBytes}); err == nil {
		t.Fatal("imaged a directory under the minimum")
	}
	// A guest's byte count is only a hint: under the minimum it starts nothing.
	for range 3 {
		c.NoteTrees(s, []Tree{{Hash: small.Hash, Size: small.SizeBytes, Bytes: 10}})
	}
	c.mu.Lock()
	building := len(c.building)
	c.mu.Unlock()
	if building != 0 {
		t.Fatal("started a build for a small directory")
	}
}
