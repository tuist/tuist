package cachevolumes

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"time"

	"golang.org/x/sys/unix"
)

// APFSImages exposes only private images through a per-VM virtio-fs share.
// The guest attaches APFS locally: virtio-fs itself cannot preserve cache xattrs.
// Seal/Delete require BOTH API pod absence and proof that its Tart VM stopped.
// Built-in Tuist/CAS images remain owned by the existing VolumeManager.
type APFSImages struct {
	LocalImages
	Create  func(context.Context, string, int64) error
	Reserve func(context.Context, Slot) (func(bool), error)
	Verify  func(string) error
	Detach  func(string) error
	// Grow extends a private copy's image to the given capacity before the guest
	// sees it, never shrinking it and never attaching its filesystem. The guest
	// grows the APFS container. Nil leaves copies at their saved size.
	Grow func(context.Context, string, int64) error
}

func (b *APFSImages) Init() error {
	for _, dir := range []string{"images", "masters"} {
		if err := os.MkdirAll(filepath.Join(b.Root, dir), 0700); err != nil {
			return err
		}
	}
	b.Clone = func(ctx context.Context, src, dst string) error {
		_, err := b.commandContext(ctx, "cp", "-c", src, dst)
		return err
	}
	return nil
}

func (b *APFSImages) Attach(ctx context.Context, slot Slot, path string) (err error) {
	source := "empty"
	if slot.BaseGeneration > 0 {
		source = "unknown"
	}
	start := time.Now()
	defer func() {
		if b.Observe != nil {
			b.Observe(Observation{Operation: "attach", Source: source, Duration: time.Since(start), Err: err})
		}
	}()
	if err = ctx.Err(); err != nil {
		return err
	}
	image := b.image(slot)
	if _, statErr := os.Lstat(image); os.IsNotExist(statErr) {
		// A job never downloads: it clones a local copy or starts empty, so one
		// image of room is enough either way.
		minimum := uint64(b.volumeBytes(slot))
		if slot.Kind == KindCheckout {
			minimum = CheckoutGrowthBytes
		}
		if err = b.operation("admission", "none", func() error { return b.reserveBytes(ctx, minimum) }); err != nil {
			return err
		}
		if b.Reserve != nil {
			finish, reserveErr := b.Reserve(ctx, slot)
			if reserveErr != nil {
				return reserveErr
			}
			defer func() { finish(err == nil) }()
		}
		tmp := image + ".sparseimage"
		_ = os.Remove(tmp)
		defer os.Remove(tmp)
		_ = os.Remove(image + ".cold")
		cold := slot.BaseGeneration == 0
		if slot.BaseGeneration > 0 {
			if !validHead(slot.Identity) {
				return errors.New("invalid master identity")
			}
			waited := b.Observe.Start("master_wait", "none")
			unlock, lockErr := b.lockContext(ctx, slot.Scope)
			waited(lockErr)
			if lockErr != nil {
				return lockErr
			}
			err = b.cloneLocal(ctx, slot, image, tmp, &source)
			unlock()
			if errors.Is(err, errNoLocalCopy) {
				// A job never waits for a download: it starts empty, the HEAD is fetched
				// in the background, and this branch is withheld from publication unless
				// the server lets it replace the saved version.
				source, cold, err = "cold", true, os.WriteFile(image+".cold", nil, 0600)
			}
			if err != nil {
				return err
			}
			if !cold && b.Grow != nil && slot.VolumeBytes > 0 {
				// A copy that cannot grow stays warm at its saved size.
				_ = b.operation("grow", "image", func() error { return b.Grow(ctx, tmp, slot.VolumeBytes) })
			}
		}
		if cold && slot.Kind == KindCheckout {
			// Never fall back to an empty image: the guest mounts it over its workspace.
			if b.Seed == nil {
				return errors.New("checkout seeding unavailable")
			}
			source = "local"
			if err = b.operation("clone", "local", func() error { return b.Seed(ctx, slot, tmp) }); err != nil {
				return err
			}
		} else if cold {
			if err = b.operation("format", "empty", func() error { return b.Create(ctx, tmp, b.volumeBytes(slot)) }); err != nil {
				return err
			}
		}
		if err = ctx.Err(); err != nil {
			return err
		}
		if err = durableRename(tmp, image); err != nil {
			return err
		}
	} else if statErr != nil {
		return statErr
	}
	if source == "unknown" {
		source = "local"
	}
	if err = ctx.Err(); err != nil {
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
		return sharedImage(image, dir)
	} else if err != nil {
		return err
	}
	return nil
}

// ErrReplaced poisons a branch whose share no longer exposes the branch image:
// whatever the guest wrote went to another file, so sealing the branch would
// publish its untouched clone.
var ErrReplaced = fmt.Errorf("%w: cache share image was replaced", ErrPoisoned)

// sharedImage checks that the share directory still exposes image itself.
func sharedImage(image string, dir *os.File) error {
	var source, destination unix.Stat_t
	if err := unix.Stat(image, &source); err != nil {
		return err
	}
	if err := unix.Fstatat(int(dir.Fd()), "cache.sparseimage", &destination, unix.AT_SYMLINK_NOFOLLOW); err != nil {
		return fmt.Errorf("%w: %v", ErrReplaced, err)
	}
	if source.Dev != destination.Dev || source.Ino != destination.Ino {
		return ErrReplaced
	}
	return nil
}

// shareExposes opens the share directory without following a guest symlink.
func shareExposes(image, path string) error {
	root, err := os.OpenRoot(filepath.Dir(path))
	if err != nil {
		return err
	}
	defer root.Close()
	dir, err := root.Open(filepath.Base(path))
	if err != nil {
		return err
	}
	defer dir.Close()
	return sharedImage(image, dir)
}

