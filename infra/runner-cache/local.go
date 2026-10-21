package cachevolumes

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

var ErrConflict = errors.New("cache generation advanced")
var ErrPoisoned = errors.New("cache image failed write-back verification")

// ErrWithheld discards a finished branch that must not replace the saved version.
var ErrWithheld = errors.New("cache branch withheld from publication")

// ErrUnchanged and ErrFull withhold a branch the job left as it found it, or
// one that ran out of space and may hold partial writes.
var ErrUnchanged = fmt.Errorf("%w: unchanged", ErrWithheld)
var ErrFull = fmt.Errorf("%w: out of space", ErrWithheld)

// ErrIdentical withholds a branch whose image is byte-identical to the master it
// was cloned from although the job reported changes: its writes never reached
// the host, and publishing it would only advance the generation.
var ErrIdentical = fmt.Errorf("%w: identical to its base", ErrWithheld)

// ImageTransfer is the same upload-before-fast-forward protocol used by macOS.
// URLs and infrastructure credentials never enter the workflow filesystem.
type ImageTransfer interface {
	Download(context.Context, Slot, string) error
	Publish(Slot, string, string, string) (int64, error)
}

// HeadReader reports the HEAD a local master's lineage has reached, or
// ErrConflict once that lineage was cleared or expired.
type HeadReader interface {
	Head(Slot) (Identity, error)
}

// LocalImages keeps immutable masters and reflinked private ext4 images on a
// dedicated host filesystem. A clone must fail rather than fall back to copying.
type LocalImages struct {
	Root         string
	SizeGB       int
	MinFreeBytes uint64
	// MaxVolumeBytes bounds guest usage reports; zero is DefaultMaxVolumeBytes.
	MaxVolumeBytes   int64
	Transfer         ImageTransfer
	Clone            func(context.Context, string, string) error
	Observe          Observer
	Run              func(context.Context, string, ...string) ([]byte, error)
	Mount            func(string, string) error
	Unmount          func(string, string) error
	Check            func(string, string) error
	MeasureFS        func(string) (int64, int64, error)
	FreeBytes        func(string) (uint64, error)
	FreeBytesContext func(context.Context, string) (uint64, error)
	// Reclaim makes room in another cache sharing this filesystem, after local
	// masters have been evicted. It must preserve all active reservations.
	Reclaim func(context.Context, uint64) error
	// RefreshWithin, when positive, refreshes a stale master last used (cloned,
	// restored or published) within it to the new HEAD in the background instead
	// of removing it right away. Refreshes take this type's filesystem admission,
	// not APFSImages' reservations.
	RefreshWithin time.Duration
	// Replace, when set, is asked to fetch the HEAD that superseded a master used
	// in the last day. The stale master stays while it reports the fetch queued, so
	// jobs can mount it until its successor is local. It replaces RefreshWithin.
	Replace func(Identity) bool
	// Seed clones the host-built master of a checkout slot to the given path.
	Seed func(context.Context, Slot, string) error
	// Displace, when set, cancels speculative work that holds space on this
	// filesystem, so admission takes that space before it evicts a master.
	// Reports whether it cancelled anything.
	Displace func(context.Context) bool
	// InUse reports whether a job holds, or is attaching, a branch of a lineage
	// (Store.InUse). Pressure eviction takes those lineages' masters last.
	InUse     func(scope string) bool
	refresh   refresher
	locks     sync.Map
	admission contextMutex
}

func (b *LocalImages) command(name string, args ...string) ([]byte, error) {
	return b.commandContext(context.Background(), name, args...)
}
func (b *LocalImages) commandContext(ctx context.Context, name string, args ...string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
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
	unlock, _ := b.lockContext(context.Background(), scope)
	return unlock
}
func (b *LocalImages) lockContext(ctx context.Context, scope string) (func(), error) {
	v, _ := b.locks.LoadOrStore(scope, &contextMutex{})
	mu := v.(*contextMutex)
	if err := mu.LockContext(ctx); err != nil {
		return nil, err
	}
	return mu.Unlock, nil
}
func (b *LocalImages) operation(operation, source string, work func() error) error {
	done := b.Observe.Start(operation, source)
	err := work()
	done(err)
	return err
}
func (b *LocalImages) image(slot Slot) string { return filepath.Join(b.Root, "images", slot.ID+".img") }

