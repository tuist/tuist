package cachevolumes

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"golang.org/x/sys/unix"
)

// APFSImages exposes only private images through a per-VM virtio-fs share.
// The guest attaches APFS locally: virtio-fs itself cannot preserve cache xattrs.
// Seal/Delete require BOTH API pod absence and proof that its Tart VM stopped.
// Built-in Tuist/CAS images remain owned by the existing VolumeManager.
type APFSImages struct {
	LocalImages
	Create func(string, int64) error
	Guard  func() func()
	Verify func(string) (int64, int64, error)
	Detach func(string) error
}

func (b *APFSImages) Init() error {
	for _, dir := range []string{"images", "masters"} {
		if err := os.MkdirAll(filepath.Join(b.Root, dir), 0700); err != nil {
			return err
		}
	}
	b.Clone = func(src, dst string) error { _, err := b.command("cp", "-c", src, dst); return err }
	return nil
}

func (b *APFSImages) Attach(slot Slot, path string) error {
	if b.Guard != nil {
		release := b.Guard()
		defer release()
	}
	image := b.image(slot)
	if _, err := os.Lstat(image); os.IsNotExist(err) {
		if err := b.reserve(); err != nil {
			return err
		}
		tmp := image + ".sparseimage"
		_ = os.Remove(tmp)
		if slot.BaseGeneration > 0 {
			unlock := b.lock(slot.Scope)
			defer unlock()
			master := b.master(slot)
			if _, err = os.Stat(master); os.IsNotExist(err) {
				if err = os.MkdirAll(filepath.Dir(master), 0700); err != nil {
					return err
				}
				download := master + ".tmp"
				_ = os.Remove(download)
				if err = b.Transfer.Download(slot, download); err != nil {
					return err
				}
				if err = durableRename(download, master); err != nil {
					return err
				}
				if err = b.recordMaster(slot, master); err != nil {
					return err
				}
			} else if err != nil {
				return err
			}
			if err = b.clone(master, tmp); err != nil {
				return err
			}
			_ = os.Chtimes(master, time.Now(), time.Now())
		} else if err = b.Create(tmp, int64(b.SizeGB)*1_000_000_000); err != nil {
			return err
		}
		if err = durableRename(tmp, image); err != nil {
			return err
		}
	} else if err != nil {
		return err
	}
	// A hard link exposes this branch's inode, never its host-only pathname.
	// Linkat pins the destination directory, so guest symlink replacement cannot
	// redirect a privileged operation outside its own share. Never overwrite it.
	root, err := os.OpenRoot(filepath.Dir(path))
	if err != nil {
		return err
	}
	defer root.Close()
	if err = root.Chmod(filepath.Base(path), 0777); err != nil {
		return err
	}
	dir, err := root.Open(filepath.Base(path))
	if err != nil {
		return err
	}
	defer dir.Close()
	if err = os.Chmod(image, 0666); err != nil {
		return err
	}
	err = unix.Linkat(unix.AT_FDCWD, image, int(dir.Fd()), "cache.sparseimage", 0)
	if errors.Is(err, unix.EEXIST) {
		var source, destination unix.Stat_t
		if err = unix.Stat(image, &source); err != nil {
			return err
		}
		if err = unix.Fstatat(int(dir.Fd()), "cache.sparseimage", &destination, unix.AT_SYMLINK_NOFOLLOW); err != nil {
			return err
		}
		if source.Dev != destination.Dev || source.Ino != destination.Ino {
			return errors.New("cache share image was replaced")
		}
	} else if err != nil {
		return err
	}
	return nil
}

// Running guests are the only writers; do not attach their image on the host.
func (b *APFSImages) Measure(slot Slot, _ string) (int64, int64, error) {
	data, err := os.ReadFile(b.image(slot) + ".metrics")
	if err != nil {
		return 0, 0, err
	}
	var values [2]int64
	if err = json.Unmarshal(data, &values); err != nil {
		return 0, 0, err
	}
	return values[0], values[1], nil
}

func (b *APFSImages) Seal(slot Slot, path string) error {
	image := b.image(slot)
	if !APFSMarker(path, ".detached", slot.ID) {
		return ErrPoisoned
	}
	if _, err := os.Stat(image + ".checking"); err == nil {
		return ErrPoisoned
	} else if !os.IsNotExist(err) {
		return err
	}
	if _, err := os.Stat(image + ".verified"); os.IsNotExist(err) {
		if err = os.WriteFile(image+".checking", nil, 0600); err != nil {
			return err
		}
		if err = syncFile(image + ".checking"); err != nil {
			return err
		}
		if err = syncFile(filepath.Dir(image)); err != nil {
			return err
		}
		used, capacity, err := b.Verify(image)
		if err != nil {
			return fmt.Errorf("%w: %v", ErrPoisoned, err)
		}
		metrics, _ := json.Marshal([2]int64{used, capacity})
		if err = os.WriteFile(image+".metrics", metrics, 0600); err != nil {
			return err
		}
		if err = durableRename(image+".checking", image+".verified"); err != nil {
			return err
		}
	} else if err != nil {
		return err
	}
	return b.publish(slot)
}

func APFSMarker(path, name, id string) bool {
	parent, err := os.OpenRoot(filepath.Dir(path))
	if err != nil {
		return false
	}
	defer parent.Close()
	root, err := parent.OpenRoot(filepath.Base(path))
	if err != nil {
		return false
	}
	defer root.Close()
	f, err := root.OpenFile(name, os.O_RDONLY|unix.O_NONBLOCK, 0)
	if err != nil {
		return false
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil || !info.Mode().IsRegular() {
		return false
	}
	data := make([]byte, len(id)+1)
	n, _ := f.Read(data)
	return string(data[:n]) == id
}

func (b *APFSImages) Delete(slot Slot, path string) error {
	if b.Detach != nil {
		if err := b.Detach(b.image(slot)); err != nil {
			return err
		}
	}
	for _, suffix := range []string{"", ".sparseimage", ".gz", ".checking", ".verified", ".metrics"} {
		if err := os.Remove(b.image(slot) + suffix); err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	root, err := os.OpenRoot(filepath.Dir(path))
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	defer root.Close()
	return root.RemoveAll(filepath.Base(path))
}
func (b *APFSImages) Keep(slot Slot, path string) error { return b.Delete(slot, path) }