// Running guests are the only writers; do not attach their image on the host.
// A detached branch reports the guest's measurement before it is sealed, so
// the server learns the size of a branch it will not save.
func (b *APFSImages) Measure(slot Slot, path string) (int64, int64, error) {
	data, err := os.ReadFile(b.image(slot) + ".metrics")
	if os.IsNotExist(err) && APFSMarker(path, ".detached", slot.ID) {
		usage, usageErr := APFSUsage(path, slot.ID, b.maxVolumeBytes())
		return usage.Used, usage.Capacity, usageErr
	}
	if err != nil {
		return 0, 0, err
	}
	var values [2]int64
	if err = json.Unmarshal(data, &values); err != nil {
		return 0, 0, err
	}
	return values[0], values[1], nil
}

func (b *APFSImages) Seal(slot Slot, path string) (err error) {
	done := b.Observe.Start("publish", "none")
	defer func() { done(err) }()
	image := b.image(slot)
	if !APFSMarker(path, ".detached", slot.ID) {
		return ErrPoisoned
	}
	if b.Cold(slot) && !slot.PublishCold {
		return ErrWithheld
	}
	if err := shareExposes(image, path); err != nil {
		return err
	}
	usage, err := APFSUsage(path, slot.ID, b.maxVolumeBytes())
	if err != nil {
		return fmt.Errorf("%w: %v", ErrPoisoned, err)
	}
	if usage.OutOfSpace() {
		return ErrFull
	}
	if !usage.Changed {
		// A branch cloned from an older generation holds that generation's content.
		if b.MountedGeneration(slot) == 0 {
			b.keepUnchanged(slot, func() error { return b.Verify(image) })
		}
		return ErrUnchanged
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
		if err := b.Verify(image); err != nil {
			return fmt.Errorf("%w: %v", ErrPoisoned, err)
		}
		metrics, _ := json.Marshal([2]int64{usage.Used, usage.Capacity})
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
	for _, suffix := range []string{"", ".sparseimage", ".zst", ".gz", ".checking", ".verified", ".metrics", ".base", ".cold"} {
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

// MountedGeneration is the older generation a branch was cloned from when its
// own base was not on this host, or 0 when it was cloned from its base.
func (b *APFSImages) MountedGeneration(slot Slot) int64 {
	data, err := os.ReadFile(b.image(slot) + ".base")
	if err != nil {
		return 0
	}
	generation, err := strconv.ParseInt(string(data), 10, 64)
	if err != nil || generation <= 0 || generation >= slot.BaseGeneration {
		return 0
	}
	return generation
}

// PrefetchReservation is the Reserve slot ID a prefetch holds while it downloads.
const PrefetchReservation = "prefetch"

// Prefetch restores a master, evicting idle masters for room. It needs room for
// the archive beside the expanded image (Identity.RestoreBytes).
func (b *APFSImages) Prefetch(ctx context.Context, slot Slot) error {
	return b.prefetchWith(ctx, slot, false)
}

// PrefetchSpare restores a master like Prefetch, but only into free space: it
// never evicts a master or reclaims a sharing cache, so a speculative download
// cannot push out masters that jobs on this host still read. Its master of a
// lineage no job used here is speculative until a job clones it.
func (b *APFSImages) PrefetchSpare(ctx context.Context, slot Slot) error {
	return b.prefetchWith(ctx, slot, true)
}

func (b *APFSImages) prefetchWith(ctx context.Context, slot Slot, spare bool) error {
	if slot.BaseGeneration <= 0 || !validHead(slot.Identity) || !scopePattern.MatchString(slot.Scope) {
		return errors.New("invalid prefetch identity")
	}
	reserve := b.reserveBytes
	if spare {
		reserve = b.reserveSpare
	}
	// A download keeps its archive beside the restored image until it expands.
	if err := reserve(ctx, uint64(slot.RestoreBytes(int64(b.SizeGB)*1_000_000_000))); err != nil {
		return err
	}
	if b.Reserve != nil {
		reservation := slot
		reservation.ID = PrefetchReservation
		finish, err := b.Reserve(ctx, reservation)
		if err != nil {
			return err
		}
		defer finish(false)
	}
	return b.prefetch(ctx, slot, spare)
}

var errNoLocalCopy = errors.New("no local copy of the lineage")

// cloneLocal clones the slot's base master, or the newest older master of the
// same lineage, into tmp. The caller holds the scope lock; nothing here touches
// the network.
func (b *APFSImages) cloneLocal(ctx context.Context, slot Slot, image, tmp string, source *string) error {
	master := b.master(slot)
	mounted := slot.BaseGeneration
	if _, err := os.Stat(master); os.IsNotExist(err) {
		older, generation := b.olderMaster(slot)
		if older == "" {
			return errNoLocalCopy
		}
		*source, master, mounted = "older", older, generation
	} else if err != nil {
		return err
	}
	if *source == "unknown" {
		*source = "local"
	}
	if err := b.operation("clone", "local", func() error { return b.cloneContext(ctx, master, tmp) }); err != nil {
		return err
	}
	if mounted != slot.BaseGeneration {
		if err := os.WriteFile(image+".base", []byte(strconv.FormatInt(mounted, 10)), 0600); err != nil {
			return err
		}
	}
	markUsed(master)
	return nil
}

// Cold reports whether a warm identity's branch started empty because no copy
// of its lineage was on this host.
func (b *APFSImages) Cold(slot Slot) bool {
	if slot.BaseGeneration <= 0 {
		return false
	}
	_, err := os.Stat(b.image(slot) + ".cold")
	return err == nil
}