// volumeBytes is the size of the slot's image: its allocation, else the host default.
func (b *LocalImages) volumeBytes(slot Slot) int64 {
	return slot.VolumeSize(int64(b.SizeGB) * 1_000_000_000)
}

func (b *LocalImages) maxVolumeBytes() int64 {
	if b.MaxVolumeBytes > 0 {
		return b.MaxVolumeBytes
	}
	return DefaultMaxVolumeBytes
}

// attachBytes is the free space an attach needs: the host floor, raised by as
// much as the volume exceeds the default size. With a 40 GB floor and 20 GB
// default that is the larger of 40 GB and the volume plus 20 GB.
func (b *LocalImages) attachBytes(slot Slot) uint64 {
	return b.MinFreeBytes + uint64(max(0, b.volumeBytes(slot)-int64(b.SizeGB)*1_000_000_000))
}

// growClone extends a private copy smaller than the slot's capacity before it
// is exposed; never shrinks. A copy that cannot grow keeps its size, and a
// server that sends no capacity never changes it.
func (b *LocalImages) growClone(slot Slot, path string) {
	info, err := os.Stat(path)
	if err != nil || slot.VolumeBytes <= 0 || info.Size() >= slot.VolumeBytes {
		return
	}
	_ = b.operation("grow", "image", func() error { return os.Truncate(path, slot.VolumeBytes) })
}

// filesystemSmaller reports whether the image's ext4 filesystem leaves more
// than the tail resize2fs may skip unused, so it must grow once mounted.
func filesystemSmaller(image string) bool {
	info, err := os.Stat(image)
	if err != nil {
		return false
	}
	size, err := ext4Bytes(image)
	return err == nil && size+64<<20 < info.Size()
}

// ext4Bytes reads the filesystem size from an ext4 superblock.
func ext4Bytes(image string) (int64, error) {
	f, err := os.Open(image)
	if err != nil {
		return 0, err
	}
	defer f.Close()
	var sb [1024]byte
	if _, err = f.ReadAt(sb[:], 1024); err != nil {
		return 0, err
	}
	if binary.LittleEndian.Uint16(sb[0x38:]) != 0xEF53 || binary.LittleEndian.Uint32(sb[0x18:]) > 6 {
		return 0, errors.New("not an ext4 filesystem")
	}
	blocks := uint64(binary.LittleEndian.Uint32(sb[0x04:]))
	if binary.LittleEndian.Uint32(sb[0x60:])&0x80 != 0 {
		blocks |= uint64(binary.LittleEndian.Uint32(sb[0x150:])) << 32
	}
	return int64(blocks << (10 + binary.LittleEndian.Uint32(sb[0x18:]))), nil
}
func (b *LocalImages) master(slot Slot) string {
	return filepath.Join(b.Root, "masters", slot.Scope, fmt.Sprintf("%020d-%s.img", slot.BaseGeneration, slot.ContentDigest))
}
func (b *LocalImages) clone(src, dst string) error {
	return b.cloneContext(context.Background(), src, dst)
}
func (b *LocalImages) cloneContext(ctx context.Context, src, dst string) error {
	if b.Clone != nil {
		return b.Clone(ctx, src, dst)
	}
	_, err := b.commandContext(ctx, "cp", "--reflink=always", "--", src, dst)
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

func (b *LocalImages) freeBytes(ctx context.Context) (uint64, error) {
	if b.FreeBytesContext != nil {
		return b.FreeBytesContext(ctx, b.Root)
	}
	return b.FreeBytes(b.Root)
}

// Reflinks share physical extents, so admission uses filesystem free space,
// exactly like the APFS manager, rather than summing logical image sizes.
func (b *LocalImages) reserve(ctx context.Context) error {
	return b.reserveBytes(ctx, b.MinFreeBytes)
}

// reserveSpare admits work only while free space already covers minimum.
func (b *LocalImages) reserveSpare(ctx context.Context, minimum uint64) error {
	if err := b.admission.LockContext(ctx); err != nil {
		return err
	}
	defer b.admission.Unlock()
	if b.FreeBytes == nil && b.FreeBytesContext == nil {
		return errors.New("missing filesystem admission")
	}
	free, err := b.freeBytes(ctx)
	if err != nil {
		return err
	}
	if free < minimum {
		return ErrCapacity
	}
	return nil
}

func (b *LocalImages) reserveBytes(ctx context.Context, minimum uint64) error {
	if err := b.admission.LockContext(ctx); err != nil {
		return err
	}
	defer b.admission.Unlock()
	if b.FreeBytes == nil && b.FreeBytesContext == nil {
		return errors.New("missing filesystem admission")
	}
	free, err := b.freeBytes(ctx)
	if err != nil {
		return err
	}
	if free < minimum && b.Displace != nil && b.Displace(ctx) {
		if free, err = b.freeBytes(ctx); err != nil {
			return err
		}
	}
	candidates, err := b.evictionOrder(free < minimum)
	if err != nil {
		return err
	}
	for _, candidate := range candidates {
		path := candidate.path
		info, err := os.Stat(path)
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			return err
		}
		reason := candidate.reason
		if free >= minimum {
			if time.Since(info.ModTime()) < 7*24*time.Hour {
				continue
			}
			reason = "expired"
		}
		if b.refreshing(path) {
			continue
		}
		unlock, err := b.lockContext(ctx, filepath.Base(filepath.Dir(path)))
		if err != nil {
			return err
		}
		err = b.operation("evict", reason, func() error { return removeMaster(path) })
		unlock()
		if err != nil {
			return err
		}
		free, err = b.freeBytes(ctx)
		if err != nil {
			return err
		}
	}
	if free < minimum && b.Reclaim != nil {
		if err := b.Reclaim(ctx, minimum); err != nil {
			return err
		}
		free, err = b.freeBytes(ctx)
		if err != nil {
			return err
		}
	}
	if free < minimum {
		return ErrCapacity
	}
	return nil
}

