//go:build linux

package guest

import (
	"log/slog"
	"os"
	"path/filepath"
	"testing"

	"golang.org/x/sys/unix"
)

// TestBindCheckoutCacheEndToEnd runs inside a sandbox, as root, against the
// real cache drive the guest agent mounted at SBX_CACHE_E2E_MOUNT, whose
// manifest maps `server/deps` to a directory holding `mix.lock.cached`
// (sandboxd's validate-checkout-cache.sh).
func TestBindCheckoutCacheEndToEnd(t *testing.T) {
	mount := os.Getenv("SBX_CACHE_E2E_MOUNT")
	if mount == "" || os.Geteuid() != 0 {
		t.Skip("needs root and a mounted cache drive (SBX_CACHE_E2E_MOUNT)")
	}
	const uid, gid = 4242, 4242
	log := slog.New(slog.NewTextHandler(os.Stderr, nil))
	checkout := func(t *testing.T) string {
		dir := filepath.Join(t.TempDir(), "tuist", "tuist")
		if err := os.MkdirAll(filepath.Join(dir, "server"), 0o755); err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = unix.Unmount(filepath.Join(dir, "server", "deps"), unix.MNT_DETACH) })
		return dir
	}
	cached := func(dir string) bool {
		_, err := os.Stat(filepath.Join(dir, "server", "deps", "mix.lock.cached"))
		return err == nil
	}

	t.Run("binds a missing path, owned by the session user, once", func(t *testing.T) {
		dir := checkout(t)
		if n := BindCheckoutCache(log, mount, dir, uid, gid); n != 1 || !cached(dir) {
			t.Fatalf("bound %d, cache visible %v", n, cached(dir))
		}
		deps := filepath.Join(dir, "server", "deps")
		if mounted, err := IsMountPoint(deps); err != nil || !mounted {
			t.Fatalf("server/deps is not a mount point: %v", err)
		}
		var st unix.Stat_t
		if err := unix.Stat(filepath.Join(deps, "mix.lock.cached"), &st); err != nil || st.Uid != uid {
			t.Fatalf("cached file owned by %d: %v", st.Uid, err)
		}
		if n := BindCheckoutCache(log, mount, dir, uid, gid); n != 0 {
			t.Fatalf("a second call bound %d paths again", n)
		}
	})

	t.Run("binds over an empty directory", func(t *testing.T) {
		dir := checkout(t)
		if err := os.Mkdir(filepath.Join(dir, "server", "deps"), 0o755); err != nil {
			t.Fatal(err)
		}
		if n := BindCheckoutCache(log, mount, dir, uid, gid); n != 1 || !cached(dir) {
			t.Fatalf("bound %d over an empty directory", n)
		}
	})

	t.Run("keeps deps the checkout already has", func(t *testing.T) {
		dir := checkout(t)
		own := filepath.Join(dir, "server", "deps", "own")
		if err := os.MkdirAll(own, 0o755); err != nil {
			t.Fatal(err)
		}
		if n := BindCheckoutCache(log, mount, dir, uid, gid); n != 0 || cached(dir) {
			t.Fatalf("bound %d over the checkout's own deps", n)
		}
		if _, err := os.Stat(own); err != nil {
			t.Fatal("the checkout's own deps went away")
		}
	})

	t.Run("refuses a symlinked parent", func(t *testing.T) {
		dir := checkout(t)
		elsewhere := t.TempDir()
		if err := os.Remove(filepath.Join(dir, "server")); err != nil {
			t.Fatal(err)
		}
		if err := os.Symlink(elsewhere, filepath.Join(dir, "server")); err != nil {
			t.Fatal(err)
		}
		if n := BindCheckoutCache(log, mount, dir, uid, gid); n != 0 {
			t.Fatalf("bound %d through a symlink", n)
		}
		if entries, _ := os.ReadDir(elsewhere); len(entries) != 0 {
			t.Fatal("the bind followed the symlink")
		}
	})
}
