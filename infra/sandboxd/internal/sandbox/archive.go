package sandbox

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
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
	"github.com/tuist/tuist/infra/sandboxd/internal/uffd"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
)

// Archiving uploads a paused sandbox's kernel and disks to object storage so
// the server can delete it from the node; a later create with from_archive
// downloads them on any node. When the sandbox's memory image is current,
// the archive holds it too, ahead of the disks (archive/memory.go): a node
// with the same SnapshotCompat resumes the VM from it warm, serving its
// memory from the archive as the guest touches it, and any other node cold
// boots the disks.
const (
	restoreAttempts  = 3
	maxKernelBytes   = 512 << 20
	maxRootfsBytes   = 256 << 30
	maxSnapshotBytes = 64 << 20

	// memSocket is where the memory server listens for Firecracker, in the
	// jail.
	memSocket = "/mem.sock"
	// Faults fetch the chunks a vCPU waits on; the fill fetches the rest
	// with fewer streams, so the image is on the node well before the
	// download URL expires.
	memoryFaultWorkers = 8
	memoryFillWorkers  = 2
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
		MaxIdleConnsPerHost:   16,
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
	// The archive holds no memory image, so writes still in the guest's
	// page cache would restore as zeroed blocks.
	if !meta.DisksSynced {
		return res, fmt.Errorf("%w: %s", ErrDisksNotSynced, args.SandboxID)
	}

	sources, closeSources, err := openArchivedFiles(sb.root)
	if err != nil {
		return res, err
	}
	defer closeSources()
	header := archive.Header{
		Template: meta.Template, Tag: meta.Tag, WorkspaceGB: meta.WorkspaceGB,
		SourceSandbox: meta.ID, CreatedAt: time.Now().UTC(), DisksSynced: meta.DisksSynced,
	}
	// The memory image travels when the server can restore it and it is
	// the one the disks belong to, written by this Firecracker; otherwise
	// the restore cold boots anyway.
	var memory *archivedMemory
	if args.Memory && !meta.ColdBoot && meta.FirecrackerVersion == m.cfg.FirecrackerVersion && m.cfg.SnapshotCompat != "" {
		if memory, err = openMemory(sb.root); err != nil {
			return res, err
		}
		defer memory.close()
		header.Memory = &archive.MemoryHeader{Size: memory.size, Compat: m.cfg.SnapshotCompat}
	}
	res, err = m.upload(ctx, args.PartURLs, args.PartSize, header, sources, memory, start)
	if err != nil {
		if sb.resumesSince(resumes) {
			return res, ErrArchiveInterrupted
		}
		return res, err
	}
	m.log.Info("sandbox archived", "sandbox", args.SandboxID, "bytes", res.Bytes, "stored_bytes", res.StoredBytes, "memory_bytes", res.MemoryBytes, "tail_offset", res.TailOffset, "parts", len(res.Parts), "disks_synced", meta.DisksSynced, "duration", time.Since(start))
	return res, nil
}

// ArchiveDisks uploads a disk snapshot's kernel, rootfs and workspace like
// Archive, so a sandbox can be created from it on any node. The files are
// opened under the snapshot lock and streamed after it is released: a
// delete or a newer save of the snapshot meanwhile only unlinks them, and
// the server discards an upload whose snapshot is gone.
func (m *Manager) ArchiveDisks(ctx context.Context, args protocol.ArchiveDisksArgs) (res protocol.ArchiveResult, err error) {
	start := time.Now()
	defer func() { m.metrics.observe(protocol.OpArchiveDisks, err) }()
	m.snapMu.Lock()
	snap, dir, err := m.loadDiskSnapshot(args.SnapshotID)
	var sources []archive.Source
	closeSources := func() {}
	if err == nil {
		sources, closeSources, err = openArchivedFiles(dir)
	}
	m.snapMu.Unlock()
	if err != nil {
		return res, err
	}
	defer closeSources()
	// A save requires a synced pause, so the disks hold every write.
	res, err = m.upload(ctx, args.PartURLs, args.PartSize, archive.Header{
		Template: snap.Template, Tag: snap.Tag, WorkspaceGB: snap.WorkspaceGB,
		SourceSandbox: snap.SourceSandbox, CreatedAt: time.Now().UTC(), DisksSynced: true,
	}, sources, nil, start)
	if err != nil {
		return res, err
	}
	m.log.Info("disk snapshot archived", "snapshot", args.SnapshotID, "bytes", res.Bytes, "stored_bytes", res.StoredBytes, "parts", len(res.Parts), "duration", time.Since(start))
	return res, nil
}

