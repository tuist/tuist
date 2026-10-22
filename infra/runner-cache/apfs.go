package cachevolumes

import (
	"context"
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
	Create  func(context.Context, string, int64) error
	Reserve func(context.Context, Slot) (func(bool), error)
	// Verify checks a detached branch image on an unmounted read-only device and
	// returns the bytes its APFS container holds.
	Verify func(string) (int64, error)
	Detach func(string) error
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
		observed := slot
		observed.MountedGeneration = b.MountedGeneration(slot)
		b.Observe.For(observed).Report("attach", source, start, err)
	}()
	ctx = WithSubject(ctx, SubjectOf(slot))
	if err = ctx.Err(); err != nil {
		return err
	}
	image := b.image(slot)
	_, statErr := os.Lstat(image)
	if os.IsNotExist(statErr) && b.exposed(slot) {
		statErr = nil
	}
	if os.IsNotExist(statErr) {
		// A job never downloads: it clones a local copy or starts empty, so what
		// it is expected to write is enough either way.
		minimum := uint64(b.expectedBytes(slot))
		if slot.Kind == KindCheckout {
			minimum = CheckoutGrowthBytes
		}
		if err = b.operation(slot, "admission", "none", func() error { return b.reserveBytes(ctx, minimum) }); err != nil {
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
			waited := b.Observe.For(slot).Start("master_wait", "none")
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
				_ = b.operation(slot, "grow", "image", func() error { return b.Grow(ctx, tmp, slot.VolumeBytes) })
			}
		}
		if cold && slot.Kind == KindCheckout {
			// Never fall back to an empty image: the guest mounts it over its workspace.
			if b.Seed == nil {
				return errors.New("checkout seeding unavailable")
			}
			source = "local"
			if err = b.operation(slot, "clone", "local", func() error { return b.Seed(ctx, slot, tmp) }); err != nil {
				return err
			}
		} else if cold {
			if err = b.operation(slot, "format", "empty", func() error { return b.Create(ctx, tmp, b.volumeBytes(slot)) }); err != nil {
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
	return b.expose(slot, path)
}

// SharedImageName is a branch image's name in its VM's share.
const SharedImageName = "cache.sparseimage"

// The VM's sandboxed virtio-fs server opens files by inode, which macOS checks
// against the name last looked up: a branch image keeps one name, in the share,
// while its VM runs.
func (b *APFSImages) expose(slot Slot, path string) error {
	image := b.image(slot)
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
	recorded, err := readSharedInode(image)
	if os.IsNotExist(err) {
		if err = os.Chmod(image, 0666); err != nil {
			return err
		}
		if recorded, err = recordSharedInode(image); err != nil {
			return err
		}
	} else if err != nil {
		return err
	}
	if _, err = os.Lstat(image); os.IsNotExist(err) {
		return sharedInode(dir, recorded)
	} else if err != nil {
		return err
	}
	// Linkat pins the destination directory, so guest symlink replacement cannot
	// redirect a privileged operation outside its own share. Never overwrite it.
	err = unix.Linkat(unix.AT_FDCWD, image, int(dir.Fd()), SharedImageName, 0)
	if errors.Is(err, unix.EEXIST) {
		err = sharedInode(dir, recorded)
	}
	if err != nil {
		return err
	}
	if err = dir.Sync(); err != nil {
		return err
	}
	if err = os.Remove(image); err != nil {
		return err
	}
	return syncFile(filepath.Dir(image))
}

// claim gives a stopped VM's branch image its private name back.
func (b *APFSImages) claim(slot Slot, path string) error {
	image := b.image(slot)
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
	if _, err = os.Lstat(image); err == nil {
		// Claimed before, or exposed through a second link.
		return sharedImage(image, dir)
	} else if !os.IsNotExist(err) {
		return err
	}
	recorded, err := readSharedInode(image)
	if os.IsNotExist(err) {
		return fmt.Errorf("%w: branch image missing", ErrReplaced)
	} else if err != nil {
		return err
	}
	if err = sharedInode(dir, recorded); err != nil {
		return err
	}
	if err = unix.Linkat(int(dir.Fd()), SharedImageName, unix.AT_FDCWD, image, 0); err != nil {
		return err
	}
	if err = syncFile(filepath.Dir(image)); err != nil {
		return err
	}
	return sharedImage(image, dir)
}

type inode struct{ Dev, Ino uint64 }

func recordSharedInode(image string) (inode, error) {
	var stat unix.Stat_t
	if err := unix.Lstat(image, &stat); err != nil {
		return inode{}, err
	}
	recorded := inode{uint64(stat.Dev), stat.Ino}
	data, _ := json.Marshal(recorded)
	tmp := image + ".shared.tmp"
	if err := os.WriteFile(tmp, data, 0600); err != nil {
		return inode{}, err
	}
	return recorded, durableRename(tmp, image+".shared")
}

func readSharedInode(image string) (inode, error) {
	var recorded inode
	data, err := os.ReadFile(image + ".shared")
	if err != nil {
		return recorded, err
	}
	return recorded, json.Unmarshal(data, &recorded)
}

// sharedInode checks that the share directory still exposes the recorded image.
func sharedInode(dir *os.File, recorded inode) error {
	var stat unix.Stat_t
	if err := unix.Fstatat(int(dir.Fd()), SharedImageName, &stat, unix.AT_SYMLINK_NOFOLLOW); err != nil {
		return fmt.Errorf("%w: %v", ErrReplaced, err)
	}
	if stat.Mode&unix.S_IFMT != unix.S_IFREG || uint64(stat.Dev) != recorded.Dev || stat.Ino != recorded.Ino {
		return ErrReplaced
	}
	return nil
}

func (b *APFSImages) exposed(slot Slot) bool {
	_, err := os.Lstat(b.image(slot) + ".shared")
	return err == nil
}

// APFSHasBranch reports whether a slot of the store at root has a branch image.
func APFSHasBranch(root string, slot Slot) bool {
	b := &APFSImages{LocalImages: LocalImages{Root: root}}
	_, err := os.Lstat(b.image(slot))
	return err == nil || b.exposed(slot)
}

// APFSBranchFile is the one name of a slot's branch image in the store at root:
// in its share while exposed, else private.
func APFSBranchFile(root string, slot Slot) string {
	b := &APFSImages{LocalImages: LocalImages{Root: root}}
	if _, err := os.Lstat(b.image(slot)); os.IsNotExist(err) && b.exposed(slot) {
		return filepath.Join(root, "pods", slot.PodUID, slot.Scope, SharedImageName)
	}
	return b.image(slot)
}

// ErrPressure withholds a branch that could be written while its cache filesystem
// was nearly out of space: a write that failed on the host may have left the image
// incomplete in a way neither the guest nor a filesystem check notices.
var ErrPressure = fmt.Errorf("%w: cache filesystem ran out of space", ErrWithheld)

// MarkPressure withholds the slot's branch from publication (ErrPressure). A slot
// without a branch image yet has written nothing and is left alone.
func (b *APFSImages) MarkPressure(slot Slot) error {
	image := b.image(slot)
	if !APFSHasBranch(b.Root, slot) {
		return nil
	}
	if _, err := os.Lstat(image + ".pressure"); err == nil {
		return nil
	}
	if err := os.WriteFile(image+".pressure", nil, 0600); err != nil {
		return err
	}
	return syncFile(filepath.Dir(image))
}

// ErrReplaced poisons a branch whose share no longer exposes the branch image:
// whatever the guest wrote went to another file, so sealing the branch would
// publish its untouched clone.
var ErrReplaced = fmt.Errorf("%w: cache share image was replaced", ErrPoisoned)

// ErrIncomplete poisons a branch whose image holds clearly less than the guest
// measured before its clean detach: writes the guest made through its share,
// or the checkpoint recording them, never reached the host, so the image would
// restore an older state of the volume, empty for a new one.
var ErrIncomplete = fmt.Errorf("%w: image holds less than the guest wrote", ErrPoisoned)

// incompleteSlackBytes is how far below the guest's measurement the host's may
// fall before a branch is incomplete. An intact image measures the same.
const incompleteSlackBytes = 32 << 20

// verifyHolds verifies a detached branch image and checks that it holds what
// the guest measured.
func (b *APFSImages) verifyHolds(image string, usage GuestUsage) error {
	held, err := b.Verify(image)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrPoisoned, err)
	}
	if usage.Used-held > max(incompleteSlackBytes, usage.Used/100) {
		return fmt.Errorf("%w: %d of %d bytes", ErrIncomplete, held, usage.Used)
	}
	return nil
}

