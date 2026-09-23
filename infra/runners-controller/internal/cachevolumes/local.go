package cachevolumes

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

var ErrConflict = errors.New("cache generation advanced")

// ImageTransfer is the same upload-before-fast-forward protocol used by macOS.
// URLs and infrastructure credentials never enter the workflow filesystem.
type ImageTransfer interface {
	Download(Slot, string) error
	Publish(Slot, string, string, string) (int64, error)
}

// LocalImages keeps immutable masters and reflinked private ext4 images on a
// dedicated host filesystem. A clone must fail rather than fall back to copying.
type LocalImages struct {
	Root         string
	SizeGB       int
	MinFreeBytes uint64
	Transfer     ImageTransfer
	Run          func(context.Context, string, ...string) ([]byte, error)
	Mount        func(string, string) error
	Unmount      func(string, string) error
	MeasureFS    func(string) (int64, int64, error)
	FreeBytes    func(string) (uint64, error)
	locks        sync.Map
	admission    sync.Mutex
}

func (b *LocalImages) command(name string, args ...string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	run := b.Run
	if run == nil {
		run = func(ctx context.Context, name string, args ...string) ([]byte, error) {
			return exec.CommandContext(ctx, name, args...).CombinedOutput()
		}
	}
	out, err := run(ctx, name, args...)
	if err != nil {
		return nil, fmt.Errorf("%s operation failed: %w", name, err)
	}
	return out, nil
}
func (b *LocalImages) lock(scope string) func() {
	v, _ := b.locks.LoadOrStore(scope, &sync.Mutex{})
	mu := v.(*sync.Mutex)
	mu.Lock()
	return mu.Unlock
}
func (b *LocalImages) image(slot Slot) string { return filepath.Join(b.Root, "images", slot.ID+".img") }
func (b *LocalImages) master(slot Slot) string {
	return filepath.Join(b.Root, "masters", slot.Scope, fmt.Sprintf("%020d-%s.img", slot.BaseGeneration, slot.ContentDigest))
}
func (b *LocalImages) clone(src, dst string) error {
	_, err := b.command("cp", "--reflink=always", "--", src, dst)
	return err
}
func syncFile(path string) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	return f.Sync()
}
func durableRename(src, dst string) error {
	if err := syncFile(src); err != nil {
		return err
	}
	if err := os.Rename(src, dst); err != nil {
		return err
	}
	return syncFile(filepath.Dir(dst))
}
func (b *LocalImages) Probe() error {
	marker := filepath.Join(b.Root, ".backend")
	if data, err := os.ReadFile(marker); err == nil {
		if string(data) != "local-image-v1" {
			return errors.New("unsupported cache backend")
		}
	} else if !os.IsNotExist(err) {
		return err
	} else {
		journals, err := filepath.Glob(filepath.Join(b.Root, "state", "*.json"))
		if err != nil {
			return err
		}
		if len(journals) > 0 {
			return errors.New("refusing legacy cache journals; use a new cache filesystem")
		}
		if err = os.WriteFile(marker, []byte("local-image-v1"), 0600); err != nil {
			return err
		}
		if err = syncFile(marker); err != nil {
			return err
		}
	}
	for _, dir := range []string{"images", "masters"} {
		if err := os.MkdirAll(filepath.Join(b.Root, dir), 0700); err != nil {
			return err
		}
	}
	// Test the actual cache mount, not an assumption about the host's root FS.
	f, err := os.CreateTemp(b.Root, ".reflink-probe-")
	if err != nil {
		return err
	}
	src := f.Name()
	defer os.Remove(src)
	defer os.Remove(src + ".clone")
	if _, err = f.WriteString("reflink"); err != nil {
		f.Close()
		return err
	}
	if err = f.Close(); err != nil {
		return err
	}
	return b.clone(src, src+".clone")
}