func openArchivedFiles(dir string) ([]archive.Source, func(), error) {
	sources := make([]archive.Source, 0, len(archivedFiles))
	closeAll := func() {
		for _, source := range sources {
			source.File.Close()
		}
	}
	for _, name := range archivedFiles {
		file, err := os.OpenFile(filepath.Join(dir, name), os.O_RDONLY|syscall.O_NOFOLLOW, 0)
		if err != nil {
			closeAll()
			return nil, nil, err
		}
		sources = append(sources, archive.Source{Name: name, File: file})
	}
	return sources, closeAll, nil
}

// archivedMemory is a paused sandbox's memory image and VM state, open for
// an archive.
type archivedMemory struct {
	mem, snapshot *os.File
	size          int64
}

func openMemory(root string) (*archivedMemory, error) {
	mem, err := os.OpenFile(filepath.Join(root, firecracker.MemPath), os.O_RDONLY|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return nil, err
	}
	snapshot, err := os.OpenFile(filepath.Join(root, firecracker.SnapshotPath), os.O_RDONLY|syscall.O_NOFOLLOW, 0)
	if err != nil {
		mem.Close()
		return nil, err
	}
	info, err := mem.Stat()
	if err != nil {
		mem.Close()
		snapshot.Close()
		return nil, err
	}
	return &archivedMemory{mem: mem, snapshot: snapshot, size: info.Size()}, nil
}

func (a *archivedMemory) close() {
	a.mem.Close()
	a.snapshot.Close()
}

// upload streams the archive through the presigned parts: the memory
// image's chunks first when there is one, then the disk stream, which also
// carries the VM state and the memory index and is hashed on its own so a
// warm restore can read and check just this tail.
func (m *Manager) upload(ctx context.Context, partURLs []string, partSize int64, header archive.Header, sources []archive.Source, memory *archivedMemory, start time.Time) (res protocol.ArchiveResult, err error) {
	uploader, err := archive.NewUploader(ctx, m.http, partURLs, partSize)
	if err != nil {
		return res, err
	}
	var tail io.Writer = uploader
	tailHash := sha256.New()
	var tailOffset, memoryBytes int64
	if memory != nil {
		var index archive.MemoryIndex
		index, memoryBytes, err = archive.WriteMemory(uploader, 0, memory.mem)
		var indexFile *os.File
		if err == nil {
			indexFile, err = tempFileWith(index.Marshal())
		}
		if err != nil {
			uploader.Close()
			return res, err
		}
		defer indexFile.Close()
		sources = append(sources, archive.Source{Name: firecracker.SnapshotPath, File: memory.snapshot}, archive.Source{Name: archive.MemoryIndexName, File: indexFile})
		tailOffset = uploader.Bytes()
		tail = io.MultiWriter(uploader, tailHash)
	}
	stored, err := archive.Write(tail, header, sources)
	if closeErr := uploader.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return res, err
	}
	parts := make([]protocol.ArchivePart, 0, len(uploader.Parts()))
	for _, part := range uploader.Parts() {
		parts = append(parts, protocol.ArchivePart{PartNumber: part.PartNumber, ETag: part.ETag})
	}
	res = protocol.ArchiveResult{
		Parts: parts, Bytes: uploader.Bytes(), SHA256: uploader.SHA256(), StoredBytes: stored + memoryBytes,
		DisksSynced: header.DisksSynced, DurationMs: time.Since(start).Milliseconds(),
	}
	if memory != nil {
		res.TailOffset, res.TailSHA256 = tailOffset, hex.EncodeToString(tailHash.Sum(nil))
		res.Compat, res.MemoryBytes = header.Memory.Compat, memoryBytes
	}
	return res, nil
}

