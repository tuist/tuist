package cachevolumes

import (
	"archive/tar"
	"bytes"
	"context"
	"errors"
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
	err := ReceiveCheckoutExport(exportArchive(t, [2]string{"head", checkoutTestCommit + "\n"}, [2]string{"pack", "PACK"}, [2]string{"lfs/" + oid, "large file"}), dst)
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
		if err := ReceiveCheckoutExport(archive(), dst); err == nil {
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