// Reflinks share physical extents, so admission uses filesystem free space,
// exactly like the APFS manager, rather than summing logical image sizes.
func (b *LocalImages) reserve() error {
	b.admission.Lock()
	defer b.admission.Unlock()
	if b.FreeBytes == nil {
		return errors.New("missing filesystem admission")
	}
	free, err := b.FreeBytes(b.Root)
	if err != nil {
		return err
	}
	entries, err := filepath.Glob(filepath.Join(b.Root, "masters", "*", "*.img"))
	if err != nil {
		return err
	}
	sort.Slice(entries, func(i, j int) bool {
		a, _ := os.Stat(entries[i])
		c, _ := os.Stat(entries[j])
		return a != nil && c != nil && a.ModTime().Before(c.ModTime())
	})
	for _, path := range entries {
		info, err := os.Stat(path)
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			return err
		}
		if free >= b.MinFreeBytes && time.Since(info.ModTime()) < 7*24*time.Hour {
			continue
		}
		unlock := b.lock(filepath.Base(filepath.Dir(path)))
		err = os.Remove(path)
		_ = os.Remove(path + ".json")
		unlock()
		if err != nil && !os.IsNotExist(err) {
			return err
		}
		free, err = b.FreeBytes(b.Root)
		if err != nil {
			return err
		}
	}
	if free < b.MinFreeBytes {
		return errors.New("cache filesystem reserve exhausted")
	}
	return nil
}
func (b *LocalImages) Attach(slot Slot, path string) error {
	image := b.image(slot)
	if _, err := os.Stat(image); os.IsNotExist(err) {
		if err = b.reserve(); err != nil {
			return err
		}
		tmp := image + ".tmp"
		_ = os.Remove(tmp)
		if slot.BaseGeneration > 0 {
			if !regexp.MustCompile(`^[a-f0-9]{64}$`).MatchString(slot.ContentDigest) {
				return errors.New("invalid master digest")
			}
			unlock := b.lock(slot.Scope)
			master := b.master(slot)
			if _, err = os.Stat(master); os.IsNotExist(err) {
				if err = os.MkdirAll(filepath.Dir(master), 0700); err == nil {
					download := master + ".tmp"
					_ = os.Remove(download)
					err = b.Transfer.Download(slot, download)
					if err == nil {
						err = durableRename(download, master)
						if err == nil {
							err = b.recordMaster(slot, master)
						}
					}
					_ = os.Remove(download)
				}
			}
			if err == nil {
				err = b.clone(master, tmp)
				_ = os.Chtimes(master, time.Now(), time.Now())
			}
			unlock()
		} else {
			var f *os.File
			f, err = os.OpenFile(tmp, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
			if err == nil {
				err = f.Truncate(int64(b.SizeGB) * 1_000_000_000)
				closeErr := f.Close()
				if err == nil {
					err = closeErr
				}
			}
			if err == nil {
				_, err = b.command("mkfs.ext4", "-F", "-m", "0", tmp)
			}
		}
		if err != nil {
			_ = os.Remove(tmp)
			return err
		}
		if err = durableRename(tmp, image); err != nil {
			return err
		}
	} else if err != nil {
		return err
	}
	device, err := b.device(image)
	if err != nil {
		return err
	}
	if device == "" {
		out, e := b.command("losetup", "--find", "--show", "--nooverlap", image)
		if e != nil {
			return e
		}
		device = strings.TrimSpace(string(out))
	}
	if !loopDevice.MatchString(device) {
		return errors.New("invalid loop device")
	}
	if err = b.Mount(device, path); err != nil {
		return err
	}
	return writeMarker(slot, path)
}

var loopDevice = regexp.MustCompile(`^/dev/loop[0-9]+$`)

func (b *LocalImages) device(image string) (string, error) {
	if _, err := os.Stat(image); os.IsNotExist(err) {
		return "", nil
	} else if err != nil {
		return "", err
	}
	// --associated compares the backing inode/device, surviving agent mount
	// namespace changes where the same file has a different path spelling.
	out, err := b.command("losetup", "--json", "--list", "--associated", image, "--output", "NAME")
	if err != nil {
		return "", err
	}
	var list struct {
		Devices []struct {
			Name string `json:"name"`
		} `json:"loopdevices"`
	}
	if err = json.Unmarshal(out, &list); err != nil {
		return "", err
	}
	if len(list.Devices) > 1 {
		return "", errors.New("image has multiple loop mappings")
	}
	if len(list.Devices) == 0 {
		return "", nil
	}
	device := list.Devices[0].Name
	if !loopDevice.MatchString(device) {
		return "", errors.New("invalid loop device")
	}
	return device, nil
}
func writeMarker(slot Slot, path string) error {
	root, err := os.OpenRoot(path)
	if err != nil {
		return err
	}
	defer root.Close()
	if err = root.Remove(".tuist-volume"); err != nil && !os.IsNotExist(err) {
		return err
	}
	f, err := root.OpenFile(".tuist-volume", os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}
	_, err = f.WriteString(slot.ID)
	closeErr := f.Close()
	if err != nil {
		return err
	}
	return closeErr
}
func (b *LocalImages) Measure(_ Slot, path string) (int64, int64, error) { return b.MeasureFS(path) }
func (b *LocalImages) detach(slot Slot, path string) error {
	device, err := b.device(b.image(slot))
	if err != nil {
		return err
	}
	if device == "" {
		return nil
	}
	if err = b.Unmount(device, path); err != nil {
		return err
	}
	_, err = b.command("losetup", "--detach", device)
	if err != nil {
		return err
	}
	// LOOP_CLR_FD may only mark a busy device for deferred destruction. Never
	// compress or delete its image while another mount can still write to it.
	remaining, err := b.device(b.image(slot))
	if err != nil {
		return err
	}
	if remaining != "" {
		return errors.New("loop device still has live references after detach")
	}
	return nil
}
func (b *LocalImages) Seal(slot Slot, path string) error {
	if err := b.detach(slot, path); err != nil {
		return err
	}
	archive := b.image(slot) + ".gz"
	defer os.Remove(archive)
	digest, content, err := compressImage(b.image(slot), archive)
	if err != nil {
		return err
	}
	generation, err := b.Transfer.Publish(slot, archive, digest, content)
	if errors.Is(err, ErrConflict) {
		return nil
	}
	if err != nil {
		return err
	}
	// The server accepted this image. Only now may it become a local master.
	// Generation-named files make a crash between clone/rename harmless and never
	// let a late publisher replace a newer master's bytes.
	slot.BaseGeneration = generation
	slot.ContentDigest = content
	unlock := b.lock(slot.Scope)
	defer unlock()
	master := b.master(slot)
	if err = os.MkdirAll(filepath.Dir(master), 0700); err != nil {
		return err
	}
	tmp := master + ".tmp"
	_ = os.Remove(tmp)
	if err = b.clone(b.image(slot), tmp); err != nil {
		return err
	}
	if err = durableRename(tmp, master); err != nil {
		return err
	}
	return b.recordMaster(slot, master)
}
func (b *LocalImages) Delete(slot Slot, path string) error {
	if err := b.detach(slot, path); err != nil {
		return err
	}
	for _, suffix := range []string{"", ".tmp", ".gz"} {
		if err := os.Remove(b.image(slot) + suffix); err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	return removeMountpoint(path)
}
func removeMountpoint(path string) error {
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return err
	}
	_ = os.Remove(filepath.Dir(path))
	return nil
}

// Keep releases the private branch only after its sealed journal is durable and
// the server has acknowledged publication. The immutable local master is evictable.
func (b *LocalImages) Keep(slot Slot, path string) error {
	if err := b.detach(slot, path); err != nil {
		return err
	}
	if err := os.Remove(b.image(slot)); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}
func (b *LocalImages) recordMaster(slot Slot, master string) error {
	data, err := json.Marshal(slot)
	if err != nil {
		return err
	}
	if err = os.WriteFile(master+".json.tmp", data, 0600); err != nil {
		return err
	}
	return durableRename(master+".json.tmp", master+".json")
}
func (b *LocalImages) Maintain() error {
	validator, ok := b.Transfer.(interface{ IsCurrent(Slot) (bool, error) })
	files, err := filepath.Glob(filepath.Join(b.Root, "masters", "*", "*.img"))
	if err != nil {
		return err
	}
	for _, path := range files {
		unlock := b.lock(filepath.Base(filepath.Dir(path)))
		err = func() error {
			info, err := os.Stat(path)
			if os.IsNotExist(err) {
				return nil
			}
			if err != nil {
				return err
			}
			remove := time.Since(info.ModTime()) >= 7*24*time.Hour
			if !remove && ok {
				data, err := os.ReadFile(path + ".json")
				if os.IsNotExist(err) {
					remove = true
				} else if err != nil {
					return err
				} else {
					var slot Slot
					if err = json.Unmarshal(data, &slot); err != nil {
						return err
					}
					current, err := validator.IsCurrent(slot)
					if err != nil {
						return err
					}
					remove = !current
				}
			}
			if remove {
				if err = os.Remove(path); err != nil {
					return err
				}
				_ = os.Remove(path + ".json")
			}
			return nil
		}()
		unlock()
		if err != nil {
			return err
		}
	}
	return nil
}