type evictionCandidate struct {
	path   string
	reason string
}

// evictionOrder lists the installed masters least likely to be cloned soon
// first: generations a newer local master of their lineage supersedes, then
// speculative copies no job has cloned, then the rest least recently used
// first. Lineages a job holds or is attaching go last: their clones share the
// masters' blocks, so removing them frees little, and an attaching job would
// lose its base. Without pressure only the age of each master matters, so the
// journal is not read.
func (b *LocalImages) evictionOrder(pressure bool) ([]evictionCandidate, error) {
	paths, err := filepath.Glob(filepath.Join(b.Root, "masters", "*", "*.img"))
	if err != nil {
		return nil, err
	}
	newest := map[string]int64{}
	for _, path := range paths {
		scope := filepath.Base(filepath.Dir(path))
		if generation, ok := masterGeneration(path); ok && generation > newest[scope] {
			newest[scope] = generation
		}
	}
	type ranked struct {
		evictionCandidate
		inUse  bool
		tier   int
		usedAt time.Time
	}
	inUse := map[string]bool{}
	var masters []ranked
	for _, path := range paths {
		info, err := os.Stat(path)
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			return nil, err
		}
		scope := filepath.Base(filepath.Dir(path))
		held, known := inUse[scope]
		if !known {
			held = pressure && b.InUse != nil && b.InUse(scope)
			inUse[scope] = held
		}
		master := ranked{evictionCandidate: evictionCandidate{path: path, reason: "idle"}, inUse: held, tier: 2, usedAt: info.ModTime()}
		if generation, ok := masterGeneration(path); ok && generation < newest[scope] {
			master.tier, master.reason = 0, "superseded"
		} else if speculative(path) {
			master.tier, master.reason = 1, "speculative"
		}
		if held {
			master.reason = "in_use"
		}
		masters = append(masters, master)
	}
	sort.SliceStable(masters, func(i, j int) bool {
		a, c := masters[i], masters[j]
		if a.inUse != c.inUse {
			return !a.inUse
		}
		if a.tier != c.tier {
			return a.tier < c.tier
		}
		return a.usedAt.Before(c.usedAt)
	})
	candidates := make([]evictionCandidate, len(masters))
	for i, master := range masters {
		candidates[i] = master.evictionCandidate
	}
	return candidates, nil
}

