package cachevolumes

import (
	"archive/tar"
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func exportArchive(t *testing.T, entries ...[2]string) *bytes.Buffer {
	t.Helper()
	var buffer bytes.Buffer
	archive := tar.NewWriter(&buffer)
	for _, entry := range entries {
		if err := archive.WriteHeader(&tar.Header{Name: entry[0], Mode: 0644, Size: int64(len(entry[1])), Typeflag: tar.TypeReg}); err != nil {
			t.Fatal(err)
		}
		if _, err := archive.Write([]byte(entry[1])); err != nil {
			t.Fatal(err)
		}
	}
	if err := archive.Close(); err != nil {
		t.Fatal(err)
	}
	return &buffer
}

func TestReceivedExportsKeepOnlyTheExportsOwnEntries(t *testing.T) {
	c, host := newCheckouts(t)
	oid := lfsOID("large file")
	host.lfs = []string{oid}
	dst := c.Incoming("pod")
	err := ReceiveCheckoutExport(exportArchive(t, [2]string{"head", checkoutTestCommit + "\n"}, [2]string{"pack", "PACK"}, [2]string{"lfs/" + oid, "large file"}), dst, nil)
	if err != nil {
		t.Fatal(err)
	}
	task := checkoutTestTask()
	task.Export = dst
	c.Process(context.Background(), task)
	if c.Master(checkoutTestScope, 1) == "" {
		t.Fatal("a streamed export did not build a master")
	}
	if _, err := os.Stat(dst + ".part"); !os.IsNotExist(err) {
		t.Fatal("left the partial export behind")
	}
}

func TestReceivedExportsRefuseAnythingElse(t *testing.T) {
	dir := t.TempDir()
	valid := [][2]string{{"head", checkoutTestCommit}, {"pack", "PACK"}}
	cases := map[string]func() *bytes.Buffer{
		"traversal": func() *bytes.Buffer { return exportArchive(t, append(valid, [2]string{"../escape", "x"})...) },
		"nested lfs": func() *bytes.Buffer {
			return exportArchive(t, append(valid, [2]string{"lfs/a/" + lfsOID("x"), "x"})...)
		},
		"unnamed lfs": func() *bytes.Buffer { return exportArchive(t, append(valid, [2]string{"lfs/object", "x"})...) },
		"duplicate":   func() *bytes.Buffer { return exportArchive(t, append(valid, [2]string{"pack", "again"})...) },
		"oversized head": func() *bytes.Buffer {
			return exportArchive(t, [2]string{"head", strings.Repeat("a", 200)}, [2]string{"pack", "PACK"})
		},
		"no pack": func() *bytes.Buffer { return exportArchive(t, [2]string{"head", checkoutTestCommit}) },
		"truncated": func() *bytes.Buffer {
			b := exportArchive(t, valid...)
			b.Truncate(600)
			return b
		},
		"link": func() *bytes.Buffer {
			var buffer bytes.Buffer
			archive := tar.NewWriter(&buffer)
			_ = archive.WriteHeader(&tar.Header{Name: "pack", Typeflag: tar.TypeSymlink, Linkname: "/etc/passwd"})
			_ = archive.Close()
			return &buffer
		},
	}
	for name, archive := range cases {
		dst := filepath.Join(dir, strings.ReplaceAll(name, " ", "-"))
		if err := ReceiveCheckoutExport(archive(), dst, nil); err == nil {
			t.Fatalf("%s accepted", name)
		}
		for _, path := range []string{dst, dst + ".part"} {
			if _, err := os.Stat(path); !os.IsNotExist(err) {
				t.Fatalf("%s left %s behind", name, path)
			}
		}
	}
	if _, err := os.Stat(filepath.Join(filepath.Dir(dir), "escape")); !os.IsNotExist(err) {
		t.Fatal("wrote outside the export")
	}
}

// fakeExt4Host stands in for mkfs.ext4, cp, losetup and mount.
type fakeExt4Host struct {
	*fakeCheckoutHost
	mapped map[string]bool
}

func newExt4Checkouts(t *testing.T) (*Checkouts, *fakeExt4Host) {
	t.Helper()
	host := &fakeExt4Host{fakeCheckoutHost: &fakeCheckoutHost{}, mapped: map[string]bool{}}
	run := func(ctx context.Context, dir string, env []string, name string, args ...string) ([]byte, error) {
		switch name {
		case "mkfs.ext4":
			host.fakeCheckoutHost.run(ctx, dir, env, name, args...)
			return nil, os.WriteFile(args[len(args)-1], []byte("image"), 0600)
		case "cp":
			if args[0] != "--reflink=always" {
				t.Fatal("byte-copy fallback enabled")
			}
			host.fakeCheckoutHost.run(ctx, dir, env, name, args...)
			data, err := os.ReadFile(args[2])
			if err != nil {
				return nil, err
			}
			return nil, os.WriteFile(args[3], data, 0600)
		case "losetup":
			host.fakeCheckoutHost.run(ctx, dir, env, name, args...)
			switch {
			case args[0] == "--json" && host.mapped[args[3]]:
				return []byte(`{"loopdevices":[{"name":"/dev/loop7"}]}`), nil
			case args[0] == "--json":
				return []byte(`{"loopdevices":[]}`), nil
			case args[0] == "--detach":
				clear(host.mapped)
			default:
				host.mapped[args[len(args)-1]] = true
			}
			return []byte("/dev/loop7\n"), nil
		}
		return host.fakeCheckoutHost.run(ctx, dir, env, name, args...)
	}
	return &Checkouts{Root: t.TempDir(), Run: run, Images: &Ext4CheckoutImages{Run: run}}, host
}

func TestExt4CheckoutBuildsInTheImagesCheckoutDirectory(t *testing.T) {
	c, host := newExt4Checkouts(t)
	task := exportFrom(t, c, "job", checkoutTestCommit, nil)
	task.UID = os.Getuid()
	c.Process(context.Background(), task)
	if c.Master(checkoutTestScope, 1) == "" || filepath.Base(c.Master(checkoutTestScope, 1)) != "master.img" {
		t.Fatal("no ext4 master after a cold build")
	}
	if !host.ran("mkfs.ext4") || !host.ran("losetup", "--find", "--show", "--nooverlap") || !host.ran("mount", "-t", "ext4", "-o", "nodev,nosuid,noatime") || !host.ran("umount") || !host.ran("losetup", "--detach", "/dev/loop7") {
		t.Fatalf("unexpected image lifecycle: %+v", host.commands())
	}
	repo := filepath.Join(c.dir(checkoutTestScope, 1), "next.mnt", "checkout")
	for _, call := range host.commands() {
		if call.name == "git" && call.dir != repo {
			t.Fatalf("git ran in %s, not the image's checkout directory", call.dir)
		}
	}
	if len(host.mapped) != 0 {
		t.Fatal("left the loop device attached")
	}
}

func TestExt4CheckoutDetachFailsWhileTheLoopDeviceLingers(t *testing.T) {
	images := &Ext4CheckoutImages{Run: func(_ context.Context, _ string, _ []string, name string, args ...string) ([]byte, error) {
		if name == "losetup" && args[0] == "--json" {
			return []byte(`{"loopdevices":[{"name":"/dev/loop7"}]}`), nil
		}
		return nil, nil
	}}
	image := filepath.Join(t.TempDir(), "next.img")
	if err := os.WriteFile(image, nil, 0600); err != nil {
		t.Fatal(err)
	}
	if err := images.Detach(context.Background(), image, t.TempDir()); err == nil {
		t.Fatal("detached an image a loop device still holds")
	}
}

func TestExt4CheckoutOwnHandsTheTreeToTheJobsUser(t *testing.T) {
	repo := t.TempDir()
	if err := os.MkdirAll(filepath.Join(repo, ".git", "objects"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("/etc/passwd", filepath.Join(repo, "link")); err != nil {
		t.Fatal(err)
	}
	if err := (&Ext4CheckoutImages{}).Own(context.Background(), repo, os.Getuid()); err != nil {
		t.Fatal(err)
	}
}

func TestLocalCheckoutSlotsAreSeededNeverFormatted(t *testing.T) {
	b, _ := newLocal(t)
	seeded := 0
	b.Seed = func(_ context.Context, slot Slot, dst string) error {
		seeded++
		return os.WriteFile(dst, []byte("master clone"), 0600)
	}
	slot := Slot{Identity: identity(first), PodUID: "p"}
	slot.Kind, slot.Generation = KindCheckout, 1
	if err := b.Attach(context.Background(), slot, t.TempDir()); err != nil {
		t.Fatal(err)
	}
	if data, _ := os.ReadFile(b.image(slot)); seeded != 1 || string(data) != "master clone" {
		t.Fatalf("checkout branch is %q after %d seeds", data, seeded)
	}

	b.Seed = nil
	other := Slot{Identity: identity(first), PodUID: "q"}
	other.ID, other.Kind, other.Generation = "00000000-0000-4000-8000-000000000009", KindCheckout, 1
	if err := b.Attach(context.Background(), other, t.TempDir()); err == nil {
		t.Fatal("a checkout without a seed attached")
	}
	if _, err := os.Stat(b.image(other)); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("a checkout fell back to an empty image")
	}
}

// gnuSparsePack is a tar stream whose "pack" is an old-style GNU sparse file
// declaring size bytes, all of them a hole: a few hundred bytes on the wire.
func gnuSparsePack(t *testing.T, size int64) *bytes.Buffer {
	t.Helper()
	var buffer bytes.Buffer
	head := exportArchive(t, [2]string{"head", checkoutTestCommit})
	buffer.Write(head.Bytes()[:head.Len()-1024])
	block := rawHeader("pack", 'S', 0)
	copy(block[257:], "ustar  \x00")
	// One sparse map entry: no data, then the declared real size.
	copy(block[386:], fmt.Sprintf("%011o\x00%011o\x00", size, 0))
	copy(block[483:], fmt.Sprintf("%011o\x00", size))
	checksum(block)
	buffer.Write(block)
	buffer.Write(make([]byte, 1024))
	return &buffer
}

func TestReceivedExportsRefuseSparseEntries(t *testing.T) {
	reader := tar.NewReader(gnuSparsePack(t, 1<<30))
	if _, err := reader.Next(); err != nil {
		t.Fatal(err)
	}
	if pack, err := reader.Next(); err != nil || pack.Typeflag != tar.TypeGNUSparse || pack.Size != 1<<30 {
		t.Fatalf("not a GNU sparse file: %+v %v", pack, err)
	}
	dst := filepath.Join(t.TempDir(), "export")
	err := ReceiveCheckoutExport(gnuSparsePack(t, 1<<30), dst, nil)
	if err == nil {
		t.Fatal("a sparse entry was accepted")
	}
	if _, statErr := os.Stat(dst + ".part"); !os.IsNotExist(statErr) {
		t.Fatal("left the partial export behind")
	}
}

func TestReceivedExportsAskForRoomBeforeEachEntry(t *testing.T) {
	var asked []int64
	held := 0
	admit := func(size int64) (func(), error) {
		asked = append(asked, size)
		held++
		return func() { held-- }, nil
	}
	archive := exportArchive(t, [2]string{"head", checkoutTestCommit}, [2]string{"pack", "PACK"})
	if err := ReceiveCheckoutExport(archive, filepath.Join(t.TempDir(), "export"), admit); err != nil {
		t.Fatal(err)
	}
	if len(asked) != 2 || asked[0] != int64(len(checkoutTestCommit)) || asked[1] != 4 || held != 0 {
		t.Fatalf("asked %v, still held %d", asked, held)
	}
	refuse := func(int64) (func(), error) { return nil, ErrCapacity }
	dst := filepath.Join(t.TempDir(), "export")
	if err := ReceiveCheckoutExport(exportArchive(t, [2]string{"head", checkoutTestCommit}, [2]string{"pack", "PACK"}), dst, refuse); !errors.Is(err, ErrCapacity) {
		t.Fatalf("got %v", err)
	}
	if _, err := os.Stat(dst); !os.IsNotExist(err) {
		t.Fatal("kept an export there was no room for")
	}
}

func TestLocalCheckoutClonesNeedRoomForTheWholeWorkspace(t *testing.T) {
	b, _ := newLocal(t)
	b.FreeBytes = func(string) (uint64, error) { return CheckoutCapacity - 1, nil }
	b.Seed = func(_ context.Context, _ Slot, dst string) error { return os.WriteFile(dst, nil, 0600) }
	slot := Slot{Identity: identity(first), PodUID: "p"}
	slot.Kind, slot.Generation = KindCheckout, 1
	if err := b.Attach(context.Background(), slot, t.TempDir()); !errors.Is(err, ErrCapacity) {
		t.Fatalf("a checkout clone was admitted without room to grow: %v", err)
	}
	custom := Slot{Identity: identity(first), PodUID: "q"}
	if err := b.Attach(context.Background(), custom, t.TempDir()); err != nil {
		t.Fatalf("a custom volume needs only the reserve: %v", err)
	}
}

func TestPressureEvictionSkipsMastersWithLiveClones(t *testing.T) {
	c, _ := newCheckouts(t)
	c.Process(context.Background(), exportFrom(t, c, "first", checkoutTestCommit, nil))
	other := exportFrom(t, c, "other", checkoutTestCommit, nil)
	other.Scope = strings.Repeat("b", 64)
	c.Process(context.Background(), other)
	c.InUse = func(scope string) bool { return scope == checkoutTestScope }
	if got := c.Evictable(func(string) (uint64, error) { return 3, nil }); got != 3 {
		t.Fatalf("evictable %d, want only the master without clones", got)
	}
	c.Evict(func() bool { return false })
	if c.Master(checkoutTestScope, 1) == "" || c.Master(other.Scope, 1) != "" {
		t.Fatal("pressure eviction removed a master a job clones")
	}
}

// rawHeader is a ustar header block, which tests need where tar.Writer refuses
// to write what a guest could send.
func rawHeader(name string, typeflag byte, size int64) []byte {
	block := make([]byte, 512)
	copy(block[0:], name)
	copy(block[100:], "0000644\x00")
	copy(block[108:], "0000000\x00")
	copy(block[116:], "0000000\x00")
	copy(block[124:], fmt.Sprintf("%011o\x00", size))
	copy(block[136:], "00000000000\x00")
	block[156] = typeflag
	copy(block[257:], "ustar\x0000")
	checksum(block)
	return block
}

func checksum(block []byte) {
	copy(block[148:], "        ")
	sum := 0
	for _, b := range block {
		sum += int(b)
	}
	copy(block[148:], fmt.Sprintf("%06o\x00 ", sum))
}

func padded(data []byte) []byte {
	return append(data, make([]byte, (512-len(data)%512)%512)...)
}

// paxSparsePack is a tar stream whose "pack" is a PAX 1.0 sparse file: a regular
// file whose GNU.sparse records and 512-byte sparse map declare size bytes, all
// of them a hole. tar.Writer drops GNU.sparse records, so it is written by hand.
func paxSparsePack(t *testing.T, size int64) *bytes.Buffer {
	t.Helper()
	var buffer bytes.Buffer
	head := exportArchive(t, [2]string{"head", checkoutTestCommit})
	buffer.Write(head.Bytes()[:head.Len()-1024])
	var records string
	for _, record := range [][2]string{{"GNU.sparse.major", "1"}, {"GNU.sparse.minor", "0"}, {"GNU.sparse.name", "pack"}, {"GNU.sparse.realsize", fmt.Sprint(size)}} {
		records += paxRecord(record[0], record[1])
	}
	buffer.Write(rawHeader("PaxHeaders/pack", 'x', int64(len(records))))
	buffer.Write(padded([]byte(records)))
	sparseMap := padded([]byte(fmt.Sprintf("1\n%d\n0\n", size)))
	buffer.Write(rawHeader("pack", '0', int64(len(sparseMap))))
	buffer.Write(sparseMap)
	buffer.Write(make([]byte, 1024))
	return &buffer
}

func TestReceivedExportsRefusePAXSparseEntries(t *testing.T) {
	// The reader presents the entry as a regular file of the declared size.
	reader := tar.NewReader(paxSparsePack(t, 1<<30))
	if _, err := reader.Next(); err != nil {
		t.Fatal(err)
	}
	pack, err := reader.Next()
	if err != nil || pack.Typeflag != tar.TypeReg || pack.Size != 1<<30 {
		t.Fatalf("not a sparse regular file: %+v %v", pack, err)
	}
	dst := filepath.Join(t.TempDir(), "export")
	if err := ReceiveCheckoutExport(paxSparsePack(t, 1<<30), dst, nil); err == nil {
		t.Fatal("a PAX sparse entry was accepted")
	}
	if _, err := os.Stat(dst + ".part"); !os.IsNotExist(err) {
		t.Fatal("left the partial export behind")
	}
}

func TestCarriedWriterRefusesBytesTheStreamDidNotCarry(t *testing.T) {
	carried := &countingReader{reader: strings.NewReader("abcd")}
	if _, err := io.ReadAll(carried); err != nil {
		t.Fatal(err)
	}
	var written int64
	var out bytes.Buffer
	writer := &carriedWriter{file: &out, carried: carried, written: &written}
	if _, err := writer.Write([]byte("abc")); err != nil {
		t.Fatal(err)
	}
	if _, err := writer.Write([]byte("de")); err == nil {
		t.Fatal("wrote more than the stream carried")
	}
	if out.String() != "abc" || written != 3 {
		t.Fatalf("wrote %q (%d)", out.String(), written)
	}
}

func TestLocalCheckoutClonesNeverEvictForTheirRoom(t *testing.T) {
	b, _ := newLocal(t)
	b.MinFreeBytes = 10
	b.FreeBytes = func(string) (uint64, error) { return CheckoutCapacity - 1, nil }
	b.Seed = func(_ context.Context, _ Slot, dst string) error { return os.WriteFile(dst, nil, 0600) }
	master := filepath.Join(b.Root, "masters", strings.Repeat("c", 64), "00000000000000000001-"+strings.Repeat("d", 64)+".img")
	if err := os.MkdirAll(filepath.Dir(master), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(master, []byte("custom master"), 0600); err != nil {
		t.Fatal(err)
	}
	reclaimed := false
	b.Reclaim = func(context.Context, uint64) error { reclaimed = true; return nil }
	slot := Slot{Identity: identity(first), PodUID: "p"}
	slot.Kind, slot.Generation = KindCheckout, 1
	if err := b.Attach(context.Background(), slot, t.TempDir()); !errors.Is(err, ErrCapacity) {
		t.Fatalf("got %v", err)
	}
	if _, err := os.Stat(master); err != nil || reclaimed {
		t.Fatal("a checkout clone evicted for its room")
	}
}

func TestDiscardWaitingDropsTheExportsOfBuildsWithoutRoom(t *testing.T) {
	c, _ := newCheckouts(t)
	c.ready, c.queue = true, make(chan string, checkoutQueue)
	c.Room = func(context.Context, uint64) (func(), error) { return nil, ErrCapacity }
	task := exportFrom(t, c, "job", checkoutTestCommit, nil)
	c.Process(context.Background(), task)
	if _, err := os.Stat(task.Export); err != nil {
		t.Fatal("the waiting build lost its export")
	}
	if dropped := c.DiscardWaiting(); dropped != 1 {
		t.Fatalf("dropped %d", dropped)
	}
	if _, err := os.Stat(task.Export); !os.IsNotExist(err) {
		t.Fatal("kept a discarded export")
	}
	c.Maintain()
	if c.Queued() != 0 {
		t.Fatal("a discarded build was retried")
	}
}

// paxRecord is "<length> <key>=<value>\n", where length counts itself.
func paxRecord(key, value string) string {
	line := " " + key + "=" + value + "\n"
	length := len(line) + 1
	for len(fmt.Sprint(length))+len(line) != length {
		length = len(fmt.Sprint(length)) + len(line)
	}
	return fmt.Sprint(length) + line
}
