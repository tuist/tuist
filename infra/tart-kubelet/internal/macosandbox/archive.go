package macosandbox

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/pkg/archive"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

// An evicted sandbox on a stacked image moves to another Mac as its disk
// alone. A clone of a stacked image reads the image's disk from Tart's content
// store and writes to its own `overlay.asif`, which therefore holds every
// write of the session, its workspace volume included. The archive is that
// overlay with the VM's `config.json` and `nvram.bin`; a restore clones the
// same image on another host and puts them in place. The checkpoint stays
// behind: Apple encrypts it for the Mac that wrote it, so a restore cold boots.
var archivedFiles = []string{"config.json", "nvram.bin", "overlay.asif"}

// archiveTimeout bounds an upload or a restore's download; the server waits
// 31 minutes for an archive.
const archiveTimeout = 30 * time.Minute

var (
	ErrNotArchivable      = errors.New("sandbox is not archivable")
	ErrArchiveInterrupted = errors.New("archive interrupted by a resume or delete")
	ErrArchiveMismatch    = errors.New("archive does not match the sandbox")
)

// Archive uploads an evicted sandbox's disk. It changes nothing on the host:
// the server deletes the sandbox once the upload is complete. A resume or a
// delete meanwhile interrupts it.
func (m *Manager) Archive(ctx context.Context, a protocol.ArchiveArgs) (protocol.ArchiveResult, error) {
	m.Gate.Lock()
	r, err := m.get(a.SandboxID)
	switch {
	case err != nil:
	case r.State != "paused" || r.Resident || r.Operation != "":
		err = fmt.Errorf("%w: it is %s and resident=%t", ErrNotArchivable, r.State, r.Resident)
	case !r.DisksSynced:
		err = fmt.Errorf("%w: its disks were not flushed before it paused", ErrNotArchivable)
	case m.archiving[a.SandboxID] != nil:
		err = fmt.Errorf("%w: it is already being archived", ErrNotArchivable)
	}
	if err != nil {
		m.Gate.Unlock()
		return protocol.ArchiveResult{}, err
	}
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	if m.archiving == nil {
		m.archiving = map[string]context.CancelFunc{}
	}
	m.archiving[a.SandboxID] = cancel
	snapshot := *r
	m.Gate.Unlock()
	defer func() {
		m.Gate.Lock()
		delete(m.archiving, a.SandboxID)
		m.Gate.Unlock()
	}()

	res, err := m.Runtime.Archive(ctx, &snapshot, a)
	if err != nil && ctx.Err() != nil {
		return res, ErrArchiveInterrupted
	}
	return res, err
}

// interruptArchive cancels an upload of the sandbox, under the host gate,
// before anything writes to its disk or removes it.
func (m *Manager) interruptArchive(id string) {
	if cancel := m.archiving[id]; cancel != nil {
		cancel()
	}
}

func (t *TartRuntime) Archive(ctx context.Context, r *Record, a protocol.ArchiveArgs) (protocol.ArchiveResult, error) {
	header := archive.Header{Template: r.Template, Tag: r.TemplateTag, WorkspaceGB: r.WorkspaceGB, SourceSandbox: r.SandboxID, CreatedAt: time.Now().UTC(), DisksSynced: true}
	res, err := uploadDisk(ctx, t.directory(r), header, a.PartURLs, a.PartSize)
	if err == nil {
		slog.Info("macOS sandbox archived", "sandbox_id", r.SandboxID, "bytes", res.Bytes, "stored_bytes", res.StoredBytes, "parts", len(res.Parts), "duration_ms", res.DurationMs)
	}
	return res, err
}