// masterGeneration parses the generation from a master's file name.
func masterGeneration(path string) (int64, bool) {
	name := filepath.Base(path)
	if len(name) < 21 || name[20] != '-' {
		return 0, false
	}
	generation, err := strconv.ParseInt(name[:20], 10, 64)
	return generation, err == nil
}

// A spare prefetch of a lineage with no copy on this host marks its master
// speculative until a job clones it.
func speculative(master string) bool {
	_, err := os.Stat(master + ".spare")
	return err == nil
}

// markUsed records that a job cloned the master. The caller holds the scope lock.
func markUsed(master string) {
	_ = os.Chtimes(master, time.Now(), time.Now())
	_ = os.Remove(master + ".spare")
}

func (b *LocalImages) Attach(ctx context.Context, slot Slot, path string) (err error) {
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
	image := b.image(slot)
	if _, err := os.Stat(image); os.IsNotExist(err) {
		if err = b.operation("admission", "none", func() error { return b.reserveBytes(ctx, b.attachBytes(slot)) }); err != nil {
			return err
		}
		// A checkout clone holds the job's whole workspace, so free space must cover
		// what it can grow to, as the reserve covers one custom volume. A checkout is
		// optional, so it never evicts anything for that room.
		if slot.Kind == KindCheckout {
			if err = b.operation("admission", "none", func() error { return b.reserveSpare(ctx, CheckoutCapacity) }); err != nil {
				return err
			}
		}
		tmp := image + ".tmp"
		_ = os.Remove(tmp)
		if slot.BaseGeneration > 0 {
			if !regexp.MustCompile(`^[a-f0-9]{64}$`).MatchString(slot.ContentDigest) {
				return errors.New("invalid master digest")
			}
			waited := b.Observe.Start("master_wait", "none")
			unlock, lockErr := b.lockContext(ctx, slot.Scope)
			waited(lockErr)
			if lockErr != nil {
				return lockErr
			}
			master := b.master(slot)
			if _, err = os.Stat(master); os.IsNotExist(err) {
				source = "remote"
				err = b.restoreMaster(ctx, slot, master)
			}
			if err == nil {
				if source == "unknown" {
					source = "local"
				}
				err = b.operation("clone", "local", func() error { return b.cloneContext(ctx, master, tmp) })
				markUsed(master)
			}
			unlock()
			if err == nil {
				b.growClone(slot, tmp)
			}
		} else if slot.Kind == KindCheckout {
			// Never fall back to an empty image: the guest mounts it over its workspace.
			if b.Seed == nil {
				err = errors.New("checkout seeding unavailable")
			} else {
				source = "local"
				err = b.operation("clone", "local", func() error { return b.Seed(ctx, slot, tmp) })
			}
		} else {
			var f *os.File
			f, err = os.OpenFile(tmp, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
			if err == nil {
				err = f.Truncate(b.volumeBytes(slot))
				closeErr := f.Close()
				if err == nil {
					err = closeErr
				}
			}
			if err == nil {
				err = b.operation("format", "empty", func() error { _, err := b.commandContext(ctx, "mkfs.ext4", "-F", "-m", "0", tmp); return err })
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
	if source == "unknown" {
		source = "local"
	}
	grow := filesystemSmaller(image)
	device, err := b.deviceContext(ctx, image)
	if err != nil {
		return err
	}
	if device == "" {
		out, e := b.commandContext(ctx, "losetup", "--find", "--show", "--nooverlap", image)
		if e != nil {
			return e
		}
		device = strings.TrimSpace(string(out))
	}
	if !loopDevice.MatchString(device) {
		return errors.New("invalid loop device")
	}
	if err = ctx.Err(); err != nil {
		return err
	}
	if err = b.operation("mount", "none", func() error { return b.Mount(device, path) }); err != nil {
		return err
	}
	if grow {
		// Online growth to fill a copy extended before exposure. On failure the
		// job keeps the old size.
		_ = b.operation("grow", "filesystem", func() error { _, err := b.commandContext(ctx, "resize2fs", device); return err })
	}
	if err = ctx.Err(); err != nil {
		return err
	}
	if err = writeMarker(slot, path); err != nil {
		return err
	}
	b.recordBaseline(slot, path)
	return nil
}

var loopDevice = regexp.MustCompile(`^/dev/loop[0-9]+$`)

func (b *LocalImages) device(image string) (string, error) {
	return b.deviceContext(context.Background(), image)
}
func (b *LocalImages) deviceContext(ctx context.Context, image string) (string, error) {
	if _, err := os.Stat(image); os.IsNotExist(err) {
		return "", nil
	} else if err != nil {
		return "", err
	}
	// --associated compares the backing inode/device, surviving agent mount
	// namespace changes where the same file has a different path spelling.
	out, err := b.commandContext(ctx, "losetup", "--json", "--list", "--associated", image, "--output", "NAME")
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
func (b *LocalImages) Seal(slot Slot, path string) (err error) {
	done := b.Observe.Start("publish", "none")
	defer func() { done(err) }()
	// A verified branch is already detached and passed these checks; verify
	// rejects one whose verification was interrupted.
	_, verified := os.Stat(b.image(slot) + ".verified")
	_, checking := os.Stat(b.image(slot) + ".checking")
	if os.IsNotExist(verified) && os.IsNotExist(checking) {
		if err := b.withheld(slot, path); err != nil {
			if errors.Is(err, ErrUnchanged) {
				b.keepUnchanged(slot, func() error {
					// A retried seal must withhold this branch again, never publish it.
					defer os.Remove(b.image(slot) + ".verified")
					return b.verify(slot, path)
				})
			}
			return err
		}
	}
	if err := b.verify(slot, path); err != nil {
		return err
	}
	return b.publish(slot)
}
func (b *LocalImages) publish(slot Slot) error {
	archive := b.image(slot) + ".zst"
	defer os.Remove(archive)
	compressDone := b.Observe.Start("compress", "none")
	digest, content, err := CompressImage(b.image(slot), archive)
	compressDone(err)
	if err != nil {
		return err
	}
	if slot.BaseGeneration > 0 && content == slot.ContentDigest {
		return ErrIdentical
	}
	uploadDone := b.Observe.Start("upload", "none")
	generation, err := b.Transfer.Publish(slot, archive, digest, content)
	uploadDone(err)
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
	return b.installBranch(slot)
}

// installBranch makes the slot's branch the master of its generation. The
// caller holds the scope lock.
func (b *LocalImages) installBranch(slot Slot) error {
	master := b.master(slot)
	if err := os.MkdirAll(filepath.Dir(master), 0700); err != nil {
		return err
	}
	tmp := master + ".tmp"
	_ = os.Remove(tmp)
	if err := b.clone(b.image(slot), tmp); err != nil {
		return err
	}
	if err := durableRename(tmp, master); err != nil {
		return err
	}
	return b.recordMaster(slot, master)
}

// keepUnchanged installs a branch the job left unchanged as the master of its
// base generation when this host no longer holds that master, as when admission
// evicted it while the job ran. The branch is a clone of that master, so the
// lineage stays warm here without a download. Only a job that may publish seals
// a branch, and verify checks it as publication would.
func (b *LocalImages) keepUnchanged(slot Slot, verify func() error) {
	if slot.BaseGeneration <= 0 || !validHead(slot.Identity) || !scopePattern.MatchString(slot.Scope) || b.HasMaster(slot.Identity) {
		return
	}
	_ = b.operation("keep", "unchanged", func() error {
		if err := verify(); err != nil {
			return err
		}
		unlock := b.lock(slot.Scope)
		defer unlock()
		if b.HasMaster(slot.Identity) {
			return nil
		}
		if err := b.installBranch(slot); err != nil {
			return err
		}
		now := time.Now()
		return os.Chtimes(b.master(slot), now, now)
	})
}

// The guard is durable before consuming one-shot kernel write-back errors.
// A crash or failure during verification permanently disqualifies this branch.
// Successful verification survives upload retries without remounting the image.
func (b *LocalImages) verify(slot Slot, path string) error {
	image := b.image(slot)
	if _, err := os.Stat(image + ".checking"); err == nil {
		return ErrPoisoned
	} else if !os.IsNotExist(err) {
		return err
	}
	if _, err := os.Stat(image + ".verified"); err == nil {
		return b.detach(slot, path)
	} else if !os.IsNotExist(err) {
		return err
	}
	if err := os.WriteFile(image+".checking", nil, 0600); err != nil {
		return err
	}
	if err := syncFile(image + ".checking"); err != nil {
		return err
	}
	if err := syncFile(filepath.Dir(image)); err != nil {
		return err
	}
	device, err := b.device(image)
	if err != nil || device == "" {
		return errors.Join(ErrPoisoned, err)
	}
	check := b.Check
	if check == nil {
		check = CheckFilesystem
	}
	if err := check(device, path); err != nil {
		return errors.Join(ErrPoisoned, err)
	}
	if err := b.detach(slot, path); err != nil {
		return errors.Join(ErrPoisoned, err)
	}
	return durableRename(image+".checking", image+".verified")
}

func (b *LocalImages) Delete(slot Slot, path string) error {
	if err := b.detach(slot, path); err != nil {
		return err
	}
	for _, suffix := range []string{"", ".tmp", ".zst", ".gz", ".checking", ".verified", ".entries"} {
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
	for _, suffix := range []string{"", ".verified", ".entries"} {
		if err := os.Remove(b.image(slot) + suffix); err != nil && !os.IsNotExist(err) {
			return err
		}
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
	heads, _ := b.Transfer.(HeadReader)
	b.removeStaleStaging()
	files, err := filepath.Glob(filepath.Join(b.Root, "masters", "*", "*.img"))
	if err != nil {
		return err
	}
	// One unreachable lineage must not stop the remaining masters from being
	// validated or evicted.
	var failures []error
	for _, path := range files {
		if _, queued := b.refresh.pending.Load(path); queued || b.refreshing(path) {
			continue
		}
		failures = append(failures, b.maintainMaster(path, heads))
	}
	return errors.Join(failures...)
}

// maintainMaster asks the server for the lineage's HEAD without the scope lock,
// so a job cloning that lineage never waits on the request, then re-checks the
// master under the lock before acting on the answer.
func (b *LocalImages) maintainMaster(path string, heads HeadReader) error {
	scope := filepath.Base(filepath.Dir(path))
	var slot Slot
	var head Identity
	var headErr error
	idle := false
	if info, err := os.Stat(path); err == nil {
		idle = time.Since(info.ModTime()) >= 7*24*time.Hour
	}
	if heads != nil && !idle {
		data, err := os.ReadFile(path + ".json")
		if err == nil {
			if err = json.Unmarshal(data, &slot); err != nil {
				return err
			}
			head, headErr = heads.Head(slot)
		} else if !os.IsNotExist(err) {
			return err
		}
	}
	unlock := b.lock(scope)
	defer unlock()
	info, err := os.Stat(path)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	if time.Since(info.ModTime()) >= 7*24*time.Hour {
		return removeMaster(path)
	}
	if heads == nil {
		return nil
	}
	if _, err = os.Stat(path + ".json"); os.IsNotExist(err) {
		return removeMaster(path)
	} else if err != nil {
		return err
	}
	if slot.Scope == "" {
		// The sidecar appeared after the unlocked read; check it next round.
		return nil
	}
	if errors.Is(headErr, ErrConflict) {
		return removeMaster(path)
	}
	if headErr != nil {
		return headErr
	}
	if head.BaseGeneration == slot.BaseGeneration {
		return nil
	}
	if b.Replace != nil {
		next := slot.Identity
		next.BaseGeneration, next.ImageDigest, next.ContentDigest = head.BaseGeneration, head.ImageDigest, head.ContentDigest
		if head.BaseGeneration > slot.BaseGeneration && validHead(next) && time.Since(info.ModTime()) < 24*time.Hour && !b.HasMaster(next) && b.Replace(next) {
			return nil
		}
		return removeMaster(path)
	}
	if b.queueRefresh(path, slot, head, info.ModTime()) {
		return nil
	}
	return removeMaster(path)
}

// olderMaster is the newest master of the slot's lineage older than its base,
// with its generation, or "" when this host holds none.
func (b *LocalImages) olderMaster(slot Slot) (string, int64) {
	if !scopePattern.MatchString(slot.Scope) {
		return "", 0
	}
	paths, err := filepath.Glob(filepath.Join(b.Root, "masters", slot.Scope, "*.img"))
	if err != nil {
		return "", 0
	}
	best, newest := "", int64(0)
	for _, path := range paths {
		generation, ok := masterGeneration(path)
		if !ok || generation <= newest || generation >= slot.BaseGeneration {
			continue
		}
		best, newest = path, generation
	}
	return best, newest
}

// HasMaster reports whether the immutable master a warm identity clones from is
// already on this host.
func (b *LocalImages) HasMaster(identity Identity) bool {
	if identity.BaseGeneration <= 0 || !validHead(identity) || !scopePattern.MatchString(identity.Scope) {
		return false
	}
	_, err := os.Stat(b.master(Slot{Identity: identity}))
	return err == nil
}

// Prefetch restores only a validated immutable master. It cannot mount a job's
// directory or publish that job's private changes after cold fallback.
func (b *LocalImages) Prefetch(ctx context.Context, slot Slot) error {
	if slot.BaseGeneration <= 0 || !validHead(slot.Identity) || !scopePattern.MatchString(slot.Scope) {
		return errors.New("invalid prefetch identity")
	}
	if err := b.reserve(ctx); err != nil {
		return err
	}
	return b.prefetch(ctx, slot, false)
}

// prefetch downloads into staging without the scope lock, so jobs and maintenance
// keep using the lineage's local masters while it runs, then installs under it.
// A spare prefetch of a lineage without a used copy here installs a speculative
// master, which pressure eviction takes before the masters jobs used.
func (b *LocalImages) prefetch(ctx context.Context, slot Slot, spare bool) error {
	master := b.master(slot)
	if _, err := os.Stat(master); err == nil {
		return nil
	} else if !os.IsNotExist(err) {
		return err
	}
	staging := filepath.Join(b.Root, "staging")
	if err := os.MkdirAll(staging, 0700); err != nil {
		return err
	}
	// One name per saved version, so the next attempt resumes the archive an
	// interrupted one left beside it. Maintenance removes it once abandoned.
	download := filepath.Join(staging, fmt.Sprintf("%s-%d-%s.img", slot.Scope, slot.BaseGeneration, slot.ContentDigest))
	_ = os.Remove(download)
	defer os.Remove(download)
	if err := b.operation("restore", "remote", func() error { return b.Transfer.Download(ctx, slot, download) }); err != nil {
		return err
	}
	unlock, err := b.lockContext(ctx, slot.Scope)
	if err != nil {
		return err
	}
	defer unlock()
	if _, err := os.Stat(master); err == nil {
		return nil
	}
	if err = os.MkdirAll(filepath.Dir(master), 0700); err != nil {
		return err
	}
	older, _ := b.olderMaster(slot)
	if err = durableRename(download, master); err != nil {
		return err
	}
	if err = b.recordMaster(slot, master); err != nil {
		return err
	}
	if spare && (older == "" || speculative(older)) {
		_ = os.WriteFile(master+".spare", nil, 0600)
	}
	return nil
}
func (b *LocalImages) restoreMaster(ctx context.Context, slot Slot, master string) error {
	if err := os.MkdirAll(filepath.Dir(master), 0700); err != nil {
		return err
	}
	download := master + ".tmp"
	_ = os.Remove(download)
	defer os.Remove(download)
	if err := b.operation("restore", "remote", func() error { return b.Transfer.Download(ctx, slot, download) }); err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if err := durableRename(download, master); err != nil {
		return err
	}
	return b.recordMaster(slot, master)
}

// removeStaleStaging deletes downloads a crash left in staging. A live download
// keeps writing, so its file stays younger than the cutoff.
func (b *LocalImages) removeStaleStaging() {
	files, _ := filepath.Glob(filepath.Join(b.Root, "staging", "*"))
	for _, path := range files {
		if info, err := os.Stat(path); err == nil && time.Since(info.ModTime()) >= time.Hour {
			_ = os.Remove(path)
		}
	}
}