// tempFileWith is an unlinked file holding data, for archive.Write.
func tempFileWith(data []byte) (*os.File, error) {
	f, err := os.CreateTemp("", "sandboxd-archive-")
	if err != nil {
		return nil, err
	}
	_ = os.Remove(f.Name())
	if _, err := f.Write(data); err != nil {
		f.Close()
		return nil, err
	}
	return f, nil
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
	header, err := m.downloadArchive(ctx, src, sb.root, template, args.WorkspaceGB, args.MemoryMB, log)
	if err != nil {
		return res, err
	}
	for _, name := range archivedFiles {
		if err := vm.Chown(filepath.Join(sb.root, name), uid, uid); err != nil {
			return res, err
		}
	}
	sb.mu.Lock()
	sb.meta.Tag = header.Tag
	sb.mu.Unlock()
	log = log.With("slot", slot, "from_archive", true)
	if header.Memory != nil {
		if header.Memory.Compat == m.cfg.SnapshotCompat && header.Memory.Size == int64(args.MemoryMB)<<20 {
			return m.warmCreate(ctx, sb, src, uid, log)
		}
		log.Warn("archived memory needs another kind of node; cold booting the disks", "compat", header.Memory.Compat, "node_compat", m.cfg.SnapshotCompat)
		for _, name := range []string{firecracker.SnapshotPath, archive.MemoryIndexName} {
			_ = os.Remove(filepath.Join(sb.root, name))
		}
	}
	return m.coldCreate(ctx, sb, log)
}

// downloadArchive extracts an archive's kernel and disks into dir, checked
// against the size and checksum it was uploaded with, and checks that it
// holds the template and workspace size asked for. An archive with memory is
// read from its disk stream on, which also holds the VM state and the memory
// index: the memory ahead of it is fetched later, and only by a warm restore.
// A failed attempt removes what it extracted; dir is left without the
// archived files on error.
func (m *Manager) downloadArchive(ctx context.Context, src *protocol.ArchiveSource, dir, template string, workspaceGB, memoryMB int, log *slog.Logger) (archive.Header, error) {
	limits := map[string]int64{
		firecracker.KernelPath:    maxKernelBytes,
		firecracker.RootfsPath:    maxRootfsBytes,
		firecracker.WorkspacePath: int64(workspaceGB) << 30,
	}
	offset, size, sum := int64(0), src.Bytes, src.SHA256
	if src.TailOffset > 0 {
		if src.TailOffset >= src.Bytes || src.TailSHA256 == "" {
			return archive.Header{}, errors.New("from_archive has a tail outside the archive")
		}
		offset, size, sum = src.TailOffset, src.Bytes-src.TailOffset, src.TailSHA256
		limits[firecracker.SnapshotPath] = maxSnapshotBytes
		limits[archive.MemoryIndexName] = archive.MaxMemoryIndexBytes(int64(memoryMB) << 20)
	}
	removeFiles := func() {
		for name := range limits {
			_ = os.Remove(filepath.Join(dir, name))
		}
	}
	start := time.Now()
	var header archive.Header
	for attempt := 1; ; attempt++ {
		err := archive.DownloadRange(ctx, m.http, src.URL, offset, size, sum, func(r io.Reader) error {
			var extractErr error
			header, extractErr = archive.Extract(r, dir, limits)
			return extractErr
		})
		if err == nil {
			break
		}
		removeFiles()
		if attempt == restoreAttempts || ctx.Err() != nil || errors.Is(err, archive.ErrInvalid) {
			return header, fmt.Errorf("restoring archive: %w", err)
		}
		log.Warn("archive download failed, retrying", "attempt", attempt, "error", err)
	}
	if header.Template != template || header.WorkspaceGB != workspaceGB {
		removeFiles()
		return header, fmt.Errorf("%w: it holds template %s with a %d GB workspace", ErrArchiveMismatch, header.Template, header.WorkspaceGB)
	}
	if size := vm.FileSize(filepath.Join(dir, firecracker.WorkspacePath)); size != int64(workspaceGB)<<30 {
		removeFiles()
		return header, fmt.Errorf("%w: workspace image is %d bytes", ErrArchiveMismatch, size)
	}
	log.Info("archive downloaded", "bytes", size, "source_sandbox", header.SourceSandbox, "download", time.Since(start))
	return header, nil
}