// sharedImage checks that the share directory still exposes image itself.
func sharedImage(image string, dir *os.File) error {
	var source, destination unix.Stat_t
	if err := unix.Stat(image, &source); err != nil {
		return err
	}
	if err := unix.Fstatat(int(dir.Fd()), SharedImageName, &destination, unix.AT_SYMLINK_NOFOLLOW); err != nil {
		return fmt.Errorf("%w: %v", ErrReplaced, err)
	}
	if source.Dev != destination.Dev || source.Ino != destination.Ino {
		return ErrReplaced
	}
	return nil
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
	done := b.Observe.For(slot).Start("publish", "none")
	defer func() { done(err) }()
	image := b.image(slot)
	if !APFSMarker(path, ".detached", slot.ID) {
		return ErrPoisoned
	}
	if _, err := os.Lstat(image + ".pressure"); err == nil {
		return ErrPressure
	} else if !os.IsNotExist(err) {
		return err
	}
	if b.Cold(slot) && !slot.PublishCold {
		return ErrWithheld
	}
	if err := b.claim(slot, path); err != nil {
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
		b.keepUnchanged(slot, func() error { return b.verifyHolds(image, usage) })
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
		if err := b.verifyHolds(image, usage); err != nil {
			return err
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
	for _, suffix := range []string{"", ".sparseimage", ".zst", ".gz", ".checking", ".verified", ".metrics", ".base", ".cold", ".pressure", ".shared", ".shared.tmp"} {
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
	ctx = WithSubject(ctx, SubjectOf(slot))
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
