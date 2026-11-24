//go:build linux

package guest

import (
	"encoding/binary"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"os"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"golang.org/x/sys/unix"
)

// EnsureCache mounts the cache drive at mount and binds each `~/` path its
// manifest lists under owner's home, owned by owner. It does nothing when the
// drive is absent, already mounted, or holds no ext4 filesystem (the blank
// placeholder a template snapshot carries), and it never fails: a cache only
// saves work, so problems are logged and the sandbox starts without it.
//
// The flush comes first because a template restore may still hold the
// placeholder's blocks for the clone sandboxd substituted under the device.
func EnsureCache(log *slog.Logger, dev, mount, owner string) {
	started := time.Now()
	if _, err := os.Stat(dev); err != nil {
		return
	}
	if mounted, err := IsMountPoint(mount); err != nil || mounted {
		return
	}
	log = log.With("device", dev, "mount", mount)
	if err := flushBuffers(dev); err != nil {
		log.Warn("cache drive not mounted", "error", err)
		return
	}
	if ok, err := isExt4(dev); err != nil || !ok {
		if err != nil {
			log.Warn("cache drive not mounted", "error", err)
		}
		return
	}
	account, err := user.Lookup(owner)
	if err != nil {
		log.Warn("cache drive not mounted", "error", err)
		return
	}
	uid, _ := strconv.Atoi(account.Uid)
	gid, _ := strconv.Atoi(account.Gid)
	if err := os.MkdirAll(mount, 0o755); err != nil {
		log.Warn("cache drive not mounted", "error", err)
		return
	}
	if err := unix.Mount(dev, mount, "ext4", unix.MS_NOATIME, ""); err != nil {
		log.Warn("cache drive not mounted", "error", err)
		return
	}
	raw, err := os.ReadFile(filepath.Join(mount, cacheManifest))
	if err != nil {
		log.Warn("cache drive has no path manifest", "error", err)
		return
	}
	bound := 0
	for _, b := range CacheBinds(raw, account.HomeDir) {
		if err := bindCache(filepath.Join(mount, b.Source), b.Target, account.HomeDir, uid, gid); err != nil {
			log.Warn("cache path not bound", "path", b.Spelling, "error", err)
			continue
		}
		bound++
	}
	log.Info("cache drive mounted", "paths", bound, "owner", owner, "duration", time.Since(started))
}

// BindCheckoutCache binds each checkout-relative path of the mounted cache's
// manifest into checkout, owned by uid and gid, so a session sees a CI job's
// `server/deps` where the job had it. A path the checkout already holds
// something at (a repository snapshot's own deps, a file) keeps it, and one
// already bound is left alone, so a resumed or rebooted sandbox can run it
// again. The worker calls it before the session's processes start; like
// EnsureCache it never fails and returns how many paths are bound.
func BindCheckoutCache(log *slog.Logger, mount, checkout string, uid, gid int) int {
	if mounted, err := IsMountPoint(mount); err != nil || !mounted {
		return 0
	}
	// Without a cache drive there is nothing to say; with one, every outcome
	// is logged, so a session that got a cache shows why it bound nothing.
	if info, err := os.Lstat(checkout); err != nil || !info.IsDir() {
		log.Info("cache not bound into checkout", "checkout", checkout, "reason", "no checkout")
		return 0
	}
	raw, err := os.ReadFile(filepath.Join(mount, cacheManifest))
	if err != nil {
		log.Info("cache not bound into checkout", "checkout", checkout, "reason", "no path manifest")
		return 0
	}
	binds := CheckoutCacheBinds(raw, checkout)
	if len(binds) == 0 {
		log.Info("cache not bound into checkout", "checkout", checkout, "reason", "no checkout-relative paths")
		return 0
	}
	started := time.Now()
	bound, kept := 0, 0
	for _, b := range binds {
		free, err := emptyTarget(b.Target)
		switch {
		case err != nil:
			log.Warn("cache path not bound", "path", b.Spelling, "error", err)
			continue
		case !free:
			kept++
			continue
		}
		if err := bindCache(filepath.Join(mount, b.Source), b.Target, checkout, uid, gid); err != nil {
			log.Warn("cache path not bound", "path", b.Spelling, "error", err)
			continue
		}
		bound++
	}
	log.Info("cache bound into checkout", "checkout", checkout, "paths", bound, "kept", kept, "duration", time.Since(started))
	return bound
}

// emptyTarget reports whether a bind may go at target: nothing there, or an
// empty directory that is not a mount point yet.
func emptyTarget(target string) (bool, error) {
	info, err := os.Lstat(target)
	if errors.Is(err, fs.ErrNotExist) {
		return true, nil
	}
	if err != nil || !info.IsDir() {
		return false, err
	}
	if mounted, err := IsMountPoint(target); err != nil || mounted {
		return false, err
	}
	entries, err := os.ReadDir(target)
	return len(entries) == 0, err
}

// bindCache hands source to uid and gid and binds it at target, creating the
// missing directories between home and target as theirs too.
func bindCache(source, target, home string, uid, gid int) error {
	info, err := os.Lstat(source)
	if err != nil {
		return err
	}
	if !info.IsDir() {
		return fmt.Errorf("%s is not a directory", source)
	}
	if err := mkdirOwned(home, target, uid, gid); err != nil {
		return err
	}
	if err := chownTree(source, uid, gid); err != nil {
		return err
	}
	if err := unix.Mount(source, target, "", unix.MS_BIND, ""); err != nil {
		return fmt.Errorf("bind %s on %s: %w", source, target, err)
	}
	return nil
}

// mkdirOwned creates target and its missing parents below home, owned by uid
// and gid. An existing component that is a symlink is refused, so a link left
// in home cannot redirect the bind.
func mkdirOwned(home, target string, uid, gid int) error {
	rel, err := filepath.Rel(home, target)
	if err != nil || rel == "." || strings.HasPrefix(rel, "..") {
		return fmt.Errorf("%s is not under %s", target, home)
	}
	dir := home
	for _, part := range strings.Split(rel, string(filepath.Separator)) {
		dir = filepath.Join(dir, part)
		info, err := os.Lstat(dir)
		switch {
		case err == nil && info.IsDir():
			continue
		case err == nil:
			return fmt.Errorf("%s exists and is not a directory", dir)
		case !errors.Is(err, fs.ErrNotExist):
			return err
		}
		if err := os.Mkdir(dir, 0o755); err != nil {
			return err
		}
		if err := os.Lchown(dir, uid, gid); err != nil {
			return err
		}
	}
	return nil
}

// chownTree gives every entry under root to uid and gid, skipping those that
// already belong to them: a cold reboot remounts a tree it already handed
// over.
func chownTree(root string, uid, gid int) error {
	return filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		var st unix.Stat_t
		if err := unix.Lstat(path, &st); err != nil {
			return err
		}
		if int(st.Uid) == uid && int(st.Gid) == gid {
			return nil
		}
		return os.Lchown(path, uid, gid)
	})
}

// isExt4 reports whether dev starts with an ext2/3/4 superblock (magic 0xEF53
// at byte 1080). The blank placeholder reads as zeros.
func isExt4(dev string) (bool, error) {
	f, err := os.Open(dev)
	if err != nil {
		return false, err
	}
	defer f.Close()
	var magic [2]byte
	if _, err := f.ReadAt(magic[:], 1024+56); err != nil {
		return false, fmt.Errorf("read superblock of %s: %w", dev, err)
	}
	return binary.LittleEndian.Uint16(magic[:]) == 0xEF53, nil
}