// uploadDisk uploads a stopped VM's archivedFiles from dir, a sandbox's or a
// disk snapshot's, through the presigned parts. A standalone disk.img would
// carry the whole image, so only a stacked VM qualifies.
func uploadDisk(ctx context.Context, dir string, header archive.Header, partURLs []string, partSize int64) (protocol.ArchiveResult, error) {
	start := time.Now()
	if _, err := os.Stat(filepath.Join(dir, "disk.img")); err == nil {
		return protocol.ArchiveResult{}, fmt.Errorf("%w: its image is not stacked", ErrNotArchivable)
	}
	sources := make([]archive.Source, 0, len(archivedFiles))
	defer func() {
		for _, s := range sources {
			s.File.Close()
		}
	}()
	for _, name := range archivedFiles {
		f, err := os.Open(filepath.Join(dir, name))
		if err != nil {
			return protocol.ArchiveResult{}, err
		}
		sources = append(sources, archive.Source{Name: name, File: f})
	}
	uploader, err := archive.NewUploader(ctx, http.DefaultClient, partURLs, partSize)
	if err != nil {
		return protocol.ArchiveResult{}, err
	}
	stored, err := archive.Write(uploader, header, sources)
	if closeErr := uploader.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return protocol.ArchiveResult{}, err
	}
	parts := make([]protocol.ArchivePart, 0, len(uploader.Parts()))
	for _, part := range uploader.Parts() {
		parts = append(parts, protocol.ArchivePart{PartNumber: part.PartNumber, ETag: part.ETag})
	}
	return protocol.ArchiveResult{Parts: parts, Bytes: uploader.Bytes(), SHA256: uploader.SHA256(), StoredBytes: stored, DisksSynced: true, DurationMs: time.Since(start).Milliseconds()}, nil
}

// restore creates the sandbox from its archive: a clone of the same image
// with the archived files in place of its own, cold booted. The archived
// config keeps the machine identity the guest's install was made with.
func (t *TartRuntime) restore(ctx context.Context, r *Record) error {
	if r.FromArchive.TailOffset != 0 || r.FromArchive.LazyDisks {
		return errors.New("from_archive needs a URL, a size and a checksum, and no memory")
	}
	start := time.Now()
	c := t.client(r)
	if err := t.roomForClone(ctx, c, r.MemoryMB); err != nil {
		return err
	}
	header, image, current, err := t.cloneArchived(ctx, c, r.VMName(), r.Template, r.TemplateTag, r.WorkspaceGB, *r.FromArchive)
	if err != nil {
		return err
	}
	src := r.FromArchive
	downloaded := time.Since(start)
	if err := c.Set(ctx, r.VMName(), r.VCPUs, r.MemoryMB); err != nil {
		return err
	}
	if err := t.checkDisk(ctx, r); err != nil {
		return err
	}
	if err := t.writeEnv(c.HomeDir, r); err != nil {
		return err
	}
	h, err := c.StartWithOptions(ctx, r.VMName(), t.options(r))
	if err != nil {
		return err
	}
	if _, err := t.waitGuestReady(ctx, r, h); err != nil {
		return err
	}
	// The workspace volume is on the restored disk, but a cold boot mounts
	// it under /Volumes.
	if _, err := c.Exec(ctx, r.VMName(), "/bin/sh", "-c", remountWorkspace); err != nil {
		return err
	}
	r.WorkspaceVolumeGB = r.WorkspaceGB
	_, err = t.control(ctx, r, "status")
	slog.Info("macOS sandbox restored from its archive", "sandbox_id", r.SandboxID, "source_sandbox", header.SourceSandbox, "image", image, "current_image", current, "bytes", src.Bytes, "download_ms", downloaded.Milliseconds(), "total_ms", time.Since(start).Milliseconds())
	return err
}