// warmCreate resumes an archived sandbox from its VM state, its memory
// served from the archive by userfaultfd: the guest runs as soon as the
// state loads, each first touch of a page fetches its chunk, and a fill
// fetches the rest. Until every chunk is on the node the sandbox depends on
// the archive, so the server keeps it until EventMemoryLoaded; a chunk that
// cannot be fetched kills the VM, which could never run on without it.
func (m *Manager) warmCreate(ctx context.Context, sb *Sandbox, src *protocol.ArchiveSource, uid int, log *slog.Logger) (protocol.CreateResult, error) {
	data, err := os.ReadFile(filepath.Join(sb.root, archive.MemoryIndexName))
	if err != nil {
		return protocol.CreateResult{}, err
	}
	index, err := archive.ParseMemoryIndex(data, src.TailOffset)
	if err != nil {
		return protocol.CreateResult{}, err
	}
	memory, err := archive.NewRemoteMemory(m.http, src.URL, index)
	if err != nil {
		return protocol.CreateResult{}, err
	}
	server, err := uffd.Listen(filepath.Join(sb.root, memSocket))
	if err == nil {
		if err = vm.Chown(filepath.Join(sb.root, memSocket), uid, uid); err != nil {
			server.Close()
		}
	}
	if err != nil {
		memory.Close()
		return protocol.CreateResult{}, err
	}
	serveCtx, stopServing := context.WithCancel(context.Background())
	served := make(chan error, 1)
	started := time.Now()
	go func() {
		defer memory.Close()
		served <- server.Serve(serveCtx, memory, uffd.Options{
			FaultWorkers: memoryFaultWorkers, FillWorkers: memoryFillWorkers,
			OnLoaded: func(stats uffd.Stats) { m.memoryLoaded(sb, stats, time.Since(started)) },
		})
	}()
	sb.mu.Lock()
	sb.memoryPending = true
	sb.mu.Unlock()
	inst, _, err := m.restoreWith(ctx, sb, log, memSocket, nil, false)
	if err != nil {
		stopServing()
		server.Close()
		<-served
		return protocol.CreateResult{}, err
	}
	// The memory server lives as long as this Firecracker process.
	go func() {
		select {
		case <-inst.Done():
			stopServing()
			<-served
		case err := <-served:
			stopServing()
			if err != nil && !errors.Is(err, uffd.ErrProcessGone) {
				m.memoryFailed(sb, inst, err)
			}
		}
	}()
	sb.mu.Lock()
	sb.meta.State = protocol.StateRunning
	sb.meta.Generation = 0
	sb.meta.FirecrackerVersion = m.cfg.FirecrackerVersion
	sb.meta.Error = ""
	err = sb.meta.Save(sb.root)
	sb.mu.Unlock()
	if err != nil {
		return protocol.CreateResult{}, err
	}
	_ = os.Remove(filepath.Join(sb.root, archive.MemoryIndexName))
	m.refreshGauges()
	stats := server.Stats()
	log.Info("sandbox resumed from its archived memory", "restore", time.Since(started), "pid", inst.PID(),
		"chunks", stats.Chunks, "stored_chunks", memory.StoredChunks(), "faulted", stats.Faulted, "filled", stats.Filled)
	return protocol.CreateResult{BootMs: time.Since(started).Milliseconds(), MemoryPending: true}, nil
}

// memoryLoaded reports that a warm restore no longer needs its archive.
func (m *Manager) memoryLoaded(sb *Sandbox, stats uffd.Stats, elapsed time.Duration) {
	sb.mu.Lock()
	pending := sb.memoryPending
	sb.memoryPending = false
	id := sb.meta.ID
	sb.mu.Unlock()
	m.log.Info("sandbox memory loaded from its archive", "sandbox", id, "elapsed", elapsed,
		"chunks", stats.Chunks, "faulted", stats.Faulted, "filled", stats.Filled, "zero", stats.Zero, "faults", stats.Faults, "bytes", stats.Bytes)
	if pending {
		m.events(protocol.Event{Type: protocol.FrameEvent, Event: protocol.EventMemoryLoaded, SandboxID: id})
	}
}

// memoryFailed kills a VM whose memory can no longer be fetched: its vCPUs
// would wait on the missing pages forever.
func (m *Manager) memoryFailed(sb *Sandbox, inst vm.Instance, err error) {
	sb.mu.Lock()
	current := sb.inst == inst
	sb.mu.Unlock()
	if !current {
		return
	}
	sb.detach()
	killCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	_ = inst.Kill(killCtx)
	m.markDied(sb, fmt.Sprintf("restoring memory from the archive: %v", err))
}
