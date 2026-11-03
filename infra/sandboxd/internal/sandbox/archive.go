package sandbox

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/archive"
	"github.com/tuist/tuist/infra/sandboxd/internal/firecracker"
	"github.com/tuist/tuist/infra/sandboxd/internal/protocol"
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
)

// Archiving uploads a paused sandbox's kernel and disks to object storage so
// the server can delete it from the node; a later create with from_archive
// downloads them on any node and cold boots. No memory image is archived.
const (
	restoreAttempts = 3
	maxKernelBytes  = 512 << 20
	maxRootfsBytes  = 256 << 30
)

var (
	ErrArchiveInterrupted = errors.New("archive interrupted by a resume or delete")
	ErrArchiveMismatch    = errors.New("archive does not match the requested sandbox")
)

var archivedFiles = []string{firecracker.KernelPath, firecracker.RootfsPath, firecracker.WorkspacePath}

func defaultHTTPClient() *http.Client {
	return &http.Client{Transport: &http.Transport{
		Proxy:                 http.ProxyFromEnvironment,
		DialContext:           (&net.Dialer{Timeout: 30 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
		TLSHandshakeTimeout:   30 * time.Second,
		ResponseHeaderTimeout: 2 * time.Minute,
		IdleConnTimeout:       90 * time.Second,
		MaxIdleConnsPerHost:   4,
	}}
}

// interruptArchive stops an archive of the sandbox, and keeps one about to
// start from running, ahead of a resume or delete.
func (sb *Sandbox) interruptArchive() {
	sb.mu.Lock()
	defer sb.mu.Unlock()
	sb.resumes++
	if sb.cancelArchive != nil {
		sb.cancelArchive()
	}
}

// Archive uploads a paused sandbox's kernel, rootfs and workspace through
// the presigned part URLs. The sandbox stays on the node, paused; a resume
// or delete arriving meanwhile cancels the upload instead of waiting for it.
func (m *Manager) Archive(ctx context.Context, args protocol.ArchiveArgs) (res protocol.ArchiveResult, err error) {
	start := time.Now()
	defer func() { m.metrics.observe(protocol.OpArchive, err) }()
	sb, err := m.get(args.SandboxID)
	if err != nil {
		return res, err
	}
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	sb.mu.Lock()
	resumes := sb.resumes
	sb.cancelArchive = cancel
	sb.mu.Unlock()
	defer func() {
		sb.mu.Lock()
		sb.cancelArchive = nil
		sb.mu.Unlock()
	}()

	sb.opMu.Lock()
	defer sb.opMu.Unlock()
	if !m.current(args.SandboxID, sb) {
		return res, fmt.Errorf("%w: %s", ErrNotFound, args.SandboxID)
	}
	sb.mu.Lock()
	meta := sb.meta
	interrupted := sb.resumes != resumes
	sb.mu.Unlock()
	if interrupted {
		return res, ErrArchiveInterrupted
	}
	if meta.State != protocol.StatePaused {
		return res, fmt.Errorf("%w: %s is %s", ErrNotPaused, args.SandboxID, meta.State)
	}

	sources := make([]archive.Source, 0, len(archivedFiles))
	for _, name := range archivedFiles {
		file, err := os.OpenFile(filepath.Join(sb.root, name), os.O_RDONLY|syscall.O_NOFOLLOW, 0)
		if err != nil {
			return res, err
		}
		defer file.Close()
		sources = append(sources, archive.Source{Name: name, File: file})
	}
	uploader, err := archive.NewUploader(ctx, m.http, args.PartURLs, args.PartSize)
	if err != nil {
		return res, err
	}
	stored, err := archive.Write(uploader, archive.Header{
		Template: meta.Template, Tag: meta.Tag, WorkspaceGB: meta.WorkspaceGB,
		SourceSandbox: meta.ID, CreatedAt: time.Now().UTC(), DisksSynced: meta.DisksSynced,
	}, sources)
	if closeErr := uploader.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		if sb.resumesSince(resumes) {
			return res, ErrArchiveInterrupted
		}
		return res, err
	}
	parts := make([]protocol.ArchivePart, 0, len(uploader.Parts()))
	for _, part := range uploader.Parts() {
		parts = append(parts, protocol.ArchivePart{PartNumber: part.PartNumber, ETag: part.ETag})
	}
	m.log.Info("sandbox archived", "sandbox", args.SandboxID, "bytes", uploader.Bytes(), "stored_bytes", stored, "parts", len(parts), "disks_synced", meta.DisksSynced, "duration", time.Since(start))
	return protocol.ArchiveResult{
		Parts: parts, Bytes: uploader.Bytes(), SHA256: uploader.SHA256(), StoredBytes: stored,
		DisksSynced: meta.DisksSynced, DurationMs: time.Since(start).Milliseconds(),
	}, nil
}

func (sb *Sandbox) resumesSince(resumes uint64) bool {
	sb.mu.Lock()
	defer sb.mu.Unlock()
	return sb.resumes != resumes
}

// createFromArchive is Create's path for a sandbox restored from an
// archive: the jail gets the archived kernel and disks, downloaded and
// checked against the size and checksum they were uploaded with, and the VM
// cold boots on them. The caller holds sb.opMu and discards the sandbox when
// this fails; the archive itself is never touched.
func (m *Manager) createFromArchive(ctx context.Context, sb *Sandbox, args protocol.CreateArgs, log *slog.Logger) (res protocol.CreateResult, err error) {
	src := args.FromArchive
	if src.URL == "" || src.Bytes <= 0 || src.SHA256 == "" {
		return res, errors.New("from_archive needs a URL, a size and a checksum")
	}
	slot, err := m.slots.Allocate()
	if err != nil {
		return res, err
	}
	sb.mu.Lock()
	sb.meta.Slot = slot
	template := sb.meta.Template
	sb.mu.Unlock()
	uid := m.cfg.UIDBase + slot
	if err := os.RemoveAll(vm.JailDir(m.cfg.JailBase, args.SandboxID)); err != nil {
		return res, err
	}
	if err := vm.Prepare(sb.root, uid, uid); err != nil {
		return res, err
	}
	limits := map[string]int64{
		firecracker.KernelPath:    maxKernelBytes,
		firecracker.RootfsPath:    maxRootfsBytes,
		firecracker.WorkspacePath: int64(args.WorkspaceGB) << 30,
	}
	downloadStart := time.Now()
	var header archive.Header
	for attempt := 1; ; attempt++ {
		err = archive.Download(ctx, m.http, src.URL, src.Bytes, src.SHA256, func(r io.Reader) error {
			var extractErr error
			header, extractErr = archive.Extract(r, sb.root, limits)
			return extractErr
		})
		if err == nil {
			break
		}
		for _, name := range archivedFiles {
			_ = os.Remove(filepath.Join(sb.root, name))
		}
		if attempt == restoreAttempts || ctx.Err() != nil || errors.Is(err, archive.ErrInvalid) {
			return res, fmt.Errorf("restoring archive: %w", err)
		}
		log.Warn("archive download failed, retrying", "attempt", attempt, "error", err)
	}
	if header.Template != template || header.WorkspaceGB != args.WorkspaceGB {
		return res, fmt.Errorf("%w: it holds template %s with a %d GB workspace", ErrArchiveMismatch, header.Template, header.WorkspaceGB)
	}
	if size := vm.FileSize(filepath.Join(sb.root, firecracker.WorkspacePath)); size != int64(args.WorkspaceGB)<<30 {
		return res, fmt.Errorf("%w: workspace image is %d bytes", ErrArchiveMismatch, size)
	}
	for _, name := range archivedFiles {
		if err := vm.Chown(filepath.Join(sb.root, name), uid, uid); err != nil {
			return res, err
		}
	}
	sb.mu.Lock()
	sb.meta.Tag = header.Tag
	sb.mu.Unlock()
	log.Info("archive downloaded", "bytes", src.Bytes, "source_sandbox", header.SourceSandbox, "download", time.Since(downloadStart))
	return m.coldCreate(ctx, sb, log.With("slot", slot, "from_archive", true))
}