// cloneArchived clones the image an archive was made on into vm, then puts
// the archived files in place of the clone's: the VM a restore boots and a
// disk snapshot copy keeps. It answers the archive's header, the image and
// whether that is the template's current one.
func (t *TartRuntime) cloneArchived(ctx context.Context, c *tart.Client, vm, template, tag string, workspaceGB int, src protocol.ArchiveSource) (archive.Header, string, bool, error) {
	var header archive.Header
	if src.URL == "" || src.Bytes <= 0 || src.SHA256 == "" {
		return header, "", false, errors.New("from_archive needs a URL, a size and a checksum")
	}
	current, ok := t.Templates.Image(template)
	if !ok {
		return header, "", false, fmt.Errorf("%w: the host has no template %s", ErrArchiveMismatch, template)
	}
	image, err := restoreImage(current, tag)
	if err != nil {
		return header, "", false, err
	}
	// The overlay holds only the blocks the session wrote, so it needs the
	// exact image it was cloned from. A release since then moved the
	// template on; the old image comes from the CI store or the registry,
	// where its base chunks are usually shared with the current one, and
	// stays in the sandbox store for the next restore.
	if image != current {
		if err := ensureImage(ctx, t.Client, t.CIStore, image); err != nil {
			return header, "", false, fmt.Errorf("preparing archived image %s: %w", image, err)
		}
	}
	if err := c.Clone(ctx, image, vm); err != nil {
		return header, "", false, err
	}
	dir := filepath.Join(c.HomeDir, "vms", vm)
	if _, err := os.Stat(filepath.Join(dir, "overlay.asif")); err != nil {
		return header, "", false, fmt.Errorf("%w: the image is not stacked", ErrArchiveMismatch)
	}
	// An overlay's nominal size grows with the session's writes, up to the
	// disk's capacity plus ASIF's own metadata, so the fresh clone's empty
	// overlay is no bound for an archived one.
	detail, err := c.Get(ctx, vm)
	if err != nil {
		return header, "", false, err
	}
	capacity := t.rootfs.Load()
	if detail != nil {
		capacity = max(capacity, rootDisk([]tart.VM{*detail}))
	}
	if capacity <= 0 {
		return header, "", false, errors.New("restoring archive: the clone's disk capacity is unknown")
	}
	staging := filepath.Join(dir, ".archive")
	if err := os.RemoveAll(staging); err != nil {
		return header, "", false, err
	}
	if err := os.Mkdir(staging, 0o700); err != nil {
		return header, "", false, err
	}
	defer os.RemoveAll(staging)
	limits := map[string]int64{"config.json": 1 << 20, "nvram.bin": 64 << 20, "overlay.asif": capacity + 1<<30}
	for attempt := 1; ; attempt++ {
		err = archive.Download(ctx, http.DefaultClient, src.URL, src.Bytes, src.SHA256, func(body io.Reader) error {
			var extractErr error
			header, extractErr = archive.Extract(body, staging, limits)
			return extractErr
		})
		if err == nil {
			break
		}
		if attempt == 3 || ctx.Err() != nil || errors.Is(err, archive.ErrInvalid) {
			return header, "", false, fmt.Errorf("restoring archive: %w", err)
		}
		slog.Warn("macOS archive download failed, retrying", "vm", vm, "attempt", attempt, "error", err)
		if err := os.RemoveAll(staging); err != nil {
			return header, "", false, err
		}
		if err := os.Mkdir(staging, 0o700); err != nil {
			return header, "", false, err
		}
	}
	if header.Tag != tag || header.WorkspaceGB != workspaceGB || !header.DisksSynced {
		return header, "", false, fmt.Errorf("%w: it holds image %s with a %d GB workspace", ErrArchiveMismatch, header.Tag, header.WorkspaceGB)
	}
	for _, name := range archivedFiles {
		if err := os.Rename(filepath.Join(staging, name), filepath.Join(dir, name)); err != nil {
			return header, "", false, err
		}
	}
	return header, image, image == current, nil
}

// restoreImage is the image an archive made on archived restores on: the
// template's current image, or an earlier image of the same repository named
// by digest. A tag can move to other content, which the overlay would not
// match, and another repository is not an image this host was given.
func restoreImage(current, archived string) (string, error) {
	if archived == "" || archived == current {
		return current, nil
	}
	repo, digest, pinned := strings.Cut(archived, "@")
	if !pinned || !strings.HasPrefix(digest, "sha256:") || len(digest) != len("sha256:")+64 || repo != repository(current) {
		return "", fmt.Errorf("%w: it needs image %s, not a digest of %s", ErrArchiveMismatch, archived, repository(current))
	}
	return archived, nil
}

// repository is an image reference without its digest or tag.
func repository(image string) string {
	if repo, _, ok := strings.Cut(image, "@"); ok {
		return repo
	}
	if i := strings.LastIndex(image, ":"); i > strings.LastIndex(image, "/") {
		return image[:i]
	}
	return image
}

const remountWorkspace = `set -eu
info=$(/usr/sbin/diskutil info -plist TuistSandboxWorkspace)
dev=$(printf '%s' "$info" | /usr/bin/plutil -extract DeviceIdentifier raw -o - -)
mounted=$(printf '%s' "$info" | /usr/bin/plutil -extract MountPoint raw -o - - 2>/dev/null || true)
if [ "$mounted" != /Users/runner/work ]; then
	[ -z "$mounted" ] || /usr/bin/sudo -n /usr/sbin/diskutil unmount "$dev"
	/usr/bin/sudo -n /usr/sbin/diskutil mount -mountPoint /Users/runner/work "$dev"
fi`
